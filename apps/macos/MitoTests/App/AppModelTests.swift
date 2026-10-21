import Foundation
import LCUKit
import MitoAssets
import MitoCore
import Testing

@testable import Mito

struct AppModelTests {
    @Test func startRunsEverySlotAndReturnsWhenAllFinish() async {
        let app = AppModel(connection: ScriptedLCUConnection(script: [.connecting, .connected]))

        await app.start()

        #expect(app.connection.state == .connected)
    }

    @Test func menuBarSymbolFollowsTheConnection() async {
        let app = AppModel(connection: ScriptedLCUConnection(script: [.connected]))
        #expect(app.menuBarSymbol == "circle.dashed")

        await app.start()

        #expect(app.menuBarSymbol == "circle.fill")
    }

    @Test func startRunsTheLifecycle() async {
        let (runs, recorder) = AsyncStream.makeStream(of: Void.self)
        let app = AppModel(
            connection: ScriptedLCUConnection(script: []),
            lifecycle: {
                recorder.yield()
                recorder.finish()
            })

        await app.start()

        var count = 0
        for await _ in runs { count += 1 }
        #expect(count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingStartCancelsTheLifecycle() async {
        let (steps, recorder) = AsyncStream.makeStream(of: String.self)
        let app = AppModel(
            connection: ScriptedLCUConnection(script: []),
            lifecycle: {
                recorder.yield("started")
                try? await Task.sleep(for: .seconds(3600))
                recorder.yield(Task.isCancelled ? "cancelled" : "finished")
                recorder.finish()
            })
        let running = Task { await app.start() }
        var iterator = steps.makeAsyncIterator()
        #expect(await iterator.next() == "started")

        running.cancel()

        #expect(await iterator.next() == "cancelled")
        await running.value
    }

    @Test(.timeLimit(.minutes(1)))
    func featuresShareOneStaticDataLoadPerConnection() async {
        let connection = ServingLCUConnection(
            script: [.connected, .searching, .connected], bodies: ClientDataFixture.bodies())
        let app = AppModel(connection: connection)

        await app.start()

        for path in ClientDataFixture.staticDataPaths {
            #expect(connection.requests(to: path) == 2, "\(path)")
        }
        #expect(app.champSelect.gameData?.champion(ChampionID(rawValue: 103))?.name == "Ahri")
    }

    @Test(.timeLimit(.minutes(1)))
    func theGameVersionReachesTheDraftPatch() async throws {
        let app = AppModel(
            connection: ServingLCUConnection(
                script: [.connected], bodies: ClientDataFixture.bodies()))
        await app.start()

        app.champSelect.show(
            try LCUEndpoint.champSelectSession.decode(ImportFixture.data("ban-pick-in-progress")),
            queue: .rankedSolo, pickable: [])

        #expect(app.champSelect.draft?.patch == Patch(rawValue: "16.21"))
    }

    @Test(arguments: [true, false])
    func champSelectOpensTheWindowOnlyWithTheSettingOn(enabled: Bool) throws {
        let app = AppModel(connection: ScriptedLCUConnection(script: []))
        app.settings.general.showWindowOnChampSelect = enabled
        #expect(!app.shouldOpenWindowForChampSelect())

        app.champSelect.show(
            try LCUEndpoint.champSelectSession.decode(ImportFixture.data("ban-pick-in-progress")),
            queue: .rankedSolo, pickable: [])

        #expect(app.champSelectPresence.isInChampSelect)
        #expect(app.shouldOpenWindowForChampSelect() == enabled)
        #expect(!app.shouldOpenWindowForChampSelect())
    }
}
