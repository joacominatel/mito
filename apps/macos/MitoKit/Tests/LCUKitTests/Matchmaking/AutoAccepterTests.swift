import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Synchronization
import Testing

private let readyCheckPath = "/lol-matchmaking/v1/ready-check"
private let acceptPath = "/lol-matchmaking/v1/ready-check/accept"
private let rankedSolo = QueueID(rawValue: 420)
private let aram = QueueID(rawValue: 450)

private func update(_ file: String) throws -> FakeLCUConnection.Event {
    .init(topic: .readyCheck, event: readyCheckEvent(.update, data: try readyCheckBody(file)))
}

private func deleted() -> FakeLCUConnection.Event {
    .init(topic: .readyCheck, event: readyCheckEvent(.delete, data: Data("null".utf8)))
}

private func recheck(_ file: String) throws -> FakeLCUConnection.Response {
    .init(method: .get, path: readyCheckPath, body: try readyCheckBody(file))
}

private func accept(status: Int = 204) -> FakeLCUConnection.Response {
    .init(method: .post, path: acceptPath, status: status)
}

/// One accepter over a scripted connection; the event stream finishes after its last event.
private final class Harness: Sendable {
    let connection: FakeLCUConnection
    let clock = ManualClock()
    let reports = Recorder<AutoAcceptReport>()
    private let context: Mutex<AutoAcceptContext>

    init(
        settings: GameSettings = GameSettings(),
        queue: QueueID? = rankedSolo,
        events: [FakeLCUConnection.Event],
        responses: [FakeLCUConnection.Response] = []
    ) {
        connection = FakeLCUConnection(responses: responses, events: events)
        context = Mutex(AutoAcceptContext(settings: settings, queue: queue))
    }

    func start() -> Task<Void, Never> {
        let accepter = AutoAccepter(connection: connection, clock: clock)
        return Task {
            await accepter.run(context: { self.context.withLock { $0 } }) { report in
                self.reports.append(report)
            }
        }
    }

    func setSettings(_ settings: GameSettings) {
        context.withLock { $0.settings = settings }
    }

    var paths: [String] { connection.requests.map { "\($0.method.rawValue) \($0.path)" } }
}

