import Foundation
import LCUKit
import MitoAssets
import MitoCore
import MitoEngine
import Observation
import Testing

@testable import Mito

@Suite(.timeLimit(.minutes(1)))
struct ChampSelectModelTests {
    let connection = DraftTestConnection()
    let clock = ManualClock()

    // MARK: Fetch on connect

    @Test func fetchesTheCurrentSessionOnceConnected() async throws {
        connection.serve(LCUEndpoint.champSelectSession.path, try Fixture.data("planning"))
        let model = makeModel()
        let run = Task { await model.run() }

        connection.enter(.connected)
        await until { model.draft != nil }

        #expect(model.draft?.phase == .planning)
        #expect(model.draft?.myCellId == 2)
        #expect(connection.requests.contains(LCUEndpoint.champSelectSession.path))
        await stop(run)
    }

    @Test func fetchesAgainOnReconnect() async throws {
        connection.serve(LCUEndpoint.champSelectSession.path, try Fixture.data("planning"))
        let model = makeModel()
        let run = Task { await model.run() }
        connection.enter(.connected)
        await until { model.draft?.phase == .planning }

        connection.enter(.searching)
        await until { model.draft == nil }
        connection.serve(
            LCUEndpoint.champSelectSession.path, try Fixture.data("ban-pick-in-progress"))
        connection.enter(.connected)
        await until { model.draft != nil }

        #expect(model.draft?.phase == .banPick)
        await stop(run)
    }

    @Test func noSessionToFetchClearsTheDraft() async throws {
        connection.serve(LCUEndpoint.champSelectSession.path, try Fixture.data("planning"))
        let model = makeModel()
        await model.refresh()
        #expect(model.draft != nil)

        connection.serve(LCUEndpoint.champSelectSession.path, nil)
        await model.refresh()

        #expect(model.draft == nil)
        #expect(model.phaseInterval == nil)
    }

    // MARK: Events and debounce

    @Test func anEventUpdatesTheDraftOnlyAfterTheDebounce() async throws {
        let model = makeModel()
        let run = Task { await model.run() }

        connection.emit(.update, try Fixture.data("ban-pick-in-progress"))
        await sleeps(1)
        clock.advance(by: .milliseconds(149))
        #expect(model.draft == nil)

        clock.advance(by: .milliseconds(1))
        await until { model.draft != nil }

        #expect(model.draft?.phase == .banPick)
        await stop(run)
    }

    @Test func aBurstOfEventsPublishesOnlyTheLastSession() async throws {
        let model = makeModel()
        let run = Task { await model.run() }

        connection.emit(.update, try Fixture.data("planning"))
        connection.emit(.update, try Fixture.data("ban-pick-in-progress"))
        connection.emit(.update, try Fixture.data("blind-pick"))
        await sleeps(3)
        clock.advance(by: ChampSelectModel.debounce)
        await until { model.draft != nil }

        #expect(model.draft?.myCellId == 0)
        #expect(model.draft?.allies.count == 2)
        await stop(run)
    }

    @Test func eachEventRestartsTheDebounce() async throws {
        let model = makeModel()
        let run = Task { await model.run() }

        connection.emit(.update, try Fixture.data("planning"))
        await sleeps(1)
        clock.advance(by: .milliseconds(100))
        connection.emit(.update, try Fixture.data("ban-pick-in-progress"))
        await sleeps(2)
        clock.advance(by: .milliseconds(100))
        #expect(model.draft == nil)

        clock.advance(by: .milliseconds(50))
        await until { model.draft != nil }

        #expect(model.draft?.phase == .banPick)
        await stop(run)
    }

