import Foundation
import LCUKit
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

    #if DEBUG
        @Test func readsTheLockfileOverrideFromDefaults() throws {
            let suite = "MitoTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set("/tmp/lockfile", forKey: AppModel.lockfileOverrideKey)

            let app = AppModel(connection: ScriptedLCUConnection(script: []), defaults: defaults)

            #expect(app.lockfileOverridePath == "/tmp/lockfile")
        }
    #endif
}
