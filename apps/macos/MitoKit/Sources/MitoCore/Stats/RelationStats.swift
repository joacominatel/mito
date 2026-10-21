/// Games and wins of a (champ, role) in one relation: with an ally (`synergy_stats`), against
/// any enemy (`vs_team_stats`), against an enemy profile (`champ_vs_profile`) or in a
/// game-length bucket (`duration_curves`) (§17).
public struct RelationStats: Hashable, Sendable {
    /// `games`; the denominator of usage in this context (§17, "Capas y denominadores").
    public let games: Int
    /// `wins`.
    public let wins: Int

    public init(games: Int, wins: Int) {
        self.games = games
        self.wins = wins
    }
}

/// A `matchup_stats` row: a (champ, role) against its lane opponent (§17, §18.1).
public struct MatchupStats: Hashable, Sendable {
    /// `games`, the match-sourced denominator vs this opponent.
    public let games: Int
    /// `wins`.
    public let wins: Int
    /// `tl_games`, the denominator of the diffs and of per-opponent build layers.
    public let timelineGames: Int
    /// `gold_diff_15`, mean over `timelineGames`; `nil` when `timelineGames` is 0.
    public let goldDiffAt15: Double?
    /// `cs_diff_15`, mean over `timelineGames`; `nil` when `timelineGames` is 0.
    public let csDiffAt15: Double?

    public init(
        games: Int, wins: Int, timelineGames: Int, goldDiffAt15: Double?, csDiffAt15: Double?
    ) {
        self.games = games
        self.wins = wins
        self.timelineGames = timelineGames
        self.goldDiffAt15 = goldDiffAt15
        self.csDiffAt15 = csDiffAt15
    }
}