    @Test(arguments: [
        (LCUEvent.EventType.delete, Data("{}".utf8)),
        (.update, Data("null".utf8)),
    ])
    func aDeleteOrAnUndecodableSessionClearsTheDraft(type: LCUEvent.EventType, data: Data)
        async throws
    {
        let model = makeModel()
        let run = Task { await model.run() }
        connection.emit(.update, try Fixture.data("ban-pick-in-progress"))
        await sleeps(1)
        clock.advance(by: ChampSelectModel.debounce)
        await until { model.draft != nil }

        connection.emit(type, data)
        await until { model.draft == nil }

        #expect(model.enemyRoles.isEmpty)
        #expect(model.turns.isEmpty)
        #expect(model.menuSummary == nil)
        await stop(run)
    }

    // MARK: Queue and pickable

    @Test func theQueueAndPickableSetReachTheDraft() async throws {
        connection.serve(
            LCUEndpoint.gameflowSession.path,
            try Fixture.data("session-ranked-solo", in: "gameflow-lobby"))
        connection.serve(
            LCUEndpoint.pickableChampionIDs.path, try Fixture.data("pickable-champion-ids"))
        let model = makeModel()
        let run = Task { await model.run() }

        connection.emit(.update, try Fixture.data("planning"))
        await sleeps(1)
        clock.advance(by: ChampSelectModel.debounce)
        await until { model.draft != nil }

        #expect(model.draft?.queue == .rankedSolo)
        #expect(model.draft?.pickable == Set([266, 103, 157].map(ChampionID.init(rawValue:))))
        await stop(run)
    }

    @Test func anUnreadableQueueFallsBackToUnknown() async throws {
        let model = makeModel()
        connection.serve(LCUEndpoint.champSelectSession.path, try Fixture.data("planning"))

        await model.refresh()

        #expect(model.draft?.queue == ChampSelectModel.unknownQueue)
        #expect(model.draft?.pickable == [])
    }

