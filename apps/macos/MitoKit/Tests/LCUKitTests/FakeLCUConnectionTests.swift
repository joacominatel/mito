import Foundation
import LCUKit
import MitoTestSupport
import Testing

struct FakeLCUConnectionTests {
    private let phase = LCUEndpoint<String>(method: .get, path: "/lol-gameflow/v1/gameflow-phase")
    private let accept = LCUEndpoint<LCUNoContent>(
        method: .post, path: "/lol-matchmaking/v1/ready-check/accept")

    @Test func servesTheResponseForTheRoute() async throws {
        let fake = FakeLCUConnection(responses: [
            .init(method: .get, path: phase.path, json: #""ChampSelect""#)
        ])
        #expect(try await fake.send(phase) == "ChampSelect")
    }

    @Test func servesResponsesInOrderThenRepeatsTheLast() async throws {
        let fake = FakeLCUConnection(responses: [
            .init(method: .get, path: phase.path, json: #""ReadyCheck""#),
            .init(method: .get, path: phase.path, json: #""ChampSelect""#),
        ])
        #expect(try await fake.send(phase) == "ReadyCheck")
        #expect(try await fake.send(phase) == "ChampSelect")
        #expect(try await fake.send(phase) == "ChampSelect")
    }

    @Test func anUnservedRouteIsA404() async {
        await #expect(throws: LCUError.http(status: 404, body: Data())) {
            try await FakeLCUConnection().send(phase)
        }
    }

    @Test func aNonSuccessStatusThrowsWithTheBody() async {
        let fake = FakeLCUConnection(responses: [
            .init(method: .post, path: accept.path, status: 500, json: #"{"message":"x"}"#)
        ])
        await #expect(throws: LCUError.http(status: 500, body: Data(#"{"message":"x"}"#.utf8))) {
            try await fake.send(accept)
        }
    }

    @Test func recordsWritesButNotReads() async throws {
        let fake = FakeLCUConnection(responses: [
            .init(method: .get, path: phase.path, json: #""Lobby""#),
            .init(method: .post, path: accept.path, status: 204),
        ])
        _ = try await fake.send(phase)
        _ = try await fake.send(accept)

        #expect(fake.requests.map(\.path) == [phase.path, accept.path])
        #expect(fake.writes == [.init(method: .post, path: accept.path, body: nil)])
    }

    @Test func streamsOnlyTheSubscribedTopicsInOrder() async {
        let fake = FakeLCUConnection(events: [
            event(.gameflowPhase, #""ReadyCheck""#),
            event(.lobby, "{}"),
            event(.gameflowPhase, #""ChampSelect""#),
        ])
        var received: [LCUEvent] = []
        for await event in fake.events([.gameflowPhase]) { received.append(event) }

        #expect(
            received.map(\.data) == [Data(#""ReadyCheck""#.utf8), Data(#""ChampSelect""#.utf8)])
    }

    @Test func loadsARecordedScenario() async throws {
        let directory = try scenario(
            rest: """
                {"method": "GET", "path": "/lol-gameflow/v1/gameflow-phase", "status": 200, "body": "ChampSelect"}

                {"method": "POST", "path": "/lol-matchmaking/v1/ready-check/accept", "status": 204, "body": null}
                """,
            events: """
                {"t_ms": 0, "topic": "OnJsonApiEvent_lol-gameflow_v1_gameflow-phase", "uri": "/lol-gameflow/v1/gameflow-phase", "eventType": "Update", "data": "ReadyCheck"}
                {"t_ms": 5, "topic": "OnJsonApiEvent_lol-unknown_v1_thing", "uri": "/lol-unknown/v1/thing", "eventType": "Create", "data": {}}
                """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = try FakeLCUConnection(directory: directory)

        #expect(try await fake.send(phase) == "ChampSelect")
        #expect(try await fake.send(accept) == LCUNoContent())
        var received: [LCUEvent] = []
        for await event in fake.events(Set(LCUTopic.allCases)) { received.append(event) }
        #expect(
            received == [
                LCUEvent(
                    uri: "/lol-gameflow/v1/gameflow-phase", eventType: .update,
                    data: Data(#""ReadyCheck""#.utf8))
            ])
    }

    @Test func aMalformedScenarioLineNamesTheLine() throws {
        let directory = try scenario(rest: #"{"method": "GET"}"#, events: nil)
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: FakeLCUConnection.ScenarioError.malformedLine(file: "rest.jsonl", line: 1))
        {
            try FakeLCUConnection(directory: directory)
        }
    }

    @Test func aMissingScenarioThrows() {
        #expect(throws: FakeLCUConnection.ScenarioError.self) {
            try FakeLCUConnection(scenario: "no-such-scenario")
        }
    }

    @Test func statesYieldTheCurrentStateFirst() async {
        let fake = FakeLCUConnection(state: .searching)
        #expect(await first(1, of: fake.states()) == [.searching])
    }

    @Test func statesYieldLaterChangesInOrder() async {
        let fake = FakeLCUConnection()
        let states = fake.states()
        fake.setState(.searching)
        fake.setState(.connecting)
        fake.setState(.connected)
        #expect(await first(4, of: states) == [.connected, .searching, .connecting, .connected])
    }

    @Test func everyStatesSubscriberReceivesTheChanges() async {
        let fake = FakeLCUConnection()
        let first = fake.states()
        let second = fake.states()
        fake.setState(.searching)
        #expect(await self.first(2, of: first) == [.connected, .searching])
        #expect(await self.first(2, of: second) == [.connected, .searching])
    }

    @Test func aLateSubscriberStartsFromTheLatestState() async {
        let fake = FakeLCUConnection()
        fake.setState(.connecting)
        #expect(await first(1, of: fake.states()) == [.connecting])
    }

    private func first(_ count: Int, of states: AsyncStream<ConnectionState>) async
        -> [ConnectionState]
    {
        var received: [ConnectionState] = []
        for await state in states {
            received.append(state)
            if received.count == count { break }
        }
        return received
    }

    private func event(_ topic: LCUTopic, _ json: String) -> FakeLCUConnection.Event {
        .init(topic: topic, event: LCUEvent(uri: "/", eventType: .update, data: Data(json.utf8)))
    }

    private func scenario(rest: String?, events: String?) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "FakeLCUConnectionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try rest?.write(
            to: directory.appending(path: "rest.jsonl"), atomically: true, encoding: .utf8)
        try events?.write(
            to: directory.appending(path: "events.jsonl"), atomically: true, encoding: .utf8)
        return directory
    }
}
