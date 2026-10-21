/// The two-sided 90 % Wilson score interval of a raw win rate (`MITO_CONTEXT.md` §18.1).
public struct WilsonInterval: Hashable, Sendable {
    public let lower: Double
    public let upper: Double

    /// No games is no information, so the interval is `[0, 1]`.
    public init(wins: Int, games: Int) {
        guard games > 0 else {
            lower = 0
            upper = 1
            return
        }
        let n = Double(games)
        let p = Double(wins) / n
        let z = Self.z
        let denominator = 1 + z * z / n
        let center = (p + z * z / (2 * n)) / denominator
        let halfWidth = z * (p * (1 - p) / n + z * z / (4 * n * n)).squareRoot() / denominator
        // The bounds are exactly 0 and 1 at the edges, but rounding misses them by an ulp.
        lower = wins > 0 ? center - halfWidth : 0
        upper = wins < games ? center + halfWidth : 1
    }

    /// The standard normal quantile at 0.95.
    static let z = 1.6448536269514722
}
