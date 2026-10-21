import MitoCore
import Testing

struct SampleLevelTests {
    private static let thresholds = [
        SampleThreshold(minimum: 200, reliable: 1_000), SampleThreshold(minimum: 30, reliable: 300),
        SampleThreshold(minimum: 50, reliable: 400),
    ]

    @Test(arguments: thresholds)
    func classifiesAThresholdAtItsBoundaries(threshold: SampleThreshold) {
        #expect(threshold.level(games: 0) == .belowMinimum)
        #expect(threshold.level(games: threshold.minimum - 1) == .belowMinimum)
        #expect(threshold.level(games: threshold.minimum) == .usable)
        #expect(threshold.level(games: threshold.reliable - 1) == .usable)
        #expect(threshold.level(games: threshold.reliable) == .reliable)
    }

    @Test func everythingShortOfReliableIsLowSample() {
        #expect(SampleLevel.belowMinimum.isLowSample)
        #expect(SampleLevel.usable.isLowSample)
        #expect(!SampleLevel.reliable.isLowSample)
    }
}
