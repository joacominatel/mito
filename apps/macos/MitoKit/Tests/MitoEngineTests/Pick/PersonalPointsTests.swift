import Foundation
import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

struct PersonalPointsTests {
    private let ahri = ChampionID(rawValue: 103)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private var noData: PersonalScore {
        PersonalScoring.score(
            champion: ahri, role: .middle, matches: [], pool: [], overrides: [],
            masteryPoints: [:], stats: InMemoryStatsProvider(), now: now)
    }

    private func score(
        edge: Double = 0, comfort: Double = 0, inPool: Bool = false, relative: Double = 0
    ) -> PersonalScore {
        PersonalScore(
            champion: ahri, role: .middle, metrics: noData.metrics, winrateEdge: edge,
            comfort: comfort, inPool: inPool, relativePerformance: relative, total: .nan)
    }

    @Test func theWinrateEdgeCountsUnscaled() {
        // 0.4 · 0.05, no ×0.1.
        #expect(isClose(PersonalPoints.points(score(edge: 0.05)), 0.02))
    }

    @Test func aMaximumComfortIsWorthTheMaxComfortWorth() {
        #expect(isClose(PersonalPoints.points(score(comfort: 1)), 0.03))
        #expect(isClose(PersonalPoints.points(score(comfort: 1), maxComfortWorth: 0.05), 0.05))
    }

    @Test func thePoolAndRelativePerformanceTermsShareTheComfortScale() {
        // (0.2 · 1 + 0.1 · 0.5) · 0.03 / 0.3 = 0.025.
        #expect(isClose(PersonalPoints.points(score(inPool: true, relative: 0.5)), 0.025))
    }

    @Test func theUnitlessTermsScaleLinearlyWithTheMaxComfortWorth() {
        // Edge 0.4 · 0.05 = 0.02; unitless 0.3 · 0.4 + 0.2 + 0.1 · 0.25 = 0.345.
        let mixed = score(edge: 0.05, comfort: 0.4, inPool: true, relative: 0.25)

        #expect(isClose(PersonalPoints.points(mixed, maxComfortWorth: 0.03), 0.02 + 0.0345))
        #expect(isClose(PersonalPoints.points(mixed, maxComfortWorth: 0.06), 0.02 + 0.069))
        #expect(isClose(PersonalPoints.points(mixed, maxComfortWorth: 0), 0.02))
    }

    @Test func aScoreWithoutPersonalDataIsWorthNothing() {
        #expect(PersonalPoints.points(noData) == 0)
    }
}
