import Foundation
import LCUKit
import MitoAssets
import MitoCore
import MitoEngine
import MitoStore
import Observation
import Synchronization
import Testing

@testable import Mito

/// The "Recomendados" column and the menu line against the snapshot fixture (§18.3, §18.5,
/// §20.1, §22.4). In `ban-pick-in-progress` the user is MID, Zed (238) is a locked enemy, and the
/// fixture's MID roster is Malzahar (90), Lux (99), Ahri (103), and Zed.
@Suite(.timeLimit(.minutes(1)))
struct ChampSelectRecommendationTests {
    static let malzahar = ChampionID(rawValue: 90)
    static let lux = ChampionID(rawValue: 99)
    static let ahri = ChampionID(rawValue: 103)
    static let zed = ChampionID(rawValue: 238)

    let connection = DraftTestConnection()
    let clock = ManualClock()
    fileprivate let settings = ChampSelectSettingsBox()
    let stats: SnapshotReader

    init() throws {
        stats = try SnapshotFixture.reader()
    }

    // MARK: Empty states

    @Test func noSnapshotMeansNoRecommendationsAndAnEmptyState() throws {
        let model = ChampSelectModel(connection: connection, clock: clock)

        model.show(try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])

        #expect(model.recommendations == .unavailable(.noSnapshot))
        #expect(model.menuRecommendation == nil)
    }

    @Test func outsideChampSelectThereIsNoColumn() {
        #expect(makeModel().recommendations == nil)
    }

    @Test func aramHasNoRoleToScoreNorAPicker() throws {
        let model = makeModel()

        model.show(try Cases.session("blind-pick"), queue: .aram, pickable: [])

        #expect(model.recommendations == .unavailable(.noRole))
        #expect(model.scoringRole == nil)
        #expect(!model.canChooseRole)
    }

    @Test func aDisabledListSaysSo() throws {
        settings.value.pickRecommendations = false
        let model = makeModel()

        model.show(try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])

        #expect(model.recommendations == .unavailable(.disabled))
    }

    // MARK: Enemy roles

    @Test func enemyRolesUseTheSnapshotOnceItOpens() throws {
        let box = StatsBox()
        let model = ChampSelectModel(
            connection: connection, clock: clock, stats: { [box] in box.value })
        model.show(try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])
        #expect(model.enemyRows.first?.role == .uncertain(.top))

        box.value = stats

        // Zed: 2.746 games in jungle and 2.195 in mid.
        guard case .inferred(let role, let confidence) = model.enemyRows.first?.role else {
            Issue.record(
                "Expected an inferred role, got \(String(describing: model.enemyRows.first))")
            return
        }
        #expect(role == .jungle)
        #expect(abs(confidence - 2746.0 / 4941.0) < 1e-9)
        #expect(model.enemyRoles[5]?.isUniformFallback == false)
    }

    // MARK: Blind pick

    @Test func blindPickDefaultsToTheDocumentedRoleOrder() throws {
        let lux = 99
        // Most of the user's games on the hovered champion.
        #expect(
            try defaultRole(
                hover: lux,
                PersonalInputs(
                    matches: (1...3).map { MyMatch.played(lux, role: .utility, win: true, id: $0) }
                        + (4...5).map { MyMatch.played(lux, role: .middle, win: true, id: $0) },
                    pool: (0...1).map { PoolEntry(role: .top, champion: Self.ahri, priority: $0) }))
                == .utility)
        // No games on it: the largest declared pool; other champions' games do not count.
        #expect(
            try defaultRole(
                hover: lux,
                PersonalInputs(
                    matches: (1...4).map { MyMatch.played(103, role: .bottom, win: true, id: $0) },
                    pool: [
                        PoolEntry(role: .jungle, champion: Self.ahri, priority: 0),
                        PoolEntry(role: .top, champion: Self.ahri, priority: 0),
                        PoolEntry(role: .top, champion: Self.lux, priority: 1),
                    ]))
                == .top)
        // A tie goes to the role declared first.
        #expect(
            try defaultRole(
                hover: nil,
                PersonalInputs(pool: [
                    PoolEntry(role: .utility, champion: Self.lux, priority: 0),
                    PoolEntry(role: .jungle, champion: Self.ahri, priority: 0),
                ]))
                == .jungle)
        #expect(try defaultRole(hover: nil, PersonalInputs()) == .middle)
        #expect(try defaultRole(hover: lux, PersonalInputs()) == .middle)
    }

    @Test func choosingTheBlindPickRoleRecomputesTheRecommendations() throws {
        settings.value.candidates = .all
        let model = makeModel()
        model.show(try Cases.session("blind-pick"), queue: .normalBlind, pickable: [])
        #expect(model.canChooseRole)
        #expect(model.scoringRole == .middle)
        #expect(Set(pickIDs(model)) == [Self.malzahar, Self.lux, Self.ahri, Self.zed])

        let changed = observesChange(of: model) { model.chooseRole(.bottom) }

        #expect(changed)
        #expect(model.scoringRole == .bottom)
        // Ashe (22), the fixture's other ADC, is locked by an ally.
        #expect(pickIDs(model) == [ChampionID(rawValue: 222)])
    }

    @Test func theRoleChoiceLastsTheChampSelectAndResetsOnTheNext() async throws {
        let model = makeModel()
        model.show(try Cases.session("blind-pick"), queue: .normalBlind, pickable: [])
        model.chooseRole(.top)

        model.show(try Cases.decode(Cases.blind(hover: 99)), queue: .normalBlind, pickable: [])
        #expect(model.scoringRole == .top)

        connection.serve(LCUEndpoint.champSelectSession.path, nil)
        await model.refresh()
        #expect(model.chosenRole == nil)
        model.show(try Cases.session("blind-pick"), queue: .normalBlind, pickable: [])

        #expect(model.scoringRole == .middle)
    }

    @Test func anAssignedRoleOffersNoPicker() throws {
        let model = makeModel()
        model.show(try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])
        model.chooseRole(.top)

        #expect(!model.canChooseRole)
        #expect(model.scoringRole == .middle)
    }

    // MARK: Picks

    @Test func picksSkipWhatIsLockedAndRecomputeOnDraftChange() throws {
        settings.value.candidates = .all
        let model = makeModel()

        model.show(try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])
        #expect(Set(pickIDs(model)) == [Self.malzahar, Self.lux, Self.ahri])

        model.show(try Cases.decode(Cases.malzaharLocked), queue: .rankedSolo, pickable: [])

        #expect(Set(pickIDs(model)) == [Self.lux, Self.ahri])
    }

    @Test func theCandidateModeRecomputesLive() throws {
        settings.value.candidates = .all
        let model = makeModel()
        model.show(
            try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [Self.ahri])
        #expect(pickIDs(model).count == 3)

        let changed = observesChange(of: model) { settings.value.candidates = .owned }

        #expect(changed)
        #expect(pickIDs(model) == [Self.ahri])
    }

    @Test func theMetaComfortSliderMovesThePersonalWeight() throws {
        settings.value.candidates = .all
        let model = makeModel()
        let history = (1...12).map { MyMatch.played(99, role: .middle, win: true, id: $0) }
        model.show(
            try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [],
            personal: PersonalInputs(matches: history))
        settings.value.metaComfortBalance = 0
        let meta = try #require(pick(Self.lux, in: model))

        let changed = observesChange(of: model) { settings.value.metaComfortBalance = 1 }
        let comfort = try #require(pick(Self.lux, in: model))

        #expect(changed)
        #expect(comfort.components[.personal]! > meta.components[.personal]!)
        #expect(comfort.components[.meta]! != meta.components[.meta]!)
    }

    @Test func theUserHistoryFeedsThePersonalTerm() throws {
        settings.value.candidates = .all
        let model = makeModel()
        let history = (1...12).map { MyMatch.played(99, role: .middle, win: $0 % 4 != 0, id: $0) }

        model.show(
            try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [],
            personal: PersonalInputs(matches: history))
        let withHistory = try #require(pick(Self.lux, in: model))
        model.show(try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])
        let without = try #require(pick(Self.lux, in: model))

        #expect(withHistory.components[.personal]! > 0)
        #expect(without.components[.personal] == 0)
        #expect(withHistory.score > without.score)
    }

    @Test func noHistoryPassesNoPersonalScore() {
        let personal = DraftRecommendations.personalPoints(
            PersonalInputs(pool: [PoolEntry(role: .middle, champion: Self.lux, priority: 0)]),
            stats: stats, now: .now)

        #expect(personal(Self.lux, .middle) == nil)
    }

    @Test func myPoolIsThePoolAmongWhatIOwn() throws {
        settings.value.candidates = .myPool
        let model = makeModel()
        let personal = PersonalInputs(
            matches: (1...5).map { MyMatch.played(90, role: .middle, win: false, id: $0) },
            pool: [PoolEntry(role: .middle, champion: Self.lux, priority: 0)])

        model.show(
            try Cases.session("ban-pick-in-progress"), queue: .rankedSolo,
            pickable: [Self.lux, Self.malzahar], personal: personal)

        #expect(Set(pickIDs(model)) == [Self.lux, Self.malzahar])
    }

    // MARK: Pool

    @Test func thePoolIsTheDeclaredOrderThenTheChampionsPlayedEnough() {
        let personal = PersonalInputs(
            matches: (1...6).map { MyMatch.played(90, role: .middle, win: true, id: $0) }
                + (7...11).map { MyMatch.played(238, role: .middle, win: true, id: $0) }
                + (12...15).map { MyMatch.played(4, role: .middle, win: true, id: $0) }
                + (16...22).map { MyMatch.played(86, role: .top, win: true, id: $0) }
                + (23...28).map { MyMatch.played(103, role: .middle, win: true, id: $0) },
            pool: [
                PoolEntry(role: .middle, champion: Self.ahri, priority: 1),
                PoolEntry(role: .middle, champion: Self.lux, priority: 0),
                PoolEntry(role: .top, champion: ChampionID(rawValue: 122), priority: 0),
            ])

        #expect(DraftRecommendations.poolMinimumGames == 5)
        #expect(
            DraftRecommendations.pool(for: .middle, personal: personal) == [
                Self.lux, Self.ahri, Self.malzahar, Self.zed,
            ])
    }

    @Test func anExclusionOverrideTakesAChampionOutOfThePool() {
        let personal = PersonalInputs(
            matches: (1...5).map { MyMatch.played(90, role: .middle, win: true, id: $0) },
            pool: [PoolEntry(role: .middle, champion: Self.lux, priority: 0)],
            overrides: [
                ChampionOverride(champion: Self.lux, role: .middle, isExcludedFromPool: true),
                ChampionOverride(champion: Self.malzahar, role: .middle, isExcludedFromPool: true),
            ])

        #expect(DraftRecommendations.pool(for: .middle, personal: personal).isEmpty)
    }

    // MARK: Bans

    @Test func theBanPhaseShowsBansAndNeverMyPool() throws {
        let model = makeModel()
        let personal = PersonalInputs(
            pool: [PoolEntry(role: .middle, champion: Self.ahri, priority: 0)])

        model.show(
            try Cases.decode(Cases.myBanTurn), queue: .rankedSolo, pickable: [], personal: personal)

        #expect(model.isBanPhase)
        guard case .bans(let bans) = model.recommendations else {
            Issue.record("Expected bans, got \(String(describing: model.recommendations))")
            return
        }
        #expect(!bans.isEmpty)
        #expect(!bans.map(\.champion).contains(Self.ahri))
        let top = try #require(bans.first)
        #expect(
            model.menuRecommendation.map { String(localized: $0) }
                == "Ban recomendado: \(model.championName(top.champion))")
    }

    @Test func thePickPhaseShowsPicks() throws {
        let model = makeModel()

        model.show(try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])

        #expect(!model.isBanPhase)
        #expect(model.recommendations?.isBans == false)
    }

    // MARK: Menu

    @Test func theMenuNamesTheTopPickWithItsScore() throws {
        settings.value.candidates = .all
        let model = makeModel(
            gameData: GameData(champions: [
                Champion(id: Self.ahri, alias: "Ahri", name: "Ahri", iconPath: ""),
                Champion(id: Self.lux, alias: "Lux", name: "Lux", iconPath: ""),
                Champion(id: Self.malzahar, alias: "Malzahar", name: "Malzahar", iconPath: ""),
            ]))

        model.show(try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])
        let first = try #require(pickIDs(model).first)
        let top = try #require(pick(first, in: model))

        let line = try #require(model.menuRecommendation)
        #expect(
            String(localized: line)
                == "Recomendado: \(model.championName(top.champion)) (\(WinratePoints.text(top.score)))"
        )
        #expect(line.table == "ChampSelect")
    }

    @Test func noCandidatesMeansNoMenuLine() throws {
        settings.value.candidates = .owned
        let model = makeModel()

        model.show(try Cases.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])

        #expect(model.recommendations == .picks([]))
        #expect(model.menuRecommendation == nil)
    }

    // MARK: Personal inputs

    @Test func personalInputsAreReadOncePerChampSelect() async throws {
        let store = RecommendationTestStore(
            matches: [MyMatch.played(103, role: .middle, win: true, id: 1)],
            pool: [PoolEntry(role: .middle, champion: Self.ahri, priority: 0)])
        connection.serve(LCUEndpoint.championMastery.path, try Cases.data("mastery", in: "history"))
        let model = makeModel(store: store)
        let run = Task { await model.run() }

        connection.emit(.update, try Cases.data("planning"))
        await sleeps(1)
        clock.advance(by: ChampSelectModel.debounce)
        await until { model.draft?.phase == .planning }
        connection.emit(.update, try Cases.data("ban-pick-in-progress"))
        await sleeps(2)
        clock.advance(by: ChampSelectModel.debounce)
        await until { model.draft?.phase == .banPick }

        #expect(await store.historyReads == 1)
        #expect(model.personal.matches.count == 1)
        #expect(model.personal.pool.map(\.champion) == [Self.ahri])
        #expect(model.personal.masteryPoints[Self.ahri] == 245_310)

        connection.emit(.delete)
        await until { model.draft == nil }
        #expect(model.personal == PersonalInputs())
        connection.emit(.update, try Cases.data("planning"))
        await sleeps(3)
        clock.advance(by: ChampSelectModel.debounce)
        await until { model.draft != nil }

        #expect(await store.historyReads == 2)
        connection.finish()
        await run.value
    }

    @Test func aPersonalReadThatLandsAfterTheDraftEndedIsDropped() async throws {
        let store = RecommendationTestStore(
            matches: [MyMatch.played(103, role: .middle, win: true, id: 1)], held: true)
        connection.serve(LCUEndpoint.champSelectSession.path, try Cases.data("planning"))
        let model = makeModel(store: store)

        let late = Task { await model.refresh() }
        while !(await store.hasWaitingReads) { await Task.yield() }
        connection.serve(LCUEndpoint.champSelectSession.path, nil)
        await model.refresh()
        await store.release()
        await late.value

        #expect(model.draft == nil)
        #expect(model.personal == PersonalInputs())
        #expect(model.recommendations == nil)
    }

    // MARK: Helpers

    private func makeModel(
        gameData: GameData? = nil, store: any PersonalStore = UnavailablePersonalStore()
    ) -> ChampSelectModel {
        ChampSelectModel(
            connection: connection, settings: { [settings] in settings.value }, clock: clock,
            gameData: gameData, stats: { [stats] in stats }, store: store)
    }

    private func defaultRole(hover: Int?, _ personal: PersonalInputs) throws -> Role? {
        let model = makeModel()
        model.show(
            try Cases.decode(Cases.blind(hover: hover)), queue: .normalBlind, pickable: [],
            personal: personal)
        return model.scoringRole
    }

    private func pickIDs(_ model: ChampSelectModel) -> [ChampionID] {
        guard case .picks(let picks) = model.recommendations else { return [] }
        return picks.map(\.champion)
    }

    private func pick(_ champion: ChampionID, in model: ChampSelectModel) -> PickRecommendation? {
        guard case .picks(let picks) = model.recommendations else { return nil }
        return picks.first { $0.champion == champion }
    }

    /// Whether reading `recommendations` is invalidated by `change`, as a view's would be.
    private func observesChange(of model: ChampSelectModel, _ change: () -> Void) -> Bool {
        let fired = Flag()
        withObservationTracking {
            _ = model.recommendations
        } onChange: {
            fired.isSet = true
        }
        change()
        return fired.isSet
    }

    private func sleeps(_ count: Int) async {
        while clock.sleepCalls < count { await Task.yield() }
    }
}

