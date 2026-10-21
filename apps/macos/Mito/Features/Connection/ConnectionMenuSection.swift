import LCUKit
import SwiftUI

struct ConnectionMenuSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ConnectionStatusRow(model: app.connection)
    }
}

struct ConnectionStatusRow: View {
    let model: ConnectionModel

    var body: some View {
        Label {
            Text(model.status)
        } icon: {
            Image(systemName: model.menuBarSymbol)
                .foregroundStyle(
                    model.isConnected ? AnyShapeStyle(Color.favorable) : AnyShapeStyle(.secondary)
                )
                .symbolEffect(.pulse, isActive: model.isConnecting)
                .accessibilityHidden(true)
        }
        .font(.headline)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Buscando") {
    ConnectionStatusRow(model: ConnectionModel(connection: DisconnectedLCUConnection()))
        .padding()
}

#Preview("Conectando") {
    ConnectionStatusRow(
        model: ConnectionModel(connection: DisconnectedLCUConnection(), state: .connecting)
    )
    .padding()
}

#Preview("Conectado") {
    ConnectionStatusRow(
        model: ConnectionModel(connection: DisconnectedLCUConnection(), state: .connected)
    )
    .padding()
}

#Preview("Conectado como") {
    ConnectionStatusRow(
        model: ConnectionModel(
            connection: DisconnectedLCUConnection(), state: .connected, riotID: "Joaco#LAS")
    )
    .padding()
}
