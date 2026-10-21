import LCUKit
import MitoAssets
import MitoCore
import Observation

/// The client's static data and game version, read once per connection and shared by every
/// feature that needs them (§9.3).
@Observable
final class ClientDataModel {
    /// What the last successful load returned; a failed reload keeps it.
    private(set) var gameData: GameData?
    /// `nil` until read, or when the read failed on this connection.
    private(set) var gameVersion: GameVersion?

    let catalog: GameDataCatalog
    private let connection: any LCUConnection

    init(connection: any LCUConnection) {
        self.connection = connection
        catalog = GameDataCatalog(connection: connection)
    }

    /// Empty while the version is unknown.
    var patch: Patch { gameVersion?.patch ?? Patch(rawValue: "") }

    func run() async {
        await withDiscardingTaskGroup { group in
            for await state in connection.states() where state == .connected {
                group.addTask { await self.load() }
            }
        }
    }

    private func load() async {
        async let version = try? connection.send(.gameVersion)
        if let loaded = try? await catalog.reload() { gameData = loaded }
        gameVersion = await version
    }
}
