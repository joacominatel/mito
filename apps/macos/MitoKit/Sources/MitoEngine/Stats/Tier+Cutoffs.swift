public import MitoCore

extension Tier {
    /// The highest tier whose cutoff `winrate` reaches; a cutoff is a minimum, so a winrate exactly
    /// at it earns that tier. Below every cutoff is D (`MITO_CONTEXT.md` §17, §18.1).
    public init(winrate: Double, cutoffs: [Tier: Double]) {
        self = Tier.allCases.first { cutoffs[$0].map { winrate >= $0 } ?? false } ?? .d
    }
}
