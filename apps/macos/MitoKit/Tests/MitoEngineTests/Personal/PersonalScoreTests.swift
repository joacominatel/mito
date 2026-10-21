import Foundation
import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

struct PersonalScoreTests {
    private let ahri = ChampionID(rawValue: 103)
    private let syndra = ChampionID(rawValue: 134)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day = 86_400.0

    /// avg KDA (5000 + 5000) / 5000 = 2; avg CS/min 70000 / 10000 = 7;
    /// wr_s = (520 + 100·0.5) / (1000 + 100) = 570/1100.
    private let ahriMiddle = ChampionRoleStats(
        games: 1_000, wins: 520, timelineGames: 0, kills: 5_000, deaths: 5_000, assists: 5_000,
        cs: 70_000, minutes: 10_000)
    private let ahriGlobalWinrate = 570.0 / 1_100.0

    private func game(
        _ champion: ChampionID? = nil, role: Role? = .middle, win: Bool = true,
        daysAgo: Double = 0, kills: Int = 2, deaths: Int = 1, assists: Int = 1, cs: Int = 210,
        durationSeconds: Int = 1_800
    ) -> MyMatch {
        MyMatch(
            game: GameID(rawValue: 1),
            queue: QueueID(rawValue: 420),
            patch: Patch(rawValue: "16.21"),
            playedAt: now.addingTimeInterval(-daysAgo * day),
            champion: champion ?? ahri,
            role: role,
            win: win,
            kills: kills,
            deaths: deaths,
            assists: assists,
            cs: cs,
            durationSeconds: durationSeconds,
            opponent: nil,
            spells: SpellPair(
                first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
            perks: [],
            items: [],
            participants: [])
    }

    private func stats(
        _ row: ChampionRoleStats? = nil, meta: SnapshotMeta? = .example()
    ) -> InMemoryStatsProvider {
        InMemoryStatsProvider(
            meta: meta, championRoleStatsByRole: row.map { [.middle: [ahri: $0]] } ?? [:])
    }

    private func score(
        matches: [MyMatch] = [],
        pool: [PoolEntry] = [],
        overrides: [ChampionOverride] = [],
        mastery: [ChampionID: Int] = [:],
        stats: InMemoryStatsProvider? = nil
    ) -> PersonalScore {
        PersonalScoring.score(
            champion: ahri, role: .middle, matches: matches, pool: pool, overrides: overrides,
            masteryPoints: mastery, stats: stats ?? self.stats(ahriMiddle), now: now)
    }

    // MARK: - §19.2 metrics

    @Test func myGamesCountsOnlyThisChampionInThisRole() {
        let matches = [
            game(), game(win: false), game(role: .top), game(role: nil), game(syndra),
        ]

        let metrics = score(matches: matches).metrics

        #expect(metrics.games == 2)
        #expect(metrics.wins == 1)
    }

    @Test func smoothedWinratePullsFiveGamesTowardTheSnapshotWinrate() {
        let matches = [game(), game(), game(), game(), game(win: false)]

        let metrics = score(matches: matches).metrics

        // (4 + 15·570/1100) / (5 + 15); raw 0.8 lands much closer to wr_s ≈ 0.518.
        #expect(isClose(metrics.globalWinrate, ahriGlobalWinrate))
        #expect(isClose(metrics.smoothedWinrate, (4 + 15 * ahriGlobalWinrate) / 20))
    }

    @Test func recencyDecaysByAThirtyDayExponentialFromTheInjectedNow() {
        let matches = [game(daysAgo: 0), game(daysAgo: 30), game(daysAgo: 60)]

        // e^0 + e^−1 + e^−2.
        #expect(isClose(score(matches: matches).metrics.recency, 1 + exp(-1) + exp(-2)))
    }

    @Test func aGameAfterNowCountsAsPlayedNow() {
        #expect(score(matches: [game(daysAgo: -10)]).metrics.recency == 1)
    }

    @Test func masteryIsNormalizedLogarithmicallyAgainstTheHighestChampion() {
        let mastery = [ahri: 999, syndra: 999_999]

        // log(1 + 999) / log(1 + 999999) = log(10³) / log(10⁶) = 0.5.
        #expect(isClose(score(mastery: mastery).metrics.masteryNorm, 0.5))
    }

    @Test func theHighestMasteryChampionIsOne() {
        #expect(score(mastery: [ahri: 250_000, syndra: 1_000]).metrics.masteryNorm == 1)
    }

    @Test func masteryIsZeroWhenEveryChampionHasZeroPoints() {
        #expect(score(mastery: [ahri: 0, syndra: 0]).metrics.masteryNorm == 0)
    }

    @Test func masteryIsZeroForAChampionWithoutAnEntry() {
        #expect(score(mastery: [syndra: 50_000]).metrics.masteryNorm == 0)
    }

    @Test func kdaIsComparedAgainstTheSnapshotKdaFromItsSums() {
        let matches = [
            game(kills: 4, deaths: 1, assists: 2), game(kills: 2, deaths: 1, assists: 4),
        ]

        // Mine (6 + 6) / 2 = 6; average 2; 6 / 2 = 3.
        #expect(isClose(score(matches: matches).metrics.kdaVsAverage, 3))
    }

    @Test func deathlessGamesDivideByOne() {
        let matches = [game(kills: 3, deaths: 0, assists: 1)]

        // (3 + 1) / max(1, 0) = 4; 4 / 2 = 2.
        #expect(isClose(score(matches: matches).metrics.kdaVsAverage, 2))
    }

    @Test func csPerMinuteIsComparedAgainstTheSnapshotCsPerMinute() {
        let matches = [
            game(cs: 240, durationSeconds: 1_800), game(cs: 240, durationSeconds: 1_800),
        ]

        // Mine 480 / 60 min = 8; average 7; 8/7.
        #expect(isClose(score(matches: matches).metrics.csVsAverage, 8.0 / 7.0))
    }

    // MARK: - §19.3 components

    @Test func comfortWeighsGamesRecencyAndMastery() {
        // 0.6·15/30 + 0.4·2.5/5 + 0.2·0.5 = 0.3 + 0.2 + 0.1.
        #expect(isClose(PersonalScore.comfort(games: 15, recency: 2.5, masteryNorm: 0.5), 0.6))
    }

    @Test func comfortGamesAndRecencyTermsSaturate() {
        // 0.6·min(1, 90/30) + 0.4·min(1, 20/5) = 0.6 + 0.4.
        #expect(PersonalScore.comfort(games: 90, recency: 20, masteryNorm: 0) == 1)
        #expect(isClose(PersonalScore.comfort(games: 90, recency: 0, masteryNorm: 0), 0.6))
    }

    @Test func comfortIsCappedAtOne() {
        // 0.6 + 0.4 + 0.2 = 1.2, capped.
        #expect(PersonalScore.comfort(games: 30, recency: 5, masteryNorm: 1) == 1)
    }

    @Test func aChampionInTheRolePoolIsInPool() {
        let pool = [PoolEntry(role: .middle, champion: ahri, priority: 0)]

        #expect(score(pool: pool).inPool)
    }

    @Test func aChampionPooledOnlyInAnotherRoleIsNotInPool() {
        let pool = [PoolEntry(role: .top, champion: ahri, priority: 0)]

        #expect(!score(pool: pool).inPool)
    }

    @Test func anExclusionOverrideWinsOverThePool() {
        let pool = [PoolEntry(role: .middle, champion: ahri, priority: 0)]
        let overrides = [ChampionOverride(champion: ahri, role: .middle, isExcludedFromPool: true)]

        #expect(!score(pool: pool, overrides: overrides).inPool)
    }

    @Test func anOverrideThatDoesNotExcludeKeepsThePooledChampion() {
        let pool = [PoolEntry(role: .middle, champion: ahri, priority: 0)]
        let overrides = [
            ChampionOverride(champion: ahri, role: .middle, isFavorite: true),
            ChampionOverride(champion: ahri, role: .top, isExcludedFromPool: true),
        ]

        #expect(score(pool: pool, overrides: overrides).inPool)
    }

    @Test func relativePerformanceIsTheMeanExcessOfBothRatios() {
        // ((1.5 − 1) + (1.1 − 1)) / 2 = 0.3.
        let performance = PersonalScore.relativePerformance(kdaVsAverage: 1.5, csVsAverage: 1.1)

        #expect(isClose(performance, 0.3))
    }

    @Test func relativePerformanceIsClampedToOne() {
        // ((4 − 1) + (2 − 1)) / 2 = 2, clamped.
        #expect(PersonalScore.relativePerformance(kdaVsAverage: 4, csVsAverage: 2) == 1)
    }

    @Test func relativePerformanceBottomsOutAtMinusOne() {
        #expect(PersonalScore.relativePerformance(kdaVsAverage: 0, csVsAverage: 0) == -1)
    }

    // MARK: - No data

    @Test func noGamesNoSnapshotAndNoMasteryIsAZeroScoreWithoutNaN() {
        let result = score(stats: InMemoryStatsProvider())
        let metrics = result.metrics

        #expect(metrics.games == 0)
        #expect(metrics.globalWinrate == 0.5)
        #expect(metrics.smoothedWinrate == 0.5)
        #expect(metrics.recency == 0)
        #expect(metrics.masteryNorm == 0)
        #expect(metrics.kdaVsAverage == 1)
        #expect(metrics.csVsAverage == 1)
        #expect(result.winrateEdge == 0)
        #expect(result.comfort == 0)
        #expect(result.relativePerformance == 0)
        #expect(result.total == 0)
    }

    @Test func noGamesWithASnapshotRowHasNoWinrateEdgeAndNeutralRatios() {
        let result = score()

        #expect(isClose(result.metrics.smoothedWinrate, ahriGlobalWinrate))
        #expect(result.winrateEdge == 0)
        #expect(result.metrics.kdaVsAverage == 1)
        #expect(result.metrics.csVsAverage == 1)
    }

    @Test func noSnapshotRowCentersOnTheChampionRoleBaseline() {
        let matches = [game(), game()]

        let metrics = score(matches: matches, stats: stats(nil)).metrics

        // wr_s = (0 + 100·0.5) / (0 + 100) = 0.5; (2 + 15·0.5) / 17.
        #expect(metrics.globalWinrate == 0.5)
        #expect(isClose(metrics.smoothedWinrate, 9.5 / 17))
        #expect(metrics.kdaVsAverage == 1)
        #expect(metrics.csVsAverage == 1)
    }

    @Test func aSnapshotRowWithEmptySumsGivesNeutralRatios() {
        let empty = ChampionRoleStats(games: 10, wins: 5, timelineGames: 0)

        let metrics = score(matches: [game()], stats: stats(empty)).metrics

        #expect(metrics.kdaVsAverage == 1)
        #expect(metrics.csVsAverage == 1)
    }

    @Test func zeroLengthGamesGiveANeutralCsRatio() {
        let metrics = score(matches: [game(durationSeconds: 0)]).metrics

        #expect(metrics.csVsAverage == 1)
    }

    // MARK: - End to end

    @Test func scoresAPooledMainWithEveryComponent() {
        // Each game: KDA (2 + 1) / 1, 210 CS in 30 min.
        let matches = [game(), game(), game(win: false), game(syndra)]
        let pool = [PoolEntry(role: .middle, champion: ahri, priority: 0)]

        let result = score(matches: matches, pool: pool, mastery: [ahri: 999, syndra: 999_999])

        // my_wr = (2 + 15·wr_s) / 18, so the edge is (2 − 3·wr_s) / 18 ≈ 0.0247.
        let edge = (2 - 3 * ahriGlobalWinrate) / 18
        #expect(result.metrics.games == 3)
        #expect(isClose(result.winrateEdge, edge))
        // recency 3 (all today), mastery 0.5: 0.6·3/30 + 0.4·3/5 + 0.2·0.5 = 0.06 + 0.24 + 0.1.
        #expect(isClose(result.comfort, 0.4))
        #expect(result.inPool)
        // KDA 9/3 = 3 vs 2 is 1.5; CS 630/90 = 7 vs 7 is 1; ((0.5) + 0) / 2.
        #expect(isClose(result.relativePerformance, 0.25))
        // 0.4·edge + 0.3·0.4 + 0.2·1 + 0.1·0.25.
        #expect(isClose(result.total, 0.4 * edge + 0.12 + 0.2 + 0.025))
    }

    // MARK: - Scaling

    @Test func aMaximumComfortAloneIsWorthThreeWinratePointsByDefault() {
        let empty = score(stats: InMemoryStatsProvider())
        // Only the comfort term: 0.3 · 1.
        let comfortOnly = PersonalScore(
            champion: ahri, role: .middle, metrics: empty.metrics, winrateEdge: 0, comfort: 1,
            inPool: false, relativePerformance: 0, total: 0.3)

        #expect(isClose(comfortOnly.winratePoints(), 0.03))
    }

    @Test func winratePointsScaleLinearlyWithTheMaxComfortWorth() {
        let result = score(
            matches: [game()], pool: [PoolEntry(role: .middle, champion: ahri, priority: 0)])

        #expect(isClose(result.winratePoints(maxComfortWorth: 0.06), 2 * result.winratePoints()))
        #expect(isClose(result.winratePoints(), result.total * 0.1))
    }
}
