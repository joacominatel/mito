import MitoCore

/// Tolerance for values computed by hand to 12+ significant digits; `Double` keeps ~16.
let statsTolerance = 1e-12
/// Wilson references were computed independently to 17 digits; this absorbs `sqrt` rounding.
let wilsonTolerance = 1e-9

func isClose(_ lhs: Double, _ rhs: Double, within tolerance: Double = statsTolerance) -> Bool {
    abs(lhs - rhs) <= tolerance
}

extension SnapshotMeta {
    /// The `meta` example of `MITO_CONTEXT.md` §17.
    static func example(
        matches: Int = 1_000_000,
        thresholds: [SampleKind: SampleThreshold] = exampleThresholds
    ) -> SnapshotMeta {
        SnapshotMeta(
            patch: Patch(rawValue: "16.21"),
            queue: QueueID(rawValue: 420),
            bracket: .emeraldPlus,
            matches: matches,
            blendPatches: [Patch(rawValue: "16.21")],
            thresholds: thresholds,
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5,
                relationStrength: 200, loadoutStrength: 500),
            tierCutoffs: [.s: 0.53, .a: 0.515, .b: 0.50, .c: 0.485])
    }

    static let exampleThresholds: [SampleKind: SampleThreshold] = [
        .championRole: SampleThreshold(minimum: 200, reliable: 1_000),
        .matchup: SampleThreshold(minimum: 30, reliable: 300),
        .synergy: SampleThreshold(minimum: 50, reliable: 400),
        .vsTeam: SampleThreshold(minimum: 30, reliable: 300),
        .profile: SampleThreshold(minimum: 100, reliable: 500),
        .runePage: SampleThreshold(minimum: 100, reliable: 800),
        .buildLayer: SampleThreshold(minimum: 100, reliable: 600),
        .itemVsProfile: SampleThreshold(minimum: 50, reliable: 300),
        .spells: SampleThreshold(minimum: 100, reliable: 500),
        .skillOrder: SampleThreshold(minimum: 100, reliable: 600),
    ]
}
