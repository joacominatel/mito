import MitoCore
import MitoStore

/// The stand-in for `PersonalDatabase` in tests and previews: no file, every call fails.
nonisolated struct UnavailablePersonalStore: PersonalStore {
    /// The real database, or this stand-in under XCTest so no test opens the user's file.
    static func live(underTest: Bool) -> any PersonalStore {
        underTest ? UnavailablePersonalStore() : PersonalDatabase()
    }

    func record(_ matches: [MyMatch]) async throws(PersonalStoreError) { throw .writeFailed }

    func matches(_ query: MyMatchQuery) async throws(PersonalStoreError) -> [MyMatch] {
        throw .readFailed
    }

    func pool(for role: Role) async throws(PersonalStoreError) -> [PoolEntry] {
        throw .readFailed
    }

    func setPool(_ champions: [ChampionID], for role: Role) async throws(PersonalStoreError) {
        throw .writeFailed
    }

    func overrides() async throws(PersonalStoreError) -> [ChampionOverride] { throw .readFailed }

    func save(_ override: ChampionOverride) async throws(PersonalStoreError) { throw .writeFailed }

    func deleteOverride(champion: ChampionID, role: Role) async throws(PersonalStoreError) {
        throw .writeFailed
    }

    func appendImportLog(_ entry: ImportLogEntry) async throws(PersonalStoreError) {
        throw .writeFailed
    }

    func importLog(limit: Int) async throws(PersonalStoreError) -> [ImportLogEntry] {
        throw .readFailed
    }

    func deleteAll() async throws(PersonalStoreError) { throw .writeFailed }
}
