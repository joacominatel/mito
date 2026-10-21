import LCUKit
import MitoCore
import Testing

private let rankedSolo = QueueID(rawValue: 420)
private let aram = QueueID(rawValue: 450)
private let pending = ReadyCheck(state: .inProgress, playerResponse: .none)

private let states: [ReadyCheck.State] = [
    .inProgress, .everyoneReady, .strangerNotReady, .partyNotReady, .invalid, .error,
    .unknown("Future"),
]
private let responses: [ReadyCheck.PlayerResponse] = [
    .none, .accepted, .declined, .unknown("Future"),
]

private func decide(
    _ settings: GameSettings, queue: QueueID? = rankedSolo, _ readyCheck: ReadyCheck = pending
) -> AutoAcceptDecision {
    AutoAcceptPolicy.decide(settings: settings, queue: queue, readyCheck: readyCheck)
}

struct AutoAcceptPolicyTests {
    @Test(arguments: [rankedSolo, nil])
    func offNeverAccepts(queue: QueueID?) {
        #expect(decide(GameSettings(autoAccept: .off), queue: queue) == .skip(.disabled))
    }

    @Test(arguments: [rankedSolo, aram, nil])
    func alwaysAcceptsInAnyQueue(queue: QueueID?) {
        #expect(
            decide(GameSettings(autoAccept: .always), queue: queue) == .accept(after: .seconds(2)))
    }

    @Test func theDefaultSettingsAcceptAfterTwoSeconds() {
        #expect(decide(GameSettings()) == .accept(after: .seconds(2)))
    }

    @Test func selectedQueuesAcceptsASelectedQueue() {
        let settings = GameSettings(
            autoAccept: .selectedQueues, autoAcceptQueues: [rankedSolo, aram])
        #expect(decide(settings, queue: aram) == .accept(after: .seconds(2)))
    }

    @Test func selectedQueuesSkipsAQueueThatIsNotSelected() {
        let settings = GameSettings(autoAccept: .selectedQueues, autoAcceptQueues: [rankedSolo])
        #expect(decide(settings, queue: aram) == .skip(.queueNotSelected(aram)))
    }

    @Test func selectedQueuesSkipsAnUnknownQueue() {
        let settings = GameSettings(autoAccept: .selectedQueues, autoAcceptQueues: [rankedSolo])
        #expect(decide(settings, queue: nil) == .skip(.unknownQueue))
    }

    @Test func selectedQueuesWithNoneSelectedNeverAccepts() {
        let settings = GameSettings(autoAccept: .selectedQueues, autoAcceptQueues: [])
        #expect(decide(settings, queue: rankedSolo) == .skip(.queueNotSelected(rankedSolo)))
    }

    @Test(arguments: states, responses)
    func acceptsOnlyAnUnansweredReadyCheckInProgress(
        state: ReadyCheck.State, response: ReadyCheck.PlayerResponse
    ) {
        let expected: AutoAcceptDecision =
            if state != .inProgress {
                .skip(.notInProgress(state))
            } else if response != .none {
                .skip(.alreadyAnswered(response))
            } else {
                .accept(after: .seconds(2))
            }
        #expect(
            decide(GameSettings(), ReadyCheck(state: state, playerResponse: response)) == expected)
    }

    @Test func theReadyCheckIsJudgedBeforeTheSettings() {
        let answered = ReadyCheck(state: .inProgress, playerResponse: .declined)
        #expect(
            decide(GameSettings(autoAccept: .off), answered) == .skip(.alreadyAnswered(.declined)))
    }

    @Test(arguments: [(-3, 0), (0, 0), (1, 1), (2, 2), (8, 8), (9, 8), (100, 8)])
    func theDelayIsClampedToZeroThroughEightSeconds(configured: Int, seconds: Int) {
        let settings = GameSettings(autoAcceptDelaySeconds: configured)
        #expect(decide(settings) == .accept(after: .seconds(seconds)))
    }
}
