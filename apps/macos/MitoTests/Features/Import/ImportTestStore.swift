import MitoCore

/// Serves fixed overrides and keeps every `import_log` entry, with the protocol's order and
/// upsert rules; the rest is inert. `MitoTestSupport` is not linkable from the app tests.
actor ImportTestStore: PersonalStore {
    private let stored: [ChampionOverride]
    private(set) var log: [ImportLogEntry] = []

    /// A repeated (champion, role) keeps the last one, as `save` would have left it.
    init(overrides: [ChampionOverride] = []) {
        let roles = Role.allCases
        var byKey: [String: ChampionOverride] = [:]
        for override in overrides {
            byKey["\(override.champion.rawValue)-\(override.role.rawValue)"] = override
        }
        stored = byKey.values.sorted {
            ($0.champion.rawValue, roles.firstIndex(of: $0.role) ?? 0)
                < ($1.champion.rawValue, roles.firstIndex(of: $1.role) ?? 0)
        }
    }

    func overrides() -> [ChampionOverride] { stored }
    func appendImportLog(_ entry: ImportLogEntry) { log.append(entry) }

    func record(_ matches: [MyMatch]) {}
    func matches(_ query: MyMatchQuery) -> [MyMatch] { [] }
    func pool(for role: Role) -> [PoolEntry] { [] }
    func setPool(_ champions: [ChampionID], for role: Role) {}
    func save(_ override: ChampionOverride) {}
    func deleteOverride(champion: ChampionID, role: Role) {}

    func importLog(limit: Int) -> [ImportLogEntry] {
        let newestFirst = log.enumerated()
            .sorted { ($0.element.timestamp, $0.offset) > ($1.element.timestamp, $1.offset) }
            .map(\.element)
        return Array(newestFirst.prefix(max(0, limit)))
    }

    func deleteAll() { log = [] }
}
