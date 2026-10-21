import Foundation
import LCUKit
import Testing

@testable import Mito

struct ConnectionModelTests {
    @Test func startsSearchingBeforeAnyState() {
        let model = ConnectionModel(connection: ScriptedLCUConnection(script: []))

        #expect(model.state == .searching)
    }

    @Test(arguments: [
        ([ConnectionState.connecting], ConnectionState.connecting),
        ([.searching, .connecting], .connecting),
        ([.connecting, .connected], .connected),
        ([.connected, .searching], .searching),
        ([.connected, .searching, .connecting, .connected], .connected),
    ])
    func followsTheLatestStateFromTheConnection(script: [ConnectionState], last: ConnectionState)
        async
    {
        let model = ConnectionModel(connection: ScriptedLCUConnection(script: script))

        await model.run()

        #expect(model.state == last)
    }

    @Test func runReturnsAndKeepsTheStateWhenTheStreamFinishes() async {
        let model = ConnectionModel(
            connection: ScriptedLCUConnection(script: []), state: .connected)

        await model.run()

        #expect(model.state == .connected)
    }

    @Test(arguments: [
        (ConnectionState.searching, "circle.dashed", "Mito — Buscando el cliente…"),
        (.connecting, "circle.dashed", "Mito — Conectando…"),
        (.connected, "circle.fill", "Mito — Conectado"),
    ])
    func presentsSymbolAndStatusPerState(state: ConnectionState, symbol: String, status: String) {
        let model = ConnectionModel(connection: ScriptedLCUConnection(script: []), state: state)

        #expect(model.menuBarSymbol == symbol)
        #expect(String(localized: model.status) == status)
        #expect(model.isConnected == (state == .connected))
        #expect(model.isConnecting == (state == .connecting))
    }

    @Test func statusResolvesFromTheConnectionTable() {
        let model = ConnectionModel(connection: ScriptedLCUConnection(script: []))

        #expect(model.status.table == "Connection")
    }
}
