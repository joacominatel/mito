import LCUKit
import MitoStore
import Testing

@testable import Mito

struct PersonalStoreWiringTests {
    @Test func underXCTestTheAppNeverOpensTheRealDatabase() {
        #expect(UnavailablePersonalStore.live(underTest: true) is UnavailablePersonalStore)
        #expect(
            AppModel(connection: ScriptedLCUConnection(script: [])).personal
                is UnavailablePersonalStore)
    }

    @Test func outsideTestsTheAppUsesThePersonalDatabase() {
        #expect(UnavailablePersonalStore.live(underTest: false) is PersonalDatabase)
    }

    @Test func profileSyncsIntoTheAppsStore() async throws {
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
    }
}
