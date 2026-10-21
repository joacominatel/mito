import Foundation
import MitoCore
import MitoEngine
import Testing

@testable import Mito

/// What the Matchup tab shows for each subject, in es-AR (§20.2).
struct MatchupPresentationTests {
    nonisolated static let locale = Locale(identifier: "es_AR")
    nonisolated static let ahri = ChampionID(rawValue: 103)
    nonisolated static let zed = ChampionID(rawValue: 238)

    static func percent(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.percent.precision(.fractionLength(digits)).locale(locale))
    }

    // MARK: States

    @Test func aramHasNoMatchup() {
        #expect(present(role: nil) == .aram)
    }

    @Test func withoutAChampionTheTabSaysSo() {
        #expect(present(champion: nil) == .noChampion)
    }

    @Test func withoutASnapshotThereIsNothingToAnalyze() {
        #expect(present(stats: MatchupTestStats(meta: nil)) == .noStats)
    }

    // MARK: Against a lane opponent

    @Test func aLaneOpponentGivesTheMatchupWithItsInferredProbability() throws {
        let report = try #require(report(present()))

        #expect(report.title == "Ahri vs Zed")
        #expect(report.opponent == "Rival de línea: Zed (MID? \(Self.percent(0.82, digits: 0)))")
        #expect(report.hasOpponent)
    }

    @Test func anAssignedOpponentHasNoQuestionMarkAndAGuessSaysItHasNoData() throws {
        let assigned = try #require(report(present(opponentRole: .assigned(.middle))))
        #expect(assigned.opponent == "Rival de línea: Zed (MID)")

        let guessed = try #require(
            report(present(opponentRole: .guessed(.middle, probability: 0.2))))
        #expect(guessed.opponent == "Rival de línea: Zed (MID?, sin datos)")
    }

    @Test func theMatchupBlockCarriesTheSmoothedWinrateIntervalDeltaAndSample() throws {
        let report = try #require(report(present()))

        let block = try #require(report.winrates.only)
        let analysis = try #require(
            MatchupAnalysis(
                champion: Self.ahri, role: .middle, opponent: Self.zed, stats: MatchupTestStats()))
        let estimate = try #require(analysis.matchup?.estimate)
        #expect(block.id == .matchup)
        #expect(block.title == "Winrate contra Zed")
        #expect(block.value == Self.percent(estimate.winrate))
        #expect(
            block.interval
                == "IC 90 %: \(Self.percent(estimate.interval.lower)) – \(Self.percent(estimate.interval.upper))"
        )
        #expect(block.delta == estimate.delta)
        #expect(block.deltaCaption == "respecto del promedio de Ahri")
        #expect(block.games == "1.000 partidas")
        #expect(block.sample == .reliable)
        #expect(block.note == nil)
    }

    @Test func theLaneDiffsAreSignedWithTheirTone() throws {
        let report = try #require(report(present()))

        let diffs = try #require(report.laneDiffs)
        #expect(
            diffs.items == [
                LaneDiffsBlock.Item(id: "Oro @15", value: "\u{2212}85", tone: .unfavorable),
                LaneDiffsBlock.Item(id: "CS @15", value: "+4,2", tone: .favorable),
            ])
        #expect(diffs.games == "400 partidas con timeline")
        #expect(diffs.sample == .reliable)
    }

    @Test func bothCurvesAreDrawnWithTheSummaryLine() throws {
        let report = try #require(report(present()))

        let curve = try #require(report.curve)
        #expect(curve.series.map(\.name) == ["Ahri", "Zed"])
        #expect(curve.series.first?.points.map(\.label) == ["<20", "40+"])
        #expect(curve.series.first?.points.first?.accessibilityLabel == "Ahri, menos de 20 minutos")
        #expect(curve.summary == "Ahri escala mejor que Zed desde el minuto 35")
        #expect(curve.sample == .reliable)
    }

    @Test func theAxisHasEveryBucketEitherCurveHasInGameLengthOrder() throws {
        var stats = MatchupTestStats()
        stats.opponentCurve[.from20To25] = RelationStats(games: 300, wins: 150)

        let report = try #require(report(present(stats: stats)))

        #expect(report.curve?.axisLabels == ["<20", "20–25", "40+"])
    }

    @Test func spikesNameTheOpponentFirstAndYouAsVos() throws {
        let report = try #require(report(present()))

        #expect(report.spikes.map(\.text) == ["Zed llega a 6 a los 7:10, vos a los 7:40"])
        #expect(report.spikes.map(\.tone) == [.unfavorable])
    }

    @Test func generatedClavesAreWordedFromTheData() throws {
        let report = try #require(report(present()))

        let points = WinratePoints.text(
            try #require(
                MatchupAnalysis(
                    champion: Self.ahri, role: .middle, opponent: Self.zed,
                    stats: MatchupTestStats())?.matchup?.estimate?.delta), locale: Self.locale)
        #expect(
            report.claves.map(\.text) == [
                "El cruce te favorece (\(points) puntos de winrate): podés tomar la iniciativa en la línea",
                "Zed llega antes al nivel 6 (7:10): jugá seguro hasta entonces",
                "Escalás mejor que Zed desde el minuto 35: no hace falta forzar temprano",
            ])
    }

    @Test func aCuratedTipFromAnOlderPatchSaysWhenItWasReviewed() throws {
        let tips = [
            CuratedTip(
                text: "Guardá la E para cuando entra la R de Zed.",
                reviewedPatch: Patch(rawValue: "16.20")),
            CuratedTip(
                text: "Pegale en la línea a nivel 2.", reviewedPatch: Patch(rawValue: "16.21")),
        ]
        let analysis = try #require(
            MatchupAnalysis(
                champion: Self.ahri, role: .middle, opponent: Self.zed, stats: MatchupTestStats(),
                curatedTips: tips))

        let report = wording().report(analysis)

        #expect(report.claves.map(\.text) == tips.map(\.text))
        #expect(report.claves.map(\.note) == ["revisado en 16.20", nil])
        #expect(report.claves.map(\.sample) == [nil, nil])
    }

    // MARK: A recommendation

    @Test func aRecommendedChampionIsPhrasedConditionally() throws {
        let report = try #require(report(present(source: .recommended)))

        #expect(report.title == "Si elegís Ahri, contra Zed")
        #expect(report.spikes.map(\.text) == ["Zed llega a 6 a los 7:10, Ahri a los 7:40"])
    }

    // MARK: Without a lane opponent

    @Test func withoutAnOpponentTheGeneralWinrateAndYourCurveAreShown() throws {
        let report = try #require(report(present(opponent: false)))

        #expect(report.title == "Ahri")
        #expect(report.opponent == "Rival de línea desconocido")
        #expect(!report.hasOpponent)
        let block = try #require(report.winrates.only)
        #expect(block.id == .general)
        #expect(block.title == "Winrate general en MID")
        #expect(block.delta == nil)
        #expect(report.laneDiffs == nil)
        #expect(report.curve?.series.map(\.name) == ["Ahri"])
        #expect(report.curve?.summary == "Ahri rinde más en partidas de 35 minutos o más")
        #expect(report.spikes.map(\.text) == ["Ahri llega a 6 a los 7:40"])
        #expect(report.claves.isEmpty)
    }

    @Test func aRecommendationWithoutAnOpponentIsStillConditional() throws {
        let report = try #require(report(present(source: .recommended, opponent: false)))

        #expect(report.title == "Si elegís Ahri")
    }

    // MARK: Low sample

    @Test func aMatchupUnderTheMinimumHasNoNumberAndFallsBackToTheGeneralWinrate() throws {
        let report = try #require(
            report(present(stats: MatchupTestStats(matchup: Self.matchup(games: 20, wins: 15)))))

        #expect(report.winrates.map(\.id) == [.matchup, .general])
        let matchup = try #require(report.winrates.first)
        #expect(matchup.value == nil)
        #expect(matchup.interval == nil)
        #expect(matchup.games == "20 partidas")
        #expect(matchup.sample == .belowMinimum)
        #expect(matchup.note == "Pocas partidas para dar un número")
        #expect(report.winrates.last?.value != nil)
    }

    @Test func aMatchupUnderReliableKeepsItsNumberMarkedAsLowSample() throws {
        let report = try #require(
            report(present(stats: MatchupTestStats(matchup: Self.matchup(games: 120, wins: 70)))))

        let block = try #require(report.winrates.only)
        #expect(block.value != nil)
        #expect(block.sample == .usable)
    }

    @Test func aMatchupWithoutARowSaysSo() throws {
        let report = try #require(report(present(stats: MatchupTestStats(matchup: nil))))

        #expect(report.winrates.map(\.id) == [.matchup, .general])
        #expect(report.winrates.first?.note == "Sin partidas de este cruce en el parche")
        #expect(report.winrates.first?.sample == nil)
    }

    // MARK: Helpers

    static func matchup(games: Int, wins: Int) -> MatchupStats {
        MatchupStats(
            games: games, wins: wins, timelineGames: 0, goldDiffAt15: nil, csDiffAt15: nil)
    }

    private func report(_ presentation: MatchupPresentation) -> MatchupReport? {
        if case .ready(let report) = presentation { report } else { nil }
    }

    private func present(
        champion: ChampionID? = ahri, source: AnalysisSubject.Champion.Source = .locked,
        role: Role? = .middle, opponent: Bool = true,
        opponentRole: AnalysisSubject.SlotRole = .inferred(.middle, probability: 0.82),
        stats: MatchupTestStats = MatchupTestStats()
    ) -> MatchupPresentation {
        let subject = AnalysisSubject(
            queue: role == nil ? .aram : .rankedSolo,
            champion: champion.map { AnalysisSubject.Champion(id: $0, source: source) },
            role: role,
            laneOpponent: opponent && role != nil
                ? AnalysisSubject.LaneOpponent(cellId: 5, champion: Self.zed, role: opponentRole)
                : nil,
            allies: [], enemies: [], stats: stats, personal: PersonalInputs(), names: Self.names,
            gameData: nil)
        return MatchupPresentation(subject: subject, locale: Self.locale)
    }

    private func wording() -> MatchupWording {
        MatchupWording(
            champion: AnalysisSubject.Champion(id: Self.ahri, source: .locked), role: .middle,
            opponent: AnalysisSubject.LaneOpponent(
                cellId: 5, champion: Self.zed, role: .assigned(.middle)),
            names: Self.names, patch: MatchupTestStats.meta.patch, locale: Self.locale)
    }

    static let names = ReasonNames(
        champion: { [103: "Ahri", 238: "Zed"][$0.rawValue] ?? "?" }, item: { _ in "?" })
}

