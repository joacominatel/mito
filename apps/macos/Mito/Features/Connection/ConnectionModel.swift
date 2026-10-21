import Foundation
import LCUKit
import Observation

@Observable
final class ConnectionModel {
    private(set) var state: ConnectionState
    /// The signed-in account's `gameName#tagLine`, only while connected.
    private(set) var riotID: String?
    private let connection: any LCUConnection
    @ObservationIgnored private var fetchGeneration = 0

    init(connection: any LCUConnection, state: ConnectionState = .searching, riotID: String? = nil)
    {
        self.connection = connection
        self.state = state
        self.riotID = riotID
    }

    /// §22.4: dashed until connected.
    var menuBarSymbol: String {
        isConnected ? "circle.fill" : "circle.dashed"
    }

    var isConnected: Bool { state == .connected }

    var isConnecting: Bool { state == .connecting }

    var status: LocalizedStringResource {
        switch state {
        case .searching:
            LocalizedStringResource("Mito — Buscando el cliente…", table: "Connection")
        case .connecting:
            LocalizedStringResource("Mito — Conectando…", table: "Connection")
        case .connected:
            if let riotID {
                LocalizedStringResource("Mito — Conectado como \(riotID)", table: "Connection")
            } else {
                LocalizedStringResource("Mito — Conectado", table: "Connection")
            }
        }
    }

    func run() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.followAccountChanges() }
            for await state in connection.states() {
                self.state = state
                if state == .connected {
                    group.addTask { await self.refreshRiotID() }
                } else {
                    fetchGeneration += 1
                    riotID = nil
                }
            }
            // The event listener would otherwise keep run() alive after states() ends.
            group.cancelAll()
        }
    }

    /// Only the latest fetch may write, and none once the connection has dropped.
    func refreshRiotID() async {
        fetchGeneration += 1
        let generation = fetchGeneration
        let summoner = try? await connection.send(.currentSummoner)
        guard generation == fetchGeneration, isConnected else { return }
        riotID = summoner?.riotID
    }

    private func followAccountChanges() async {
        for await _ in connection.events([.currentSummoner]) where isConnected {
            await refreshRiotID()
        }
    }
}