@Suite(.timeLimit(.minutes(1)))
struct AutoAccepterTests {
    @Test func acceptsAfterTheDelayOnceTheReCheckStillQualifies() async throws {
        let harness = Harness(
            events: [try update("in-progress")],
            responses: [try recheck("in-progress"), accept()])
        let run = harness.start()

        await harness.clock.sleeps(1)
        #expect(harness.connection.requests.isEmpty)
        #expect(harness.clock.requestedSleeps == [.seconds(2)])

        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.paths == ["GET \(readyCheckPath)", "POST \(acceptPath)"])
        #expect(harness.reports.values == [.accepted])
    }

    @Test func waitsTheConfiguredDelayClampedToEightSeconds() async throws {
        let harness = Harness(
            settings: GameSettings(autoAcceptDelaySeconds: 30),
            events: [try update("in-progress")],
            responses: [try recheck("in-progress"), accept()])
        let run = harness.start()

        await harness.clock.sleeps(1)
        harness.clock.advance(by: .seconds(8))
        await run.value
        #expect(harness.clock.requestedSleeps == [.seconds(8)])
        #expect(harness.reports.values == [.accepted])
    }

    @Test(arguments: [("declined", ReadyCheck.PlayerResponse.declined), ("accepted", .accepted)])
    func skipsWhenAnEventShowsTheUserAnsweredDuringTheDelay(
        file: String, response: ReadyCheck.PlayerResponse
    ) async throws {
        let harness = Harness(
            events: [try update("in-progress"), try update(file)],
            responses: [try recheck("in-progress"), accept()])
        let run = harness.start()

        await harness.reports.wait(for: 1)
        await harness.clock.sleeps(1)
        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.reports.values == [.skipped(.alreadyAnswered(response))])
        #expect(harness.connection.requests.isEmpty)
    }

    @Test(arguments: [("declined", ReadyCheck.PlayerResponse.declined), ("accepted", .accepted)])
    func skipsWhenTheReCheckShowsTheUserAnswered(
        file: String, response: ReadyCheck.PlayerResponse
    ) async throws {
        let harness = Harness(
            events: [try update("in-progress")],
            responses: [try recheck(file), accept()])
        let run = harness.start()

        await harness.clock.sleeps(1)
        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.reports.values == [.skipped(.alreadyAnswered(response))])
        #expect(harness.connection.writes.isEmpty)
    }

    @Test func skipsWhenTheReadyCheckIsDeletedDuringTheDelay() async throws {
        let harness = Harness(
            events: [try update("in-progress"), deleted()],
            responses: [try recheck("in-progress"), accept()])
        let run = harness.start()

        await harness.reports.wait(for: 1)
        await harness.clock.sleeps(1)
        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.reports.values == [.skipped(.readyCheckEnded)])
        #expect(harness.connection.requests.isEmpty)
    }

    @Test func skipsWhenTheReadyCheckEndsDuringTheDelay() async throws {
        let harness = Harness(
            events: [try update("in-progress"), try update("stranger-not-ready")],
            responses: [try recheck("in-progress"), accept()])
        let run = harness.start()

        await harness.reports.wait(for: 1)
        await harness.clock.sleeps(1)
        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.reports.values == [.skipped(.notInProgress(.strangerNotReady))])
        #expect(harness.connection.requests.isEmpty)
    }

    @Test func skipsWhenTheReCheckFindsNoReadyCheck() async throws {
        let harness = Harness(events: [try update("in-progress")], responses: [accept()])
        let run = harness.start()

        await harness.clock.sleeps(1)
        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.reports.values == [.skipped(.readyCheckEnded)])
        #expect(harness.connection.writes.isEmpty)
    }

    @Test func acceptsTheSameReadyCheckOnlyOnce() async throws {
        let harness = Harness(
            events: [
                try update("in-progress"), try update("in-progress"), try update("in-progress"),
            ],
            responses: [try recheck("in-progress"), accept()])
        let run = harness.start()

        await harness.clock.sleeps(1)
        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.clock.requestedSleeps.count == 1)
        #expect(harness.connection.writes.count == 1)
        #expect(harness.reports.values == [.accepted])
    }

    @Test func doesNotAnswerAgainAfterTheUserAnsweredTheSameReadyCheck() async throws {
        let harness = Harness(
            events: [try update("declined"), try update("in-progress")],
            responses: [try recheck("in-progress"), accept()])
        await harness.start().value
        #expect(harness.reports.values.isEmpty)
        #expect(harness.connection.requests.isEmpty)
    }

    @Test func answersANewReadyCheckAfterTheLastOneEnded() async throws {
        let harness = Harness(
            events: [try update("in-progress"), try update("invalid"), try update("in-progress")],
            responses: [try recheck("in-progress"), accept()])
        let run = harness.start()

        await harness.reports.wait(for: 1)
        await harness.clock.sleeps(2)
        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.reports.values == [.skipped(.notInProgress(.invalid)), .accepted])
        #expect(harness.connection.writes.count == 1)
    }

    @Test func reportsAFailedAcceptWithoutRetrying() async throws {
        let harness = Harness(
            events: [try update("in-progress"), try update("in-progress")],
            responses: [try recheck("in-progress"), accept(status: 500)])
        let run = harness.start()

        await harness.clock.sleeps(1)
        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.reports.values == [.failed(.http(status: 500, body: Data()))])
        #expect(harness.connection.writes.count == 1)
    }

    @Test func reportsAFailedReCheckWithoutAccepting() async throws {
        let harness = Harness(
            events: [try update("in-progress")],
            responses: [.init(method: .get, path: readyCheckPath, status: 500), accept()])
        let run = harness.start()

        await harness.clock.sleeps(1)
        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.reports.values == [.failed(.http(status: 500, body: Data()))])
        #expect(harness.connection.writes.isEmpty)
    }

    @Test func offSendsNothingAndDoesNotWait() async throws {
        let harness = Harness(
            settings: GameSettings(autoAccept: .off),
            events: [try update("in-progress")],
            responses: [try recheck("in-progress"), accept()])
        await harness.start().value
        #expect(harness.reports.values == [.skipped(.disabled)])
        #expect(harness.connection.requests.isEmpty)
        #expect(harness.clock.requestedSleeps.isEmpty)
    }

    @Test func skipsAQueueThatIsNotSelected() async throws {
        let harness = Harness(
            settings: GameSettings(autoAccept: .selectedQueues, autoAcceptQueues: [rankedSolo]),
            queue: aram,
            events: [try update("in-progress")],
            responses: [try recheck("in-progress"), accept()])
        await harness.start().value
        #expect(harness.reports.values == [.skipped(.queueNotSelected(aram))])
        #expect(harness.connection.requests.isEmpty)
    }

    @Test func turningItOffDuringTheDelayCancelsTheAccept() async throws {
        let harness = Harness(
            events: [try update("in-progress")],
            responses: [try recheck("in-progress"), accept()])
        let run = harness.start()

        await harness.clock.sleeps(1)
        harness.setSettings(GameSettings(autoAccept: .off))
        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.reports.values == [.skipped(.disabled)])
        #expect(harness.connection.writes.isEmpty)
    }

    @Test func cancellingTheRunDuringTheDelaySendsNothing() async throws {
        let harness = Harness(
            events: [try update("in-progress")],
            responses: [try recheck("in-progress"), accept()])
        let run = harness.start()

        await harness.clock.sleeps(1)
        run.cancel()
        await run.value
        #expect(harness.connection.requests.isEmpty)
        #expect(harness.reports.values.isEmpty)
    }

    @Test func anUnreadableEventIsIgnored() async throws {
        let harness = Harness(
            events: [try update("missing-player-response"), try update("in-progress")],
            responses: [try recheck("in-progress"), accept()])
        let run = harness.start()

        await harness.clock.sleeps(1)
        harness.clock.advance(by: .seconds(2))
        await run.value
        #expect(harness.reports.values == [.accepted])
    }

    @Test func aReadyCheckEndingWithNothingPendingReportsNothing() async throws {
        let harness = Harness(events: [deleted(), try update("everyone-ready")])
        await harness.start().value
        #expect(harness.reports.values.isEmpty)
        #expect(harness.connection.requests.isEmpty)
    }

    @Test func listensOnlyToTheReadyCheckTopic() async throws {
        let phase = FakeLCUConnection.Event(
            topic: .gameflowPhase,
            event: LCUEvent(
                uri: "/lol-gameflow/v1/gameflow-phase", eventType: .update,
                data: try readyCheckBody("in-progress")))
        let harness = Harness(events: [phase])
        await harness.start().value
        #expect(harness.reports.values.isEmpty)
        #expect(harness.clock.requestedSleeps.isEmpty)
    }
}
