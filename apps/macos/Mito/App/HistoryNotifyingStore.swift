import MitoCore

/// The personal store, plus a call after each successful `record`: how the shell learns that a
/// history sync landed without reaching into `ProfileModel`.
nonisolated struct HistoryNotifyingStore: PersonalStore {
    let base: any PersonalStore
    let didRecord: @Sendable () async -> Void

    func record(_ matches: [MyMatch]) async throws(PersonalStoreError) {
        try await base.record(matches)
        await didRecord()
    }

    func matches(_ query: MyMatchQuery) async throws(PersonalStoreError) -> [MyMatch] {
        try await base.matches(query)
    }

    func pool(for role: Role) async throws(PersonalStoreError) -> [PoolEntry] {
        try await base.pool(for: role)
    }

    func setPool(_ champions: [ChampionID], for role: Role) async throws(PersonalStoreError) {
        try await base.setPool(champions, for: role)
    }

    func overrides() async throws(PersonalStoreError) -> [ChampionOverride] {
        try await base.overrides()
    }

    func save(_ override: ChampionOverride) async throws(PersonalStoreError) {
        try await base.save(override)
    }

    func deleteOverride(champion: ChampionID, role: Role) async throws(PersonalStoreError) {
        try await base.deleteOverride(champion: champion, role: role)
    }

    func appendImportLog(_ entry: ImportLogEntry) async throws(PersonalStoreError) {
        try await base.appendImportLog(entry)
    }

    func importLog(limit: Int) async throws(PersonalStoreError) -> [ImportLogEntry] {
        try await base.importLog(limit: limit)
    }

    func deleteAll() async throws(PersonalStoreError) {
        try await base.deleteAll()
    }
}
