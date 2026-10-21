import LCUKit
import MitoCore
import Observation

@Observable
final class GameflowModel {
    private let connection: any LCUConnection
    let settings: @MainActor () -> GameSettings

    init(
        connection: any LCUConnection,
        settings: @escaping @MainActor () -> GameSettings = { GameSettings() }
    ) {
        self.connection = connection
        self.settings = settings
    }

    /// The §22.4 symbol for the current phase; `nil` leaves the connection symbol.
    var menuBarSymbol: String? { nil }

    func run() async {}
}
