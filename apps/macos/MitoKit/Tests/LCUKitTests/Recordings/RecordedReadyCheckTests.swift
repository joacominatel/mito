import LCUKit
import MitoCore
import Testing

private func check(_ state: ReadyCheck.State, _ response: ReadyCheck.PlayerResponse) -> ReadyCheck {
    ReadyCheck(state: state, playerResponse: response)
}

private func observed(_ scenario: String) throws -> [ReadyCheck?] {
    try Recording(scenario).events(on: .readyCheck).map { try ReadyCheck($0) }
}

struct RecordedReadyCheckTests {
    @Test(arguments: ["ready-check", "champ-select"])
    func aHandAcceptedReadyCheckEndsInEveryoneReadyAndADelete(_ scenario: String) throws {
        #expect(
            try observed(scenario) == [
                check(.inProgress, .none), check(.inProgress, .none), check(.inProgress, .none),
                check(.inProgress, .accepted), check(.inProgress, .accepted),
                check(.everyoneReady, .accepted), nil,
            ])
    }

    @Test func theReadAnswersInvalidWhileQueuedAndAfterTheReadyCheck() throws {
        let recording = try Recording("champ-select")
        let reads = try recording.bodies(at: LCUEndpoint.readyCheck.path).map {
            try LCUEndpoint.readyCheck.decode($0)
        }
        #expect(
            reads == [check(.invalid, .none), check(.inProgress, .none), check(.invalid, .none)])
    }

    @Test func theReadIs404BeforeTheSearchStarts() throws {
        let reads = try Recording("lobby-to-game").exchanges(at: LCUEndpoint.readyCheck.path)
        #expect(reads.map(\.status) == [404, 200])
        #expect(try LCUEndpoint.readyCheck.decode(reads[1].body) == check(.invalid, .none))
    }

    @Test func thePolicyAcceptsOnlyTheUnansweredObservations() throws {
        let decisions = try observed("ready-check").compactMap { $0 }.map {
            AutoAcceptPolicy.decide(
                settings: GameSettings(autoAccept: .always), queue: QueueID(rawValue: 400),
                readyCheck: $0)
        }
        let accept = AutoAcceptDecision.accept(after: .seconds(2))
        #expect(
            decisions == [
                accept, accept, accept, .skip(.alreadyAnswered(.accepted)),
                .skip(.alreadyAnswered(.accepted)), .skip(.notInProgress(.everyoneReady)),
            ])
    }
}
