/// `personal(c, r)` in winrate points, the unit `PickScoring` adds it in (§19.3).
public enum PersonalPoints {
    /// The edge is already in winrate points and stays unscaled; the unitless terms are scaled
    /// so that `0.3 · comfort` at its maximum is worth `maxComfortWorth`.
    public static func points(
        _ score: PersonalScore,
        maxComfortWorth: Double = PersonalScore.defaultMaxComfortWorth
    ) -> Double {
        score.winratePoints(maxComfortWorth: maxComfortWorth)
    }
}

/// `personal(c, r)` as the pick score takes it, with the facts of its `comfort` reason (§18.3).
public struct PersonalTerm: Hashable, Sendable {
    /// Winrate points, before `w_personal`.
    public let points: Double
    /// The user's own games with the champion in the role.
    public let games: Int
    public let wins: Int
    /// The 1-based place in the role's pool order (§18.3); `nil` outside it.
    public let poolRank: Int?

    public init(points: Double, games: Int, wins: Int, poolRank: Int?) {
        self.points = points
        self.games = games
        self.wins = wins
        self.poolRank = poolRank
    }

    public init(
        _ score: PersonalScore, poolRank: Int?,
        maxComfortWorth: Double = PersonalScore.defaultMaxComfortWorth
    ) {
        self.init(
            points: PersonalPoints.points(score, maxComfortWorth: maxComfortWorth),
            games: score.metrics.games, wins: score.metrics.wins, poolRank: poolRank)
    }
}

extension PickWeights {
    /// The Meta ↔ Comfort slider of §18.3: `balance` 0 is pure meta, 1 pure comfort, and 0.5
    /// (the `ChampSelectSettings` default) gives the default weights. Outside [0, 1] it clamps.
    public init(metaComfortBalance balance: Double) {
        let s = min(1, max(0, balance))
        self.init(
            meta: 1.5 - s,
            personal: s <= 0.5 ? 0.2 + 1.6 * s : 1.0 + 3.0 * (s - 0.5))
    }
}
