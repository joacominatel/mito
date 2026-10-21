public import Foundation
import GRDB
public import MitoCore
import os

/// `PersonalStore` on SQLite at `<base>/<bundle id>/personal.sqlite` (`MITO_CONTEXT.md` §17,
/// "Base personal"). The file is opened and migrated on first use, inside the actor, so
/// nothing touches the disk on the caller's actor.
public actor PersonalDatabase: PersonalStore {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SettingsStore.fallbackBundleIdentifier,
        category: "MitoStore")

    public nonisolated let fileURL: URL
    private var queue: DatabaseQueue?

    public init(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        baseDirectory: URL = .applicationSupportDirectory
    ) {
        fileURL =
            baseDirectory
            .appending(
                path: bundleIdentifier ?? SettingsStore.fallbackBundleIdentifier,
                directoryHint: .isDirectory
            )
            .appending(path: "personal.sqlite", directoryHint: .notDirectory)
    }

    public func record(_ matches: [MyMatch]) async throws(PersonalStoreError) {
        try await write { db in
            for match in matches { try PersonalRows.Match.replace(match, in: db) }
        }
    }

    public func matches(_ query: MyMatchQuery) async throws(PersonalStoreError) -> [MyMatch] {
        try await read { db in try PersonalRows.Match.fetch(query, in: db) }
    }

    public func pool(for role: Role) async throws(PersonalStoreError) -> [PoolEntry] {
        try await read { db in
            try Row.fetchAll(
                db, sql: "SELECT champion_id, priority FROM pool WHERE role = ? ORDER BY priority",
                arguments: [role.rawValue]
            ).map { row in
                PoolEntry(
                    role: role,
                    champion: ChampionID(rawValue: try row.decode(forColumn: "champion_id")),
                    priority: try row.decode(forColumn: "priority"))
            }
        }
    }

    public func setPool(_ champions: [ChampionID], for role: Role) async throws(PersonalStoreError)
    {
        var seen: Set<ChampionID> = []
        let unique = champions.filter { seen.insert($0).inserted }
        try await write { db in
            try db.execute(sql: "DELETE FROM pool WHERE role = ?", arguments: [role.rawValue])
            for (priority, champion) in unique.enumerated() {
                try db.execute(
                    sql: "INSERT INTO pool (role, champion_id, priority) VALUES (?, ?, ?)",
                    arguments: [role.rawValue, champion.rawValue, priority])
            }
        }
    }

    public func overrides() async throws(PersonalStoreError) -> [ChampionOverride] {
        let roleOrder = Role.allCases
        return try await read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM champion_overrides")
                .map(PersonalRows.championOverride)
        }.sorted {
            ($0.champion.rawValue, roleOrder.firstIndex(of: $0.role) ?? 0)
                < ($1.champion.rawValue, roleOrder.firstIndex(of: $1.role) ?? 0)
        }
    }

    public func save(_ override: ChampionOverride) async throws(PersonalStoreError) {
        try await write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO champion_overrides (
                        champion_id, role, runes_mode, fixed_page, spells_mode, fixed_spells,
                        items_mode, fixed_items, favorite, banned_from_pool
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: try PersonalRows.arguments(for: override))
        }
    }

    public func deleteOverride(champion: ChampionID, role: Role) async throws(PersonalStoreError) {
        try await write { db in
            try db.execute(
                sql: "DELETE FROM champion_overrides WHERE champion_id = ? AND role = ?",
                arguments: [champion.rawValue, role.rawValue])
        }
    }

    public func appendImportLog(_ entry: ImportLogEntry) async throws(PersonalStoreError) {
        try await write { db in
            try db.execute(
                sql: """
                    INSERT INTO import_log (ts, game_id, champion_id, what, result, detail)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    PersonalRows.milliseconds(entry.timestamp), entry.game?.rawValue,
                    entry.champion.rawValue, entry.part.rawValue, entry.outcome.rawValue,
                    entry.detail,
                ])
        }
    }

    public func importLog(limit: Int) async throws(PersonalStoreError) -> [ImportLogEntry] {
        try await read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM import_log ORDER BY ts DESC, rowid DESC LIMIT ?",
                arguments: [max(0, limit)]
            ).map { row in
                ImportLogEntry(
                    timestamp: PersonalRows.date(milliseconds: try row.decode(forColumn: "ts")),
                    game: (try row.decode(Int?.self, forColumn: "game_id")).map(GameID.init),
                    champion: ChampionID(rawValue: try row.decode(forColumn: "champion_id")),
                    part: ImportLogEntry.Part(rawValue: try row.decode(forColumn: "what")),
                    outcome: ImportLogEntry.Outcome(rawValue: try row.decode(forColumn: "result")),
                    detail: try row.decode(forColumn: "detail"))
            }
        }
    }

    public func deleteAll() async throws(PersonalStoreError) {
        try await write { db in
            for table in PersonalSchema.tables {
                try db.execute(sql: "DELETE FROM \(table)")
            }
        }
    }
}

extension PersonalDatabase {
    private enum Access: String {
        case open, read, write
    }

    private func read<T: Sendable>(
        _ body: @escaping @Sendable (Database) throws -> T
    ) async throws(PersonalStoreError) -> T {
        do {
            return try await opened().read(body)
        } catch {
            log(.read, error)
            throw .readFailed
        }
    }

    private func write(
        _ body: @escaping @Sendable (Database) throws -> Void
    ) async throws(PersonalStoreError) {
        do {
            try await opened().write(body)
        } catch {
            log(.write, error)
            throw .writeFailed
        }
    }

    private func opened() throws -> DatabaseQueue {
        if let queue { return queue }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let opened = try DatabaseQueue(path: fileURL.path(percentEncoded: false))
            try PersonalSchema.migrator.migrate(opened)
            queue = opened
            return opened
        } catch {
            log(.open, error)
            throw error
        }
    }

    /// The kind and the SQLite code only: the SQL and its arguments carry personal data.
    private func log(_ access: Access, _ error: any Error) {
        if let error = error as? DatabaseError {
            Self.logger.error(
                "Personal database \(access.rawValue, privacy: .public) failed: SQLite \(error.resultCode.rawValue, privacy: .public)"
            )
        } else {
            Self.logger.error(
                "Personal database \(access.rawValue, privacy: .public) failed: \(String(describing: type(of: error)), privacy: .public)"
            )
        }
    }
}
