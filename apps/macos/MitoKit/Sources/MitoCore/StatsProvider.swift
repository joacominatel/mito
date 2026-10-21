/// Raw counts from the open snapshot (`MITO_CONTEXT.md` §17); rates are the engine's job.
/// Missing data is `nil` or empty, never an error.
public protocol StatsProvider: Sendable {
    /// Games per role from `champion_roles`; empty when the champion has no rows this patch.
    func roleGames(for champion: ChampionID) -> [Role: Int]

    /// `nil` when no snapshot is open.
    var meta: SnapshotMeta? { get }

    /// Every champion with a `champ_role_stats` row in this role.
    func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats]

    /// General (`opp_id = 0`) rows.
    func runePages(for champion: ChampionID, role: Role) -> [RunePageCandidate]

    /// General (`opp_id = 0`) rows.
    func spellPairs(for champion: ChampionID, role: Role) -> [SpellPairCandidate]

    /// General (`opp_id = 0`) candidates of every layer; filter by `layer`.
    func itemBuilds(for champion: ChampionID, role: Role) -> [ItemBuildCandidate]

    func skillOrders(for champion: ChampionID, role: Role) -> [SkillOrderCandidate]

    /// `matchup_stats` against the lane opponent `opponent`.
    func matchup(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> MatchupStats?

    /// `synergy_stats` with `ally` playing `allyRole`.
    func synergy(for champion: ChampionID, role: Role, with ally: ChampionID, allyRole: Role)
        -> RelationStats?

    /// `vs_team_stats` against `enemy` in any role.
    func versusTeam(for champion: ChampionID, role: Role, against enemy: ChampionID)
        -> RelationStats?

    /// `champion_profiles`.
    func championProfile(for champion: ChampionID, role: Role) -> ChampionProfile?

    /// `champ_vs_profile`: the games against teams with `profile`, the denominator of the
    /// profile layers.
    func profileStats(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> RelationStats?

    /// `rune_pages` rows with `opp_id = opponent`.
    func runePages(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [RunePageCandidate]

    /// `spell_pairs` rows with `opp_id = opponent`.
    func spellPairs(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [SpellPairCandidate]

    /// `item_builds` rows with `opp_id = opponent`, of every layer the export kept.
    func itemBuilds(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [ItemBuildCandidate]

    /// `rune_page_vs_profile`.
    func runePages(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> [RunePageCandidate]

    /// `item_vs_profile` with `enemy_profile = 'any'`, the situational baseline (§18.7).
    func finalItems(for champion: ChampionID, role: Role) -> [FinalItemCandidate]

    /// `item_vs_profile` against `profile`.
    func finalItems(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> [FinalItemCandidate]

    /// `champ_ban_stats.bans`: matches in which the champion was banned.
    func bans(of champion: ChampionID) -> Int?

    /// `champion_flags`; empty when none is curated.
    func flags(of champion: ChampionID) -> Set<ChampionFlag>

    /// `duration_curves`: games and wins per game-length bucket, the source of
    /// `early_strength` and `late_strength` (§18.4). A bucket without a row is absent.
    func durationCurves(for champion: ChampionID, role: Role) -> [DurationBucket: RelationStats]

    /// `item_classes.class` (§16.3); `nil` for an item the snapshot does not classify.
    func itemClass(of item: ItemID) -> ItemClass?

    /// `item_classes.antiheal` (§16.3, §18.7); `false` for an unclassified item.
    func isAntiheal(_ item: ItemID) -> Bool
}

extension StatsProvider {
    public var meta: SnapshotMeta? { nil }

    public func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] { [:] }

    public func runePages(for champion: ChampionID, role: Role) -> [RunePageCandidate] { [] }

    public func spellPairs(for champion: ChampionID, role: Role) -> [SpellPairCandidate] { [] }

    public func itemBuilds(for champion: ChampionID, role: Role) -> [ItemBuildCandidate] { [] }

    public func skillOrders(for champion: ChampionID, role: Role) -> [SkillOrderCandidate] { [] }

    public func matchup(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> MatchupStats?
    { nil }

    public func synergy(
        for champion: ChampionID, role: Role, with ally: ChampionID, allyRole: Role
    ) -> RelationStats? { nil }

    public func versusTeam(for champion: ChampionID, role: Role, against enemy: ChampionID)
        -> RelationStats?
    { nil }

    public func championProfile(for champion: ChampionID, role: Role) -> ChampionProfile? { nil }

    public func profileStats(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> RelationStats?
    { nil }

    public func runePages(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [RunePageCandidate]
    { [] }

    public func spellPairs(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [SpellPairCandidate]
    { [] }

    public func itemBuilds(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [ItemBuildCandidate]
    { [] }

    public func runePages(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> [RunePageCandidate]
    { [] }

    public func finalItems(for champion: ChampionID, role: Role) -> [FinalItemCandidate] { [] }

    public func finalItems(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> [FinalItemCandidate]
    { [] }

    public func bans(of champion: ChampionID) -> Int? { nil }

    public func flags(of champion: ChampionID) -> Set<ChampionFlag> { [] }

    public func durationCurves(for champion: ChampionID, role: Role)
        -> [DurationBucket: RelationStats]
    { [:] }

    public func itemClass(of item: ItemID) -> ItemClass? { nil }

    public func isAntiheal(_ item: ItemID) -> Bool { false }
}
