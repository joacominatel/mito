import Foundation
import MitoCore
import MitoEngine
import MitoStore
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
        #expect(report.champion == Self.ahri)
        #expect(report.opponentChampion == Self.zed)
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

    @Test(arguments: [AnalysisSubject.Champion.Source.locked, .hovered])
    func generatedClavesAreWordedFromTheData(source: AnalysisSubject.Champion.Source) throws {
        let report = try #require(report(present(source: source)))

        let points = try Self.points(MatchupTestStats())
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

    // MARK: The subject's curated tips

    private static func tip(
        _ text: String, against opponent: ChampionID?, champion: ChampionID = ahri,
        role: Role = .middle, reviewed patch: String = "16.21"
    ) -> CuratedTipRecord {
        CuratedTipRecord(
            champion: champion, role: role, opponent: opponent,
            reviewedPatch: Patch(rawValue: patch), text: text)
    }

    @Test func theSubjectsTipsReplaceTheGeneratedClavesOpponentTipsFirst() throws {
        let tips = CuratedTips(records: [
            Self.tip("Jugá el nivel 2.", against: nil),
            Self.tip("Guardá la E para la R de Zed.", against: Self.zed, reviewed: "16.20"),
            Self.tip("Contra Syndra, esquivá la E.", against: ChampionID(rawValue: 134)),
            Self.tip("Zed en la jungla.", against: nil, role: .jungle),
            Self.tip("Zed de Zed.", against: nil, champion: Self.zed),
        ])

        let report = try #require(report(present(tips: tips)))

        #expect(report.claves.map(\.text) == ["Guardá la E para la R de Zed.", "Jugá el nivel 2."])
        #expect(report.claves.map(\.note) == ["revisado en 16.20", nil])
        #expect(report.claves.map(\.symbol) == ["lightbulb", "lightbulb"])
    }

    @Test func withoutAnOpponentOnlyTheGeneralTipsShow() throws {
        let tips = CuratedTips(records: [
            Self.tip("Guardá la E para la R de Zed.", against: Self.zed),
            Self.tip("Jugá el nivel 2.", against: nil, reviewed: "16.19"),
        ])

        let report = try #require(report(present(opponent: false, tips: tips)))

        #expect(report.claves.map(\.text) == ["Jugá el nivel 2."])
        #expect(report.claves.map(\.note) == ["revisado en 16.19"])
    }

    @Test func tipsForAnotherMatchupLeaveTheGeneratedClaves() throws {
        let tips = CuratedTips(records: [
            Self.tip("Contra Syndra, esquivá la E.", against: ChampionID(rawValue: 134))
        ])

        let withTips = try #require(report(present(tips: tips)))
        let without = try #require(report(present()))

        #expect(withTips.claves == without.claves)
        #expect(!withTips.claves.isEmpty)
    }

    // MARK: A recommendation

    @Test func aRecommendedChampionIsPhrasedConditionally() throws {
        let report = try #require(report(present(source: .recommended)))

        #expect(report.title == "Si elegís Ahri, contra Zed")
        #expect(report.spikes.map(\.text) == ["Zed llega a 6 a los 7:10, Ahri a los 7:40"])
        let points = try Self.points(MatchupTestStats())
        #expect(
            report.claves.map(\.text) == [
                "Con Ahri, el cruce te favorecería (\(points) puntos de winrate): podrías tomar la iniciativa en la línea",
                "Zed llega antes que Ahri al nivel 6 (7:10): convendría jugar seguro hasta entonces",
                "Ahri escala mejor que Zed desde el minuto 35: no haría falta forzar temprano",
            ])
        #expect(report.claves.map(\.symbol) == ["arrow.up", "bolt", "chart.line.uptrend.xyaxis"])
        #expect(report.claves.map(\.tone) == [.favorable, .unfavorable, .favorable])
    }

    @Test func aRecommendationShowsItsCuratedTipsAsWritten() throws {
        let tips = CuratedTips(records: [
            Self.tip("Guardá la E para la R de Zed.", against: Self.zed)
        ])

        let report = try #require(report(present(source: .recommended, tips: tips)))

        #expect(report.claves.map(\.text) == ["Guardá la E para la R de Zed."])
    }

    // MARK: Without a lane opponent

    @Test func withoutAnOpponentTheGeneralWinrateAndYourCurveAreShown() throws {
        let report = try #require(report(present(opponent: false)))

        #expect(report.title == "Ahri")
        #expect(report.opponent == "Rival de línea desconocido")
        #expect(!report.hasOpponent)
        #expect(report.opponentChampion == nil)
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

    // MARK: Missing rows

    @Test func aChampionWithoutARowInTheRoleSaysItHasNoGamesThere() throws {
        var stats = MatchupTestStats()
        stats.championRow = nil

        let report = try #require(report(present(opponent: false, stats: stats)))

        let block = try #require(report.winrates.only)
        #expect(block.id == .general)
        #expect(block.value == nil)
        #expect(block.sample == nil)
        #expect(block.note == "Sin partidas de Ahri en MID este parche")
    }

    @Test func withNeitherRowBothBlocksSayTheyHaveNoGames() throws {
        var stats = MatchupTestStats(matchup: nil)
        stats.championRow = nil

        let report = try #require(report(present(stats: stats)))

        #expect(
            report.winrates.map(\.note) == [
                "Sin partidas de este cruce en el parche",
                "Sin partidas de Ahri en MID este parche",
            ])
    }

    @Test func withoutYourProfileOnlyTheOpponentsSpikeIsShown() throws {
        var stats = MatchupTestStats()
        stats.levelSix = [238: 430]

        let report = try #require(report(present(stats: stats)))

        #expect(report.spikes.map(\.text) == ["Zed llega a 6 a los 7:10"])
        #expect(report.spikes.map(\.tone) == [.neutral])
    }

    @Test func aSpikeYouReachFirstIsFavorable() throws {
        var stats = MatchupTestStats()
        stats.levelSix = [103: 400, 238: 430]

        let report = try #require(report(present(stats: stats)))

        #expect(report.spikes.map(\.text) == ["Zed llega a 6 a los 7:10, vos a los 6:40"])
        #expect(report.spikes.map(\.tone) == [.favorable])
    }

    @Test func everyLegendarySpikeIsWordedForBothSidesAndForOne() throws {
        var stats = MatchupTestStats()
        stats.levelSix = [:]
        stats.items = [103: [600, 900, 1_200], 238: [580, 960]]

        let report = try #require(report(present(stats: stats)))

        #expect(
            report.spikes.map(\.text) == [
                "Zed completa el 1.er legendario a los 9:40, vos a los 10:00",
                "Zed completa el 2.º legendario a los 16:00, vos a los 15:00",
                "Ahri completa el 3.er legendario a los 20:00",
            ])
        #expect(report.spikes.map(\.tone) == [.unfavorable, .favorable, .neutral])
    }

    @Test func anOpponentOnlyLegendarySpikeNamesTheOpponent() throws {
        var stats = MatchupTestStats()
        stats.levelSix = [:]
        stats.items = [238: [580, 960, 1_300]]

        let report = try #require(report(present(stats: stats)))

        #expect(
            report.spikes.map(\.text) == [
                "Zed completa el 1.er legendario a los 9:40",
                "Zed completa el 2.º legendario a los 16:00",
                "Zed completa el 3.er legendario a los 21:40",
            ])
    }

    // MARK: Curves

    @Test func aChartWithAShortCurveCarriesTheLowerSample() throws {
        var stats = MatchupTestStats()
        stats.opponentCurve = [
            .under20: RelationStats(games: 300, wins: 165),
            .over40: RelationStats(games: 200, wins: 90),
        ]

        let report = try #require(report(present(stats: stats)))

        #expect(report.curve?.series.count == 2)
        #expect(report.curve?.sample == .usable)
    }

    @Test(arguments: [
        (
            MatchupTestStats.strongEarlyCurve, MatchupTestStats.flatCurve,
            "Ahri es más fuerte que Zed hasta el minuto 25",
            "Sos más fuerte que Zed hasta el minuto 25: aprovechá el arranque",
            "Ahri es más fuerte que Zed hasta el minuto 25: podrías aprovechar el arranque",
            "chart.line.uptrend.xyaxis", Tone.favorable
        ),
        (
            MatchupTestStats.flatCurve, MatchupTestStats.strongEarlyCurve,
            "Zed es más fuerte que Ahri hasta el minuto 25",
            "Zed es más fuerte hasta el minuto 25: aguantá y escalá",
            "Zed es más fuerte que Ahri hasta el minuto 25: convendría aguantar y escalar",
            "chart.line.downtrend.xyaxis", .unfavorable
        ),
        (
            MatchupTestStats.fadingCurve, MatchupTestStats.lateCurve,
            "Zed escala mejor que Ahri desde el minuto 35",
            "Zed escala mejor desde el minuto 35: buscá cerrar antes",
            "Zed escala mejor que Ahri desde el minuto 35: convendría cerrar antes",
            "chart.line.downtrend.xyaxis", .unfavorable
        ),
        (
            MatchupTestStats.lateCurve, MatchupTestStats.fadingCurve,
            "Ahri escala mejor que Zed desde el minuto 35",
            "Escalás mejor que Zed desde el minuto 35: no hace falta forzar temprano",
            "Ahri escala mejor que Zed desde el minuto 35: no haría falta forzar temprano",
            "chart.line.uptrend.xyaxis", .favorable
        ),
    ])
    func theStrongerCurveIsSummarizedAndBecomesAClave(
        mine: [DurationBucket: RelationStats], theirs: [DurationBucket: RelationStats],
        summary: String, clave: String, recommended: String, symbol: String, tone: Tone
    ) throws {
        var stats = MatchupTestStats(matchup: nil)
        stats.championCurve = mine
        stats.opponentCurve = theirs
        stats.levelSix = [:]

        let locked = try #require(report(present(stats: stats)))
        let named = try #require(report(present(source: .recommended, stats: stats)))

        #expect(locked.curve?.summary == summary)
        #expect(locked.claves.map(\.text) == [clave])
        #expect(named.claves.map(\.text) == [recommended])
        for report in [locked, named] {
            #expect(report.claves.map(\.symbol) == [symbol])
            #expect(report.claves.map(\.tone) == [tone])
        }
    }

    @Test func aloneAnEarlyCurveIsReadUpToMinuteTwentyFive() throws {
        var stats = MatchupTestStats()
        stats.championCurve = MatchupTestStats.strongEarlyCurve

        let report = try #require(report(present(opponent: false, stats: stats)))

        #expect(report.curve?.summary == "Ahri rinde más en partidas de hasta 25 minutos")
    }

    // MARK: Generated claves

    static let otherWayStats: MatchupTestStats = {
        var stats = MatchupTestStats(
            matchup: MatchupStats(
                games: 1_000, wins: 400, timelineGames: 400, goldDiffAt15: 250, csDiffAt15: 0))
        stats.levelSix = [103: 400, 238: 430]
        stats.opponentCurve = MatchupTestStats.lateCurve
        return stats
    }()

    @Test func eachDataClaveHasItsIconAndToneEitherWay() throws {
        let report = try #require(report(present(stats: Self.otherWayStats)))

        let points = try Self.points(Self.otherWayStats)
        #expect(
            report.claves.map(\.text) == [
                "El cruce es difícil (\(points) puntos de winrate): priorizá farmear seguro",
                "Se suele llegar al minuto 15 con 250 de oro a favor: hacé valer la ventaja",
                "Llegás antes que Zed al nivel 6 (6:40): es tu momento para pelear",
            ])
        #expect(report.claves.map(\.symbol) == ["arrow.down", "plus.circle", "bolt.fill"])
        #expect(report.claves.map(\.tone) == [.unfavorable, .favorable, .favorable])
    }

    @Test func eachDataClaveForARecommendationNamesItWithTheSameIconAndTone() throws {
        let report = try #require(report(present(source: .recommended, stats: Self.otherWayStats)))

        let points = try Self.points(Self.otherWayStats)
        #expect(
            report.claves.map(\.text) == [
                "Con Ahri, el cruce sería difícil (\(points) puntos de winrate): convendría farmear seguro",
                "Ahri suele llegar al minuto 15 con 250 de oro a favor: podrías hacer valer la ventaja",
                "Ahri llega antes que Zed al nivel 6 (6:40): sería tu momento para pelear",
            ])
        #expect(report.claves.map(\.symbol) == ["arrow.down", "plus.circle", "bolt.fill"])
        #expect(report.claves.map(\.tone) == [.unfavorable, .favorable, .favorable])
    }

    @Test(arguments: [
        (
            AnalysisSubject.Champion.Source.locked,
            "Zed suele sacar 250 de oro de ventaja al minuto 15: evitá los intercambios largos temprano"
        ),
        (
            .recommended,
            "Zed le suele sacar 250 de oro de ventaja a Ahri al minuto 15: convendría evitar los intercambios largos temprano"
        ),
    ])
    func goldBehindAtFifteenNamesTheOpponent(
        source: AnalysisSubject.Champion.Source, text: String
    ) throws {
        let stats = MatchupTestStats(
            matchup: MatchupStats(
                games: 1_000, wins: 519, timelineGames: 400, goldDiffAt15: -250, csDiffAt15: nil))

        let report = try #require(report(present(source: source, stats: stats)))

        let gold = try #require(report.claves.first { $0.symbol == "minus.circle" })
        #expect(gold.text == text)
        #expect(gold.tone == .unfavorable)
    }

    // MARK: Signs

    @Test(
        arguments: [
            (0.4, nil, "0", Tone.neutral), (-0.4, nil, "0", .neutral), (85, nil, "+85", .favorable),
            (nil, 0.04, "0,0", .neutral), (nil, -4.2, "\u{2212}4,2", .unfavorable),
        ] as [(Double?, Double?, String, Tone)])
    func aLaneDiffIsSignedOnlyWhenItIsNotZero(
        gold: Double?, cs: Double?, value: String, tone: Tone
    ) throws {
        let stats = MatchupTestStats(
            matchup: MatchupStats(
                games: 1_000, wins: 600, timelineGames: 400, goldDiffAt15: gold, csDiffAt15: cs))

        let item = try #require(report(present(stats: stats))?.laneDiffs?.items.only)

        #expect(item.value == value)
        #expect(item.tone == tone)
    }

    @Test(
        arguments: [
            (0.5, nil), (-0.5, nil), (nil, -0.05), (nil, 0.05),
        ] as [(Double?, Double?)])
    func aLaneDiffThatShowsAsZeroHasNoSignAtTheHalf(gold: Double?, cs: Double?) throws {
        let stats = MatchupTestStats(
            matchup: MatchupStats(
                games: 1_000, wins: 600, timelineGames: 400, goldDiffAt15: gold, csDiffAt15: cs))

        let item = try #require(report(present(stats: stats))?.laneDiffs?.items.only)

        #expect(item.value == (gold == nil ? "0,0" : "0"))
        #expect(item.tone == .neutral)
    }

    @Test(
        arguments: [
            (2.5, nil, "+2", Tone.favorable), (-2.5, nil, "\u{2212}2", .unfavorable),
            (3.5, nil, "+4", .favorable), (nil, 0.25, "+0,2", .favorable),
            (nil, -0.15, "\u{2212}0,2", .unfavorable),
        ] as [(Double?, Double?, String, Tone)])
    func aLaneDiffAtTheHalfShowsTheNumberItsToneReads(
        gold: Double?, cs: Double?, value: String, tone: Tone
    ) throws {
        let stats = MatchupTestStats(
            matchup: MatchupStats(
                games: 1_000, wins: 600, timelineGames: 400, goldDiffAt15: gold, csDiffAt15: cs))

        let item = try #require(report(present(stats: stats))?.laneDiffs?.items.only)

        #expect(item.value == value)
        #expect(item.tone == tone)
    }

    // MARK: Helpers

    /// The matchup delta as a clave words it.
    static func points(_ stats: MatchupTestStats) throws -> String {
        let delta = try #require(
            MatchupAnalysis(champion: ahri, role: .middle, opponent: zed, stats: stats)?.matchup?
                .estimate?.delta)
        return WinratePoints.text(delta, locale: locale)
    }

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
        stats: MatchupTestStats = MatchupTestStats(), tips: CuratedTips = .empty
    ) -> MatchupPresentation {
        let subject = AnalysisSubject(
            queue: role == nil ? .aram : .rankedSolo,
            champion: champion.map { AnalysisSubject.Champion(id: $0, source: source) },
            role: role,
            laneOpponent: opponent && role != nil
                ? AnalysisSubject.LaneOpponent(cellId: 5, champion: Self.zed, role: opponentRole)
                : nil,
            allies: [], enemies: [], stats: stats, tips: tips, personal: PersonalInputs(),
            names: Self.names,
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

    /// Total 530/1,000: strong before minute 25, a little weak from 35.
    static let strongEarlyCurve: [DurationBucket: RelationStats] = [
        .under20: RelationStats(games: 300, wins: 180),
        .from25To30: RelationStats(games: 400, wins: 200),
        .over40: RelationStats(games: 300, wins: 150),
    ]
    static let flatCurve: [DurationBucket: RelationStats] = [
        .under20: RelationStats(games: 500, wins: 250),
        .over40: RelationStats(games: 500, wins: 250),
    ]
    static let lateCurve: [DurationBucket: RelationStats] = [
        .under20: RelationStats(games: 600, wins: 270),
        .over40: RelationStats(games: 400, wins: 230),
    ]
    static let fadingCurve: [DurationBucket: RelationStats] = [
        .under20: RelationStats(games: 600, wins: 330),
        .over40: RelationStats(games: 400, wins: 180),
    ]

    var meta: SnapshotMeta? = Self.meta
    var championRow: ChampionRoleStats? = ChampionRoleStats(
        games: 3_000, wins: 1_560, timelineGames: 0)
    var matchup: MatchupStats? = MatchupStats(
        games: 1_000, wins: 600, timelineGames: 400, goldDiffAt15: -85, csDiffAt15: 4.2)
    var championCurve: [DurationBucket: RelationStats] = Self.lateCurve
    var opponentCurve: [DurationBucket: RelationStats] = Self.fadingCurve
    /// `lvl6_s` by champion raw value; a champion left out has no profile.
    var levelSix: [Int: Int] = [103: 460, 238: 430]
    /// The 1st to 3rd legendary's second by champion raw value.
    var items: [Int: [Int]] = [:]

    func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }

    func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
        guard role == .middle, let championRow else { return [:] }
        return [ChampionID(rawValue: 103): championRow]
    }

    func matchup(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> MatchupStats?
    {
        champion.rawValue == 103 && role == .middle && opponent.rawValue == 238 ? matchup : nil
    }

    func durationCurves(for champion: ChampionID, role: Role) -> [DurationBucket: RelationStats] {
        guard role == .middle else { return [:] }
        return switch champion.rawValue {
        case 103: championCurve
        case 238: opponentCurve
        default: [:]
        }
    }

    func championProfile(for champion: ChampionID, role: Role) -> ChampionProfile? {
        let id = champion.rawValue
        let item = items[id] ?? []
        guard levelSix[id] != nil || !item.isEmpty else { return nil }
        return ChampionProfile(
            physicalShare: 0.5, magicShare: 0.5, trueShare: 0, damagePerMinute: 600,
            tankiness: 0.3, ccScore: 0.4, timelineGames: 800, levelSixSeconds: levelSix[id],
            firstItemSeconds: item.first, secondItemSeconds: item.dropFirst().first,
            thirdItemSeconds: item.dropFirst(2).first)
    }
}
