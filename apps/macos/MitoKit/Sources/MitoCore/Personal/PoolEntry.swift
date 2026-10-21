/// A `pool` row: a champion the user declared for a role (§19.1).
public struct PoolEntry: Hashable, Sendable {
    public let role: Role
    public let champion: ChampionID
    /// 0 is the first choice.
    public let priority: Int

    public init(role: Role, champion: ChampionID, priority: Int) {
        self.role = role
        self.champion = champion
        self.priority = priority
    }
}
