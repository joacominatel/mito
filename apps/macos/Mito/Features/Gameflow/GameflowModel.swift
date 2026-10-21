import LCUKit
import Observation

@Observable
final class GameflowModel {
    private let connection: any LCUConnection

    init(connection: any LCUConnection) {
        self.connection = connection
    }

    /// The §22.4 symbol for the current phase; `nil` leaves the connection symbol.
    var menuBarSymbol: String? { nil }

    func run() async {}
}
