import Foundation
import GRDB
import MitoCore
import MitoStore
import Testing

struct PersonalDatabaseTests {
    private typealias Sample = PersonalSamples

    @Test func theFirstOperationMigratesAnEmptyLocationToTheV1Schema() async throws {
        try await withDatabase { store in
            #expect(try await store.overrides().isEmpty)

            let schema = try await raw(store).read { db in
                (
                    migrations: try String.fetchAll(
                        db, sql: "SELECT identifier FROM grdb_migrations"),
                    columns: try Dictionary(
                        uniqueKeysWithValues: [
                            "my_matches", "my_match_participants", "champion_overrides", "pool",
                            "import_log",
                        ].map { table in (table, try db.columns(in: table).map(\.name)) })
                )
            }
            #expect(schema.migrations == ["v1"])
            #expect(
                schema.columns == [
                    "my_matches": [
                        "game_id", "queue_id", "patch", "played_at", "champion_id", "role", "win",
                        "kills", "deaths", "assists", "cs", "duration_s", "opp_champion_id",
                        "spell1", "spell2", "perks", "items",
                    ],
                    "my_match_participants": [
                        "game_id", "slot", "champion_id", "is_enemy", "role",
                    ],
                    "champion_overrides": [
                        "champion_id", "role", "runes_mode", "fixed_page", "spells_mode",
                        "fixed_spells", "items_mode", "fixed_items", "favorite", "banned_from_pool",
                    ],
                    "pool": ["role", "champion_id", "priority"],
                    "import_log": ["ts", "game_id", "champion_id", "what", "result", "detail"],
                ])
        }
    }

    @Test func aReopenedDatabaseKeepsTheData() async throws {
        try await withTemporaryPersonalBase { base in
            let match = Sample.match(game: 7_100_000_001)
            let entry = Sample.logEntry(at: 1_760_000_000_456)
            let first = PersonalDatabase(
                bundleIdentifier: Sample.bundleIdentifier, baseDirectory: base)
            try await first.record([match])
            try await first.setPool([ChampionID(rawValue: 103)], for: .middle)
            try await first.save(Sample.fullOverride)
            try await first.appendImportLog(entry)

            let reopened = PersonalDatabase(
                bundleIdentifier: Sample.bundleIdentifier, baseDirectory: base)
            #expect(try await reopened.matches(MyMatchQuery()) == [match])
            #expect(
                try await reopened.pool(for: .middle) == [
                    PoolEntry(role: .middle, champion: ChampionID(rawValue: 103), priority: 0)
                ])
            #expect(try await reopened.overrides() == [Sample.fullOverride])
            #expect(try await reopened.importLog(limit: 1) == [entry])
        }
    }

    @Test func encodedColumnsHoldThePinnedJSONAndRoundTrip() async throws {
        try await withDatabase { store in
            let match = Sample.match(game: 7_100_000_001)
            try await store.record([match])
            try await store.save(Sample.fullOverride)

            let stored = try await raw(store).read { db in
                try Dictionary(
                    uniqueKeysWithValues: [
                        ("my_matches", "played_at"), ("my_matches", "role"),
                        ("my_matches", "perks"),
                        ("my_matches", "items"), ("champion_overrides", "role"),
                        ("champion_overrides", "runes_mode"), ("champion_overrides", "fixed_page"),
                        ("champion_overrides", "spells_mode"),
                        ("champion_overrides", "fixed_spells"),
                        ("champion_overrides", "items_mode"), ("champion_overrides", "fixed_items"),
                    ].map { table, column in
                        (
                            "\(table).\(column)",
                            try String.fetchOne(
                                db, sql: "SELECT CAST(\(column) AS TEXT) FROM \(table)")
                        )
                    })
            }
            #expect(
                stored == [
                    "my_matches.played_at": "1760000000123",
                    "my_matches.role": "MIDDLE",
                    "my_matches.perks": "[8112,8139,8138,8135,8226,8210,5008,5008,5011]",
                    "my_matches.items": "[3089,3157,3020,4645]",
                    "champion_overrides.role": "MIDDLE",
                    "champion_overrides.runes_mode": "fixed",
                    "champion_overrides.fixed_page":
                        #"{"perks":[8112,8139,8138,8135,8226,8210,5008,5008,5011],"primaryStyle":8100,"subStyle":8200}"#,
                    "champion_overrides.spells_mode": "fixed",
                    "champion_overrides.fixed_spells": "[4,14]",
                    "champion_overrides.items_mode": "fixed_set",
                    "champion_overrides.fixed_items":
                        #"{"blocks":[{"items":[{"count":1,"id":1056},{"count":2,"id":2003}],"title":"Start"},{"items":[{"count":1,"id":6655}],"title":"Core"}]}"#,
                ])

            #expect(try await store.matches(MyMatchQuery()) == [match])
            #expect(try await store.overrides() == [Sample.fullOverride])
        }
    }

    @Test func anOverrideWithoutFixedChoicesStoresNulls() async throws {
        try await withDatabase { store in
            let plain = ChampionOverride(champion: ChampionID(rawValue: 103), role: .middle)
            try await store.save(plain)

            let nulls = try await raw(store).read { db in
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM champion_overrides WHERE fixed_page IS NULL
                        AND fixed_spells IS NULL AND fixed_items IS NULL
                        """)
            }
            #expect(nulls == 1)
            #expect(try await store.overrides() == [plain])
        }
    }

    @Test func unknownModeStringsLoadAsUnknown() async throws {
        try await withDatabase { store in
            #expect(try await store.overrides().isEmpty)
            try await raw(store).write { db in
                try db.execute(
                    sql: """
                        INSERT INTO champion_overrides VALUES
                            (103, 'MIDDLE', 'by_opponent', NULL, 'smart', NULL, 'mirror', NULL, 0, 0)
                        """)
                try db.execute(
                    sql:
                        "INSERT INTO import_log VALUES (1000, NULL, 103, 'skills', 'deferred', NULL)"
                )
            }

            let loaded = try #require(try await store.overrides().first)
            #expect(loaded.runeMode == .unknown("by_opponent"))
            #expect(loaded.spellMode == .unknown("smart"))
            #expect(loaded.itemMode == .unknown("mirror"))
            let entry = try #require(try await store.importLog(limit: 1).first)
            #expect(entry.part == .unknown("skills"))
            #expect(entry.outcome == .unknown("deferred"))
        }
    }

    @Test func aRowOutsideTheEncodingFailsTheReadWithReadFailed() async throws {
        try await withDatabase { store in
            #expect(try await store.overrides().isEmpty)
            try await raw(store).write { db in
                try db.execute(
                    sql: """
                        INSERT INTO champion_overrides VALUES
                            (103, 'MIDDLE', 'fixed', '{"perks":', 'recommended', NULL,
                            'recommended', NULL, 0, 0)
                        """)
            }

            await #expect(throws: PersonalStoreError.readFailed) { try await store.overrides() }
        }
    }

    @Test func deleteAllRollsBackEveryTableWhenOneDeleteFails() async throws {
        try await withDatabase { store in
            try await store.record([Sample.match(game: 1)])
            try await store.setPool([ChampionID(rawValue: 103)], for: .middle)
            try await store.save(Sample.fullOverride)
            try await store.appendImportLog(Sample.logEntry(at: 1_000))
            try await raw(store).write { db in
                try db.execute(
                    sql: """
                        CREATE TRIGGER keep_log BEFORE DELETE ON import_log
                        BEGIN SELECT RAISE(ABORT, 'blocked'); END
                        """)
            }

            await #expect(throws: PersonalStoreError.writeFailed) { try await store.deleteAll() }

            #expect(try await store.matches(MyMatchQuery()) == [Sample.match(game: 1)])
            #expect(try await store.pool(for: .middle).count == 1)
            #expect(try await store.overrides() == [Sample.fullOverride])
            #expect(try await store.importLog(limit: 10).count == 1)
        }
    }

    @Test func eachBundleIdentifierGetsItsOwnFile() async throws {
        try await withTemporaryPersonalBase { base in
            let release = PersonalDatabase(
                bundleIdentifier: "com.joacominatel.mito", baseDirectory: base)
            let debug = PersonalDatabase(
                bundleIdentifier: "com.joacominatel.mito.debug", baseDirectory: base)

            try await debug.setPool([ChampionID(rawValue: 103)], for: .middle)

            #expect(
                debug.fileURL == base.appending(path: "com.joacominatel.mito.debug/personal.sqlite")
            )
            #expect(
                release.fileURL == base.appending(path: "com.joacominatel.mito/personal.sqlite"))
            #expect(try await release.pool(for: .middle).isEmpty)
            #expect(try await debug.pool(for: .middle).count == 1)
        }
    }

    @Test func aMissingBundleIdentifierFallsBackToTheReleaseIdentifier() {
        let base = URL(filePath: "/base", directoryHint: .isDirectory)
        let store = PersonalDatabase(bundleIdentifier: nil, baseDirectory: base)
        #expect(store.fileURL == base.appending(path: "com.joacominatel.mito/personal.sqlite"))
    }

    @Test func anUnwritableLocationReportsTheFailedOperationsKind() async throws {
        try await withTemporaryPersonalBase { base in
            let blocker = base.appending(path: "blocker", directoryHint: .notDirectory)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            try Data("not a directory".utf8).write(to: blocker)
            let store = PersonalDatabase(
                bundleIdentifier: Sample.bundleIdentifier, baseDirectory: blocker)

            await #expect(throws: PersonalStoreError.writeFailed) {
                try await store.record([Sample.match(game: 1)])
            }
            await #expect(throws: PersonalStoreError.readFailed) {
                try await store.matches(MyMatchQuery())
            }
        }
    }

    private func withDatabase(_ body: (PersonalDatabase) async throws -> Void) async throws {
        try await withTemporaryPersonalBase { base in
            try await body(
                PersonalDatabase(bundleIdentifier: Sample.bundleIdentifier, baseDirectory: base))
        }
    }

    /// A second connection to the store's file, for what the protocol cannot see.
    private func raw(_ store: PersonalDatabase) throws -> DatabaseQueue {
        try DatabaseQueue(path: store.fileURL.path(percentEncoded: false))
    }
}
