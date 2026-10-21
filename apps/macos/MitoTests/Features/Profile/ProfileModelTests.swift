import Foundation
import LCUKit
import MitoCore
import Testing

@testable import Mito

private typealias Fixture = HistoryFixture

/// The ranked page, then nothing: the first sync stops at the second page.
private func rankedHistory(
    script: [ConnectionState] = [.connected], phases: [String] = []
) throws -> HistoryTestConnection {
    HistoryTestConnection(
        script: script, phases: phases,
        bodies: [
            LCUEndpoint.currentSummoner.path: Fixture.summoner,
            Fixture.pagePath(0): Fixture.page(try Fixture.rankedGames()),
            Fixture.pagePath(20): Fixture.emptyPage,
        ])
}

private func games(_ matches: [MyMatch]) -> [Int] {
    matches.map(\.game.rawValue).sorted()
}

struct ProfileModelTests {
    @Test func aSyncOnConnectStoresTheHistory() async throws {
        let connection = try rankedHistory()
        let store = HistoryTestStore()
        let model = ProfileModel(connection: connection, store: store)

        await model.run()

        #expect(games(await store.stored) == [7_000_000_001, 7_000_000_002, 7_000_000_003])
        #expect(model.syncStatus == .synced(newGames: 3))
    }

    @Test func aSyncOnEndOfGameStoresTheHistory() async throws {
        let connection = try rankedHistory(script: [], phases: ["InProgress", "EndOfGame"])
        let store = HistoryTestStore()
        let model = ProfileModel(connection: connection, store: store)

        await model.run()

        #expect(connection.requests(to: LCUEndpoint.currentSummoner.path) == 1)
        #expect(games(await store.stored).count == 3)
    }

    @Test func otherPhasesDoNotSync() async throws {
        let connection = try rankedHistory(
            script: [.connecting], phases: ["Lobby", "ChampSelect", "InProgress", "PreEndOfGame"])
        let model = ProfileModel(connection: connection, store: HistoryTestStore())

        await model.run()

        #expect(connection.requests(to: LCUEndpoint.currentSummoner.path) == 0)
        #expect(model.syncStatus == .idle)
    }

    @Test func fetchesTheFullGameOnlyForIncompleteGamesNotStored() async throws {
        let ranked = try Fixture.rankedGames()
        // Game 1 lists only the local player; game 3 has no opponent but is already stored.
        let page = Fixture.page([Fixture.trimmed(ranked[0], keeping: [3]), ranked[1], ranked[2]])
        let storedThird = try #require(try Fixture.matches(in: Fixture.page([ranked[2]])).first)
        let connection = HistoryTestConnection(
            script: [.connected],
            bodies: [
                LCUEndpoint.currentSummoner.path: Fixture.summoner,
                Fixture.pagePath(0): page,
                Fixture.pagePath(20): Fixture.emptyPage,
                Fixture.gamePath(7_000_000_001): Fixture.json(ranked[0]),
            ])
        let store = HistoryTestStore(matches: [storedThird])
        let model = ProfileModel(connection: connection, store: store)

        await model.run()

        #expect(connection.requests(to: Fixture.gamePath(7_000_000_001)) == 1)
        #expect(connection.requests(to: Fixture.gamePath(7_000_000_002)) == 0)
        #expect(connection.requests(to: Fixture.gamePath(7_000_000_003)) == 0)
        let first = await store.stored.first { $0.game.rawValue == 7_000_000_001 }
        #expect(first?.participants.count == 9)
        #expect(model.syncStatus == .synced(newGames: 2))
    }

    @Test func aFailedFullGameFetchKeepsTheListVersion() async throws {
        let ranked = try Fixture.rankedGames()
        let connection = HistoryTestConnection(
            script: [.connected],
            bodies: [
                LCUEndpoint.currentSummoner.path: Fixture.summoner,
                Fixture.pagePath(0): Fixture.page([Fixture.trimmed(ranked[0], keeping: [3])]),
                Fixture.pagePath(20): Fixture.emptyPage,
            ])
        let store = HistoryTestStore()
        let model = ProfileModel(connection: connection, store: store)

        await model.run()

        #expect(connection.requests(to: Fixture.gamePath(7_000_000_001)) == 1)
        #expect(await store.stored.first?.participants.isEmpty == true)
    }

