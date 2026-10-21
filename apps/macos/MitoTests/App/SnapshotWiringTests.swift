import MitoCore
import Observation
import Synchronization
import Testing

@testable import Mito

struct SnapshotWiringTests {
    @Test func championsShowsRowsOnceASnapshotOpens() async {
        let app = AppModel(
            connection: ScriptedLCUConnection(script: []),
            snapshots: SnapshotModel(origin: .file(SnapshotFixture.file)))
        #expect(app.champions.rows.isEmpty)
        let changed = Mutex(false)
        withObservationTracking {
            _ = app.champions.rows
        } onChange: {
            changed.withLock { $0 = true }
        }

        await app.start()

        #expect(changed.withLock { $0 })
        #expect(app.champions.meta?.patch == Patch(rawValue: "16.21"))
        #expect(app.champions.rows.map(\.champion).contains(ChampionID(rawValue: 122)))
    }

}
