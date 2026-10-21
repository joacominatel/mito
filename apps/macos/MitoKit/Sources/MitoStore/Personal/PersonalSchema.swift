import GRDB

/// The `MITO_CONTEXT.md` §17 "Base personal" schema. Migrations only append: a shipped one is
/// never edited.
enum PersonalSchema {
    static let tables = [
        "my_matches", "my_match_participants", "champion_overrides", "pool", "import_log",
    ]

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(
                sql: """
                    CREATE TABLE my_matches (
                      game_id INTEGER PRIMARY KEY, queue_id INTEGER, patch TEXT, played_at INTEGER,
                      champion_id INTEGER, role TEXT, win INTEGER,
                      kills INTEGER, deaths INTEGER, assists INTEGER, cs INTEGER, duration_s INTEGER,
                      opp_champion_id INTEGER,
                      spell1 INTEGER, spell2 INTEGER, perks TEXT, items TEXT
                    );

                    CREATE TABLE my_match_participants (
                      game_id INTEGER NOT NULL, slot INTEGER NOT NULL,
                      champion_id INTEGER NOT NULL, is_enemy INTEGER NOT NULL, role TEXT,
                      PRIMARY KEY (game_id, slot)
                    );

                    CREATE TABLE champion_overrides (
                      champion_id INTEGER, role TEXT,
                      runes_mode TEXT, fixed_page TEXT,
                      spells_mode TEXT, fixed_spells TEXT,
                      items_mode TEXT, fixed_items TEXT,
                      favorite INTEGER, banned_from_pool INTEGER,
                      PRIMARY KEY (champion_id, role)
                    );

                    CREATE TABLE pool (
                      role TEXT, champion_id INTEGER, priority INTEGER,
                      PRIMARY KEY (role, champion_id)
                    );

                    CREATE TABLE import_log (
                      ts INTEGER, game_id INTEGER, champion_id INTEGER, what TEXT, result TEXT, detail TEXT
                    );
                    """)
        }
        return migrator
    }
}
