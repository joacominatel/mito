import Foundation
import Testing

/// Pins `fixtures/snapshot/schema.sql` to the tables `MitoStore/Snapshot/` reads
/// (`MITO_CONTEXT.md` §17), so neither side changes without the other.
struct ContractPinTests {
    /// Every column of each table the reader queries. Schema 1, pinned in P6-02.
    private static let pinnedTables: [String: [String]] = [
        "meta": ["key", "value"],
        "champion_roles": ["champion_id", "role", "games"],
        "champ_role_stats": [
            "champion_id", "role", "games", "wins", "kills", "deaths", "assists", "cs", "minutes",
        ],
        "champion_profiles": [
            "champion_id", "role", "phys_share", "magic_share", "true_share", "dmg_per_min",
            "tankiness", "cc_score", "tl_games", "gold_diff_15", "lvl6_s", "item1_s", "item2_s",
            "item3_s",
        ],
        "rune_page_defs": [
            "page_id", "primary_style", "sub_style", "perk1", "perk2", "perk3", "perk4", "perk5",
            "perk6", "shard_offense", "shard_flex", "shard_defense",
        ],
        "rune_pages": ["champion_id", "role", "opp_id", "page_id", "games", "wins"],
        "spell_pairs": ["champion_id", "role", "opp_id", "spell_a", "spell_b", "games", "wins"],
        "item_builds": [
            "champion_id", "role", "opp_id", "layer", "item1", "item2", "item3", "games", "wins",
        ],
        "skill_orders": ["champion_id", "role", "max_order", "sequence", "games", "wins"],
    ]

    @Test func theFixtureSchemaMatchesThePinnedReaderTables() throws {
        let schema = try Self.fixtureSchema()
        for (table, columns) in Self.pinnedTables.sorted(by: { $0.key < $1.key }) {
            #expect(
                schema[table] == columns,
                """
                fixtures/snapshot/schema.sql has \(table) as \(schema[table] ?? []), pinned as \
                \(columns). The snapshot contract changed: bump schema_version, update \
                MitoStore/Snapshot/ and §17 with it, then this pin.
                """)
        }
    }

    @Test func theReaderQueriesExactlyThePinnedTables() throws {
        let tree = try SourceTree()
        let files = try tree.swiftFiles(in: tree.target("MitoStore").appending(path: "Snapshot"))
        #expect(!files.isEmpty, "no sources under MitoStore/Snapshot")
        let reference = #/\b(?:FROM|JOIN)\s+(\w+)/#
        let queried = Set(
            files.flatMap { file in file.code.matches(of: reference).map { String($0.1) } })
        #expect(
            queried == Set(Self.pinnedTables.keys),
            """
            MitoStore/Snapshot queries \(queried.sorted()), pinned \
            \(Self.pinnedTables.keys.sorted()). Pin every table the reader reads, and only those.
            """)
    }

    private static func fixtureSchema() throws -> [String: [String]] {
        let url = try SourceTree().packageRoot
            .deletingLastPathComponent()  // macos/
            .deletingLastPathComponent()  // apps/
            .deletingLastPathComponent()  // repository root
            .appending(path: "fixtures/snapshot/schema.sql")
        let header = #/^CREATE TABLE (\w+) \($/#
        var tables: [String: [String]] = [:]
        var current: String?
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let match = try header.wholeMatch(in: trimmed) {
                current = String(match.1)
                tables[String(match.1)] = []
            } else if trimmed.hasPrefix(")") {
                current = nil
            } else if let table = current, let name = trimmed.split(separator: " ").first,
                name != "PRIMARY"
            {
                tables[table, default: []].append(String(name))
            }
        }
        return tables
    }
}
