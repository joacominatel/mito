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
