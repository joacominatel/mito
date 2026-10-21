public import MitoCore

/// Where a sample stands against its `[minimum, reliable]` threshold (`MITO_CONTEXT.md` §18.2).
public enum SampleLevel: Comparable, Sendable {
    /// Not used, unless the exporter kept it as the only option (§14.12).
    case belowMinimum
    case usable
    case reliable

    /// Anything short of reliable carries the "muestra baja" mark (§18.1).
    public var isLowSample: Bool { self != .reliable }
}

extension SampleThreshold {
    public func level(games: Int) -> SampleLevel {
        if games < minimum { return .belowMinimum }
        return games < reliable ? .usable : .reliable
    }
}
