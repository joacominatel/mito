import Foundation
import LCUKit
import MitoAssets
import MitoCore
import MitoEngine
import Observation

/// Follows the live champ-select session and publishes its `DraftContext` and the pick or ban
/// recommendations for it (§12.4, §20.1).
@Observable
final class ChampSelectModel {
    typealias Turn = DraftTurn

    static let debounce: Duration = .milliseconds(150)
    /// What the draft carries when the gameflow session cannot be read.
    static let unknownQueue = QueueType.other(QueueID(rawValue: 0))

    /// `nil` outside champ select or while the session has no usable draft (§12.2).
    private(set) var draft: DraftContext?
    /// The role picked by hand in blind pick; `nil` follows the default (§20.3).
    private(set) var chosenRole: Role?
    /// The cells whose ban or pick is in progress.
    private(set) var turns: [Int: Turn] = [:]
    private(set) var phaseInterval: ClosedRange<Date>?
    /// Read once per champ select, with the queue and the pickable set.
    private(set) var personal = PersonalInputs()

    let settings: @MainActor () -> ChampSelectSettings
    private let connection: any LCUConnection
    private let patch: @MainActor () -> Patch
    private let readGameData: @MainActor () -> GameData?
    private let readStats: @MainActor () -> any StatsProvider
    private let store: any PersonalStore
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
        gameData: @autoclosure @escaping @MainActor () -> GameData? = nil,
        stats: @escaping @MainActor () -> any StatsProvider = { NoStats() },
        store: any PersonalStore = UnavailablePersonalStore()
    ) {
        self.connection = connection
        readStats = stats
        self.store = store
        self.settings = settings
        self.patch = patch
        self.clock = clock
        self.now = now
        readGameData = gameData
    }

    /// The shell's shared catalog, read live: names appear once it loads.
    var gameData: GameData? { readGameData() }

    var isInChampSelect: Bool { draft != nil }

    /// Bans while anyone is banning, picks otherwise; `nil` outside champ select. Derived on
    /// read, so the draft, the settings, and a snapshot that opens mid-draft all apply at once.
    var recommendations: RecommendationList? {
        recommendations(isBanPhase: isBanPhase)
    }

    /// The first pick recommendation, even while the column shows bans: the analysis's champion
    /// before you lock or hover one (§20.1).
    var topPick: ChampionID? {
        guard case .picks(let picks) = recommendations(isBanPhase: false) else { return nil }
        return picks.first?.champion
    }

    private func recommendations(isBanPhase: Bool) -> RecommendationList? {
        guard let draft else { return nil }
        return DraftRecommendations.list(
            for: draft, role: scoringRole, isBanPhase: isBanPhase, settings: settings(),
            stats: readStats(), personal: personal, now: now())
    }

    /// Locked enemies without a client role, by cell, inferred from the open snapshot for
    /// display (§12.3). Derived on read, so a snapshot that opens mid-draft applies at once.
    var enemyRoles: [Int: InferredRole] {
        guard let draft else { return [:] }
        return Self.inferRoles(of: draft.enemies, stats: readStats())
    }

    /// The role the recommendations score for: the assigned one, or in blind pick the user's
    /// choice or its default (§20.3). ARAM has none.
    var scoringRole: Role? {
        guard let draft else { return nil }
        if let role = draft.myRole { return role }
        guard canChooseRole else { return nil }
        return chosenRole ?? DraftRecommendations.blindRole(for: draft, personal: personal)
    }

    /// Blind pick: no assigned role, and not ARAM.
    var canChooseRole: Bool {
        guard let draft else { return false }
        return draft.myRole == nil && draft.queue != .aram
    }

    /// Kept until the champ select ends (§20.3).
    func chooseRole(_ role: Role) {
        chosenRole = role
    }

    var isBanPhase: Bool {
        draft?.isMyTurnToBan == true || turns.values.contains(.ban)
    }

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
    func show(
        _ session: ChampSelectSession, queue: QueueType, pickable: Set<ChampionID>,
        personal: PersonalInputs = PersonalInputs()
    ) {
        guard
            let draft = session.draftContext(
                queue: queue, patch: patch(), pickable: pickable)
        else { return clearDraft() }
        self.draft = draft
        if self.personal != personal { self.personal = personal }
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
        show(
            session, queue: inputs.queue, pickable: inputs.pickable, personal: inputs.personal)
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
        chosenRole = nil
        turns = [:]
        phaseInterval = nil
        personal = PersonalInputs()
    }

    // MARK: Session inputs

    private struct Inputs {
        let queue: QueueType
        let pickable: Set<ChampionID>
        let personal: PersonalInputs
    }

    /// Fetched once per champ select, when its first session arrives.
    private func sessionInputs() async -> Inputs {
        if let inputs { return await inputs.value }
        let task = Task { [connection, store] in
            async let session = try? connection.send(.gameflowSession)
            async let pickable = try? connection.send(.pickableChampionIDs)
            async let mastery = try? connection.send(.championMastery)
            async let personal = Self.readPersonal(from: store)
            var inputs = await personal
            inputs.masteryPoints = Dictionary(
                (await mastery?.masteries ?? []).map { ($0.champion, $0.points) },
                uniquingKeysWith: max)
            return Inputs(
                queue: await session?.queueType ?? Self.unknownQueue,
                pickable: await pickable ?? [], personal: inputs)
        }
        inputs = task
        return await task.value
    }

    /// A failed read leaves that part empty: the recommendations run without it.
    nonisolated private static func readPersonal(from store: any PersonalStore) async
        -> PersonalInputs
    {
        var pool: [PoolEntry] = []
        for role in Role.allCases {
            pool += (try? await store.pool(for: role)) ?? []
        }
        return PersonalInputs(
            matches: (try? await store.matches(MyMatchQuery())) ?? [], pool: pool,
            overrides: (try? await store.overrides()) ?? [])
    }

    // MARK: Derivations

    struct NoStats: StatsProvider {
        func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }
    }

    private static func inferRoles(of enemies: [DraftSlot], stats: some StatsProvider)
        -> [Int: InferredRole]
    {
        let locked = enemies.filter { $0.role == nil && $0.champion != nil }
        let inferred = RoleInference.infer(
            enemies: locked.compactMap(\.champion),
            takenRoles: Set(enemies.compactMap(\.role)),
            stats: stats)
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
