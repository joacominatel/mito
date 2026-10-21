import MitoCore
import Testing

@testable import MitoEngine

struct SmoothingTests {
    private let priors = SnapshotMeta.example().priors

    @Test func smallChampionRoleSamplePullsTowardTheBaseline() {
        // 6/10 raw is 0.6; (6 + 100·0.5) / (10 + 100) = 56/110.
        let smoothed = priors.championRoleWinrate(wins: 6, games: 10)

        #expect(isClose(smoothed, 56.0 / 110.0))
        #expect(abs(smoothed - 0.5) < abs(0.6 - smoothed))
    }

    @Test func largeChampionRoleSampleStaysNearTheRawRate() {
        // (6000 + 50) / (10000 + 100) = 6050/10100 ≈ 0.59901.
        let smoothed = priors.championRoleWinrate(wins: 6_000, games: 10_000)

        #expect(isClose(smoothed, 6_050.0 / 10_100.0))
        #expect(abs(smoothed - 0.6) < 0.001)
    }

    @Test func noGamesIsExactlyTheBaseline() {
        #expect(priors.championRoleWinrate(wins: 0, games: 0) == 0.5)
    }

    @Test func relationCentersOnTheGivenBaselineWithTheRelationStrength() {
        // (30 + 200·0.52) / (50 + 200) = 134/250.
        let smoothed = priors.relationWinrate(wins: 30, games: 50, baseline: 0.52)

        #expect(isClose(smoothed, 0.536))
    }

    @Test func loadoutCentersOnTheGivenBaselineWithTheLoadoutStrength() {
        // (60 + 500·0.52) / (100 + 500) = 320/600.
        let smoothed = priors.loadoutWinrate(wins: 60, games: 100, baseline: 0.52)

        #expect(isClose(smoothed, 320.0 / 600.0))
    }

    @Test func strongerPriorPullsHarderOnTheSameSample() {
        let relation = priors.relationWinrate(wins: 60, games: 100, baseline: 0.5)
        let loadout = priors.loadoutWinrate(wins: 60, games: 100, baseline: 0.5)

        #expect(loadout < relation)
        #expect(relation < 0.6)
    }

    @Test func zeroStrengthAndZeroGamesFallsBackToTheBaselineInsteadOfNaN() {
        let smoothed = Smoothing.winrate(wins: 0, games: 0, strength: 0, baseline: 0.51)

        #expect(smoothed == 0.51)
    }

    @Test func zeroStrengthIsTheRawRate() {
        #expect(Smoothing.winrate(wins: 3, games: 4, strength: 0, baseline: 0.5) == 0.75)
    }
}
