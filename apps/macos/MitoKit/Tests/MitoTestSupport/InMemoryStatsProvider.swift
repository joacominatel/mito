public import MitoCore

public struct InMemoryStatsProvider: StatsProvider {
    public var roleGamesByChampion: [ChampionID: [Role: Int]]
    public var meta: SnapshotMeta?
    public var championRoleStatsByRole: [Role: [ChampionID: ChampionRoleStats]]
    public var runePagesByChampion: [ChampionID: [Role: [RunePageCandidate]]]
    public var spellPairsByChampion: [ChampionID: [Role: [SpellPairCandidate]]]
    public var itemBuildsByChampion: [ChampionID: [Role: [ItemBuildCandidate]]]
    public var skillOrdersByChampion: [ChampionID: [Role: [SkillOrderCandidate]]]
    /// Champion → role → lane opponent.
    public var matchupsByChampion: [ChampionID: [Role: [ChampionID: MatchupStats]]]
    /// Champion → role → ally → ally role.
    public var synergiesByChampion: [ChampionID: [Role: [ChampionID: [Role: RelationStats]]]]
    /// Champion → role → enemy.
    public var versusTeamByChampion: [ChampionID: [Role: [ChampionID: RelationStats]]]
    public var championProfilesByChampion: [ChampionID: [Role: ChampionProfile]]
    public var profileStatsByChampion: [ChampionID: [Role: [EnemyProfile: RelationStats]]]
    /// Champion → role → lane opponent.
    public var opponentRunePagesByChampion: [ChampionID: [Role: [ChampionID: [RunePageCandidate]]]]
    public var opponentSpellPairsByChampion:
        [ChampionID: [Role: [ChampionID: [SpellPairCandidate]]]]
    public var opponentItemBuildsByChampion:
        [ChampionID: [Role: [ChampionID: [ItemBuildCandidate]]]]
    public var profileRunePagesByChampion: [ChampionID: [Role: [EnemyProfile: [RunePageCandidate]]]]
    /// The `'any'` rows of `item_vs_profile`.
    public var baselineFinalItemsByChampion: [ChampionID: [Role: [FinalItemCandidate]]]
    public var profileFinalItemsByChampion:
        [ChampionID: [Role: [EnemyProfile: [FinalItemCandidate]]]]
    public var bansByChampion: [ChampionID: Int]
    public var flagsByChampion: [ChampionID: Set<ChampionFlag>]
    public var durationCurvesByChampion: [ChampionID: [Role: [DurationBucket: RelationStats]]]
    public var itemClasses: [ItemID: ItemClass]
    public var antihealItems: Set<ItemID>

    public init(
        roleGamesByChampion: [ChampionID: [Role: Int]] = [:],
        meta: SnapshotMeta? = nil,
        championRoleStatsByRole: [Role: [ChampionID: ChampionRoleStats]] = [:],
        runePagesByChampion: [ChampionID: [Role: [RunePageCandidate]]] = [:],
        spellPairsByChampion: [ChampionID: [Role: [SpellPairCandidate]]] = [:],
        itemBuildsByChampion: [ChampionID: [Role: [ItemBuildCandidate]]] = [:],
        skillOrdersByChampion: [ChampionID: [Role: [SkillOrderCandidate]]] = [:],
        matchupsByChampion: [ChampionID: [Role: [ChampionID: MatchupStats]]] = [:],
        synergiesByChampion: [ChampionID: [Role: [ChampionID: [Role: RelationStats]]]] = [:],
        versusTeamByChampion: [ChampionID: [Role: [ChampionID: RelationStats]]] = [:],
        championProfilesByChampion: [ChampionID: [Role: ChampionProfile]] = [:],
        profileStatsByChampion: [ChampionID: [Role: [EnemyProfile: RelationStats]]] = [:],
        opponentRunePagesByChampion: [ChampionID: [Role: [ChampionID: [RunePageCandidate]]]] =
            [:],
        opponentSpellPairsByChampion: [ChampionID: [Role: [ChampionID: [SpellPairCandidate]]]] =
            [:],
        opponentItemBuildsByChampion: [ChampionID: [Role: [ChampionID: [ItemBuildCandidate]]]] =
            [:],
        profileRunePagesByChampion: [ChampionID: [Role: [EnemyProfile: [RunePageCandidate]]]] =
            [:],
        baselineFinalItemsByChampion: [ChampionID: [Role: [FinalItemCandidate]]] = [:],
        profileFinalItemsByChampion: [ChampionID: [Role: [EnemyProfile: [FinalItemCandidate]]]] =
            [:],
        bansByChampion: [ChampionID: Int] = [:],
        flagsByChampion: [ChampionID: Set<ChampionFlag>] = [:],
        durationCurvesByChampion: [ChampionID: [Role: [DurationBucket: RelationStats]]] = [:],
        itemClasses: [ItemID: ItemClass] = [:],
        antihealItems: Set<ItemID> = []
    ) {
        self.roleGamesByChampion = roleGamesByChampion
        self.meta = meta
        self.championRoleStatsByRole = championRoleStatsByRole
        self.runePagesByChampion = runePagesByChampion
        self.spellPairsByChampion = spellPairsByChampion
        self.itemBuildsByChampion = itemBuildsByChampion
        self.skillOrdersByChampion = skillOrdersByChampion
        self.matchupsByChampion = matchupsByChampion
        self.synergiesByChampion = synergiesByChampion
        self.versusTeamByChampion = versusTeamByChampion
        self.championProfilesByChampion = championProfilesByChampion
        self.profileStatsByChampion = profileStatsByChampion
        self.opponentRunePagesByChampion = opponentRunePagesByChampion
        self.opponentSpellPairsByChampion = opponentSpellPairsByChampion
        self.opponentItemBuildsByChampion = opponentItemBuildsByChampion
        self.profileRunePagesByChampion = profileRunePagesByChampion
        self.baselineFinalItemsByChampion = baselineFinalItemsByChampion
        self.profileFinalItemsByChampion = profileFinalItemsByChampion
        self.bansByChampion = bansByChampion
        self.flagsByChampion = flagsByChampion
        self.durationCurvesByChampion = durationCurvesByChampion
        self.itemClasses = itemClasses
        self.antihealItems = antihealItems
    }

