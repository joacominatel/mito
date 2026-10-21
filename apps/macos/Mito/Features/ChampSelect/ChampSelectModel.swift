import Foundation
import LCUKit
import MitoAssets
import MitoCore
import MitoEngine
import Observation

/// Follows the live champ-select session and publishes its `DraftContext` (§12.4, §20.1).
@Observable
final class ChampSelectModel {
    enum Turn: Hashable {
        case ban
        case pick
    }

    static let debounce: Duration = .milliseconds(150)
    /// What the draft carries when the gameflow session cannot be read.
    static let unknownQueue = QueueType.other(QueueID(rawValue: 0))

    /// `nil` outside champ select or while the session has no usable draft (§12.2).
    private(set) var draft: DraftContext?
    /// Locked enemies without a client role, by cell. Display only: no snapshot yet (§12.3).
    private(set) var enemyRoles: [Int: InferredRole] = [:]
    /// The cells whose ban or pick is in progress.
    private(set) var turns: [Int: Turn] = [:]
    private(set) var phaseInterval: ClosedRange<Date>?

    let settings: @MainActor () -> ChampSelectSettings
    private let connection: any LCUConnection
    private let patch: @MainActor () -> Patch
    private let readGameData: @MainActor () -> GameData?
    private let clock: any Clock<Duration>
    private let now: () -> Date

    @ObservationIgnored private var inputs: Task<Inputs, Never>?
    @ObservationIgnored private var pendingUpdate: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init(
        connection: any LCUConnection,
        settings: @escaping @MainActor () -> ChampSelectSettings = { ChampSelectSettings() },
        patch: @escaping @MainActor () -> Patch = { Patch(rawValue: "") },
        clock: any Clock<Duration> = ContinuousClock(),
        now: @escaping () -> Date = { .now },
        gameData: @autoclosure @escaping @MainActor () -> GameData? = nil
    ) {
        self.connection = connection
        self.settings = settings
        self.patch = patch
        self.clock = clock
        self.now = now
        readGameData = gameData
    }

    /// The shell's shared catalog, read live: names appear once it loads.
    var gameData: GameData? { readGameData() }

    var isInChampSelect: Bool { draft != nil }

    func run() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.followSession() }
            for await state in connection.states() {
                if state == .connected {
                    group.addTask { await self.refresh() }
                } else {
                    reset()
                }
            }
            group.cancelAll()
        }
        pendingUpdate?.cancel()
    }

    /// Events only carry changes, so the current session is read once per connection.
    func refresh() async {
        let generation = supersede()
        let session = try? await connection.send(.champSelectSession)
        guard generation == self.generation else { return }
        guard let session else { return reset() }
        await apply(session, generation: generation)
    }

    /// Maps `session` right away; previews use it to skip the connection.
    func show(_ session: ChampSelectSession, queue: QueueType, pickable: Set<ChampionID>) {
        guard
            let draft = session.draftContext(
                queue: queue, patch: patch(), pickable: pickable)
        else { return clearDraft() }
        self.draft = draft
        enemyRoles = Self.inferRoles(of: draft.enemies)
        turns = Self.turns(in: session)
        phaseInterval = session.timer?.adjustedTimeLeftInPhase.map { milliseconds in
            let start = now()
            return start...start.addingTimeInterval(Double(max(milliseconds, 0)) / 1000)
        }
    }

    private func followSession() async {
        for await event in connection.events([.champSelectSession]) {
            guard event.eventType != .delete, let session = try? ChampSelectSession(event) else {
                reset()
                continue
            }
            let generation = supersede()
            pendingUpdate = Task { [clock] in
                do {
                    try await clock.sleep(for: Self.debounce)
                } catch {
                    return
                }
                await self.apply(session, generation: generation)
            }
        }
    }

    private func apply(_ session: ChampSelectSession, generation: Int) async {
        let inputs = await sessionInputs()
        guard generation == self.generation else { return }
        show(session, queue: inputs.queue, pickable: inputs.pickable)
    }

    /// Only the newest session write may land.
    private func supersede() -> Int {
        pendingUpdate?.cancel()
        pendingUpdate = nil
        generation += 1
        return generation
    }

    private func reset() {
        _ = supersede()
        inputs = nil
        clearDraft()
    }

    private func clearDraft() {
        draft = nil
        enemyRoles = [:]
        turns = [:]
        phaseInterval = nil
    }

    // MARK: Session inputs

    private struct Inputs {
        let queue: QueueType
        let pickable: Set<ChampionID>
    }

    /// Fetched once per champ select, when its first session arrives.
    private func sessionInputs() async -> Inputs {
        if let inputs { return await inputs.value }
        let task = Task { [connection] in
            async let session = try? connection.send(.gameflowSession)
            async let pickable = try? connection.send(.pickableChampionIDs)
            return Inputs(
                queue: await session?.queueType ?? Self.unknownQueue, pickable: await pickable ?? []
            )
        }
        inputs = task
        return await task.value
    }

    // MARK: Derivations

    private struct NoStats: StatsProvider {
        func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }
    }

    private static func inferRoles(of enemies: [DraftSlot]) -> [Int: InferredRole] {
        let locked = enemies.filter { $0.role == nil && $0.champion != nil }
        let inferred = RoleInference.infer(
            enemies: locked.compactMap(\.champion),
            takenRoles: Set(enemies.compactMap(\.role)),
            stats: NoStats())
        return Dictionary(
            zip(locked.map(\.cellId), inferred), uniquingKeysWith: { first, _ in first })
    }

    private static func turns(in session: ChampSelectSession) -> [Int: Turn] {
        let active = session.actions.joined().compactMap { action -> (Int, Turn)? in
            guard action.isInProgress == true, action.completed != true,
                let cell = action.actorCellId
            else { return nil }
            switch action.type {
            case .ban: return (cell, .ban)
            case .pick: return (cell, .pick)
            default: return nil
            }
        }
        return Dictionary(active, uniquingKeysWith: { first, _ in first })
    }
}
