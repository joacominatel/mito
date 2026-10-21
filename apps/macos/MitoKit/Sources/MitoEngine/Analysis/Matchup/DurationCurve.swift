public import MitoCore

/// One (champ, role)'s `duration_curves` as the chart draws it (§20.2).
public struct DurationCurve: Hashable, Sendable {
    public struct Point: Hashable, Sendable {
        public let bucket: DurationBucket
        /// Smoothed toward the curve's own total with the relation prior, as `PowerCurve` does.
        public let winrate: Double
        public let games: Int
    }

    public let champion: ChampionID
    /// In bucket order; a bucket without games is absent.
    public let points: [Point]
    public let power: PowerCurve
    /// The `champ_role` threshold over the curve's games.
    public let sample: SampleLevel

    /// `nil` without games or below the `champ_role` minimum.
    init?(champion: ChampionID, role: Role, stats: some StatsProvider, meta: SnapshotMeta) {
        let buckets = stats.durationCurves(for: champion, role: role)
        guard let power = PowerCurve(buckets, priors: meta.priors),
            let sample = meta.sampleLevel(.championRole, games: power.games),
            sample != .belowMinimum
        else { return nil }
        self.champion = champion
        self.power = power
        self.sample = sample
        points = DurationBucket.allCases.compactMap { bucket in
            guard let stats = buckets[bucket], stats.games > 0 else { return nil }
            return Point(
                bucket: bucket,
                winrate: meta.priors.relationWinrate(
                    wins: stats.wins, games: stats.games, baseline: power.winrate),
                games: stats.games)
        }
    }
}

/// The one line under the chart (§20.2): which curve is stronger and when, from the buckets'
/// `early_strength` and `late_strength` (§18.4). Absent when nothing stands out.
public struct CurveSummary: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        /// Games that end by `PowerCurve.earlyEndMinutes`.
        case early
        /// Games from `PowerCurve.lateStartMinutes`.
        case late

        /// Where the phase ends (early) or starts (late).
        public var minute: Int {
            switch self {
            case .early: PowerCurve.earlyEndMinutes
            case .late: PowerCurve.lateStartMinutes
            }
        }
    }

    public let stronger: ChampionID
    public let phase: Phase
    /// The other curve's champion; `nil` when a curve is read against its own average.
    public let versus: ChampionID?
    /// The lower sample of the curves compared.
    public let sample: SampleLevel

    /// With `versus`, the larger gap between the two curves' segments; alone, the larger
    /// segment. Either needs `margin`; a tie goes to late.
    init?(_ curve: DurationCurve, versus other: DurationCurve?) {
        if let other {
            let late = curve.power.late - other.power.late
            let early = curve.power.early - other.power.early
            let (phase, gap) = abs(late) >= abs(early) ? (Phase.late, late) : (.early, early)
            guard abs(gap) >= Self.margin else { return nil }
            stronger = gap > 0 ? curve.champion : other.champion
            versus = gap > 0 ? other.champion : curve.champion
            self.phase = phase
            sample = min(curve.sample, other.sample)
        } else {
            let (phase, strength) =
                curve.power.late >= curve.power.early
                ? (Phase.late, curve.power.late) : (.early, curve.power.early)
            guard strength >= Self.margin else { return nil }
            stronger = curve.champion
            versus = nil
            self.phase = phase
            sample = curve.sample
        }
    }

    /// One winrate point, the comp fit's cutoff for a candidate that shares a curve (§18.4).
    static let margin = 0.01
}
