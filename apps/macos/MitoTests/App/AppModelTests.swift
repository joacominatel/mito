import Foundation
import LCUKit
import MitoAssets
import MitoCore
import Observation
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

    @Test(.timeLimit(.minutes(1)))
    func theIconSourceReadsTheSharedClientDataAndLoadsNothingByDefault() async throws {
        let app = AppModel(
            connection: ServingLCUConnection(
                script: [.connected], bodies: ClientDataFixture.bodies()))
        await app.start()

        let request = try #require(app.icons.request(for: .champion(ChampionID(rawValue: 103))))
        #expect(request.gameVersion == "16.21.723.1234")
        await app.icons.load(request)
        #expect(app.icons.image(for: request) == nil)
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

    @Test(.timeLimit(.minutes(1)))
    func changingTheInstallPathWhileSearchingRestartsTheLifecycle() async {
        let (steps, recorder) = AsyncStream.makeStream(of: String.self)
        let app = AppModel(
            connection: ScriptedLCUConnection(script: []),
            lifecycle: {
                recorder.yield("started")
                try? await Task.sleep(for: .seconds(3600))
                recorder.yield("stopped")
            })
        let running = Task { await app.start() }
        var iterator = steps.makeAsyncIterator()
        #expect(await iterator.next() == "started")

        app.leagueInstallPath = "/Volumes/Games/LoL.app"

        #expect(app.settings.general.leagueInstallPath == "/Volumes/Games/LoL.app")
        #expect(await iterator.next() == "stopped")
        #expect(await iterator.next() == "started")
        running.cancel()
        #expect(await iterator.next() == "stopped")
        await running.value
    }

    @Test(.timeLimit(.minutes(1)))
    func changingTheInstallPathWhileConnectedKeepsTheClient() async {
        let (steps, recorder) = AsyncStream.makeStream(of: String.self)
        let app = AppModel(
            connection: ScriptedLCUConnection(script: [.connected]),
            lifecycle: {
                recorder.yield("started")
                try? await Task.sleep(for: .seconds(3600))
                recorder.yield("stopped")
            })
        let running = Task { await app.start() }
        var iterator = steps.makeAsyncIterator()
        #expect(await iterator.next() == "started")
        while app.connection.state != .connected { await Task.yield() }

        app.leagueInstallPath = "/Volumes/Games/LoL.app"
        running.cancel()

        #expect(await iterator.next() == "stopped")
        await running.value
        recorder.finish()
        #expect(await iterator.next() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func champSelectOpensTheWindowWithNoViewAlive() async throws {
        let app = AppModel(connection: ScriptedLCUConnection(script: []))
        let (opens, recorder) = AsyncStream.makeStream(of: Void.self)
        app.presence.setMainWindowOpener { recorder.yield() }
        let reacting = Task { await app.react() }

        app.champSelect.show(
            try LCUEndpoint.champSelectSession.decode(ImportFixture.data("ban-pick-in-progress")),
            queue: .rankedSolo, pickable: [])

        var iterator = opens.makeAsyncIterator()
        _ = await iterator.next()
        #expect(app.mainWindow.destination == .now)
        reacting.cancel()
        await reacting.value
    }
}

@MainActor
struct ObserveChangesTests {
    @Observable final class Box {
        var value = 0
        var other = 0
    }

    @Test(.timeLimit(.minutes(1)))
    func appliesTheCurrentValueThenEachDistinctChange() async {
        let box = Box()
        let (seen, recorder) = AsyncStream.makeStream(of: Int.self)
        let watching = Task {
            await observeChanges(of: { box.value }) { recorder.yield($0) }
        }
        var iterator = seen.makeAsyncIterator()
        #expect(await iterator.next() == 0)

        box.value = 1
        #expect(await iterator.next() == 1)
        box.other = 5
        box.value = 1
        box.value = 2
        #expect(await iterator.next() == 2)

        watching.cancel()
        await watching.value
    }
}
