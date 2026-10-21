import Foundation
import MitoCore

/// Serves a fixed history, pool, and overrides, counts the history reads, and can hold every
/// read until `release()` so a test can land it late. Writes do nothing.
actor RecommendationTestStore: PersonalStore {
    private let history: [MyMatch]
    private let poolEntries: [PoolEntry]
    private let championOverrides: [ChampionOverride]
    private var isHeld: Bool
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var historyReads = 0

    init(
        matches: [MyMatch] = [], pool: [PoolEntry] = [], overrides: [ChampionOverride] = [],
        held: Bool = false
    ) {
        history = matches
        poolEntries = pool
        championOverrides = overrides
        isHeld = held
    }

    /// Whether a read is parked on the hold.
    var hasWaitingReads: Bool { !waiting.isEmpty }

    func release() {
        isHeld = false
        for continuation in waiting { continuation.resume() }
        waiting = []
    }

    private func gate() async {
        guard isHeld else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func matches(_ query: MyMatchQuery) async throws(PersonalStoreError) -> [MyMatch] {
        historyReads += 1
        await gate()
        return history
    }

    func pool(for role: Role) async throws(PersonalStoreError) -> [PoolEntry] {
        poolEntries.filter { $0.role == role }
    }

    func overrides() async throws(PersonalStoreError) -> [ChampionOverride] { championOverrides }

    func record(_ matches: [MyMatch]) async throws(PersonalStoreError) {}
    func setPool(_ champions: [ChampionID], for role: Role) async throws(PersonalStoreError) {}
    func save(_ override: ChampionOverride) async throws(PersonalStoreError) {}
    func deleteOverride(champion: ChampionID, role: Role) async throws(PersonalStoreError) {}
    func appendImportLog(_ entry: ImportLogEntry) async throws(PersonalStoreError) {}
    func importLog(limit: Int) async throws(PersonalStoreError) -> [ImportLogEntry] { [] }
    func deleteAll() async throws(PersonalStoreError) {}
}

extension MyMatch {
    /// One of the user's games with only what the personal score reads.
    static func played(
        _ champion: Int, role: Role?, win: Bool, id: Int, playedAt: Date = .now
    ) -> MyMatch {
        MyMatch(
            game: GameID(rawValue: id), queue: QueueID(rawValue: 420),
            patch: Patch(rawValue: "16.21"), playedAt: playedAt,
            champion: ChampionID(rawValue: champion), role: role, win: win, kills: 8, deaths: 3,
            assists: 7, cs: 210, durationSeconds: 1800, opponent: nil,
            spells: SpellPair(
                first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
            perks: [], items: [], participants: [])
    }
}
