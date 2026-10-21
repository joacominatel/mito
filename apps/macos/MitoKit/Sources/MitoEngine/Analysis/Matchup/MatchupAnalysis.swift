public import MitoCore

/// The Matchup tab of the analysis panel (§20.2): your champion in the role, against the lane
/// opponent when there is one. Every number comes with its sample; below a minimum it is absent.
public struct MatchupAnalysis: Hashable, Sendable {
    /// Against the lane opponent; `nil` without one or without a `matchup_stats` row.
    public let matchup: SmoothedWinrate?
    /// `wr_smoothed(champ, role)`; `nil` without a `champ_role_stats` row.
    public let general: SmoothedWinrate?
    public let laneDiffs: LaneDiffs?
    public let curve: DurationCurve?
    /// The lane opponent's curve in the same role.
    public let opponentCurve: DurationCurve?
    public let curveSummary: CurveSummary?
    public let spikes: [SpikeComparison]
    public let claves: [Clave]

    /// `nil` without a snapshot. `curatedTips` are the tips file's for (champion, role,
    /// opponent); with any, they replace the generated claves.
    public init?(
        champion: ChampionID, role: Role, opponent: ChampionID?, stats: some StatsProvider,
        curatedTips: [CuratedTip] = []
    ) {
        guard let meta = stats.meta else { return nil }
        let championStats = stats.championRoleStats(in: role)[champion]
        let matchupStats = opponent.flatMap {
            stats.matchup(for: champion, role: role, against: $0)
        }
        let matchup = matchupStats.flatMap {
            SmoothedWinrate(matchup: $0, championStats: championStats, meta: meta)
        }
        let laneDiffs = matchupStats.flatMap { LaneDiffs($0, meta: meta) }
        let curve = DurationCurve(champion: champion, role: role, stats: stats, meta: meta)
        let opponentCurve = opponent.flatMap {
            DurationCurve(champion: $0, role: role, stats: stats, meta: meta)
        }
        let curveSummary = curve.flatMap { CurveSummary($0, versus: opponentCurve) }
        let spikes = SpikeComparison.compare(
            mine: stats.championProfile(for: champion, role: role),
            theirs: opponent.flatMap { stats.championProfile(for: $0, role: role) }, meta: meta)
        general = championStats.flatMap { SmoothedWinrate(general: $0, meta: meta) }
        self.matchup = matchup
        self.laneDiffs = laneDiffs
        self.curve = curve
        self.opponentCurve = opponentCurve
        self.curveSummary = curveSummary
        self.spikes = spikes
        if !curatedTips.isEmpty {
            claves = curatedTips.map(Clave.curated)
        } else if opponent != nil {
            claves = MatchupClaves.generated(
                matchup: matchup, laneDiffs: laneDiffs, spikes: spikes, curveSummary: curveSummary,
                champion: champion)
        } else {
            claves = []
        }
    }
}

/// A smoothed winrate (§18.1) with its 90 % Wilson interval and the sample behind it.
public struct SmoothedWinrate: Hashable, Sendable {
    public struct Estimate: Hashable, Sendable {
        public let winrate: Double
        /// Over the raw counts, not the smoothed rate (§18.1).
        public let interval: WilsonInterval
        /// `matchup_delta`: against `wr_smoothed(champ, role)`. `nil` for the general winrate.
        public let delta: Double?
    }

    public let games: Int
    public let sample: SampleLevel
    /// `nil` below the minimum: the data is not used (§18.2).
    public let estimate: Estimate?

    init?(general stats: ChampionRoleStats, meta: SnapshotMeta) {
        guard stats.games > 0 else { return nil }
        games = stats.games
        sample = meta.sampleLevel(.championRole, games: stats.games) ?? .belowMinimum
        estimate =
            sample == .belowMinimum
            ? nil
            : Estimate(
                winrate: meta.priors.championRoleWinrate(wins: stats.wins, games: stats.games),
                interval: WilsonInterval(wins: stats.wins, games: stats.games), delta: nil)
    }

    init?(matchup stats: MatchupStats, championStats: ChampionRoleStats?, meta: SnapshotMeta) {
        guard stats.games > 0 else { return nil }
        games = stats.games
        guard
            let delta = MatchupDelta(
                wins: stats.wins, games: stats.games, kind: .matchup,
                championStats: championStats, meta: meta)
        else {
            sample = .belowMinimum
            estimate = nil
            return
        }
        let baseline = meta.priors.championRoleWinrate(
            wins: championStats?.wins ?? 0, games: championStats?.games ?? 0)
        sample = delta.sample
        estimate = Estimate(
            winrate: baseline + delta.delta,
            interval: WilsonInterval(wins: stats.wins, games: stats.games), delta: delta.delta)
    }
}

/// Gold and CS at 15 minutes against the lane opponent, from `matchup_stats` (§17).
public struct LaneDiffs: Hashable, Sendable {
    public let goldAt15: Double?
    public let csAt15: Double?
    public let timelineGames: Int
    /// The `matchup` threshold over `timelineGames`, the diffs' denominator.
    public let sample: SampleLevel

    /// `nil` without timeline games, without either diff, or below the `matchup` minimum.
    init?(_ stats: MatchupStats, meta: SnapshotMeta) {
        guard stats.timelineGames > 0, stats.goldDiffAt15 != nil || stats.csDiffAt15 != nil,
            let sample = meta.sampleLevel(.matchup, games: stats.timelineGames),
            sample != .belowMinimum
        else { return nil }
        goldAt15 = stats.goldDiffAt15
        csAt15 = stats.csDiffAt15
        timelineGames = stats.timelineGames
        self.sample = sample
    }
}

/// Whose side a comparison falls on.
public enum MatchupSide: Hashable, Sendable {
    case you
    case opponent
}