    @Test func queueAndPickableAreFetchedOncePerChampSelect() async throws {
        let model = makeModel()
        let run = Task { await model.run() }

        connection.emit(.update, try Fixture.data("planning"))
        await sleeps(1)
        clock.advance(by: ChampSelectModel.debounce)
        await until { model.draft?.phase == .planning }
        connection.emit(.update, try Fixture.data("ban-pick-in-progress"))
        await sleeps(2)
        clock.advance(by: ChampSelectModel.debounce)
        await until { model.draft?.phase == .banPick }
        #expect(pickableRequests == 1)

        connection.emit(.delete)
        await until { model.draft == nil }
        connection.emit(.update, try Fixture.data("planning"))
        await sleeps(3)
        clock.advance(by: ChampSelectModel.debounce)
        await until { model.draft != nil }

        #expect(pickableRequests == 2)
        #expect(
            connection.requests.filter { $0 == LCUEndpoint.gameflowSession.path }.count == 2)
        await stop(run)
    }

    // MARK: Enemy roles

    @Test func uniformInferredRolesAreMarkedUncertain() throws {
        let model = makeModel()

        model.show(try Fixture.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])

        let zed = try #require(model.enemyRoles[5])
        #expect(zed.isUniformFallback)
        #expect(model.enemyRoles[6] == nil)
        #expect(model.enemyRows.first?.role == .uncertain(.top))
        #expect(model.enemyRows.last?.role == DraftSlotRow.RoleLabel.none)
    }

    @Test func assignedAllyRolesAreShownAsFact() throws {
        let model = makeModel()

        model.show(try Fixture.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])

        #expect(
            model.allyRows.map(\.role) == [.assigned(.top), .assigned(.jungle), .assigned(.middle)])
    }

    // MARK: Presentation

    @Test func rowsSeparateLocksHoversAndTurns() throws {
        let model = makeModel(
            gameData: GameData(champions: [
                Champion(
                    id: ChampionID(rawValue: 266), alias: "Aatrox", name: "Aatrox", iconPath: ""),
                Champion(id: ChampionID(rawValue: 103), alias: "Ahri", name: "Ahri", iconPath: ""),
            ]))

        model.show(try Fixture.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])

        let rows = model.allyRows
        #expect(
            rows.map(\.pick) == [.locked("Aatrox"), .hovering("Campeón 64"), .hovering("Ahri")])
        #expect(rows.map(\.turn) == [nil, .pick, .pick])
        #expect(rows.map(\.isMe) == [false, false, true])
        #expect(model.enemyRows.map(\.pick) == [.locked("Campeón 238"), .empty])
    }

    @Test func championNamesFollowTheSharedDataOnceItLoads() {
        let shared = SharedData()
        let model = ChampSelectModel(connection: connection, gameData: shared.gameData)
        #expect(model.championName(ChampionID(rawValue: 103)) == "Campeón 103")

        shared.gameData = GameData(champions: [
            Champion(id: ChampionID(rawValue: 103), alias: "Ahri", name: "Ahri", iconPath: "")
        ])

        #expect(model.championName(ChampionID(rawValue: 103)) == "Ahri")
        #expect(model.championName(ChampionID(rawValue: 238)) == "Campeón 238")
    }

    @Test func theDraftCarriesThePatchOfTheGameVersion() throws {
        let model = ChampSelectModel(
            connection: connection, patch: { Patch(rawValue: "16.21") }, clock: clock)

        model.show(try Fixture.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])

        #expect(model.draft?.patch == Patch(rawValue: "16.21"))
    }

    @Test func bansAreListedByName() throws {
        let model = makeModel()

        model.show(try Fixture.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])

        #expect(model.bannedNames == ["Campeón 157", "Campeón 555"])
    }

    @Test func theTimerCountsFromWhenTheSessionArrived() throws {
        let arrival = Date(timeIntervalSinceReferenceDate: 1_000)
        let model = makeModel(now: { arrival })

        model.show(try Fixture.session("ban-pick-in-progress"), queue: .rankedSolo, pickable: [])

        #expect(model.phaseInterval == arrival...arrival.addingTimeInterval(27))
    }

    @Test(arguments: [
        ("ban-pick-in-progress", "Champ select · tu turno de elegir"),
        ("planning", "Champ select · 0 de 10 lockeados"),
    ])
    func theMenuSummarizesTheDraft(fixture: String, summary: String) throws {
        let model = makeModel()
        #expect(model.menuSummary == nil)

        model.show(try Fixture.session(fixture), queue: .rankedSolo, pickable: [])

        #expect(model.menuSummary.map { String(localized: $0) } == summary)
        #expect(model.menuSummary?.table == "ChampSelect")
    }

    // MARK: Helpers

    private var pickableRequests: Int {
        connection.requests.filter { $0 == LCUEndpoint.pickableChampionIDs.path }.count
    }

    private func makeModel(
        now: @escaping () -> Date = { .now }, gameData: GameData? = nil
    ) -> ChampSelectModel {
        ChampSelectModel(connection: connection, clock: clock, now: now, gameData: gameData)
    }

    /// Waits until the model has armed `count` debounces in total.
    private func sleeps(_ count: Int) async {
        while clock.sleepCalls < count { await Task.yield() }
    }

    private func stop(_ run: Task<Void, Never>) async {
        connection.finish()
        await run.value
    }
}

/// Stands in for the shell's `ClientDataModel`.
@Observable
private final class SharedData {
    var gameData: GameData?
}

/// The hand-written cases in `fixtures/lcu/cases/`, read in place like `MitoTestSupport` does.
private enum Fixture {
    static let cases = URL(filePath: #filePath)
        .deletingLastPathComponent()  // ChampSelect/
        .deletingLastPathComponent()  // Features/
        .deletingLastPathComponent()  // MitoTests/
        .deletingLastPathComponent()  // macos/
        .deletingLastPathComponent()  // apps/
        .deletingLastPathComponent()  // repository root
        .appending(path: "fixtures/lcu/cases", directoryHint: .isDirectory)

    static func data(_ name: String, in folder: String = "champ-select") throws -> Data {
        try Data(contentsOf: cases.appending(path: "\(folder)/\(name).json"))
    }

    static func session(_ name: String) throws -> ChampSelectSession {
        try LCUEndpoint.champSelectSession.decode(data(name))
    }
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
