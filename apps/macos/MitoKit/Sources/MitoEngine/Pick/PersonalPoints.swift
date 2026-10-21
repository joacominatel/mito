/// `personal(c, r)` in winrate points, the unit `PickScoring` adds it in (§19.3).
public enum PersonalPoints {
    /// The edge is already in winrate points and stays unscaled; the unitless terms are scaled
    /// so that `0.3 · comfort` at its maximum is worth `maxComfortWorth`.
    public static func points(
        _ score: PersonalScore,
        maxComfortWorth: Double = PersonalScore.defaultMaxComfortWorth
    ) -> Double {
        let unitless =
            PersonalScore.comfortWeight * score.comfort
            + PersonalScore.poolWeight * (score.inPool ? 1 : 0)
            + PersonalScore.performanceWeight * score.relativePerformance
        return PersonalScore.winrateEdgeWeight * score.winrateEdge
            + unitless * maxComfortWorth / PersonalScore.comfortWeight
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
