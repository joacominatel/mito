import Foundation
import MitoCore
import MitoEngine
import Testing

@testable import Mito

/// The Mi historial tab's mapping from the analysis subject (§20.2).
@Suite(.timeLimit(.minutes(1)))
struct HistorySummaryTests {
    static let ahri = ChampionID(rawValue: 103)
    static let syndra = ChampionID(rawValue: 134)
    static let zed = ChampionID(rawValue: 238)
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let locale = Locale(identifier: "es_AR")

    // MARK: States

    @Test func noGamesAtAllIsTheEmptyHistory() {
        let summary = Self.summary(matches: [])

        #expect(summary.content == .noHistory)
        #expect(summary.notes.isEmpty)
    }

    @Test func noChampionIsItsOwnEmptyState() {
        let summary = Self.summary(champion: nil, matches: [Self.game()])

        #expect(summary.content == .noChampion)
    }

    @Test func aLockedChampionShowsAllThreeBlocksWithoutNotes() {
        let summary = Self.summary(matches: [Self.game()])

        #expect(Self.blocks(summary).map(\.kind) == [.champion, .opponent, .role])
        #expect(summary.notes.isEmpty)
    }

    @Test func aramShowsOnlyTheChampionAndSaysWhy() {
        let summary = Self.summary(
            queue: .aram, role: nil, rival: nil,
            matches: [Self.game(role: nil, queue: 450), Self.game()])

        let blocks = Self.blocks(summary)
        #expect(blocks.map(\.kind) == [.champion])
        #expect(blocks[0].title == "Con Ahri en ARAM")
        #expect(Self.value("Victorias", in: blocks[0]) == "1 de 1")
        #expect(summary.notes == ["ARAM no tiene roles: cuentan solo tus partidas de ARAM."])
    }

