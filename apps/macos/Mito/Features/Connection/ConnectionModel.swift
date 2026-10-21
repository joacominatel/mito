import LCUKit
import Observation

@Observable
final class ConnectionModel {
    private(set) var state: ConnectionState = .searching
    private let connection: any LCUConnection

    init(connection: any LCUConnection) {
        self.connection = connection
    }

    /// §22.4: dashed until connected.
    var menuBarSymbol: String {
        state == .connected ? "circle.fill" : "circle.dashed"
    }

    func run() async {
        for await state in connection.states() {
            self.state = state
        }
    }
}
