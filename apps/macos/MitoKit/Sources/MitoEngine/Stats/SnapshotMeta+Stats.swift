public import MitoCore

extension SnapshotMeta {
    /// `nil` when the file carries no threshold for `kind`.
    public func sampleLevel(_ kind: SampleKind, games: Int) -> SampleLevel? {
        thresholds[kind]?.level(games: games)
    }

    /// `games / matches`; 0 for a file without matches.
    public func pickRate(games: Int) -> Double {
        matches > 0 ? Double(games) / Double(matches) : 0
    }

    /// The tier of `wr_smoothed(champ, role)`; `nil` below the `champ_role` minimum or when the
    /// file has no `champ_role` threshold.
    public func tier(for stats: ChampionRoleStats) -> Tier? {
        guard let level = sampleLevel(.championRole, games: stats.games), level != .belowMinimum
        else { return nil }
        return Tier(
            winrate: priors.championRoleWinrate(wins: stats.wins, games: stats.games),
            cutoffs: tierCutoffs)
    }
}