/// Stands in for `SnapshotModel.provider`: no snapshot until a test opens one.
@Observable
private final class StatsBox {
    var value: any StatsProvider = ChampSelectModel.NoStats()
}

/// Stands in for `SettingsModel`: an observable value the model reads live.
@Observable
private final class ChampSelectSettingsBox {
    var value = ChampSelectSettings()
}

nonisolated private final class Flag: Sendable {
    private let value = Mutex(false)

    var isSet: Bool {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }
}

private enum Cases {
    static let root = URL(filePath: #filePath)
        .deletingLastPathComponent()  // ChampSelect/
        .deletingLastPathComponent()  // Features/
        .deletingLastPathComponent()  // MitoTests/
        .deletingLastPathComponent()  // macos/
        .deletingLastPathComponent()  // apps/
        .deletingLastPathComponent()  // repository root
        .appending(path: "fixtures/lcu/cases", directoryHint: .isDirectory)

    static func data(_ name: String, in folder: String = "champ-select") throws -> Data {
        try Data(contentsOf: root.appending(path: "\(folder)/\(name).json"))
    }

    static func session(_ name: String) throws -> ChampSelectSession {
        try LCUEndpoint.champSelectSession.decode(data(name))
    }

    static func decode(_ json: String) throws -> ChampSelectSession {
        try LCUEndpoint.champSelectSession.decode(Data(json.utf8))
    }

    /// `ban-pick-in-progress` with Malzahar locked by the enemy too.
    static let malzaharLocked = """
        {"localPlayerCellId": 2,
         "myTeam": [
           {"cellId": 0, "championId": 266, "assignedPosition": "top"},
           {"cellId": 1, "championPickIntent": 64, "assignedPosition": "jungle"},
           {"cellId": 2, "championPickIntent": 103, "assignedPosition": "middle"}],
         "theirTeam": [{"cellId": 5, "championId": 238}, {"cellId": 6, "championId": 90}],
         "actions": [[{"actorCellId": 2, "championId": 103, "type": "pick", "isInProgress": true}]],
         "bans": {"myTeamBans": [157], "theirTeamBans": [555]},
         "timer": {"phase": "BAN_PICK", "adjustedTimeLeftInPhase": 27000}}
        """

    /// Blind pick with the user's cell hovering `hover`, Ashe locked by an ally.
    static func blind(hover: Int?) -> String {
        """
        {"localPlayerCellId": 0,
         "myTeam": [{"cellId": 0, "championPickIntent": \(hover ?? 0)},
           {"cellId": 1, "championId": 22}],
         "theirTeam": [{"cellId": 5}],
         "actions": [[{"actorCellId": 0, "type": "pick", "isInProgress": true}]],
         "timer": {"phase": "BAN_PICK", "adjustedTimeLeftInPhase": 81000}}
        """
    }

    /// The user's ban is in progress; Lee Sin hovers jungle.
    static let myBanTurn = """
        {"localPlayerCellId": 2,
         "myTeam": [
           {"cellId": 0, "assignedPosition": "top"},
           {"cellId": 1, "championPickIntent": 64, "assignedPosition": "jungle"},
           {"cellId": 2, "assignedPosition": "middle"}],
         "theirTeam": [{"cellId": 5}, {"cellId": 6}],
         "actions": [[
           {"actorCellId": 2, "type": "ban", "isInProgress": true},
           {"actorCellId": 5, "type": "ban", "isInProgress": true}]],
         "timer": {"phase": "BAN_PICK", "adjustedTimeLeftInPhase": 25000}}
        """
}

/// Suspends until `condition` holds, re-checking on every change to what it reads.
private func until(_ condition: () -> Bool) async {
    while !condition() {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = condition()
            } onChange: {
                continuation.resume()
            }
        }
    }
}
