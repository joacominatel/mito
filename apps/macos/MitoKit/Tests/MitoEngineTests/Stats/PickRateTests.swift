import MitoCore
import Testing

@testable import MitoEngine

struct PickRateTests {
    @Test func pickRateIsGamesOverMatches() {
        let meta = SnapshotMeta.example(matches: 200_000)

        #expect(isClose(meta.pickRate(games: 10_000), 0.05))
    }

    @Test func fileWithoutMatchesHasAZeroPickRate() {
        let meta = SnapshotMeta.example(matches: 0)

        #expect(meta.pickRate(games: 0) == 0)
        #expect(meta.pickRate(games: 10) == 0)
    }
}
