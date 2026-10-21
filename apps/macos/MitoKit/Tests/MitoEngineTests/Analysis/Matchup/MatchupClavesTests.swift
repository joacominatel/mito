import MitoCore
import Testing

@testable import MitoEngine

/// The "Claves" of the Matchup tab: curated tips win, otherwise templates from data (§20.2).
struct MatchupClavesTests {
    typealias Fixture = MatchupAnalysisTests

    @Test func everyStrongSignalBecomesAGeneratedClaveInOrder() throws {
        let analysis = try #require(
            Fixture().analysis(
                matchup: MatchupStats(
                    games: 1_000, wins: 600, timelineGames: 400, goldDiffAt15: -250,
                    csDiffAt15: -6),
                curves: [Fixture.ahri: Fixture.lateCurve, Fixture.zed: Fixture.earlyCurve],
                profiles: [
                    Fixture.ahri: Fixture.spikeProfile(levelSix: 460, first: 600),
                    Fixture.zed: Fixture.spikeProfile(levelSix: 455, first: 640),
                ]))

        let delta = try #require(analysis.matchup?.estimate?.delta)
        #expect(
            analysis.claves == [
                .generated(.matchup(delta: delta), sample: .reliable),
                .generated(.laneGold(diff: -250), sample: .reliable),
                // Level 6 is 5 s apart, so the first clear spike is the first item.
                .generated(.spike(.firstItem, first: .you, atSeconds: 600), sample: .reliable),
                .generated(.powerCurve(stronger: .you, phase: .late), sample: .reliable),
            ])
    }

    @Test func theOpponentsEdgeIsTheirClave() throws {
        let analysis = try #require(
            Fixture().analysis(
                curves: [Fixture.ahri: Fixture.earlyCurve, Fixture.zed: Fixture.lateCurve],
                profiles: [
                    Fixture.ahri: Fixture.spikeProfile(levelSix: 460),
                    Fixture.zed: Fixture.spikeProfile(levelSix: 430),
                ]))

        #expect(
            analysis.claves == [
                .generated(.spike(.levelSix, first: .opponent, atSeconds: 430), sample: .reliable),
                .generated(.powerCurve(stronger: .opponent, phase: .late), sample: .reliable),
            ])
    }

    @Test func weakSignalsAndShortSamplesMakeNoClave() throws {
        let analysis = try #require(
            Fixture().analysis(
                // A matchup at the champion's own winrate, a small gold diff, and a curve
                // under the champ_role minimum.
                matchup: MatchupStats(
                    games: 1_000, wins: 519, timelineGames: 400, goldDiffAt15: 60,
                    csDiffAt15: 1),
                curves: [Fixture.ahri: [.under20: RelationStats(games: 150, wins: 100)]]))

        #expect(analysis.claves.isEmpty)
    }

    @Test func aMatchupUnderReliableCarriesItsSample() throws {
        let analysis = try #require(
            Fixture().analysis(matchup: Fixture.matchup(games: 120, wins: 90)))

        guard case .generated(.matchup, let sample) = analysis.claves.first else {
            Issue.record("Expected a matchup clave, got \(analysis.claves)")
            return
        }
        #expect(sample == .usable)
    }

    @Test func curatedTipsReplaceTheGeneratedOnes() throws {
        let tip = CuratedTip(
            text: "Guardá la E para cuando entra la R de Zed.",
            reviewedPatch: Patch(rawValue: "16.20"))

        let analysis = try #require(
            Fixture().analysis(
                matchup: Fixture.matchup(games: 1_000, wins: 600), curatedTips: [tip]))

        #expect(analysis.claves == [.curated(tip)])
    }

    @Test func withoutAnOpponentNothingIsGenerated() throws {
        let analysis = try #require(
            Fixture().analysis(curves: [Fixture.ahri: Fixture.lateCurve], opponent: nil))

        #expect(analysis.curveSummary != nil)
        #expect(analysis.claves.isEmpty)
    }

    @Test func aLopsidedMatchupUnderTheMinimumMakesNoClave() throws {
        let analysis = try #require(
            Fixture().analysis(matchup: Fixture.matchup(games: 29, wins: 29)))

        #expect(analysis.claves.isEmpty)
    }

    @Test(arguments: [(100.0, true), (-100.0, true), (99.9, false), (-99.9, false)])
    func theGoldClaveTakesAHundredGoldEitherWay(diff: Double, isClave: Bool) throws {
        let analysis = try #require(
            Fixture().analysis(
                matchup: MatchupStats(
                    games: 1_000, wins: 519, timelineGames: 400, goldDiffAt15: diff,
                    csDiffAt15: nil)))

        #expect(
            analysis.claves
                == (isClave ? [.generated(.laneGold(diff: diff), sample: .reliable)] : []))
    }

    @Test func aLaneWithOnlyCSMakesNoGoldClave() throws {
        let analysis = try #require(
            Fixture().analysis(
                matchup: MatchupStats(
                    games: 1_000, wins: 519, timelineGames: 400, goldDiffAt15: nil,
                    csDiffAt15: -12)))

        #expect(analysis.laneDiffs != nil)
        #expect(analysis.claves.isEmpty)
    }

    @Test func withoutTheOpponentsCurveThereIsNoCurveClave() throws {
        let analysis = try #require(Fixture().analysis(curves: [Fixture.ahri: Fixture.lateCurve]))

        #expect(analysis.curveSummary?.versus == nil)
        #expect(analysis.claves.isEmpty)
    }

    @Test func curatedTipsApplyWithoutAnOpponent() throws {
        let tip = CuratedTip(text: "Jugá el nivel 2.", reviewedPatch: Patch(rawValue: "16.21"))

        let analysis = try #require(Fixture().analysis(opponent: nil, curatedTips: [tip]))

        #expect(analysis.claves == [.curated(tip)])
    }
}