    public func roleGames(for champion: ChampionID) -> [Role: Int] {
        roleGamesByChampion[champion] ?? [:]
    }

    public func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
        championRoleStatsByRole[role] ?? [:]
    }

    public func runePages(for champion: ChampionID, role: Role) -> [RunePageCandidate] {
        runePagesByChampion[champion]?[role] ?? []
    }

    public func spellPairs(for champion: ChampionID, role: Role) -> [SpellPairCandidate] {
        spellPairsByChampion[champion]?[role] ?? []
    }

    public func itemBuilds(for champion: ChampionID, role: Role) -> [ItemBuildCandidate] {
        itemBuildsByChampion[champion]?[role] ?? []
    }

    public func skillOrders(for champion: ChampionID, role: Role) -> [SkillOrderCandidate] {
        skillOrdersByChampion[champion]?[role] ?? []
    }

    public func matchup(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> MatchupStats?
    {
        matchupsByChampion[champion]?[role]?[opponent]
    }

    public func synergy(
        for champion: ChampionID, role: Role, with ally: ChampionID, allyRole: Role
    ) -> RelationStats? {
        synergiesByChampion[champion]?[role]?[ally]?[allyRole]
    }

    public func versusTeam(for champion: ChampionID, role: Role, against enemy: ChampionID)
        -> RelationStats?
    {
        versusTeamByChampion[champion]?[role]?[enemy]
    }

    public func championProfile(for champion: ChampionID, role: Role) -> ChampionProfile? {
        championProfilesByChampion[champion]?[role]
    }

    public func profileStats(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> RelationStats?
    {
        profileStatsByChampion[champion]?[role]?[profile]
    }

    public func runePages(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [RunePageCandidate]
    {
        opponentRunePagesByChampion[champion]?[role]?[opponent] ?? []
    }

    public func spellPairs(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [SpellPairCandidate]
    {
        opponentSpellPairsByChampion[champion]?[role]?[opponent] ?? []
    }

    public func itemBuilds(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [ItemBuildCandidate]
    {
        opponentItemBuildsByChampion[champion]?[role]?[opponent] ?? []
    }

    public func runePages(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> [RunePageCandidate]
    {
        profileRunePagesByChampion[champion]?[role]?[profile] ?? []
    }

    public func finalItems(for champion: ChampionID, role: Role) -> [FinalItemCandidate] {
        baselineFinalItemsByChampion[champion]?[role] ?? []
    }

    public func finalItems(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> [FinalItemCandidate]
    {
        profileFinalItemsByChampion[champion]?[role]?[profile] ?? []
    }

    public func bans(of champion: ChampionID) -> Int? {
        bansByChampion[champion]
    }

    public func flags(of champion: ChampionID) -> Set<ChampionFlag> {
        flagsByChampion[champion] ?? []
    }

    public func durationCurves(for champion: ChampionID, role: Role)
        -> [DurationBucket: RelationStats]
    {
        durationCurvesByChampion[champion]?[role] ?? [:]
    }

    public func itemClass(of item: ItemID) -> ItemClass? {
        itemClasses[item]
    }

    public func isAntiheal(_ item: ItemID) -> Bool {
        antihealItems.contains(item)
    }
}
