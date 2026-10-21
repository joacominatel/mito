public enum PersonalStoreError: Error, Equatable, Sendable {
    case readFailed
    case writeFailed
}

/// The local read-write personal database (`MITO_CONTEXT.md` §17, "Base personal"). It never
/// leaves the Mac (§25).
public protocol PersonalStore: Sendable {
    /// Inserts or replaces each game by its ID, participants included.
    func record(_ matches: [MyMatch]) async throws(PersonalStoreError)

    /// Newest first.
    func matches(_ query: MyMatchQuery) async throws(PersonalStoreError) -> [MyMatch]

    /// Ordered by priority.
    func pool(for role: Role) async throws(PersonalStoreError) -> [PoolEntry]

    /// Replaces the role's pool; the order is the priority and a repeated champion keeps its
    /// first position.
    func setPool(_ champions: [ChampionID], for role: Role) async throws(PersonalStoreError)

    /// Ordered by champion ID, then by role.
    func overrides() async throws(PersonalStoreError) -> [ChampionOverride]

    /// Inserts or replaces the override for its (champion, role).
    func save(_ override: ChampionOverride) async throws(PersonalStoreError)

    /// Deleting a missing override is not an error.
    func deleteOverride(champion: ChampionID, role: Role) async throws(PersonalStoreError)

    func appendImportLog(_ entry: ImportLogEntry) async throws(PersonalStoreError)

    /// The most recent `limit` entries, newest first.
    func importLog(limit: Int) async throws(PersonalStoreError) -> [ImportLogEntry]

    /// "Borrar mis datos" (§25): every table, emptied.
    func deleteAll() async throws(PersonalStoreError)
}
