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
    private let tables: Tables

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
        tables.roleGames[champion] ?? [:]
    }

    public func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
        tables.stats[role] ?? [:]
    }

    public func runePages(for champion: ChampionID, role: Role) -> [RunePageCandidate] {
        loadouts(champion, role, Self.general).runePages
    }

    public func spellPairs(for champion: ChampionID, role: Role) -> [SpellPairCandidate] {
        loadouts(champion, role, Self.general).spellPairs
    }

    public func itemBuilds(for champion: ChampionID, role: Role) -> [ItemBuildCandidate] {
        loadouts(champion, role, Self.general).itemBuilds
    }

    public func skillOrders(for champion: ChampionID, role: Role) -> [SkillOrderCandidate] {
        loadouts(champion, role, Self.general).skillOrders
    }

    public func matchup(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> MatchupStats?
    {
        tables.matchups[Context(champion, role, opponent)]
    }

    public func synergy(
        for champion: ChampionID, role: Role, with ally: ChampionID, allyRole: Role
    ) -> RelationStats? {
        tables.synergies[Context(champion, role, ChampionRole(champion: ally, role: allyRole))]
    }

    public func versusTeam(for champion: ChampionID, role: Role, against enemy: ChampionID)
        -> RelationStats?
    {
        tables.versusTeam[Context(champion, role, enemy)]
    }

    public func championProfile(for champion: ChampionID, role: Role) -> ChampionProfile? {
        tables.profiles[ChampionRole(champion: champion, role: role)]
    }

    public func profileStats(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> RelationStats?
    {
        tables.profileStats[Context(champion, role, profile)]
    }

    public func runePages(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [RunePageCandidate]
    {
        opponent == Self.general ? [] : loadouts(champion, role, opponent).runePages
    }

    public func spellPairs(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [SpellPairCandidate]
    {
        opponent == Self.general ? [] : loadouts(champion, role, opponent).spellPairs
    }

    public func itemBuilds(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [ItemBuildCandidate]
    {
        opponent == Self.general ? [] : loadouts(champion, role, opponent).itemBuilds
    }

    public func runePages(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> [RunePageCandidate]
    {
        tables.profileRunePages[Context(champion, role, profile)] ?? []
    }

    public func finalItems(for champion: ChampionID, role: Role) -> [FinalItemCandidate] {
        tables.baselineFinalItems[ChampionRole(champion: champion, role: role)] ?? []
    }

    public func finalItems(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> [FinalItemCandidate]
    {
        tables.profileFinalItems[Context(champion, role, profile)] ?? []
    }

    public func bans(of champion: ChampionID) -> Int? {
        tables.bans[champion]
    }

    public func flags(of champion: ChampionID) -> Set<ChampionFlag> {
        tables.flags[champion] ?? []
    }

    private func loadouts(_ champion: ChampionID, _ role: Role, _ opponent: ChampionID)
        -> Loadouts
    {
        tables.loadouts[Context(champion, role, opponent)] ?? Loadouts()
    }
}

extension SnapshotReader {
    /// `opp_id = 0`, the general rows (§17).
    private static let general = ChampionID(rawValue: 0)

    /// The `item_vs_profile.enemy_profile` of the situational baseline, which is not a profile.
    private static let baselineProfile = "any"

    private struct ChampionRole: Hashable, Sendable {
        let champion: ChampionID
        let role: Role
    }

    /// A (champ, role) in one context: a lane opponent, an ally in a role, or an enemy profile.
    private struct Context<Other: Hashable & Sendable>: Hashable, Sendable {
        let subject: ChampionRole
        let other: Other

        init(_ champion: ChampionID, _ role: Role, _ other: Other) {
            subject = ChampionRole(champion: champion, role: role)
            self.other = other
        }
    }

    private struct Loadouts: Sendable {
        var runePages: [RunePageCandidate] = []
        var spellPairs: [SpellPairCandidate] = []
        var itemBuilds: [ItemBuildCandidate] = []
        var skillOrders: [SkillOrderCandidate] = []
    }

    private struct Tables: Sendable {
        var roleGames: [ChampionID: [Role: Int]] = [:]
        var stats: [Role: [ChampionID: ChampionRoleStats]] = [:]
        var profiles: [ChampionRole: ChampionProfile] = [:]
        /// Keyed by `opp_id`; `general` holds the general rows and every skill order.
        var loadouts: [Context<ChampionID>: Loadouts] = [:]
        var matchups: [Context<ChampionID>: MatchupStats] = [:]
        var synergies: [Context<ChampionRole>: RelationStats] = [:]
        var versusTeam: [Context<ChampionID>: RelationStats] = [:]
        var profileStats: [Context<EnemyProfile>: RelationStats] = [:]
        var profileRunePages: [Context<EnemyProfile>: [RunePageCandidate]] = [:]
        var profileFinalItems: [Context<EnemyProfile>: [FinalItemCandidate]] = [:]
        var baselineFinalItems: [ChampionRole: [FinalItemCandidate]] = [:]
        var bans: [ChampionID: Int] = [:]
        var flags: [ChampionID: Set<ChampionFlag>] = [:]
    }

    /// A value outside the §17 encoding; reported as `malformedTable`.
    private struct OutOfContract: Error {}

    private init(meta: SnapshotMeta, tables: Tables) {
        openMeta = meta
        self.tables = tables
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
        var tables = Tables()
        try readChampions(db, into: &tables)
        try readRelations(db, into: &tables)
        try readLoadouts(db, into: &tables)
        try readProfileLoadouts(db, into: &tables)
        return SnapshotReader(meta: meta, tables: tables)
    }

    private static func readChampions(_ db: Database, into tables: inout Tables)
        throws(SnapshotReadError)
    {
        try each(db, "champion_roles", "SELECT champion_id, role, games FROM champion_roles") {
            row in
            tables.roleGames[try champion(row), default: [:]][try role(row)] = try row.decode(
                forColumn: "games")
        }

        try each(
            db, "champion_profiles",
            """
            SELECT champion_id, role, phys_share, magic_share, true_share, dmg_per_min, tankiness,
                cc_score, tl_games, gold_diff_15, lvl6_s, item1_s, item2_s, item3_s
            FROM champion_profiles
            """
        ) { row in
            tables.profiles[try key(row)] = ChampionProfile(
                physicalShare: try row.decode(forColumn: "phys_share"),
                magicShare: try row.decode(forColumn: "magic_share"),
                trueShare: try row.decode(forColumn: "true_share"),
                damagePerMinute: try row.decode(forColumn: "dmg_per_min"),
                tankiness: try row.decode(forColumn: "tankiness"),
                ccScore: try row.decode(forColumn: "cc_score"),
                timelineGames: try row.decode(forColumn: "tl_games"),
                goldDiffAt15: try row.decode(forColumn: "gold_diff_15"),
                levelSixSeconds: try row.decode(forColumn: "lvl6_s"),
                firstItemSeconds: try row.decode(forColumn: "item1_s"),
                secondItemSeconds: try row.decode(forColumn: "item2_s"),
                thirdItemSeconds: try row.decode(forColumn: "item3_s"))
        }

        try each(
            db, "champ_role_stats",
            """
            SELECT champion_id, role, games, wins, kills, deaths, assists, cs, minutes
            FROM champ_role_stats
            """
        ) { [profiles = tables.profiles] row in
            let key = try key(row)
            tables.stats[key.role, default: [:]][key.champion] = ChampionRoleStats(
                games: try row.decode(forColumn: "games"),
                wins: try row.decode(forColumn: "wins"),
                timelineGames: profiles[key]?.timelineGames ?? 0,
                kills: try row.decode(forColumn: "kills"),
                deaths: try row.decode(forColumn: "deaths"),
                assists: try row.decode(forColumn: "assists"),
                cs: try row.decode(forColumn: "cs"),
                minutes: try row.decode(forColumn: "minutes"))
        }

        try each(db, "champ_ban_stats", "SELECT champion_id, bans FROM champ_ban_stats") { row in
            tables.bans[try champion(row)] = try row.decode(forColumn: "bans")
        }

        try each(db, "champion_flags", "SELECT champion_id, flag FROM champion_flags") { row in
            tables.flags[try champion(row), default: []].insert(
                ChampionFlag(rawValue: try row.decode(forColumn: "flag")))
        }
    }

    private static func readRelations(_ db: Database, into tables: inout Tables)
        throws(SnapshotReadError)
    {
        try each(
            db, "matchup_stats",
            """
            SELECT champion_id, role, opp_id, games, wins, tl_games, gold_diff_15, cs_diff_15
            FROM matchup_stats
            """
        ) { row in
            tables.matchups[try opponentKey(row)] = MatchupStats(
                games: try row.decode(forColumn: "games"),
                wins: try row.decode(forColumn: "wins"),
                timelineGames: try row.decode(forColumn: "tl_games"),
                goldDiffAt15: try row.decode(forColumn: "gold_diff_15"),
                csDiffAt15: try row.decode(forColumn: "cs_diff_15"))
        }

        try each(
            db, "synergy_stats",
            "SELECT champion_id, role, ally_id, ally_role, games, wins FROM synergy_stats"
        ) { row in
            let ally = ChampionRole(
                champion: ChampionID(rawValue: try row.decode(forColumn: "ally_id")),
                role: try role(row, column: "ally_role"))
            tables.synergies[Context(try champion(row), try role(row), ally)] = try relation(row)
        }

        try each(
            db, "vs_team_stats",
            "SELECT champion_id, role, enemy_id, games, wins FROM vs_team_stats"
        ) { row in
            let enemy = ChampionID(rawValue: try row.decode(forColumn: "enemy_id"))
            tables.versusTeam[Context(try champion(row), try role(row), enemy)] = try relation(
                row)
        }

        try each(
            db, "champ_vs_profile",
            "SELECT champion_id, role, enemy_profile, games, wins FROM champ_vs_profile"
        ) { row in
            tables.profileStats[try profileKey(row)] = try relation(row)
        }
    }

    private static func readLoadouts(_ db: Database, into tables: inout Tables)
        throws(SnapshotReadError)
    {
        try each(
            db, "rune_pages",
            """
            SELECT r.champion_id, r.role, r.opp_id, r.games, r.wins, \(pageColumns)
            FROM rune_pages r JOIN rune_page_defs d ON d.page_id = r.page_id
            ORDER BY r.games DESC, r.page_id
            """
        ) { row in
            tables.loadouts[try opponentKey(row), default: Loadouts()].runePages.append(
                try runePage(row))
        }

        try each(
            db, "spell_pairs",
            """
            SELECT champion_id, role, opp_id, spell_a, spell_b, games, wins FROM spell_pairs
            ORDER BY games DESC, spell_a, spell_b
            """
        ) { row in
            let a: Int = try row.decode(forColumn: "spell_a")
            let b: Int = try row.decode(forColumn: "spell_b")
            tables.loadouts[try opponentKey(row), default: Loadouts()].spellPairs.append(
                SpellPairCandidate(
                    spellA: SummonerSpellID(rawValue: min(a, b)),
                    spellB: SummonerSpellID(rawValue: max(a, b)),
                    games: try row.decode(forColumn: "games"),
                    wins: try row.decode(forColumn: "wins")))
        }

        try each(
            db, "item_builds",
            """
            SELECT champion_id, role, opp_id, layer, item1, item2, item3, games, wins
            FROM item_builds ORDER BY games DESC, layer, item1, item2, item3
            """
        ) { row in
            guard let layer = BuildLayer(rawValue: try row.decode(forColumn: "layer")) else {
                throw OutOfContract()
            }
            let items = try ["item1", "item2", "item3"]
                .map { column -> Int in try row.decode(forColumn: column) }
                .filter { $0 != 0 }
                .map(ItemID.init(rawValue:))
            tables.loadouts[try opponentKey(row), default: Loadouts()].itemBuilds.append(
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
            let key = Context(try champion(row), try role(row), general)
            tables.loadouts[key, default: Loadouts()].skillOrders.append(
                SkillOrderCandidate(
                    order: order, games: try row.decode(forColumn: "games"),
                    wins: try row.decode(forColumn: "wins")))
        }
    }

    private static func readProfileLoadouts(_ db: Database, into tables: inout Tables)
        throws(SnapshotReadError)
    {
        try each(
            db, "rune_page_vs_profile",
            """
            SELECT r.champion_id, r.role, r.enemy_profile, r.games, r.wins, \(pageColumns)
            FROM rune_page_vs_profile r JOIN rune_page_defs d ON d.page_id = r.page_id
            ORDER BY r.games DESC, r.page_id
            """
        ) { row in
            tables.profileRunePages[try profileKey(row), default: []].append(try runePage(row))
        }

        try each(
            db, "item_vs_profile",
            """
            SELECT champion_id, role, enemy_profile, item_id, games, wins FROM item_vs_profile
            ORDER BY games DESC, item_id
            """
        ) { row in
            let item = FinalItemCandidate(
                item: ItemID(rawValue: try row.decode(forColumn: "item_id")),
                games: try row.decode(forColumn: "games"),
                wins: try row.decode(forColumn: "wins"))
            if try row.decode(String.self, forColumn: "enemy_profile") == baselineProfile {
                tables.baselineFinalItems[try key(row), default: []].append(item)
            } else {
                tables.profileFinalItems[try profileKey(row), default: []].append(item)
            }
        }
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

    private static let pageColumns = """
        d.primary_style, d.sub_style, d.perk1, d.perk2, d.perk3, d.perk4, d.perk5, d.perk6,
        d.shard_offense, d.shard_flex, d.shard_defense
        """

    private static func runePage(_ row: Row) throws -> RunePageCandidate {
        let perkColumns = [
            "perk1", "perk2", "perk3", "perk4", "perk5", "perk6", "shard_offense", "shard_flex",
            "shard_defense",
        ]
        let page = RunePage(
            primaryStyle: PerkStyleID(rawValue: try row.decode(forColumn: "primary_style")),
            subStyle: PerkStyleID(rawValue: try row.decode(forColumn: "sub_style")),
            perks: try perkColumns.map { PerkID(rawValue: try row.decode(forColumn: $0)) })
        return RunePageCandidate(
            page: page, games: try row.decode(forColumn: "games"),
            wins: try row.decode(forColumn: "wins"))
    }

    private static func relation(_ row: Row) throws -> RelationStats {
        RelationStats(
            games: try row.decode(forColumn: "games"), wins: try row.decode(forColumn: "wins"))
    }

    private static func champion(_ row: Row) throws -> ChampionID {
        ChampionID(rawValue: try row.decode(forColumn: "champion_id"))
    }

    private static func role(_ row: Row, column: String = "role") throws -> Role {
        guard let role = Role(rawValue: try row.decode(forColumn: column)) else {
            throw OutOfContract()
        }
        return role
    }

    private static func key(_ row: Row) throws -> ChampionRole {
        ChampionRole(champion: try champion(row), role: try role(row))
    }

    private static func opponentKey(_ row: Row) throws -> Context<ChampionID> {
        Context(
            try champion(row), try role(row),
            ChampionID(rawValue: try row.decode(forColumn: "opp_id")))
    }

    private static func profileKey(_ row: Row) throws -> Context<EnemyProfile> {
        Context(
            try champion(row), try role(row),
            EnemyProfile(rawValue: try row.decode(forColumn: "enemy_profile")))
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