    @Test func aResyncChangesNothingAndReadsOnlyTheFirstPage() async throws {
        let connection = try rankedHistory()
        let store = HistoryTestStore()
        let model = ProfileModel(connection: connection, store: store)
        await model.run()
        let afterFirst = await store.stored

        await model.run()

        #expect(await store.stored == afterFirst)
        #expect(model.syncStatus == .synced(newGames: 0))
        #expect(connection.requests(to: Fixture.pagePath(0)) == 2)
        #expect(connection.requests(to: Fixture.pagePath(20)) == 1)
        // Game 3 has no opponent: its full game is asked for once, while it is new.
        #expect(connection.requests(to: Fixture.gamePath(7_000_000_003)) == 1)
    }

    @Test func theFirstSyncPagesBackToTheLastHundredGames() async throws {
        let page = Fixture.page(try Fixture.rankedGames())
        let connection = HistoryTestConnection(
            script: [.connected], bodies: [LCUEndpoint.currentSummoner.path: Fixture.summoner])
        for begin in stride(from: 0, to: 200, by: 20) {
            connection.serve(Fixture.pagePath(begin), page)
        }
        let model = ProfileModel(connection: connection, store: HistoryTestStore())

        await model.run()

        for begin in stride(from: 0, to: 100, by: 20) {
            #expect(connection.requests(to: Fixture.pagePath(begin)) == 1, "\(begin)")
        }
        #expect(connection.requests(to: Fixture.pagePath(100)) == 0)
    }

    @Test func theFirstSyncStopsAtAnEmptyPage() async throws {
        let connection = try rankedHistory()
        connection.serve(Fixture.pagePath(40), Fixture.page(try Fixture.rankedGames()))

        await ProfileModel(connection: connection, store: HistoryTestStore()).run()

        #expect(connection.requests(to: Fixture.pagePath(20)) == 1)
        #expect(connection.requests(to: Fixture.pagePath(40)) == 0)
    }

    @Test func aClientFailureIsReportedAndWaitsForTheNextTrigger() async throws {
        let connection = try rankedHistory()
        connection.serve(Fixture.pagePath(0), nil)
        let model = ProfileModel(connection: connection, store: HistoryTestStore())

        await model.run()

        #expect(model.syncStatus == .failed(.client))
        #expect(connection.requests(to: Fixture.pagePath(0)) == 1)
    }

    @Test func aSyncAfterAFailureStillPagesBack() async throws {
        let connection = try rankedHistory()
        connection.serve(Fixture.pagePath(0), nil)
        let store = HistoryTestStore()
        let model = ProfileModel(connection: connection, store: store)
        await model.run()

        connection.serve(Fixture.pagePath(0), Fixture.page(try Fixture.rankedGames()))
        await model.run()

        #expect(connection.requests(to: Fixture.pagePath(20)) == 1)
        #expect(model.syncStatus == .synced(newGames: 3))
    }

    @Test func aStoreFailureIsReported() async throws {
        let model = ProfileModel(
            connection: try rankedHistory(), store: HistoryTestStore(failure: .writeFailed))

        await model.run()

        #expect(model.syncStatus == .failed(.storage))
    }

    @Test(arguments: [nil, #"{"summonerLevel": 30}"#, #"{"puuid": ""}"#])
    func withoutTheCurrentSummonerNothingSyncs(summoner: String?) async throws {
        let connection = try rankedHistory()
        connection.serve(LCUEndpoint.currentSummoner.path, summoner.map { Data($0.utf8) })
        let store = HistoryTestStore()
        let model = ProfileModel(connection: connection, store: store)

        await model.run()

        #expect(connection.requests(to: Fixture.pagePath(0)) == 0)
        #expect(await store.stored.isEmpty)
        #expect(model.syncStatus == .idle)
    }

    @Test func statusLinesCarryTheCountAndASymbol() {
        #expect(ProfileModel.SyncStatus.idle.title == nil)
        let synced = ProfileModel.SyncStatus.synced(newGames: 3)
        #expect(synced.title.map { String(localized: $0) } == "Historial al día: 3 partidas nuevas")
        #expect(synced.symbol == "checkmark.circle")
        #expect(ProfileModel.SyncStatus.failed(.storage).symbol == "exclamationmark.triangle")
    }
}
