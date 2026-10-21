import Foundation
import MitoAssets
import MitoCore

/// Pools and history in memory; reads and writes fail on demand. Only the pool and history
/// calls are real. `MitoTestSupport` is not linkable from the app tests.
actor PoolTestStore: PersonalStore {
    private var pools: [Role: [ChampionID]]
    private let history: [MyMatch]
    private var failsReads: Bool
    private var failsWrites: Bool
    /// Every `setPool` that succeeded, in order.
    private(set) var saved: [(role: Role, champions: [ChampionID])] = []
    private(set) var lastQuery: MyMatchQuery?

    init(
        pools: [Role: [ChampionID]] = [:], history: [MyMatch] = [], failsReads: Bool = false,
        failsWrites: Bool = false
    ) {
        self.pools = pools
        self.history = history
        self.failsReads = failsReads
        self.failsWrites = failsWrites
    }

    func failWrites() { failsWrites = true }

    func stored(_ role: Role) -> [ChampionID] { pools[role] ?? [] }

    /// Out of order on purpose: the model must sort by priority.
    func pool(for role: Role) throws(PersonalStoreError) -> [PoolEntry] {
        if failsReads { throw .readFailed }
        return (pools[role] ?? []).enumerated()
            .map { PoolEntry(role: role, champion: $1, priority: $0) }
            .reversed()
    }

    func setPool(_ champions: [ChampionID], for role: Role) throws(PersonalStoreError) {
        if failsWrites { throw .writeFailed }
        var seen: Set<ChampionID> = []
        let unique = champions.filter { seen.insert($0).inserted }
        pools[role] = unique
        saved.append((role, unique))
    }

    func matches(_ query: MyMatchQuery) throws(PersonalStoreError) -> [MyMatch] {
        if failsReads { throw .readFailed }
        lastQuery = query
        let newest = history.sorted {
            ($0.playedAt, $0.game.rawValue) > ($1.playedAt, $1.game.rawValue)
        }
        return query.limit.map { Array(newest.prefix(max(0, $0))) } ?? newest
    }

    func record(_ matches: [MyMatch]) {}
    func overrides() -> [ChampionOverride] { [] }
    func save(_ override: ChampionOverride) {}
    func deleteOverride(champion: ChampionID, role: Role) {}
    func appendImportLog(_ entry: ImportLogEntry) {}
    func importLog(limit: Int) -> [ImportLogEntry] { [] }
    func deleteAll() { pools = [:] }
}

enum OnboardingFixture {
    static let ahri = ChampionID(rawValue: 103)
    static let annie = ChampionID(rawValue: 1)
    static let zed = ChampionID(rawValue: 238)
    static let flash = SummonerSpellID(rawValue: 4)
    static let ignite = SummonerSpellID(rawValue: 14)
    static let teleport = SummonerSpellID(rawValue: 12)

    /// The shared data as the client sends it: the `-1` placeholder first, then out of name order.
    static let gameData = GameData(champions: [
        Champion(id: ChampionID(rawValue: -1), alias: "None", name: "None", iconPath: ""),
        Champion(id: annie, alias: "Annie", name: "Annie", iconPath: ""),
        Champion(id: ahri, alias: "Ahri", name: "Ahri", iconPath: ""),
    ])

    static func game(_ id: Int, spells: SpellPair, playedAt: Date = .init(timeIntervalSince1970: 0))
        -> MyMatch
    {
        MyMatch(
            game: GameID(rawValue: id), queue: QueueID(rawValue: 420),
            patch: Patch(rawValue: "16.21"), playedAt: playedAt,
            champion: ahri, role: .middle, win: true, kills: 0, deaths: 0, assists: 0, cs: 0,
            durationSeconds: 0, opponent: nil, spells: spells, perks: [], items: [],
            participants: [])
    }

    /// `d` games with Flash on D, `f` with it on F, and `without` with no Flash, newest first.
    static func history(d: Int, f: Int, without: Int = 0) -> [MyMatch] {
        let onD = (0..<d).map { (id: $0, spells: SpellPair(first: flash, second: ignite)) }
        let onF = (0..<f).map { (id: 100 + $0, spells: SpellPair(first: ignite, second: flash)) }
        let none = (0..<without).map {
            (id: 200 + $0, spells: SpellPair(first: teleport, second: ignite))
        }
        return (onD + onF + none).enumerated().map { index, entry in
            game(
                entry.id, spells: entry.spells,
                playedAt: Date(timeIntervalSince1970: 1_000_000 - Double(index) * 3_600))
        }
    }
}
