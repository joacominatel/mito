import MitoCore
import MitoEngine
import Testing

struct SnapshotMetaSampleLevelTests {
    private let meta = SnapshotMeta.example()

    @Test(arguments: SampleKind.allCases)
    func classifiesEveryKindWithItsOwnThreshold(kind: SampleKind) throws {
        let threshold = try #require(SnapshotMeta.exampleThresholds[kind])

        #expect(meta.sampleLevel(kind, games: threshold.minimum - 1) == .belowMinimum)
        #expect(meta.sampleLevel(kind, games: threshold.minimum) == .usable)
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
}
