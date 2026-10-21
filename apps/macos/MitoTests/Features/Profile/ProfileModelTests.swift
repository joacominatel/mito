import Foundation
import LCUKit
import MitoCore
import MitoEngine
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

/// The test swaps the open snapshot, as `SnapshotModel` does when a download lands.
@MainActor private final class StatsBox {
    var provider: any StatsProvider = TestStats()
}

private let ahri = ChampionID(rawValue: 103)

extension ProfileModelTests {
    @Test func runReadsTheStoredHistoryWithoutAClient() async {
        let stored = [
            TestGame.make(1, champion: 103, win: true),
            TestGame.make(2, champion: 103, win: false, hoursAgo: 1),
        ]
        let model = ProfileModel(
            connection: HistoryTestConnection(script: [.searching]),
            store: HistoryTestStore(matches: stored))

        await model.run()

        #expect(model.history.map(\.game.rawValue) == [1, 2])
        #expect(model.bestChampions.first?.rows.first?.games == 2)
        #expect(model.masteryPoints.isEmpty)
    }

    @Test func anEmptyHistoryLeavesTheProfileEmpty() async {
        let model = ProfileModel(
            connection: HistoryTestConnection(script: [.searching]), store: HistoryTestStore())

        await model.run()

        #expect(model.history.isEmpty)
        #expect(model.bestChampions.isEmpty)
        #expect(model.matchups.isEmpty)
        #expect(model.shortGames == nil)
        #expect(model.lossStreak == nil)
    }

    @Test func aSyncShowsTheNewGamesInTheProfile() async throws {
        let model = ProfileModel(connection: try rankedHistory(), store: HistoryTestStore())

        await model.run()

        #expect(games(model.history) == [7_000_000_001, 7_000_000_002, 7_000_000_003])
    }

    @Test func thePoolAndOverridesComeFromTheStore() async {
        let store = HistoryTestStore(
            matches: [
                TestGame.make(1, champion: 103, win: true),
                TestGame.make(2, champion: 134, win: true),
            ],
            pool: [
                PoolEntry(role: .middle, champion: ahri, priority: 0),
                PoolEntry(role: .middle, champion: ChampionID(rawValue: 134), priority: 1),
            ],
            overrides: [
                ChampionOverride(
                    champion: ChampionID(rawValue: 134), role: .middle, isExcludedFromPool: true)
            ])
        let model = ProfileModel(connection: HistoryTestConnection(script: []), store: store)

        await model.run()

        let rows = model.bestChampions.first?.rows ?? []
        #expect(rows.map(\.score.inPool) == [true, false])
        #expect(rows.first?.champion == ahri)
    }

    @Test func masteryIsReadLiveOnConnect() async throws {
        let connection = try rankedHistory()
        connection.serve(LCUEndpoint.championMastery.path, try HistoryFixture.mastery())
        let model = ProfileModel(
            connection: connection,
            store: HistoryTestStore(matches: [TestGame.make(1, champion: 103, win: true)]))

        await model.run()

        #expect(connection.requests(to: LCUEndpoint.championMastery.path) == 1)
        #expect(model.masteryPoints[ahri] == 245_310)
        let row = model.bestChampions.flatMap(\.rows).first { $0.champion == ahri }
        #expect(row?.score.metrics.masteryNorm == 1)
    }

    @Test func aFailedMasteryReadMeansNoMastery() async throws {
        let connection = try rankedHistory()
        connection.serve(LCUEndpoint.championMastery.path, try HistoryFixture.mastery())
        let model = ProfileModel(connection: connection, store: HistoryTestStore())
        await model.run()

        connection.serve(LCUEndpoint.championMastery.path, nil)
        await model.run()

        #expect(model.masteryPoints.isEmpty)
    }

    @Test func masteryIsDroppedWhenTheClientGoes() async throws {
        let connection = HistoryTestConnection(
            script: [.connected, .searching],
            bodies: [LCUEndpoint.championMastery.path: try HistoryFixture.mastery()])
        let model = ProfileModel(connection: connection, store: HistoryTestStore())

        await model.run()

        #expect(connection.requests(to: LCUEndpoint.championMastery.path) == 1)
        #expect(model.masteryPoints.isEmpty)
    }

    @Test func theScoreFollowsTheOpenSnapshot() async throws {
        let box = StatsBox()
        let model = ProfileModel(
            connection: HistoryTestConnection(script: []),
            store: HistoryTestStore(matches: [TestGame.make(1, champion: 103, win: true)]),
            stats: { box.provider })
        await model.run()
        let before = try #require(model.bestChampions.first?.rows.first?.score)

        box.provider = TestStats(rows: [
            .middle: [ahri: ChampionRoleStats(games: 10_000, wins: 5_600, timelineGames: 0)]
        ])

        let after = try #require(model.bestChampions.first?.rows.first?.score)
        #expect(before.metrics.globalWinrate == 0.5)
        #expect(after.metrics.globalWinrate > 0.55)
        #expect(after.winrateEdge < before.winrateEdge)
    }
}

struct ProfileRecordFailureTests {
    @Test func aFailedRecordIsAStorageFailureAndTheHistoryStaysAsItWas() async throws {
        let stored = TestGame.make(1, champion: 103, win: true)
        let store = HistoryTestStore(matches: [stored])
        await store.failRecords(with: .writeFailed)
        let model = ProfileModel(connection: try rankedHistory(), store: store)

        await model.run()

        #expect(model.syncStatus == .failed(.storage))
        #expect(model.history == [stored])
        #expect(await store.stored == [stored])
    }

    /// Nothing landed, so the next sync still pages back for the backfill.
    @Test func theSyncAfterAFailedRecordStillPagesBack() async throws {
        let connection = try rankedHistory()
        let store = HistoryTestStore()
        await store.failRecords(with: .writeFailed)
        let model = ProfileModel(connection: connection, store: store)
        await model.run()

        await store.failRecords(with: nil)
        await model.run()

        #expect(connection.requests(to: Fixture.pagePath(20)) == 2)
        #expect(model.syncStatus == .synced(newGames: 3))
    }
}
