public protocol StatsProvider: Sendable {
    /// Games per role from `champion_roles`; empty when the champion has no rows this patch.
    func roleGames(for champion: ChampionID) -> [Role: Int]
}
