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

private actor CallCounter {
    private(set) var calls = 0
    func count() { calls += 1 }
}