extension Array {
    fileprivate var only: Element? { count == 1 ? first : nil }
}

/// Ahri MID 3,000 games; against Zed 1,000 games at 60 %, with 400 timeline games. Ahri's curve
/// gains late and Zed's fades; Zed reaches level 6 at 7:10 and Ahri at 7:40.
nonisolated struct MatchupTestStats: StatsProvider {
    static let meta = SnapshotMeta(
        patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420), bracket: .emeraldPlus,
        matches: 100_000, blendPatches: [Patch(rawValue: "16.21")],
        thresholds: [
            .championRole: SampleThreshold(minimum: 200, reliable: 1_000),
            .matchup: SampleThreshold(minimum: 30, reliable: 300),
            .buildLayer: SampleThreshold(minimum: 100, reliable: 600),
        ],
        priors: SmoothingPriors(
            championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
            loadoutStrength: 500),
        tierCutoffs: [:])

    var meta: SnapshotMeta? = Self.meta
    var matchup: MatchupStats? = MatchupStats(
        games: 1_000, wins: 600, timelineGames: 400, goldDiffAt15: -85, csDiffAt15: 4.2)
    var opponentCurve: [DurationBucket: RelationStats] = [
        .under20: RelationStats(games: 600, wins: 330),
        .over40: RelationStats(games: 400, wins: 180),
    ]

    func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }

    func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
        role == .middle
            ? [
                ChampionID(rawValue: 103): ChampionRoleStats(
                    games: 3_000, wins: 1_560, timelineGames: 0)
            ]
            : [:]
    }

    func matchup(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> MatchupStats?
    {
        champion.rawValue == 103 && role == .middle && opponent.rawValue == 238 ? matchup : nil
    }

    func durationCurves(for champion: ChampionID, role: Role) -> [DurationBucket: RelationStats] {
        guard role == .middle else { return [:] }
        return switch champion.rawValue {
        case 103:
            [
                .under20: RelationStats(games: 600, wins: 270),
                .over40: RelationStats(games: 400, wins: 230),
            ]
        case 238: opponentCurve
        default: [:]
        }
    }

    func championProfile(for champion: ChampionID, role: Role) -> ChampionProfile? {
        let levelSix = [103: 460, 238: 430][champion.rawValue]
        return levelSix.map {
            ChampionProfile(
                physicalShare: 0.5, magicShare: 0.5, trueShare: 0, damagePerMinute: 600,
                tankiness: 0.3, ccScore: 0.4, timelineGames: 800, levelSixSeconds: $0)
        }
    }
}
