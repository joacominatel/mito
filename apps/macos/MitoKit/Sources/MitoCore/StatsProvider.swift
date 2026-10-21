/// Raw counts from the open snapshot (`MITO_CONTEXT.md` §17); rates are the engine's job.
/// Missing data is `nil` or empty, never an error.
public protocol StatsProvider: Sendable {
    /// Games per role from `champion_roles`; empty when the champion has no rows this patch.
    func roleGames(for champion: ChampionID) -> [Role: Int]

    /// `nil` when no snapshot is open.
    var meta: SnapshotMeta? { get }

    /// Every champion with a `champ_role_stats` row in this role.
    func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats]

    func runePages(for champion: ChampionID, role: Role) -> [RunePageCandidate]

    func spellPairs(for champion: ChampionID, role: Role) -> [SpellPairCandidate]

    /// Candidates of every layer; filter by `layer`.
    func itemBuilds(for champion: ChampionID, role: Role) -> [ItemBuildCandidate]

    func skillOrders(for champion: ChampionID, role: Role) -> [SkillOrderCandidate]
}

extension StatsProvider {
    public var meta: SnapshotMeta? { nil }

    public func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] { [:] }

    public func runePages(for champion: ChampionID, role: Role) -> [RunePageCandidate] { [] }

    public func spellPairs(for champion: ChampionID, role: Role) -> [SpellPairCandidate] { [] }

    public func itemBuilds(for champion: ChampionID, role: Role) -> [ItemBuildCandidate] { [] }

    public func skillOrders(for champion: ChampionID, role: Role) -> [SkillOrderCandidate] { [] }
}
