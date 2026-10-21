public import Foundation
import GRDB
public import MitoCore
import os

/// The installed snapshot (`MITO_CONTEXT.md` §17), loaded whole into memory at open so champ
/// select never waits on a query (§18.10). The file is opened read-only and closed before
/// `init` returns. Candidates come most played first.
public struct SnapshotReader: StatsProvider {
    public static let supportedSchemaVersions: ClosedRange<Int> = 1...1

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SettingsStore.fallbackBundleIdentifier,
        category: "MitoStore")

    private let openMeta: SnapshotMeta
    private let roleGamesByChampion: [ChampionID: [Role: Int]]
    private let statsByRole: [Role: [ChampionID: ChampionRoleStats]]
    private let loadouts: [ChampionRole: Loadouts]

    /// Reads the whole file, so call it off the main actor; `fileURL` is
    /// `InstalledSnapshot.fileURL`.
    public init(fileURL: URL) throws(SnapshotReadError) {
        do {
            self = try Self.load(fileURL)
        } catch {
            Self.logger.error("Snapshot not opened: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    public var meta: SnapshotMeta? { openMeta }

    public func roleGames(for champion: ChampionID) -> [Role: Int] {
        roleGamesByChampion[champion] ?? [:]
    }

    public func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
        statsByRole[role] ?? [:]
    }

    public func runePages(for champion: ChampionID, role: Role) -> [RunePageCandidate] {
        loadouts[ChampionRole(champion: champion, role: role)]?.runePages ?? []
    }

    public func spellPairs(for champion: ChampionID, role: Role) -> [SpellPairCandidate] {
        loadouts[ChampionRole(champion: champion, role: role)]?.spellPairs ?? []
    }

    public func itemBuilds(for champion: ChampionID, role: Role) -> [ItemBuildCandidate] {
        loadouts[ChampionRole(champion: champion, role: role)]?.itemBuilds ?? []
    }

    public func skillOrders(for champion: ChampionID, role: Role) -> [SkillOrderCandidate] {
        loadouts[ChampionRole(champion: champion, role: role)]?.skillOrders ?? []
    }
}

extension SnapshotReader {
    private struct ChampionRole: Hashable {
        let champion: ChampionID
        let role: Role
    }

    private struct Loadouts {
        var runePages: [RunePageCandidate] = []
        var spellPairs: [SpellPairCandidate] = []
        var itemBuilds: [ItemBuildCandidate] = []
        var skillOrders: [SkillOrderCandidate] = []
    }

    /// A value outside the §17 encoding; reported as `malformedTable`.
    private struct OutOfContract: Error {}

    private init(
        meta: SnapshotMeta,
        roleGames: [ChampionID: [Role: Int]],
        stats: [Role: [ChampionID: ChampionRoleStats]],
        loadouts: [ChampionRole: Loadouts]
    ) {
        openMeta = meta
        roleGamesByChampion = roleGames
        statsByRole = stats
        self.loadouts = loadouts
    }

    private static func load(_ fileURL: URL) throws(SnapshotReadError) -> SnapshotReader {
        var configuration = Configuration()
        configuration.readonly = true
        let result: Result<SnapshotReader, SnapshotReadError>
        do {
            let queue = try DatabaseQueue(
                path: fileURL.path(percentEncoded: false), configuration: configuration)
            result = try queue.read { db in
                Result { () throws(SnapshotReadError) in try read(db) }
            }
        } catch {
            throw .unreadable
        }
        return try result.get()
    }

    private static func read(_ db: Database) throws(SnapshotReadError) -> SnapshotReader {
        let meta = try readMeta(db)

        var roleGames: [ChampionID: [Role: Int]] = [:]
        try each(db, "champion_roles", "SELECT champion_id, role, games FROM champion_roles") {
            row in
            roleGames[try champion(row), default: [:]][try role(row)] = try row.decode(
                forColumn: "games")
        }

        var stats: [Role: [ChampionID: ChampionRoleStats]] = [:]
        try each(
            db, "champ_role_stats",
            """
            SELECT s.champion_id, s.role, s.games, s.wins, COALESCE(p.tl_games, 0) AS tl_games
            FROM champ_role_stats s
            LEFT JOIN champion_profiles p ON p.champion_id = s.champion_id AND p.role = s.role
            """
        ) { row in
            stats[try role(row), default: [:]][try champion(row)] = ChampionRoleStats(
                games: try row.decode(forColumn: "games"),
                wins: try row.decode(forColumn: "wins"),
                timelineGames: try row.decode(forColumn: "tl_games"))
        }

        var loadouts: [ChampionRole: Loadouts] = [:]
        try each(
            db, "rune_pages",
            """
            SELECT r.champion_id, r.role, r.games, r.wins, d.primary_style, d.sub_style,
                d.perk1, d.perk2, d.perk3, d.perk4, d.perk5, d.perk6,
                d.shard_offense, d.shard_flex, d.shard_defense
            FROM rune_pages r JOIN rune_page_defs d ON d.page_id = r.page_id
            WHERE r.opp_id = 0
            ORDER BY r.games DESC, r.page_id
            """
        ) { row in
            let perkColumns = [
                "perk1", "perk2", "perk3", "perk4", "perk5", "perk6", "shard_offense",
                "shard_flex", "shard_defense",
            ]
            let page = RunePage(
                primaryStyle: PerkStyleID(rawValue: try row.decode(forColumn: "primary_style")),
                subStyle: PerkStyleID(rawValue: try row.decode(forColumn: "sub_style")),
                perks: try perkColumns.map { PerkID(rawValue: try row.decode(forColumn: $0)) })
            loadouts[try key(row), default: Loadouts()].runePages.append(
                RunePageCandidate(
                    page: page, games: try row.decode(forColumn: "games"),
                    wins: try row.decode(forColumn: "wins")))
        }

        try each(
            db, "spell_pairs",
            """
            SELECT champion_id, role, spell_a, spell_b, games, wins FROM spell_pairs
            WHERE opp_id = 0 ORDER BY games DESC, spell_a, spell_b
            """
        ) { row in
            let a: Int = try row.decode(forColumn: "spell_a")
            let b: Int = try row.decode(forColumn: "spell_b")
            loadouts[try key(row), default: Loadouts()].spellPairs.append(
                SpellPairCandidate(
                    spellA: SummonerSpellID(rawValue: min(a, b)),
                    spellB: SummonerSpellID(rawValue: max(a, b)),
                    games: try row.decode(forColumn: "games"),
                    wins: try row.decode(forColumn: "wins")))
        }

        try each(
            db, "item_builds",
            """
            SELECT champion_id, role, layer, item1, item2, item3, games, wins FROM item_builds
            WHERE opp_id = 0 ORDER BY games DESC, layer, item1, item2, item3
            """
        ) { row in
            guard let layer = BuildLayer(rawValue: try row.decode(forColumn: "layer")) else {
                throw OutOfContract()
            }
            let items = try ["item1", "item2", "item3"]
                .map { column -> Int in try row.decode(forColumn: column) }
                .filter { $0 != 0 }
                .map(ItemID.init(rawValue:))
            loadouts[try key(row), default: Loadouts()].itemBuilds.append(
                ItemBuildCandidate(
                    layer: layer, items: items, games: try row.decode(forColumn: "games"),
                    wins: try row.decode(forColumn: "wins")))
        }

        try each(
            db, "skill_orders",
            """
            SELECT champion_id, role, max_order, sequence, games, wins FROM skill_orders
            ORDER BY games DESC, max_order
            """
        ) { row in
            let order = SkillOrder(
                maxOrder: try abilities(row.decode(forColumn: "max_order")),
                sequence: try abilities(row.decode(forColumn: "sequence")))
            loadouts[try key(row), default: Loadouts()].skillOrders.append(
                SkillOrderCandidate(
                    order: order, games: try row.decode(forColumn: "games"),
                    wins: try row.decode(forColumn: "wins")))
        }

        return SnapshotReader(meta: meta, roleGames: roleGames, stats: stats, loadouts: loadouts)
    }

    private static func readMeta(_ db: Database) throws(SnapshotReadError) -> SnapshotMeta {
        var values: [String: String] = [:]
        do {
            for row in try Row.fetchAll(db, sql: "SELECT key, value FROM meta") {
                values[try row.decode(forColumn: "key")] = try row.decode(forColumn: "value")
            }
        } catch {
            throw .unreadable
        }
        guard values["schema_version"] != nil else { throw .missingMetaKey("schema_version") }
        let version = try SnapshotMeta.integer(values, "schema_version")
        guard supportedSchemaVersions.contains(version) else {
            throw .unsupportedSchemaVersion(version)
        }
        return try SnapshotMeta(values: values)
    }

    private static func each(
        _ db: Database, _ table: String, _ sql: String, _ body: (Row) throws -> Void
    ) throws(SnapshotReadError) {
        do {
            let rows = try Row.fetchCursor(db, sql: sql)
            while let row = try rows.next() { try body(row) }
        } catch {
            throw .malformedTable(table)
        }
    }

    private static func champion(_ row: Row) throws -> ChampionID {
        ChampionID(rawValue: try row.decode(forColumn: "champion_id"))
    }

    private static func role(_ row: Row) throws -> Role {
        guard let role = Role(rawValue: try row.decode(forColumn: "role")) else {
            throw OutOfContract()
        }
        return role
    }

    private static func key(_ row: Row) throws -> ChampionRole {
        ChampionRole(champion: try champion(row), role: try role(row))
    }

    private static func abilities(_ letters: String) throws -> [SkillOrder.Ability] {
        try letters.map { letter in
            guard let ability = SkillOrder.Ability(rawValue: String(letter)) else {
                throw OutOfContract()
            }
            return ability
        }
    }
}
