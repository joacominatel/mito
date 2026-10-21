import Foundation
import LCUKit
import MitoTestSupport
import Testing

private let knownCases: [(file: String, readyCheck: ReadyCheck)] = [
    ("in-progress", ReadyCheck(state: .inProgress, playerResponse: .none)),
    ("accepted", ReadyCheck(state: .inProgress, playerResponse: .accepted)),
    ("declined", ReadyCheck(state: .inProgress, playerResponse: .declined)),
    ("everyone-ready", ReadyCheck(state: .everyoneReady, playerResponse: .accepted)),
    ("stranger-not-ready", ReadyCheck(state: .strangerNotReady, playerResponse: .accepted)),
    ("party-not-ready", ReadyCheck(state: .partyNotReady, playerResponse: .accepted)),
    ("invalid", ReadyCheck(state: .invalid, playerResponse: .none)),
    ("error", ReadyCheck(state: .error, playerResponse: .none)),
    (
        "unknown-values",
        ReadyCheck(
            state: .unknown("StateFromAFuturePatch"),
            playerResponse: .unknown("ResponseFromAFuturePatch"))
    ),
]

func readyCheckBody(_ file: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/gameflow-lobby/ready-check-\(file).json"))
}

func readyCheckEvent(_ eventType: LCUEvent.EventType, data: Data) -> LCUEvent {
    LCUEvent(uri: "/lol-matchmaking/v1/ready-check", eventType: eventType, data: data)
}

private func isDecodingError(_ error: any Error) -> Bool {
    if case .decoding = error as? LCUError { true } else { false }
}

struct ReadyCheckTests {
    @Test(arguments: knownCases)
    func decodesTheRESTBody(file: String, readyCheck: ReadyCheck) throws {
        #expect(try LCUEndpoint.readyCheck.decode(readyCheckBody(file)) == readyCheck)
    }

    @Test(arguments: knownCases)
    func decodesTheEventData(file: String, readyCheck: ReadyCheck) throws {
        #expect(try ReadyCheck(readyCheckEvent(.update, data: readyCheckBody(file))) == readyCheck)
    }

    @Test func aCreateEventCarriesTheReadyCheck() throws {
        let event = readyCheckEvent(.create, data: try readyCheckBody("in-progress"))
        #expect(try ReadyCheck(event) == ReadyCheck(state: .inProgress, playerResponse: .none))
    }

    @Test func aDeleteEventMeansTheReadyCheckIsGone() throws {
        let event = readyCheckEvent(.delete, data: try readyCheckBody("in-progress"))
        #expect(try ReadyCheck(event) == nil)
    }

    @Test(arguments: ["null", "", " null\n", "  "])
    func anEventWithoutDataMeansTheReadyCheckIsGone(_ json: String) throws {
        #expect(try ReadyCheck(readyCheckEvent(.update, data: Data(json.utf8))) == nil)
    }

    @Test func matchingIsCaseSensitive() {
        #expect(ReadyCheck.State("inprogress") == .unknown("inprogress"))
        #expect(ReadyCheck.PlayerResponse("none") == .unknown("none"))
    }

    @Test func aMissingPlayerResponseIsADecodingError() {
        #expect {
            try LCUEndpoint.readyCheck.decode(readyCheckBody("missing-player-response"))
        } throws: { isDecodingError($0) }
    }

    @Test(arguments: ["{}", "{\"state\":\"InProgress\",\"playerResponse\":3}", "\"InProgress\""])
    func aMalformedEventIsADecodingError(_ json: String) {
        #expect {
            try ReadyCheck(readyCheckEvent(.update, data: Data(json.utf8)))
        } throws: { isDecodingError($0) }
    }
}

struct MatchmakingEndpointTests {
    @Test func readyCheckIsAGetOnTheReadyCheckPath() {
        let endpoint = LCUEndpoint.readyCheck
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/lol-matchmaking/v1/ready-check")
        #expect(endpoint.body == nil)
    }

    @Test func acceptIsABodylessPostOnTheAcceptPath() {
        let endpoint = LCUEndpoint.acceptReadyCheck
        #expect(endpoint.method == .post)
        #expect(endpoint.path == "/lol-matchmaking/v1/ready-check/accept")
        #expect(endpoint.body == nil)
    }

    @Test func acceptTreatsAnEmptyBodyAsSuccess() async throws {
        let connection = FakeLCUConnection(responses: [
            .init(method: .post, path: "/lol-matchmaking/v1/ready-check/accept", status: 204)
        ])
        #expect(try await connection.send(.acceptReadyCheck) == LCUNoContent())
    }

    @Test func readyCheckSendsThroughAConnection() async throws {
        let connection = FakeLCUConnection(responses: [
            .init(
                method: .get, path: "/lol-matchmaking/v1/ready-check",
                body: try readyCheckBody("declined"))
        ])
        #expect(
            try await connection.send(.readyCheck)
                == ReadyCheck(state: .inProgress, playerResponse: .declined))
    }
}
