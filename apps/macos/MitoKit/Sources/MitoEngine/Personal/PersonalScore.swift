public import Foundation
public import MitoCore

/// `personal(c, r)` with every component, so the UI can explain it (`MITO_CONTEXT.md` §19.3).
public struct PersonalScore: Hashable, Sendable {
    public let champion: ChampionID
    public let role: Role
    public let metrics: PersonalMetrics
    /// `my_wr_smoothed − wr_s`, already in winrate points.
    public let winrateEdge: Double
    /// `comfort(c, r)`, in [0, 1].
    public let comfort: Double
    /// In the role's pool and not excluded by an override.
    public let inPool: Bool
    /// The mean of `kda_vs_avg − 1` and `cs_vs_avg − 1`, clamped to [−1, 1].
    public let relativePerformance: Double
    /// `personal(c, r)`, unscaled.
    public let total: Double

    public init(
        champion: ChampionID, role: Role, metrics: PersonalMetrics, winrateEdge: Double,
        comfort: Double, inPool: Bool, relativePerformance: Double, total: Double
    ) {
        self.champion = champion
        self.role = role
        self.metrics = metrics
        self.winrateEdge = winrateEdge
        self.comfort = comfort
        self.inPool = inPool
        self.relativePerformance = relativePerformance
        self.total = total
    }

    /// What a maximum comfort adds, in winrate points: "unos +3 puntos" (§19.3).
    public static let defaultMaxComfortWorth = 0.03

    /// `total` scaled so the comfort term at its maximum is worth `maxComfortWorth`.
    public func winratePoints(maxComfortWorth: Double = defaultMaxComfortWorth) -> Double {
        total * maxComfortWorth / Self.comfortWeight
    }
}

extension PersonalScore {
    static let winrateEdgeWeight = 0.4
    static let comfortWeight = 0.3
    static let poolWeight = 0.2
    static let performanceWeight = 0.1

    /// The games and the recency at which their comfort terms saturate.
    static let comfortGames = 30.0
    static let comfortRecency = 5.0

    static func comfort(games: Int, recency: Double, masteryNorm: Double) -> Double {
        min(
            1,
            0.6 * min(1, Double(games) / comfortGames) + 0.4 * min(1, recency / comfortRecency)
                + 0.2 * masteryNorm)
    }

    /// An exclusion override wins over the pool (§17, "Decisiones de la base personal").
    static func isInPool(
        _ champion: ChampionID, role: Role, pool: [PoolEntry], overrides: [ChampionOverride]
    ) -> Bool {
        let isExcluded = overrides.contains {
            $0.champion == champion && $0.role == role && $0.isExcludedFromPool
        }
        return !isExcluded && pool.contains { $0.champion == champion && $0.role == role }
    }

    static func relativePerformance(kdaVsAverage: Double, csVsAverage: Double) -> Double {
        let mean = ((kdaVsAverage - 1) + (csVsAverage - 1)) / 2
        return min(1, max(-1, mean))
    }
}

/// The personal score of §19.2–§19.3; the rules §19 leaves open are written in §19.3.
public enum PersonalScoring {
    /// Only `matches` with this champion and role count, whatever their queue: the caller
    /// picks which games are the user's history. `pool` may hold every role.
    /// `masteryPoints` is the user's points per champion; its maximum is `max_points`.
    public static func score(
        champion: ChampionID,
        role: Role,
        matches: [MyMatch],
        pool: [PoolEntry],
        overrides: [ChampionOverride],
        masteryPoints: [ChampionID: Int],
        stats: some StatsProvider,
        now: Date
    ) -> PersonalScore {
        let meta = stats.meta
        let metrics = PersonalMetrics(
            matches: matches.filter { $0.champion == champion && $0.role == role },
            masteryPoints: masteryPoints[champion] ?? 0,
            maxMasteryPoints: masteryPoints.values.max() ?? 0,
            snapshot: stats.championRoleStats(in: role)[champion],
            priors: meta?.priors,
            now: now)

        let winrateEdge = metrics.smoothedWinrate - metrics.globalWinrate
        let comfort = PersonalScore.comfort(
            games: metrics.games, recency: metrics.recency, masteryNorm: metrics.masteryNorm)
        let inPool = PersonalScore.isInPool(
            champion, role: role, pool: pool, overrides: overrides)
        let relativePerformance = PersonalScore.relativePerformance(
            kdaVsAverage: metrics.kdaVsAverage, csVsAverage: metrics.csVsAverage)

        return PersonalScore(
            champion: champion,
            role: role,
            metrics: metrics,
            winrateEdge: winrateEdge,
            comfort: comfort,
            inPool: inPool,
            relativePerformance: relativePerformance,
            total: PersonalScore.winrateEdgeWeight * winrateEdge
                + PersonalScore.comfortWeight * comfort
                + PersonalScore.poolWeight * (inPool ? 1 : 0)
                + PersonalScore.performanceWeight * relativePerformance)
    }
}
