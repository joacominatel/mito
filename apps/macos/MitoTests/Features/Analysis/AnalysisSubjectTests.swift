import Foundation
import LCUKit
import MitoAssets
import MitoCore
import MitoEngine
import Testing

@testable import Mito

/// The subject the analysis tabs read, derived from the live draft (§20.1, §20.2).
@Suite(.timeLimit(.minutes(1)))
struct AnalysisSubjectTests {
    static let ahri = ChampionID(rawValue: 103)
    static let lux = ChampionID(rawValue: 99)
    static let zed = ChampionID(rawValue: 238)
    static let darius = ChampionID(rawValue: 122)

    // MARK: My champion

    @Test func aLockBeatsAHover() throws {
        let subject = try #require(
            try subject(of: Self.session(me: #""championId": 99, "championPickIntent": 103"#)))

        #expect(subject.champion == AnalysisSubject.Champion(id: Self.lux, source: .locked))
        #expect(subject.champion?.isRecommendation == false)
    }

    @Test func aHoverBeatsTheTopRecommendation() throws {
        let subject = try #require(try subject(of: Self.session(me: #""championPickIntent": 99"#)))

        #expect(subject.champion == AnalysisSubject.Champion(id: Self.lux, source: .hovered))
    }

    @Test func withNeitherTheTopPickStandsInFlaggedAsARecommendation() throws {
        let subject = try #require(try subject(of: Self.session()))

        #expect(subject.champion == AnalysisSubject.Champion(id: Self.ahri, source: .recommended))
        #expect(subject.champion?.isRecommendation == true)
    }

    @Test func theTopPickStandsInEvenWhileTheColumnShowsBans() throws {
        let model = champSelect()
        model.show(
            try Self.decode(Self.session(myBanInProgress: true)), queue: .rankedSolo, pickable: [])
        #expect(model.recommendations?.isBans == true)

        let subject = try #require(
            AnalysisModel(champSelect: model, stats: { AnalysisTestStats() }).subject)

        #expect(subject.champion == AnalysisSubject.Champion(id: Self.ahri, source: .recommended))
    }

    @Test func withoutAnyPickRecommendationThereIsNoChampion() throws {
        let subject = try #require(
            try subject(
                of: Self.session(), settings: ChampSelectSettings(pickRecommendations: false)))

        #expect(subject.champion == nil)
    }

    // MARK: My role

    @Test func theAssignedRoleIsMine() throws {
        let subject = try #require(try subject(of: Self.session(position: "top")))

        #expect(subject.role == .top)
    }

    @Test func blindPickUsesTheDefaultRoleThenTheChosenOne() throws {
        let model = champSelect()
        model.show(try Self.decode(Self.session(position: nil)), queue: .normalBlind, pickable: [])
        let analysis = AnalysisModel(champSelect: model, stats: { AnalysisTestStats() })
        #expect(analysis.subject?.role == .middle)

        model.chooseRole(.top)

        #expect(analysis.subject?.role == .top)
    }

    @Test func aramHasNoRoleAndNoLaneOpponent() throws {
        let subject = try #require(try subject(of: Self.session(position: nil), queue: .aram))

        #expect(subject.role == nil)
        #expect(subject.laneOpponent == nil)
    }

    // MARK: Lane opponent and teams

    @Test func theLaneOpponentIsTheEnemyInferredInMyRoleWithItsProbability() throws {
        let subject = try #require(try subject(of: Self.session(enemies: [238, 122])))

        let opponent = try #require(subject.laneOpponent)
        #expect(opponent.champion == Self.zed)
        #expect(opponent.cellId == 5)
        guard case .inferred(.middle, let probability) = opponent.role else {
            Issue.record("Expected an inferred MID, got \(opponent.role)")
            return
        }
        #expect(probability < 1)
        #expect(opponent.probability == probability)
    }

    @Test func noEnemyInMyRoleMeansNoLaneOpponent() throws {
        let subject = try #require(try subject(of: Self.session(enemies: [122])))

        #expect(subject.laneOpponent == nil)
    }

    @Test func bothTeamsCarryChampionsAndRolesWithInferredEnemies() throws {
        let subject = try #require(try subject(of: Self.session(enemies: [238, 122])))

        #expect(subject.allies.map(\.role) == [.assigned(.top), .assigned(.middle)])
        #expect(subject.allies.map(\.isMe) == [false, true])
        #expect(subject.enemies.map(\.champion) == [Self.zed, Self.darius, nil])
        #expect(subject.enemies.map(\.role?.role) == [.middle, .top, nil])
        #expect(subject.enemies.allSatisfy { !$0.isMe })
    }

    @Test func anEnemyWithoutGamesIsAGuess() throws {
        let subject = try #require(try subject(of: Self.session(enemies: [1])))

        guard case .guessed = subject.enemies.first?.role else {
            Issue.record(
                "Expected a guessed role, got \(String(describing: subject.enemies.first))")
            return
        }
    }

    // MARK: Data and states

    @Test func theSubjectCarriesTheSnapshotAndThePersonalLoad() throws {
        let model = champSelect()
        let personal = PersonalInputs(pool: [
            PoolEntry(role: .middle, champion: Self.lux, priority: 0)
        ])
        model.show(
            try Self.decode(Self.session()), queue: .rankedSolo, pickable: [], personal: personal)

        let subject = try #require(
            AnalysisModel(champSelect: model, stats: { AnalysisTestStats() }).subject)

