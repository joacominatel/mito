import Foundation
import LCUKit
import MitoCore
import Synchronization
import Testing

private let recheckRoute = "GET /lol-matchmaking/v1/ready-check"
private let acceptRoute = "POST /lol-matchmaking/v1/ready-check/accept"

private func event(_ file: String) throws -> LCUEvent {
    readyCheckEvent(.update, data: try readyCheckBody(file))
}

private func deleted() -> LCUEvent {
    readyCheckEvent(.delete, data: Data("null".utf8))
}

/// One accepter over a stepped connection, where events land between the accepter's own
/// requests instead of all at once.
private final class Stepped: Sendable {
    let connection: SteppedConnection
    let clock = ManualClock()
    let reports = Recorder<AutoAcceptReport>()
    private let settings = Mutex(GameSettings())
    private let contextReads = Mutex(0)
    private let contextGate: (call: Int, gate: Gate)?

    init(gates: [String: Gate] = [:], contextGate: (call: Int, gate: Gate)? = nil) throws {
        connection = SteppedConnection(
            replies: [
                recheckRoute: .success(try readyCheckBody("in-progress")),
                acceptRoute: .success(Data()),
            ],
            gates: gates)
        self.contextGate = contextGate
    }

    func start() -> Task<Void, Never> {
        let accepter = AutoAccepter(connection: connection, clock: clock)
        return Task {
            await accepter.run(context: { await self.context() }) { self.reports.append($0) }
        }
    }

    func setSettings(_ newSettings: GameSettings) {
        settings.withLock { $0 = newSettings }
    }

    private func context() async -> AutoAcceptContext {
        let call = contextReads.withLock { reads in
            reads += 1
            return reads
        }
        if let contextGate, contextGate.call == call { await contextGate.gate.pass() }
        return AutoAcceptContext(
            settings: settings.withLock { $0 }, queue: QueueID(rawValue: 420))
    }

    /// Emits a ready check in progress and lets its delay run out.
    func reachTheReCheck() async throws {
        connection.emit(try event("in-progress"))
        await clock.sleeps(1)
        clock.advance(by: .seconds(2))
    }

    var writes: [String] { connection.requests.filter { !$0.hasPrefix("GET ") } }
}

@Suite(.timeLimit(.minutes(1)))
struct AutoAccepterInterleavingTests {
    @Test func anAnswerArrivingDuringTheReCheckWithdrawsTheAccept() async throws {
        let recheck = Gate()
        let stepped = try Stepped(gates: [recheckRoute: recheck])
        let run = stepped.start()
        try await stepped.reachTheReCheck()
        await recheck.arrival()

        stepped.connection.emit(try event("declined"))
        await stepped.reports.wait(for: 1)
        recheck.open()
        stepped.connection.finishEvents()
        await run.value

        #expect(stepped.reports.values == [.skipped(.alreadyAnswered(.declined))])
        #expect(stepped.writes.isEmpty)
    }

    @Test func aReadyCheckEndingWhileTheSettingsAreReReadWithdrawsTheAccept() async throws {
        // Read 1 is the first decision; read 2 is the one after the re-check.
        let reread = Gate()
        let stepped = try Stepped(contextGate: (call: 2, gate: reread))
        let run = stepped.start()
        try await stepped.reachTheReCheck()
        await reread.arrival()

        stepped.connection.emit(deleted())
        await stepped.reports.wait(for: 1)
        reread.open()
        stepped.connection.finishEvents()
        await run.value

        #expect(stepped.reports.values == [.skipped(.readyCheckEnded)])
        #expect(stepped.connection.requests == [recheckRoute])
    }

    @Test func nothingWithdrawsAnAcceptOnceItsPostIsOnTheWay() async throws {
        let post = Gate()
        let stepped = try Stepped(gates: [acceptRoute: post])
        let run = stepped.start()
        try await stepped.reachTheReCheck()
        await post.arrival()

        stepped.connection.emit(try event("declined"))
        // A second ready check, skipped as off, proves the answer above was observed first.
        stepped.setSettings(GameSettings(autoAccept: .off))
        stepped.connection.emit(try event("everyone-ready"))
        stepped.connection.emit(try event("in-progress"))
        await stepped.reports.wait(for: 1)
        post.open()
        stepped.connection.finishEvents()
        await run.value

        #expect(stepped.reports.values == [.skipped(.disabled), .accepted])
        #expect(stepped.writes == [acceptRoute])
    }

    @Test func aNewReadyCheckDuringAStaleReCheckIsDecidedOnItsOwn() async throws {
        let recheck = Gate()
        let stepped = try Stepped(gates: [recheckRoute: recheck])
        let run = stepped.start()
        try await stepped.reachTheReCheck()
        await recheck.arrival()

        stepped.connection.emit(try event("invalid"))
        stepped.connection.emit(try event("in-progress"))
        await stepped.reports.wait(for: 1)
        await stepped.clock.sleeps(2)
        recheck.open()
        stepped.clock.advance(by: .seconds(2))
        stepped.connection.finishEvents()
        await run.value

        #expect(stepped.reports.values == [.skipped(.notInProgress(.invalid)), .accepted])
        #expect(stepped.writes == [acceptRoute])
    }

    @Test func cancellingTheRunDuringTheReCheckSendsNothing() async throws {
        let recheck = Gate()
        let stepped = try Stepped(gates: [recheckRoute: recheck])
        let run = stepped.start()
        try await stepped.reachTheReCheck()
        await recheck.arrival()

        run.cancel()
        recheck.open()
        await run.value

        #expect(stepped.writes.isEmpty)
        #expect(stepped.reports.values.isEmpty)
    }
}
