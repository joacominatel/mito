import MitoCore

/// Serves fixed overrides and keeps every `import_log` entry; the rest is inert. `MitoTestSupport`
/// is not linkable from the app tests.
actor ImportTestStore: PersonalStore {
    private let stored: [ChampionOverride]
    private(set) var log: [ImportLogEntry] = []

    init(overrides: [ChampionOverride] = []) {
        stored = overrides
    }

    func overrides() -> [ChampionOverride] { stored }
    func appendImportLog(_ entry: ImportLogEntry) { log.append(entry) }

    func record(_ matches: [MyMatch]) {}
    func matches(_ query: MyMatchQuery) -> [MyMatch] { [] }
    func pool(for role: Role) -> [PoolEntry] { [] }
    func setPool(_ champions: [ChampionID], for role: Role) {}
    func save(_ override: ChampionOverride) {}
    func deleteOverride(champion: ChampionID, role: Role) {}
    func importLog(limit: Int) -> [ImportLogEntry] { Array(log.suffix(limit).reversed()) }
    func deleteAll() { log = [] }
}
