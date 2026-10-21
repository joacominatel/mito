import LCUKit
import MitoCore
import Testing

private func restPhases(_ recording: Recording) throws -> [GameflowPhase] {
    try recording.bodies(at: LCUEndpoint.gameflowPhase.path).map {
        try LCUEndpoint.gameflowPhase.decode($0)
    }
}

private func eventPhases(_ recording: Recording) throws -> [GameflowPhase] {
    try recording.events(on: .gameflowPhase).map { try GameflowPhase($0) }
}

struct RecordedGameflowTests {
    @Test func lobbyToGameGoesFromNoneThroughLobbyIntoMatchmaking() throws {
        let recording = try Recording("lobby-to-game")
        #expect(try restPhases(recording) == [.none, .lobby, .matchmaking])
        #expect(try eventPhases(recording) == [.lobby, .matchmaking])
    }

    @Test func aReadyCheckPhaseEventPrecedesChampSelect() throws {
        #expect(try eventPhases(Recording("ready-check")) == [.readyCheck, .champSelect])
    }

    @Test func leavingChampSelectWithoutAGameReturnsToNone() throws {
        #expect(try eventPhases(Recording("champ-select")) == [.readyCheck, .champSelect, .none])
    }

    @Test(arguments: Recording.scenarios)
    func everyRecordedPhaseIsAKnownValue(_ scenario: String) throws {
        let recording = try Recording(scenario)
        let phases = try restPhases(recording) + eventPhases(recording)
        #expect(!phases.isEmpty)
        for phase in phases {
            if case .unknown(let raw) = phase { Issue.record("Unknown phase \(raw)") }
        }
    }

    @Test func theStateMachineFollowsTheRecordedPhasesFromTheConnectRead() throws {
        let recording = try Recording("champ-select")
        var machine = MitoStateMachine()
        machine.apply(.connected)
        var states: [MitoState] = []
        for phase in try [restPhases(recording)[0]] + eventPhases(recording) {
            machine.apply(phase)
            states.append(machine.state)
        }
        #expect(states == [.matchmaking, .readyCheck, .champSelect, .idle])
    }

    @Test(arguments: Recording.scenarios)
    func theGameflowSessionCarriesTheRecordedQueueOnSummonersRift(_ scenario: String) throws {
        let recording = try Recording(scenario)
        let bodies = recording.bodies(at: LCUEndpoint.gameflowSession.path)
        #expect(!bodies.isEmpty)
        for body in bodies {
            #expect(
                try LCUEndpoint.gameflowSession.decode(body)
                    == GameflowSession(queueID: QueueID(rawValue: recording.queueID), mapID: 11))
        }
    }

    @Test func theGameflowSessionIs404OutsideALobby() throws {
        let recording = try Recording("lobby-to-game")
        let first = try #require(recording.exchanges(at: LCUEndpoint.gameflowSession.path).first)
        #expect(first.status == 404)
        #expect(try restPhases(recording).first == GameflowPhase.none)
    }
}
