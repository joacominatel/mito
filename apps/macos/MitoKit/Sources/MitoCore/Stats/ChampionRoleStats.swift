/// General counts for one (champ, role), from `champ_role_stats` and `champion_profiles`.
public struct ChampionRoleStats: Hashable, Sendable {
    /// Games played in this role; the denominator of match-sourced loadout usage.
    public let games: Int
    public let wins: Int
    /// Games with a timeline (`tl_games`), the denominator of build layers and skill orders.
    public let timelineGames: Int

    public init(games: Int, wins: Int, timelineGames: Int) {
        self.games = games
        self.wins = wins
        self.timelineGames = timelineGames
    }
}
