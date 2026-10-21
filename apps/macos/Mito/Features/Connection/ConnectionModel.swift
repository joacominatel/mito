import Foundation
import LCUKit
import Observation

@Observable
final class ConnectionModel {
    private(set) var state: ConnectionState
    private let connection: any LCUConnection

    init(connection: any LCUConnection, state: ConnectionState = .searching) {
        self.connection = connection
        self.state = state
    }

    /// §22.4: dashed until connected.
    var menuBarSymbol: String {
        isConnected ? "circle.fill" : "circle.dashed"
    }

    var isConnected: Bool { state == .connected }

    var isConnecting: Bool { state == .connecting }

    var status: LocalizedStringResource {
        switch state {
        case .searching: LocalizedStringResource("Mito — Buscando el cliente…", table: "Connection")
        case .connecting: LocalizedStringResource("Mito — Conectando…", table: "Connection")
        case .connected: LocalizedStringResource("Mito — Conectado", table: "Connection")
        }
    }

    func run() async {
        for await state in connection.states() {
            self.state = state
        }
    }
}
