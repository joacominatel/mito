import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

/// Ahri MID against Zed, on the §17 example `meta`: `champ_role` 200/1,000, `matchup` 30/300,
/// `build_layer` 100/600, relation prior 200 games.
struct MatchupAnalysisTests {
    static let ahri = ChampionID(rawValue: 103)
    static let zed = ChampionID(rawValue: 238)
    /// `wr_smoothed(Ahri, MID)` = (1,560 + 50) / 3,100.
    static let ahriStats = ChampionRoleStats(games: 3_000, wins: 1_560, timelineGames: 0)
    static let ahriBaseline = 1_610.0 / 3_100.0

    // MARK: Winrate

    @Test func theMatchupIsSmoothedTowardTheChampionsWinrateWithARawInterval() throws {
        let analysis = try #require(
            analysis(
                matchup: MatchupStats(
                    games: 1_000, wins: 560, timelineGames: 0, goldDiffAt15: nil, csDiffAt15: nil)))

        let matchup = try #require(analysis.matchup)
        let estimate = try #require(matchup.estimate)
        let smoothed = (560 + 200 * Self.ahriBaseline) / 1_200
        #expect(isClose(estimate.winrate, smoothed))
        #expect(estimate.delta.map { isClose($0, smoothed - Self.ahriBaseline) } == true)
        #expect(estimate.interval == WilsonInterval(wins: 560, games: 1_000))
        #expect(matchup.games == 1_000)
        #expect(matchup.sample == .reliable)
    }

    @Test func aMatchupUnderReliableIsUsableAndUnderTheMinimumHasNoNumber() throws {
        let usable = try #require(analysis(matchup: Self.matchup(games: 299, wins: 150)))
        #expect(usable.matchup?.sample == .usable)
        #expect(usable.matchup?.estimate != nil)

        let short = try #require(analysis(matchup: Self.matchup(games: 29, wins: 20)))
        #expect(short.matchup?.games == 29)
        #expect(short.matchup?.sample == .belowMinimum)
        #expect(short.matchup?.estimate == nil)
    }

    @Test func theGeneralWinrateIsTheChampionRoleRowWithoutADelta() throws {
        let analysis = try #require(analysis(opponent: nil))

        #expect(analysis.matchup == nil)
        let general = try #require(analysis.general)
        #expect(general.sample == .reliable)
        #expect(general.estimate.map { isClose($0.winrate, Self.ahriBaseline) } == true)
        #expect(general.estimate?.delta == nil)
        #expect(general.estimate?.interval == WilsonInterval(wins: 1_560, games: 3_000))
    }

    @Test func aChampionUnderTheChampRoleMinimumHasNoGeneralNumber() throws {
        let analysis = try #require(
            analysis(
                championStats: ChampionRoleStats(games: 150, wins: 90, timelineGames: 0),
                opponent: nil))

        #expect(analysis.general?.sample == .belowMinimum)
        #expect(analysis.general?.estimate == nil)
    }

    @Test func withoutASnapshotThereIsNoAnalysis() {
        let stats = InMemoryStatsProvider()

        #expect(
            MatchupAnalysis(champion: Self.ahri, role: .middle, opponent: Self.zed, stats: stats)
                == nil)
    }

    // MARK: Lane diffs

    @Test func theDiffsNeedTimelineGamesOverTheMatchupMinimum() throws {
        let shown = try #require(
            analysis(
                matchup: MatchupStats(
                    games: 1_000, wins: 500, timelineGames: 120, goldDiffAt15: -85,
                    csDiffAt15: 4.2)))
        #expect(shown.laneDiffs?.goldAt15 == -85)
        #expect(shown.laneDiffs?.csAt15 == 4.2)
        #expect(shown.laneDiffs?.timelineGames == 120)
        #expect(shown.laneDiffs?.sample == .usable)

        let none = try #require(
            analysis(
                matchup: MatchupStats(
                    games: 1_000, wins: 500, timelineGames: 0, goldDiffAt15: nil,
                    csDiffAt15: nil)))
        #expect(none.laneDiffs == nil)

        let few = try #require(
            analysis(
                matchup: MatchupStats(
                    games: 1_000, wins: 500, timelineGames: 29, goldDiffAt15: 300,
                    csDiffAt15: 9)))
        #expect(few.laneDiffs == nil)
    }

    // MARK: Duration curve

    @Test func theCurveSkipsEmptyBucketsAndSmoothsTowardItsOwnTotal() throws {
        let analysis = try #require(
            analysis(curves: [
                Self.ahri: [
                    .over40: RelationStats(games: 400, wins: 240),
                    .under20: RelationStats(games: 600, wins: 260),
                    .from25To30: RelationStats(games: 0, wins: 0),
                ]
            ]))

        let curve = try #require(analysis.curve)
        #expect(curve.points.map(\.bucket) == [.under20, .over40])
        #expect(curve.points.map(\.games) == [600, 400])
        // Total 500/1,000 = 0.5; <20 is (260 + 100) / 800.
        #expect(curve.points.first.map { isClose($0.winrate, 360.0 / 800.0) } == true)
        #expect(curve.sample == .reliable)
    }

    @Test func aCurveUnderTheChampRoleMinimumIsNotDrawn() throws {
        let analysis = try #require(
            analysis(curves: [Self.ahri: [.under20: RelationStats(games: 150, wins: 80)]]))

        #expect(analysis.curve == nil)
        #expect(analysis.curveSummary == nil)
    }

    @Test func theOpponentsCurveIsReadInTheSameRole() throws {
        let analysis = try #require(analysis(curves: [Self.zed: Self.earlyCurve]))

        #expect(analysis.opponentCurve?.champion == Self.zed)
        #expect(analysis.curve == nil)
    }

    // MARK: Curve summary

    @Test func theCurveThatGainsMoreLateScalesBetter() throws {
        let analysis = try #require(
            analysis(curves: [Self.ahri: Self.lateCurve, Self.zed: Self.earlyCurve]))

        let summary = try #require(analysis.curveSummary)
        #expect(summary.stronger == Self.ahri)
        #expect(summary.versus == Self.zed)
        #expect(summary.phase == .late)
        #expect(summary.phase.minute == 35)
    }

    @Test func theOpponentCanBeTheStrongerOne() throws {
        let analysis = try #require(
            analysis(curves: [Self.ahri: Self.earlyCurve, Self.zed: Self.lateCurve]))

        #expect(analysis.curveSummary?.stronger == Self.zed)
        #expect(analysis.curveSummary?.versus == Self.ahri)
    }

    @Test func curvesThatDifferByLessThanAPointSayNothing() throws {
        let analysis = try #require(
            analysis(curves: [Self.ahri: Self.lateCurve, Self.zed: Self.lateCurve]))

        #expect(analysis.curveSummary == nil)
    }

    @Test func aloneTheCurveIsReadAgainstItsOwnAverage() throws {
        let late = try #require(analysis(curves: [Self.ahri: Self.lateCurve], opponent: nil))
        #expect(late.curveSummary?.phase == .late)
        #expect(late.curveSummary?.versus == nil)

        let early = try #require(analysis(curves: [Self.ahri: Self.earlyCurve], opponent: nil))
        #expect(early.curveSummary?.phase == .early)
        #expect(early.curveSummary?.phase.minute == 25)

        let flat = try #require(
            analysis(
                curves: [
                    Self.ahri: [
                        .under20: RelationStats(games: 500, wins: 250),
                        .over40: RelationStats(games: 500, wins: 250),
                    ]
                ], opponent: nil))
        #expect(flat.curveSummary == nil)
    }

    // MARK: Power spikes

    @Test func spikesCompareBothSidesInMilestoneOrder() throws {
        let analysis = try #require(
            analysis(profiles: [
                Self.ahri: Self.spikeProfile(levelSix: 460, first: 620, third: 1_500),
                Self.zed: Self.spikeProfile(levelSix: 430, first: 610),
            ]))

        #expect(analysis.spikes.map(\.milestone) == [.levelSix, .firstItem, .thirdItem])
        #expect(analysis.spikes.map(\.mine) == [460, 620, 1_500])
        #expect(analysis.spikes.map(\.theirs) == [430, 610, nil])
        // 30 s apart is clear; 10 s is noise; one-sided has no leader.
        #expect(analysis.spikes.map(\.first) == [.opponent, nil, nil])
    }

    @Test func aProfileUnderTheBuildLayerMinimumIsLeftOut() throws {
        let analysis = try #require(
            analysis(profiles: [
                Self.ahri: Self.spikeProfile(levelSix: 460, timelineGames: 400),
                Self.zed: Self.spikeProfile(levelSix: 430, timelineGames: 99),
            ]))

        #expect(analysis.spikes.map(\.theirs) == [nil])
        #expect(analysis.spikes.map(\.sample) == [.usable])
    }

    @Test func withoutAnOpponentOnlyYourSpikesAreShown() throws {
        let analysis = try #require(
            analysis(
                profiles: [
                    Self.ahri: Self.spikeProfile(levelSix: 460),
                    Self.zed: Self.spikeProfile(levelSix: 430),
                ], opponent: nil))

        #expect(analysis.spikes.map(\.mine) == [460])
        #expect(analysis.spikes.map(\.theirs) == [nil])
    }

    // MARK: Helpers

    static func matchup(games: Int, wins: Int) -> MatchupStats {
        MatchupStats(
            games: games, wins: wins, timelineGames: 0, goldDiffAt15: nil, csDiffAt15: nil)
    }

    /// Early 600/330, late 400/180 on a 0.51 total.
    static let earlyCurve: [DurationBucket: RelationStats] = [
        .under20: RelationStats(games: 600, wins: 330),
        .over40: RelationStats(games: 400, wins: 180),
    ]
    /// Early 600/270, late 400/230 on a 0.5 total.
    static let lateCurve: [DurationBucket: RelationStats] = [
        .under20: RelationStats(games: 600, wins: 270),
        .over40: RelationStats(games: 400, wins: 230),
    ]

    static func spikeProfile(
        levelSix: Int? = nil, first: Int? = nil, third: Int? = nil, timelineGames: Int = 800
    ) -> ChampionProfile {
        ChampionProfile(
            physicalShare: 0, magicShare: 1, trueShare: 0, damagePerMinute: 600, tankiness: 0.2,
            ccScore: 0.4, timelineGames: timelineGames, levelSixSeconds: levelSix,
            firstItemSeconds: first, thirdItemSeconds: third)
    }

    func analysis(
        championStats: ChampionRoleStats = ahriStats, matchup: MatchupStats? = nil,
        curves: [ChampionID: [DurationBucket: RelationStats]] = [:],
        profiles: [ChampionID: ChampionProfile] = [:], opponent: ChampionID? = zed,
        curatedTips: [CuratedTip] = []
    ) -> MatchupAnalysis? {
        let stats = InMemoryStatsProvider(
            meta: .example(),
            championRoleStatsByRole: [.middle: [Self.ahri: championStats]],
            matchupsByChampion: matchup.map { [Self.ahri: [.middle: [Self.zed: $0]]] } ?? [:],
            championProfilesByChampion: profiles.mapValues { [.middle: $0] },
            durationCurvesByChampion: curves.mapValues { [.middle: $0] })
        return MatchupAnalysis(
            champion: Self.ahri, role: .middle, opponent: opponent, stats: stats,
            curatedTips: curatedTips)
    }
}
