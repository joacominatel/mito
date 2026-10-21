import MitoCore
import Testing

@testable import MitoEngine

struct TierTests {
    private let meta = SnapshotMeta.example()

    @Test(arguments: [
        (0.60, Tier.s), (0.53, .s),
        (0.5299, .a), (0.515, .a),
        (0.5149, .b), (0.50, .b),
        (0.4999, .c), (0.485, .c),
        (0.4849, .d), (0.0, .d),
    ])
    func winrateAtOrAboveACutoffEarnsThatTier(winrate: Double, tier: Tier) {
        #expect(Tier(winrate: winrate, cutoffs: meta.tierCutoffs) == tier)
    }

    @Test func tierMissingFromTheCutoffsIsSkipped() {
        let cutoffs: [Tier: Double] = [.a: 0.515, .c: 0.485]

        #expect(Tier(winrate: 0.60, cutoffs: cutoffs) == .a)
        #expect(Tier(winrate: 0.50, cutoffs: cutoffs) == .c)
    }

    @Test func championRoleTierComesFromTheSmoothedWinrate() {
        // Raw 0.54 would be S; (540 + 50) / (1000 + 100) = 0.5364 is still S.
        // Raw 0.535 on 200 games: (107 + 50) / 300 = 0.5233 drops to A.
        #expect(meta.tier(for: ChampionRoleStats(games: 1_000, wins: 540, timelineGames: 0)) == .s)
        #expect(meta.tier(for: ChampionRoleStats(games: 200, wins: 107, timelineGames: 0)) == .a)
    }

    @Test func championRoleBelowTheMinimumHasNoTier() {
        let stats = ChampionRoleStats(games: 199, wins: 150, timelineGames: 0)

        #expect(meta.tier(for: stats) == nil)
    }

    @Test func championRoleExactlyAtTheMinimumHasATier() {
        // (100 + 50) / (200 + 100) = 0.5 → B.
        let stats = ChampionRoleStats(games: 200, wins: 100, timelineGames: 0)

        #expect(meta.tier(for: stats) == .b)
    }

    @Test func fileWithoutAChampionRoleThresholdAssignsNoTier() {
        let meta = SnapshotMeta.example(thresholds: [:])
        let stats = ChampionRoleStats(games: 10_000, wins: 6_000, timelineGames: 0)

        #expect(meta.tier(for: stats) == nil)
    }
}
