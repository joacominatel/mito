import Foundation
import LCUKit
import MitoTestSupport
import Testing

private let knownCases: [(file: String, phase: GameflowPhase)] = [
    ("phase-none", .none), ("phase-lobby", .lobby), ("phase-matchmaking", .matchmaking),
    ("phase-ready-check", .readyCheck), ("phase-champ-select", .champSelect),
    ("phase-game-start", .gameStart), ("phase-in-progress", .inProgress),
    ("phase-waiting-for-stats", .waitingForStats), ("phase-pre-end-of-game", .preEndOfGame),
    ("phase-end-of-game", .endOfGame), ("phase-reconnect", .reconnect),
    ("phase-checked-into-tournament", .checkedIntoTournament),
    ("phase-unknown", .unknown("PhaseFromAFuturePatch")),
]

private func body(_ file: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/gameflow-lobby/\(file).json"))
}

struct GameflowPhaseTests {
    @Test(arguments: knownCases)
    func decodesTheRESTBody(file: String, phase: GameflowPhase) throws {
        #expect(try LCUEndpoint.gameflowPhase.decode(body(file)) == phase)
    }

    @Test(arguments: knownCases)
    func decodesTheEventData(file: String, phase: GameflowPhase) throws {
        let event = LCUEvent(
            uri: "/lol-gameflow/v1/gameflow-phase", eventType: .update, data: try body(file))
        #expect(try GameflowPhase(event) == phase)
    }

    @Test func anUnknownValueKeepsItsRawString() {
        #expect(GameflowPhase("TFTSpecialPhase") == .unknown("TFTSpecialPhase"))
    }

    @Test func matchingIsCaseSensitive() {
        #expect(GameflowPhase("champselect") == .unknown("champselect"))
    }

    @Test(arguments: ["null", "42", "{\"phase\":\"Lobby\"}", ""])
    func aNonStringBodyIsADecodingError(_ json: String) {
        #expect {
            try LCUEndpoint.gameflowPhase.decode(Data(json.utf8))
        } throws: { error in
            if case .decoding = error as? LCUError { true } else { false }
        }
    }

    @Test func eventDataThatIsNotAStringIsADecodingError() {
        let event = LCUEvent(
            uri: "/lol-gameflow/v1/gameflow-phase", eventType: .delete, data: Data("null".utf8))
        #expect {
            try GameflowPhase(event)
        } throws: { error in
            if case .decoding = error as? LCUError { true } else { false }
        }
    }
}

struct GameflowPhaseEndpointTests {
    @Test func isAGetOnTheGameflowPhasePath() {
        let endpoint = LCUEndpoint.gameflowPhase
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/lol-gameflow/v1/gameflow-phase")
        #expect(endpoint.body == nil)
    }

    @Test func sendsThroughAConnection() async throws {
        let connection = FakeLCUConnection(responses: [
            .init(
                method: .get, path: "/lol-gameflow/v1/gameflow-phase",
                body: try body("phase-champ-select"))
        ])
        #expect(try await connection.send(.gameflowPhase) == .champSelect)
    }
}
