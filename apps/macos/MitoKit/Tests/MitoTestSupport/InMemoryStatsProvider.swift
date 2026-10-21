public import MitoCore

public struct InMemoryStatsProvider: StatsProvider {
    public var roleGamesByChampion: [ChampionID: [Role: Int]]
    public var meta: SnapshotMeta?
    public var championRoleStatsByRole: [Role: [ChampionID: ChampionRoleStats]]
    public var runePagesByChampion: [ChampionID: [Role: [RunePageCandidate]]]
    public var spellPairsByChampion: [ChampionID: [Role: [SpellPairCandidate]]]
    public var itemBuildsByChampion: [ChampionID: [Role: [ItemBuildCandidate]]]
    public var skillOrdersByChampion: [ChampionID: [Role: [SkillOrderCandidate]]]

    public init(
        roleGamesByChampion: [ChampionID: [Role: Int]] = [:],
        meta: SnapshotMeta? = nil,
        championRoleStatsByRole: [Role: [ChampionID: ChampionRoleStats]] = [:],
        runePagesByChampion: [ChampionID: [Role: [RunePageCandidate]]] = [:],
        spellPairsByChampion: [ChampionID: [Role: [SpellPairCandidate]]] = [:],
        itemBuildsByChampion: [ChampionID: [Role: [ItemBuildCandidate]]] = [:],
        skillOrdersByChampion: [ChampionID: [Role: [SkillOrderCandidate]]] = [:]
    ) {
        self.roleGamesByChampion = roleGamesByChampion
        self.meta = meta
        self.championRoleStatsByRole = championRoleStatsByRole
        self.runePagesByChampion = runePagesByChampion
        self.spellPairsByChampion = spellPairsByChampion
        self.itemBuildsByChampion = itemBuildsByChampion
        self.skillOrdersByChampion = skillOrdersByChampion
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
}
