import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

/// The relation prior is 200 games (`compositionMeta`), so a segment's smoothed winrate is
/// `(wins + 200 · total) / (games + 200)`.
struct PowerCurveTests {
    private let priors = compositionMeta().priors

    @Test func earlyIsTheBucketsUpToTwentyFiveMinutesAndLateFromThirtyFive() {
        // Early 300/180: 280/500 = 0.56. Late 300/120: 220/500 = 0.44. Total 1,000/500.
        let curve = PowerCurve(earlyCurve, priors: priors)

        #expect(curve.map { isClose($0.early, 0.06) } == true)
        #expect(curve.map { isClose($0.late, -0.06) } == true)
        #expect(curve?.winrate == 0.5)
        #expect(curve?.games == 1_000)
    }

    @Test func theMiddleBucketsMoveNeitherSegment() {
        var curve = earlyCurve
        curve[.from25To30] = RelationStats(games: 200, wins: 200)
        curve[.from30To35] = RelationStats(games: 200, wins: 0)

        let result = PowerCurve(curve, priors: priors)

        #expect(result.map { isClose($0.early, 0.06) } == true)
        #expect(result.map { isClose($0.late, -0.06) } == true)
    }

    @Test func theBaselineIsTheCurvesOwnTotalWinrate() {
        // Total 1,000/600 = 0.6; early 200/120 is exactly that, and late has no games.
        let result = PowerCurve(
            [
                .under20: RelationStats(games: 200, wins: 120),
                .from30To35: RelationStats(games: 800, wins: 480),
            ], priors: priors)

        #expect(result?.winrate == 0.6)
        #expect(result.map { isClose($0.early, 0) } == true)
        #expect(result.map { isClose($0.late, 0) } == true)
    }

    @Test func aSmallSegmentIsSmoothedTowardTheTotal() {
        // Early 20/20 on a 0.5 total: (20 + 100)/220 − 0.5, not the raw +0.5.
        let result = PowerCurve(
            [
                .from20To25: RelationStats(games: 20, wins: 20),
                .from30To35: RelationStats(games: 980, wins: 480),
            ], priors: priors)

        #expect(result.map { isClose($0.early, 120.0 / 220.0 - 0.5) } == true)
    }

    @Test func aCurveWithoutGamesHasNoStrength() {
        #expect(PowerCurve([:], priors: priors) == nil)
        #expect(PowerCurve([.under20: RelationStats(games: 0, wins: 0)], priors: priors) == nil)
    }

    // MARK: - team_early

    private let garen = ChampionID(rawValue: 86)
    private let leeSin = ChampionID(rawValue: 64)
    private let jinx = ChampionID(rawValue: 222)

    @Test func teamEarlyIsTheMeanEarlyStrengthOfTheMembersWithACurve() {
        let stats = InMemoryStatsProvider(
            meta: compositionMeta(),
            durationCurvesByChampion: [
                garen: [.top: earlyCurve], leeSin: [.jungle: lateCurve],
                jinx: [.bottom: earlyCurve],
            ])
        let members = [
            TeamMember(champion: garen, role: .top), TeamMember(champion: leeSin, role: .jungle),
            TeamMember(champion: jinx, role: .bottom),
            TeamMember(champion: ChampionID(rawValue: 1), role: .middle),
        ]

        let result = Composition.teamEarly(of: members, stats: stats)

        // (0.06 − 0.06 + 0.06) / 3; the fourth member has no curve.
        #expect(result.map { isClose($0.value, 0.02) } == true)
        #expect(result?.members == 3)
    }

    @Test func aTeamWithoutCurvesHasNoTeamEarly() {
        let members = [TeamMember(champion: garen, role: .top)]

        #expect(
            Composition.teamEarly(
                of: members, stats: InMemoryStatsProvider(meta: compositionMeta())) == nil)
        #expect(
            Composition.teamEarly(
                of: members,
                stats: InMemoryStatsProvider(durationCurvesByChampion: [garen: [.top: earlyCurve]]))
                == nil)
    }
}
