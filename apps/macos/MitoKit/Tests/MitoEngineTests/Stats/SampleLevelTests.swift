import MitoCore
import Testing

@testable import MitoEngine

struct SampleLevelTests {
    private let meta = SnapshotMeta.example()

    @Test(arguments: SampleKind.allCases)
    func classifiesEveryKindAtItsBoundaries(kind: SampleKind) throws {
        let threshold = try #require(SnapshotMeta.exampleThresholds[kind])

        #expect(meta.sampleLevel(kind, games: 0) == .belowMinimum)
        #expect(meta.sampleLevel(kind, games: threshold.minimum - 1) == .belowMinimum)
        #expect(meta.sampleLevel(kind, games: threshold.minimum) == .usable)
        #expect(meta.sampleLevel(kind, games: threshold.reliable - 1) == .usable)
        #expect(meta.sampleLevel(kind, games: threshold.reliable) == .reliable)
    }

    @Test func usesTheThresholdsFromTheFileNotTheDocumentedDefaults() {
        let meta = SnapshotMeta.example(thresholds: [
            .matchup: SampleThreshold(minimum: 10, reliable: 20)
        ])

        #expect(meta.sampleLevel(.matchup, games: 10) == .usable)
        #expect(meta.sampleLevel(.matchup, games: 20) == .reliable)
    }

    @Test func kindMissingFromTheFileHasNoLevel() {
        let meta = SnapshotMeta.example(thresholds: [:])

        #expect(meta.sampleLevel(.matchup, games: 10_000) == nil)
    }

    @Test func everythingShortOfReliableIsLowSample() {
        #expect(SampleLevel.belowMinimum.isLowSample)
        #expect(SampleLevel.usable.isLowSample)
        #expect(!SampleLevel.reliable.isLowSample)
    }
}
