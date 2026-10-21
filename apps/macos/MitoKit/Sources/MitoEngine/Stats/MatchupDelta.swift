import MitoCore

/// `wr_smoothed(relation) − wr_smoothed(champ, role)` (§18.1) for a matchup, synergy or
/// vs_team row, with the sample level of that row.
struct MatchupDelta: Hashable, Sendable {
    let delta: Double
    let games: Int
    let sample: SampleLevel

    /// `nil` below the `kind` minimum or when the file has no `kind` threshold. `championStats`
    /// is the champion's own row in the role; without one the baseline is `p0`.
    init?(
        wins: Int, games: Int, kind: SampleKind, championStats: ChampionRoleStats?,
        meta: SnapshotMeta
    ) {
        guard let sample = meta.sampleLevel(kind, games: games), sample != .belowMinimum
        else { return nil }
        let baseline = meta.priors.championRoleWinrate(
            wins: championStats?.wins ?? 0, games: championStats?.games ?? 0)
        self.delta =
            meta.priors.relationWinrate(wins: wins, games: games, baseline: baseline) - baseline
        self.games = games
        self.sample = sample
    }
}
