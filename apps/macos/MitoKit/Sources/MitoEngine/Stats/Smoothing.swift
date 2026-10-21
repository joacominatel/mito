public import MitoCore

/// Bayesian smoothing toward a prior (`MITO_CONTEXT.md` §18.1): `(wins + m·p0) / (games + m)`,
/// which is `(wins + α) / (games + α + β)` with `α = m·p0` and `β = m·(1 − p0)`.
public enum Smoothing {
    /// Returns `baseline` when there is neither a sample nor a prior to divide by.
    public static func winrate(wins: Int, games: Int, strength: Double, baseline: Double) -> Double
    {
        let denominator = Double(games) + strength
        guard denominator > 0 else { return baseline }
        return (Double(wins) + strength * baseline) / denominator
    }
}

extension SmoothingPriors {
    /// `wr_smoothed(champ, role)`, centered on `championRoleBaseline`.
    public func championRoleWinrate(wins: Int, games: Int) -> Double {
        Smoothing.winrate(
            wins: wins, games: games, strength: championRoleStrength,
            baseline: championRoleBaseline)
    }

    /// Matchup, synergy, vs_team and enemy profile; `baseline` is `wr_smoothed(champ, role)`.
    public func relationWinrate(wins: Int, games: Int, baseline: Double) -> Double {
        Smoothing.winrate(wins: wins, games: games, strength: relationStrength, baseline: baseline)
    }

    /// Runes, items, spells and skill orders; `baseline` is `wr_smoothed(champ, role)`.
    public func loadoutWinrate(wins: Int, games: Int, baseline: Double) -> Double {
        Smoothing.winrate(wins: wins, games: games, strength: loadoutStrength, baseline: baseline)
    }
}
