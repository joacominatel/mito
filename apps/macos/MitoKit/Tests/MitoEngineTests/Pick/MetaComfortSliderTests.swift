import Foundation
import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

struct MetaComfortSliderTests {
    private let ahri = ChampionID(rawValue: 103)
    private let syndra = ChampionID(rawValue: 134)

    @Test func pureMetaGivesTheLowestPersonalWeightAndTheHighestMetaWeight() {
        let weights = PickWeights(metaComfortBalance: 0)

        #expect(isClose(weights.personal, 0.2))
        #expect(isClose(weights.meta, 1.5))
    }

    @Test func pureComfortGivesTheHighestPersonalWeightAndAPositiveMetaWeight() {
        let weights = PickWeights(metaComfortBalance: 1)

        #expect(isClose(weights.personal, 2.5))
        #expect(isClose(weights.meta, 0.5))
    }

    @Test func theSettingsDefaultReproducesTheDefaultWeights() {
        let balance = ChampSelectSettings().metaComfortBalance

        #expect(PickWeights(metaComfortBalance: balance) == PickWeights())
    }

    @Test func theOtherWeightsDoNotMove() {
        let defaults = PickWeights()
        for balance in [0.0, 0.3, 1.0] {
            let weights = PickWeights(metaComfortBalance: balance)
            #expect(weights.matchup == defaults.matchup)
            #expect(weights.counter == defaults.counter)
            #expect(weights.synergy == defaults.synergy)
            #expect(weights.composition == defaults.composition)
        }
    }

    @Test func movingTowardComfortRaisesPersonalAndLowersMeta() {
        let steps = stride(from: 0.0, through: 1.0, by: 0.05).map {
            PickWeights(metaComfortBalance: $0)
        }

        for (lower, higher) in zip(steps, steps.dropFirst()) {
            #expect(higher.personal > lower.personal)
            #expect(higher.meta < lower.meta)
            #expect(higher.meta > 0)
        }
    }

    @Test func aBalanceOutsideTheSliderClampsToItsEnds() {
        #expect(PickWeights(metaComfortBalance: -1) == PickWeights(metaComfortBalance: 0))
        #expect(PickWeights(metaComfortBalance: 2) == PickWeights(metaComfortBalance: 1))
    }

    @Test func movingTowardComfortRanksAComfortPickAboveAMetaPick() {
        // Syndra: (1050 + 50) / (1900 + 100) − 0.5 = 0.05 meta, no personal data.
        // Ahri: meta 0, comfort 1 and in pool: (0.3 + 0.2) · 0.1 = 0.05 personal points.
        let stats = InMemoryStatsProvider(
            meta: .example(),
            championRoleStatsByRole: [
                .middle: [
                    ahri: ChampionRoleStats(games: 1_000, wins: 500, timelineGames: 0),
                    syndra: ChampionRoleStats(games: 1_900, wins: 1_050, timelineGames: 0),
                ]
            ])
        let blank = PersonalScoring.score(
            champion: ahri, role: .middle, matches: [], pool: [], overrides: [],
            masteryPoints: [:], stats: stats, now: Date(timeIntervalSince1970: 0))
        let comfortable = PersonalScore(
            champion: ahri, role: .middle, metrics: blank.metrics, winrateEdge: 0, comfort: 1,
            inPool: true, relativePerformance: 0, total: 0.5)
        let draft = DraftContext(
            queue: .rankedSolo, patch: Patch(rawValue: "16.21"), myRole: .middle, myCellId: 0,
            allies: [slot(0, nil, .middle)], enemies: [], bans: [], pickable: [],
            phase: .banPick, isMyTurnToPick: true, isMyTurnToBan: false)

        func ranking(at balance: Double) -> [ChampionID] {
            PickScoring.recommendations(
                for: draft, role: .middle, mode: .all, stats: stats,
                weights: PickWeights(metaComfortBalance: balance),
                personal: { champion, _ in
                    champion == ahri ? PersonalPoints.points(comfortable) : nil
                }
            ).map(\.champion)
        }

        // s = 0: Syndra 1.5 · 0.05 = 0.075 against Ahri 0.2 · 0.05 = 0.01.
        #expect(ranking(at: 0) == [syndra, ahri])
        // s = 1: Syndra 0.5 · 0.05 = 0.025 against Ahri 2.5 · 0.05 = 0.125.
        #expect(ranking(at: 1) == [ahri, syndra])
    }
}
