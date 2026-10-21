/// General counts for one (champ, role), from `champ_role_stats` and `champion_profiles`.
public struct ChampionRoleStats: Hashable, Sendable {
    /// Games played in this role; the denominator of match-sourced loadout usage.
    public let games: Int
    public let wins: Int
    /// Games with a timeline (`tl_games`), the denominator of build layers and skill orders.
    public let timelineGames: Int
    /// Kills summed over `games`.
    public let kills: Int
    /// Deaths summed over `games`.
    public let deaths: Int
    /// Assists summed over `games`.
    public let assists: Int
    /// Creep score summed over `games`.
    public let cs: Int
    /// Minutes played summed over `games`, the denominator of CS per minute.
    public let minutes: Int

    public init(
        games: Int, wins: Int, timelineGames: Int, kills: Int = 0, deaths: Int = 0,
        assists: Int = 0, cs: Int = 0, minutes: Int = 0
    ) {
        self.games = games
        self.wins = wins
        self.timelineGames = timelineGames
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.cs = cs
        self.minutes = minutes
    }
}
