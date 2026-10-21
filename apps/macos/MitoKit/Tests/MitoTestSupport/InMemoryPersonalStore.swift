public import MitoCore

/// A `PersonalStore` without a database, with the protocol's ordering and replacement rules.
/// With `failure` set, every operation throws it and changes nothing.
public actor InMemoryPersonalStore: PersonalStore {
    public var failure: PersonalStoreError?
    private var matchesByGame: [GameID: MyMatch] = [:]
    private var poolByRole: [Role: [PoolEntry]] = [:]
    private var overridesByKey: [OverrideKey: ChampionOverride] = [:]
    private var log: [ImportLogEntry] = []

    private struct OverrideKey: Hashable {
        let champion: ChampionID
        let role: Role
    }

    public init(
        matches: [MyMatch] = [],
        overrides: [ChampionOverride] = [],
        importLog: [ImportLogEntry] = [],
        failure: PersonalStoreError? = nil
    ) {
        for match in matches { matchesByGame[match.game] = match }
        for override in overrides {
            overridesByKey[OverrideKey(champion: override.champion, role: override.role)] = override
        }
        log = importLog
        self.failure = failure
    }

    public func setFailure(_ failure: PersonalStoreError?) {
        self.failure = failure
    }

    public func record(_ matches: [MyMatch]) throws(PersonalStoreError) {
        try check()
        for match in matches { matchesByGame[match.game] = match }
    }

    public func matches(_ query: MyMatchQuery) throws(PersonalStoreError) -> [MyMatch] {
        try check()
        let matching = matchesByGame.values
            .filter { match in
                (query.champion.map { $0 == match.champion } ?? true)
                    && (query.role.map { $0 == match.role } ?? true)
                    && (query.patch.map { $0 == match.patch } ?? true)
            }
            .sorted { ($0.playedAt, $0.game.rawValue) > ($1.playedAt, $1.game.rawValue) }
        return query.limit.map { Array(matching.prefix(max(0, $0))) } ?? matching
    }

    public func pool(for role: Role) throws(PersonalStoreError) -> [PoolEntry] {
        try check()
        return poolByRole[role] ?? []
    }

    public func setPool(_ champions: [ChampionID], for role: Role) throws(PersonalStoreError) {
        try check()
        var seen: Set<ChampionID> = []
        poolByRole[role] = champions.filter { seen.insert($0).inserted }.enumerated().map {
            PoolEntry(role: role, champion: $0.element, priority: $0.offset)
        }
    }

    public func overrides() throws(PersonalStoreError) -> [ChampionOverride] {
        try check()
        let roleOrder = Role.allCases
        return overridesByKey.values.sorted {
            ($0.champion.rawValue, roleOrder.firstIndex(of: $0.role) ?? 0)
                < ($1.champion.rawValue, roleOrder.firstIndex(of: $1.role) ?? 0)
        }
    }

    public func save(_ override: ChampionOverride) throws(PersonalStoreError) {
        try check()
        overridesByKey[OverrideKey(champion: override.champion, role: override.role)] = override
    }

    public func deleteOverride(champion: ChampionID, role: Role) throws(PersonalStoreError) {
        try check()
        overridesByKey[OverrideKey(champion: champion, role: role)] = nil
    }

    public func appendImportLog(_ entry: ImportLogEntry) throws(PersonalStoreError) {
        try check()
        log.append(entry)
    }

    public func importLog(limit: Int) throws(PersonalStoreError) -> [ImportLogEntry] {
        try check()
        let newestFirst = log.enumerated()
            .sorted { ($0.element.timestamp, $0.offset) > ($1.element.timestamp, $1.offset) }
            .map(\.element)
        return Array(newestFirst.prefix(max(0, limit)))
    }

    public func deleteAll() throws(PersonalStoreError) {
        try check()
        matchesByGame = [:]
        poolByRole = [:]
        overridesByKey = [:]
        log = []
    }

    private func check() throws(PersonalStoreError) {
        if let failure { throw failure }
    }
}