        #expect(subject.meta == AnalysisTestStats.meta)
        #expect(subject.personal == personal)
    }

    @Test func theSubjectCarriesTheClientsGameData() throws {
        let gameData = GameData(champions: [
            Champion(id: Self.ahri, alias: "Ahri", name: "Ahri", iconPath: "")
        ])
        let model = ChampSelectModel(
            connection: DisconnectedLCUConnection(),
            settings: { ChampSelectSettings(candidates: .all) }, gameData: gameData,
            stats: { AnalysisTestStats() })
        model.show(try Self.decode(Self.session()), queue: .rankedSolo, pickable: [])

        let subject = try #require(
            AnalysisModel(champSelect: model, stats: { AnalysisTestStats() }).subject)

        #expect(subject.gameData == gameData)
    }

    @Test func withoutASnapshotOnlyMatchupAndComposicionAreEmpty() throws {
        let model = champSelect(stats: ChampSelectModel.NoStats())
        model.show(try Self.decode(Self.session()), queue: .rankedSolo, pickable: [])
        let analysis = AnalysisModel(champSelect: model)

        let subject = try #require(analysis.subject)
        #expect(subject.meta == nil)
        #expect(subject.champion == nil)
        for tab in AnalysisModel.Tab.allCases {
            analysis.tab = tab
            #expect(analysis.isMissingSnapshot == [.matchup, .composition].contains(tab))
        }
    }

    @Test func withASnapshotNoTabIsEmpty() {
        let analysis = AnalysisModel(champSelect: champSelect(), stats: { AnalysisTestStats() })

        for tab in AnalysisModel.Tab.allCases {
            analysis.tab = tab
            #expect(!analysis.isMissingSnapshot)
        }
    }

    @Test func outsideChampSelectThereIsNoSubject() throws {
        let model = champSelect()
        let analysis = AnalysisModel(champSelect: model, stats: { AnalysisTestStats() })
        #expect(analysis.subject == nil)

        model.show(try Self.decode(Self.session()), queue: .rankedSolo, pickable: [])
        #expect(analysis.subject != nil)
    }

    @Test func theAppAnalyzesItsOwnChampSelect() throws {
        let app = AppModel(connection: DisconnectedLCUConnection())

        app.champSelect.show(try Self.decode(Self.session()), queue: .rankedSolo, pickable: [])

        #expect(app.analysis.subject?.role == .middle)
    }

    // MARK: Helpers

    private func champSelect(
        stats: any StatsProvider = AnalysisTestStats(),
        settings: ChampSelectSettings = ChampSelectSettings(candidates: .all)
    ) -> ChampSelectModel {
        ChampSelectModel(
            connection: DisconnectedLCUConnection(), settings: { settings }, stats: { stats })
    }

    private func subject(
        of json: String, queue: QueueType = .rankedSolo,
        settings: ChampSelectSettings = ChampSelectSettings(candidates: .all)
    ) throws -> AnalysisSubject? {
        let model = champSelect(settings: settings)
        model.show(try Self.decode(json), queue: queue, pickable: [])
        return AnalysisModel(champSelect: model, stats: { AnalysisTestStats() }).subject
    }

    static func decode(_ json: String) throws -> ChampSelectSession {
        try LCUEndpoint.champSelectSession.decode(Data(json.utf8))
    }

    /// An ally in TOP (cell 0) and you (cell 2); `enemies` lock cells 5 onward, plus one empty.
    static func session(
        me: String? = nil, position: String? = "middle", enemies: [Int] = [],
        myBanInProgress: Bool = false
    ) -> String {
        let mine = [
            #""cellId": 2"#, me, position.map { #""assignedPosition": "\#($0)""# },
        ].compactMap(\.self).joined(separator: ", ")
        let allyPosition = position == nil ? "" : #", "assignedPosition": "top""#
        let theirs =
            (enemies.enumerated().map {
                #"{"cellId": \#($0.offset + 5), "championId": \#($0.element)}"#
            }
            + [#"{"cellId": \#(enemies.count + 5)}"#]).joined(separator: ", ")
        let actions =
            myBanInProgress
            ? #"[[{"actorCellId": 2, "type": "ban", "isInProgress": true}]]"# : "[]"
        return """
            {"localPlayerCellId": 2,
             "myTeam": [{"cellId": 0\(allyPosition)}, {\(mine)}],
             "theirTeam": [\(theirs)],
             "actions": \(actions),
             "timer": {"phase": "BAN_PICK", "adjustedTimeLeftInPhase": 30000}}
            """
    }
}

/// MID: Ahri well above Lux. Zed plays MID, Darius TOP; anyone else has no games.
nonisolated struct AnalysisTestStats: StatsProvider {
    static let meta = SnapshotMeta(
        patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420), bracket: .emeraldPlus,
        matches: 20_000, blendPatches: [Patch(rawValue: "16.21")],
        thresholds: [
            .championRole: SampleThreshold(minimum: 200, reliable: 1000),
            .matchup: SampleThreshold(minimum: 30, reliable: 300),
        ],
        priors: SmoothingPriors(
            championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
            loadoutStrength: 500),
        tierCutoffs: [.s: 0.53, .a: 0.515, .b: 0.5, .c: 0.485])

    var meta: SnapshotMeta? { Self.meta }

    private static let middle: [ChampionID: ChampionRoleStats] = [
        ChampionID(rawValue: 103): ChampionRoleStats(games: 3000, wins: 1680, timelineGames: 0),
        ChampionID(rawValue: 99): ChampionRoleStats(games: 3000, wins: 1440, timelineGames: 0),
    ]

    func roleGames(for champion: ChampionID) -> [Role: Int] {
        switch champion.rawValue {
        case 238: [.middle: 3000, .jungle: 1000]
        case 122: [.top: 3000]
        case 103, 99: [.middle: 3000]
        default: [:]
        }
    }

    func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
        role == .middle ? Self.middle : [:]
    }
}
