import Foundation
import LCUKit
import MitoCore
import Observation

@Observable
final class GameflowModel {
    private var machine: MitoStateMachine
    let settings: @MainActor () -> GameSettings
    private let connection: any LCUConnection
    private let poster: any NotificationPosting
    private let accepter: AutoAccepter
    private let readyChecks: AsyncStream<LCUEvent>.Continuation
    // Bumped by every phase event and connection change: a REST phase older than either is dropped.
    @ObservationIgnored private var phaseGeneration = 0
    /// Bumped by every live ready-check event and every drop: a REST read older than either is
    /// stale. Observable so tests can tell when the live stream was consumed.
    private(set) var readyCheckGeneration = 0

    init(
        connection: any LCUConnection,
        settings: @escaping @MainActor () -> GameSettings = { GameSettings() },
        poster: any NotificationPosting = SystemNotificationPoster(),
        clock: any Clock<Duration> = ContinuousClock(),
        machine: MitoStateMachine = MitoStateMachine()
    ) {
        self.connection = connection
        self.settings = settings
        self.poster = poster
        self.machine = machine
        let (stream, readyChecks) = AsyncStream.makeStream(
            of: LCUEvent.self, bufferingPolicy: .unbounded)
        self.readyChecks = readyChecks
        accepter = AutoAccepter(
            connection: ReadyCheckFeed(base: connection, readyChecks: stream), clock: clock)
    }

    var state: MitoState { machine.state }

    /// The §22.4 symbol for the current phase; `nil` leaves the connection symbol.
    var menuBarSymbol: String? {
        switch state {
        case .matchmaking: "magnifyingglass"
        case .champSelect: "person.3.fill"
        case .inGame: "gamecontroller.fill"
        case .searching, .connecting, .idle, .lobby, .readyCheck: nil
        }
    }

    var phaseSymbol: String {
        if let menuBarSymbol { return menuBarSymbol }
        return switch state {
        case .lobby: "person.2"
        case .readyCheck: "bell.badge"
        default: "moon.zzz"
        }
    }

    var phaseTitle: LocalizedStringResource {
        switch state {
        case .searching, .connecting, .idle:
            LocalizedStringResource("Sin partida en curso", table: "Gameflow")
        case .lobby: LocalizedStringResource("Fase: Lobby", table: "Gameflow")
        case .matchmaking: LocalizedStringResource("Fase: Buscando partida", table: "Gameflow")
        case .readyCheck: LocalizedStringResource("Fase: Partida encontrada", table: "Gameflow")
        case .champSelect: LocalizedStringResource("Fase: Champ select", table: "Gameflow")
        case .inGame: LocalizedStringResource("Fase: En partida", table: "Gameflow")
        }
    }

    var isInMatchFlow: Bool {
        switch state {
        case .searching, .connecting, .idle: false
        case .lobby, .matchmaking, .readyCheck, .champSelect, .inGame: true
        }
    }

    /// Returns once the connection's streams finish and any accept in flight settles.
    func run() async {
        await withDiscardingTaskGroup { group in
            group.addTask {
                await self.accepter.run(context: { await self.autoAcceptContext() }) { report in
                    await self.handle(report)
                }
            }
            // Everything that feeds the accepter; once it is all done, nothing more can arrive.
            await withDiscardingTaskGroup { feeders in
                feeders.addTask { await self.followPhases() }
                feeders.addTask { await self.followReadyChecks() }
                for await state in connection.states() {
                    // The end of a ready check is never seen across a drop: the next one is new.
                    if machine.connection == .connected, state != .connected {
                        readyCheckGeneration += 1
                        readyChecks.yield(ReadyCheckFeed.ended)
                    }
                    machine.apply(state)
                    phaseGeneration += 1
                    if state == .connected {
                        feeders.addTask { await self.refreshPhase() }
                        feeders.addTask { await self.readCurrentReadyCheck() }
                    }
                }
            }
            readyChecks.finish()
        }
    }

    private func followPhases() async {
        for await event in connection.events([.gameflowPhase]) {
            guard let phase = try? GameflowPhase(event) else { continue }
            phaseGeneration += 1
            machine.apply(phase)
        }
    }

    private func refreshPhase() async {
        let generation = phaseGeneration
        guard let phase = try? await connection.send(.gameflowPhase),
            generation == phaseGeneration
        else { return }
        machine.apply(phase)
    }

    /// One stream for the live events and the connect read keeps them in the order they happened.
    private func followReadyChecks() async {
        for await event in connection.events([.readyCheck]) {
            readyCheckGeneration += 1
            readyChecks.yield(event)
        }
    }

    /// A 404 means no ready check. A live event that came in meanwhile is newer: replaying the
    /// read after it would start a second ready check, and a second notification (§11.3).
    private func readCurrentReadyCheck() async {
        let generation = readyCheckGeneration
        guard let body = try? await connection.send(ReadyCheckFeed.current),
            generation == readyCheckGeneration
        else { return }
        readyChecks.yield(ReadyCheckFeed.event(body))
    }

    private func autoAcceptContext() async -> AutoAcceptContext {
        let settings = settings()
        let queue = try? await connection.send(.gameflowSession).queueID
        return AutoAcceptContext(settings: settings, queue: queue)
    }

    /// The accepter reports at most one decision per ready check, so this posts at most once.
    private func handle(_ report: AutoAcceptReport) async {
        let title: LocalizedStringResource
        switch report {
        case .accepted:
            title = LocalizedStringResource("Partida encontrada, aceptada", table: "Gameflow")
        case .skipped(.disabled), .skipped(.queueNotSelected), .skipped(.unknownQueue):
            title = LocalizedStringResource("Partida encontrada", table: "Gameflow")
        case .skipped, .failed:
            return
        }
        guard settings().notifyMatchFound else { return }
        // One identifier for both: the match-found notification of §22.5.
        await poster.post(.matchFound, title: title)
    }
}

extension GameSettings {
    /// Whether `selectedQueues` answers ready checks in `queue`.
    subscript(autoAccepts queue: QueueID) -> Bool {
        get { autoAcceptQueues.contains(queue) }
        set {
            if newValue {
                autoAcceptQueues.insert(queue)
            } else {
                autoAcceptQueues.remove(queue)
            }
        }
    }
}
