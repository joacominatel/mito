import Foundation
import LCUKit
import MitoCore
import MitoStore
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

    @Test func theAnalysisCarriesTheInstalledTipsWhenTheirDownloadFails() async throws {
        let tips = SnapshotModelTests.tips("Jugá el nivel 2.")
        let app = AppModel(
            connection: ScriptedLCUConnection(script: []),
            snapshots: SnapshotModel(
                origin: .source(
                    FakeSnapshotSource(
                        cached: nil, download: .failure(.noMatchingSnapshot),
                        installedTips: tips, tipsDownload: .failure(.tipsInvalid)))))

        await app.snapshots.run()
        app.champSelect.show(
            try LCUEndpoint.champSelectSession.decode(
                Data(AnalysisSubjectTests.session(me: #""championId": 103"#).utf8)),
            queue: .rankedSolo, pickable: [])

        #expect(app.analysis.subject?.tips == tips)
    }

}
