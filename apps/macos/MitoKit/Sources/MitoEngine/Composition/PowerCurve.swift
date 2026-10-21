public import MitoCore

/// `early_strength` and `late_strength` of one (champ, role) from its `duration_curves` (§18.4).
public struct PowerCurve: Hashable, Sendable {
    /// The smoothed winrate of the buckets that end by 25 minutes, minus `winrate`.
    public let early: Double
    /// The smoothed winrate of the buckets from 35 minutes, minus `winrate`.
    public let late: Double
    /// Σ wins / Σ games over every bucket: the baseline and the prior's center.
    public let winrate: Double
    /// Σ games over every bucket.
    public let games: Int

    /// `nil` for a curve without games. The baseline is the curve's own total, not
    /// `wr_smoothed(champ, role)`, so its segments are measured against the same matches.
    public init?(_ curve: [DurationBucket: RelationStats], priors: SmoothingPriors) {
        let games = curve.values.reduce(0) { $0 + $1.games }
        guard games > 0 else { return nil }
        let winrate = Double(curve.values.reduce(0) { $0 + $1.wins }) / Double(games)

        func strength(_ isInSegment: (DurationBucket) -> Bool) -> Double {
            let segment = curve.filter { isInSegment($0.key) }.values
            return priors.relationWinrate(
                wins: segment.reduce(0) { $0 + $1.wins },
                games: segment.reduce(0) { $0 + $1.games }, baseline: winrate) - winrate
        }
        self.early = strength { ($0.upperMinutes ?? .max) <= Self.earlyEndMinutes }
        self.late = strength { $0.lowerMinutes >= Self.lateStartMinutes }
        self.winrate = winrate
        self.games = games
    }

    static let earlyEndMinutes = 25
    static let lateStartMinutes = 35
}

extension Composition {
    /// `team_early`: the mean `early_strength` of the members with a curve, and how many have
    /// one. `nil` when none has.
    public static func teamEarly(of members: [TeamMember], stats: some StatsProvider)
        -> (value: Double, members: Int)?
    {
        guard let priors = stats.meta?.priors else { return nil }
        let curves = members.compactMap {
            PowerCurve(stats.durationCurves(for: $0.champion, role: $0.role), priors: priors)
        }
        guard !curves.isEmpty else { return nil }
        return (curves.reduce(0) { $0 + $1.early } / Double(curves.count), curves.count)
    }
}
