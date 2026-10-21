import Foundation
import LCUKit
import MitoCore
import Testing

@testable import Mito

@Suite(.timeLimit(.minutes(1)))
struct FlashAndCatalogWiringTests {
    @Test func onboardingListsTheSharedChampionsWithoutARequestOfItsOwn() async {
        let connection = ServingLCUConnection(
            script: [.connected], bodies: ClientDataFixture.bodies())
        let app = AppModel(connection: connection)

        await app.start()

        #expect(app.onboarding.searchResults.map(\.name) == ["Ahri"])
        #expect(connection.requests(to: LCUEndpoint.gameDataChampions.path) == 1)
    }

    @Test func aHistorySyncDetectsTheFlashSlotWithoutTheTabOpen() async throws {
        let store = HistoryTestStore()
        let connection = HistoryTestConnection(
            script: [.connected],
            bodies: [
                LCUEndpoint.currentSummoner.path: HistoryFixture.summoner,
                HistoryFixture.pagePath(0): HistoryFixture.page(try HistoryFixture.rankedGames()),
                HistoryFixture.pagePath(20): HistoryFixture.emptyPage,
            ])
        let app = AppModel(connection: connection, personal: store)

        await app.start()

        #expect(await store.stored.count == 3)
        guard case .loaded(let detection) = app.onboarding.flash else {
            Issue.record("Flash not detected: \(app.onboarding.flash)")
            return
        }
        #expect(detection.games == 3)
    }

    @Test func anImportAfterAHistorySyncPutsFlashInTheDetectedSlot() async throws {
        let games = try HistoryFixture.rankedGames().map(withFlashOnF)
        var bodies = ImportFixture.gameData
        bodies[LCUEndpoint.gameVersion.path] = ClientDataFixture.version
        bodies[LCUEndpoint.currentSummoner.path] = Data(
            #"{"puuid": "fake-puuid-local", "summonerId": 1, "summonerLevel": 30}"#.utf8)
        bodies[HistoryFixture.pagePath(0)] = HistoryFixture.page(games)
        bodies[HistoryFixture.pagePath(20)] = HistoryFixture.emptyPage
        bodies[LCUEndpoint.perkStyles.path] = try ImportFixture.data("styles", in: "runes")
        bodies[LCUEndpoint.perkPages.path] = try ImportFixture.data(
            "pages-without-mito-page", in: "runes")
        bodies[LCUEndpoint.perkInventory.path] = try ImportFixture.data(
            "inventory-with-room", in: "runes")
        bodies[LCUEndpoint.gameflowSession.path] = try ImportFixture.data(
            "session-ranked-solo", in: "gameflow-lobby")
        bodies[LCUEndpoint.itemSets(summonerId: 1).path] = try ImportFixture.data(
            "empty", in: "item-sets")
        let connection = BroadcastLCUConnection(bodies: bodies)
        let poster = RecordingPoster()
        let app = AppModel(
            connection: connection, snapshots: SnapshotModel(origin: .file(SnapshotFixture.file)),
            personal: HistoryTestStore(), poster: poster, appIsActive: { false })
        let start = Task { await app.start() }

        await waitUntil {
            app.onboarding.resolvedFlashSlot(.auto) == .f && app.snapshots.status == .ready
        }
        // The session holds Flash on D and Ignite; the snapshot's pair is Flash and Teleport
        // (0.512 against Ignite's 0.473).
        connection.emit(try ImportFixture.lockedSession(mySpells: [4, 14]))
        await waitUntil { !poster.posts.isEmpty }
        connection.finish()
        await start.value

        let spells = try #require(
            connection.writes(.patch, "/lol-champ-select/v1/session/my-selection").first?.body)
        #expect(
            try JSONSerialization.jsonObject(with: spells) as? [String: Int]
                == ["spell1Id": 12, "spell2Id": 4])
        #expect(
            poster.posts.map(\.notification) == [
                .loadoutImported(champion: ChampionID(rawValue: 103), opponent: nil)
            ])
    }

    @Test func theStoreHookRunsAfterEachRecordThatLands() async throws {
        let calls = CallCounter()
        let store = HistoryNotifyingStore(base: HistoryTestStore()) { await calls.count() }

        try await store.record([])
        try await store.record([])

        #expect(await calls.calls == 2)
    }

    @Test func aFailedRecordSkipsTheHook() async {
        let calls = CallCounter()
        let store = HistoryNotifyingStore(base: HistoryTestStore(failure: .writeFailed)) {
            await calls.count()
        }

        await #expect(throws: PersonalStoreError.writeFailed) { try await store.record([]) }
        #expect(await calls.calls == 0)
    }
}

/// `game` with the local player holding Ignite on D and Flash on F.
private func withFlashOnF(_ game: [String: Any]) -> [String: Any] {
    let identities = (game["participantIdentities"] as? [[String: Any]]) ?? []
    let local =
        identities.first {
            ($0["player"] as? [String: Any])?["puuid"] as? String == HistoryFixture.localPUUID
        }?["participantId"] as? Int
    var game = game
    game["participants"] = ((game["participants"] as? [[String: Any]]) ?? []).map { participant in
        guard participant["participantId"] as? Int == local else { return participant }
        var participant = participant
        participant["spell1Id"] = 14
        participant["spell2Id"] = 4
        return participant
    }
    return game
}

private actor CallCounter {
    private(set) var calls = 0
    func count() { calls += 1 }
}