    @Test func theRecommendedPickIsPhrasedAsAnIf() {
        let summary = Self.summary(
            champion: .init(id: Self.ahri, source: .recommended), matches: [Self.game()])

        #expect(
            summary.notes == ["Si elegís Ahri (el pick recomendado): tu historial con ese campeón."]
        )
    }

    // MARK: Champion

    @Test func theChampionBlockCountsEveryRoleAndShowsMastery() {
        let summary = Self.summary(
            matches: [
                Self.game(), Self.game(role: .top, win: false), Self.game(win: false),
                Self.game(Self.syndra),
            ],
            mastery: [Self.ahri: 182_340])

        let block = Self.block(.champion, in: summary)
        #expect(block.title == "Con Ahri")
        #expect(block.empty == nil)
        #expect(Self.value("Victorias", in: block) == "1 de 3")
        #expect(Self.value("Maestría", in: block) == "182.340 puntos")
        #expect(Self.value("Última partida", in: block) != nil)
    }

    @Test func aChampionNeverPlayedSaysSoAndKeepsItsMastery() {
        let summary = Self.summary(matches: [Self.game(Self.syndra)], mastery: [Self.ahri: 900])

        let block = Self.block(.champion, in: summary)
        #expect(block.empty == "Nunca jugaste Ahri")
        #expect(block.rows.map(\.label) == ["Maestría"])
    }

    // MARK: Small samples

    @Test func fewerThanFiveGamesShowCountsNotARate() {
        let three = Self.summary(matches: [Self.game(), Self.game(), Self.game(win: false)])
        let five = Self.summary(
            matches: [
                Self.game(), Self.game(), Self.game(), Self.game(win: false), Self.game(win: false),
            ])

        #expect(Self.value("Victorias", in: Self.block(.champion, in: three)) == "2 de 3")
        #expect(
            Self.value("Victorias", in: Self.block(.champion, in: five))
                == "3 de 5 · \(0.6.percentText(locale: Self.locale))")
    }

    // MARK: Rival

    @Test func anAssignedRivalIsNamedAsFact() {
        let summary = Self.summary(
            rival: .assigned(.middle), matches: [Self.game(opponent: Self.zed)])

        let block = Self.block(.opponent, in: summary)
        #expect(block.title == "vs Zed")
        #expect(Self.value("Victorias", in: block) == "1 de 1")
    }

    @Test(arguments: [
        AnalysisSubject.SlotRole.inferred(.middle, probability: 0.82),
        .guessed(.middle, probability: 0.2),
    ])
    func anInferredRivalIsOnlyProbable(_ role: AnalysisSubject.SlotRole) {
        let summary = Self.summary(rival: role, matches: [Self.game(opponent: Self.zed)])

        #expect(Self.block(.opponent, in: summary).title == "vs Zed (rival probable)")
    }

    @Test func aRivalNeverFacedSaysSo() {
        let summary = Self.summary(matches: [Self.game()])

        let block = Self.block(.opponent, in: summary)
        #expect(block.empty == "Nunca jugaste Ahri contra Zed")
        #expect(block.rows.isEmpty)
    }

    @Test func withoutARivalTheBlockWaitsForOne() {
        let summary = Self.summary(rival: nil, matches: [Self.game(opponent: Self.zed)])

        let block = Self.block(.opponent, in: summary)
        #expect(block.title == "vs tu rival de línea")
        #expect(block.empty == "Todavía no hay un rival lockeado en tu rol.")
    }

    // MARK: Role

    @Test func theRoleBlockSplitsTheChampionFromEveryChampion() {
        let summary = Self.summary(matches: [
            Self.game(), Self.game(role: .top), Self.game(Self.syndra, win: false),
        ])

        let block = Self.block(.role, in: summary)
        #expect(block.title == "De Mid")
        #expect(Self.value("Con Ahri", in: block) == "1 de 1")
        #expect(Self.value("Todos tus campeones", in: block) == "1 de 2")
    }

    @Test func aRoleNeverPlayedWithTheChampionSaysNoGames() {
        let summary = Self.summary(matches: [Self.game(role: .top), Self.game(Self.syndra)])

        let block = Self.block(.role, in: summary)
        #expect(Self.value("Con Ahri", in: block) == "Sin partidas")
        #expect(Self.value("KDA", in: block) == nil)
    }

    // MARK: Snapshot

    /// avg KDA (5000 + 5000) / 5000 = 2; yours (3 + 1) / 1 = 4, so +100 %.
    @Test func withASnapshotTheRoleComparesAgainstTheAverage() {
        let summary = Self.summary(
            matches: Array(repeating: Self.game(), count: 5), stats: HistoryTestStats(row: true))

        #expect(
            Self.value("KDA", in: Self.block(.role, in: summary))
                == "4,0 (+\(1.0.percentText(locale: Self.locale)) vs. promedio)")
        #expect(Self.value("KDA", in: Self.block(.champion, in: summary)) == "4,0")
    }

    @Test func withoutASnapshotNothingComparesAgainstAnAverage() {
        let summary = Self.summary(
            matches: Array(repeating: Self.game(), count: 5),
            stats: HistoryTestStats(row: true, meta: false))

        #expect(Self.value("KDA", in: Self.block(.role, in: summary)) == "4,0")
    }

    @Test func aSmallSampleIsNotComparedAgainstTheAverage() {
        let summary = Self.summary(
            matches: Array(repeating: Self.game(), count: 4), stats: HistoryTestStats(row: true))

        #expect(Self.value("KDA", in: Self.block(.role, in: summary)) == "4,0")
    }

    @Test func signedPercentsCarryTheirSign() {
        #expect(HistoryText.signedPercent(0.12, locale: Self.locale).hasPrefix("+"))
        #expect(HistoryText.signedPercent(-0.08, locale: Self.locale).hasPrefix("\u{2212}"))
        #expect(
            HistoryText.signedPercent(0.001, locale: Self.locale)
                == 0.0.percentText(locale: Self.locale))
    }

    // MARK: Helpers

    private static func summary(
        queue: QueueType = .rankedSolo, role: Role? = .middle,
        champion: AnalysisSubject.Champion? = .init(id: ahri, source: .locked),
        rival: AnalysisSubject.SlotRole? = .inferred(.middle, probability: 0.82),
        matches: [MyMatch], mastery: [ChampionID: Int] = [:],
        stats: HistoryTestStats = HistoryTestStats()
    ) -> HistorySummary {
        let subject = AnalysisSubject(
            queue: queue, champion: champion, role: role,
            laneOpponent: rival.map { .init(cellId: 5, champion: zed, role: $0) },
            allies: [], enemies: [], stats: stats,
            personal: PersonalInputs(matches: matches, masteryPoints: mastery),
            names: ReasonNames(
                champion: { [103: "Ahri", 134: "Syndra", 238: "Zed"][$0.rawValue] ?? "?" },
                item: { _ in "" }),
            gameData: nil)
        return HistorySummary(subject: subject, now: now, locale: locale)
    }

    private static func game(
        _ champion: ChampionID = ahri, role: Role? = .middle, queue: Int = 420,
        win: Bool = true, opponent: ChampionID? = nil
    ) -> MyMatch {
        MyMatch(
            game: GameID(rawValue: 1), queue: QueueID(rawValue: queue),
            patch: Patch(rawValue: "16.21"), playedAt: now.addingTimeInterval(-86_400),
            champion: champion, role: role, win: win, kills: 3, deaths: 1, assists: 1,
            cs: 210, durationSeconds: 1_800, opponent: opponent,
            spells: SpellPair(
                first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
            perks: [], items: [], participants: [])
    }

    private static func blocks(_ summary: HistorySummary) -> [HistorySummary.Block] {
        if case .blocks(let blocks) = summary.content { return blocks }
        return []
    }

    private static func block(_ kind: HistorySummary.Block.Kind, in summary: HistorySummary)
        -> HistorySummary.Block
    {
        blocks(summary).first { $0.kind == kind }
            ?? HistorySummary.Block(kind: kind, title: "", empty: nil, rows: [])
    }

    private static func value(_ label: String, in block: HistorySummary.Block) -> String? {
        block.rows.first { $0.label == label }?.value
    }
}

/// Ahri's middle row when asked for, under a snapshot or none.
nonisolated struct HistoryTestStats: StatsProvider {
    let row: Bool
    let hasMeta: Bool

    init(row: Bool = false, meta: Bool = true) {
        self.row = row
        hasMeta = meta
    }

    var meta: SnapshotMeta? {
        guard hasMeta else { return nil }
        return SnapshotMeta(
            patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420),
            bracket: .emeraldPlus, matches: 20_000, blendPatches: [Patch(rawValue: "16.21")],
            thresholds: [:],
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                loadoutStrength: 500),
            tierCutoffs: [:],
            profileRules: ProfileRules(
                minimumChampions: 3, heavyADPhysicalShare: 0.625, heavyAPMagicShare: 0.5625,
                heavyCCScore: 0.75, mixedExcludes: [.heavyAD, .heavyAP]))
    }

    func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }

    func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
        guard row, role == .middle else { return [:] }
        return [
            ChampionID(rawValue: 103): ChampionRoleStats(
                games: 1_000, wins: 520, timelineGames: 0, kills: 5_000, deaths: 5_000,
                assists: 5_000, cs: 70_000, minutes: 10_000)
        ]
    }
}
