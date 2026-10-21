import LCUKit
import SwiftUI

struct GameflowMenuSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        GameflowStatusRow(model: app.gameflow)
    }
}

struct GameflowStatusRow: View {
    let model: GameflowModel

    var body: some View {
        Label {
            Text(model.phaseTitle)
        } icon: {
            Image(systemName: model.phaseSymbol)
                .accessibilityHidden(true)
        }
        .foregroundStyle(model.isInMatchFlow ? .primary : .secondary)
        .accessibilityElement(children: .combine)
    }
}

extension GameflowModel {
    /// A model frozen in `connection` and `phase`, for previews.
    static func preview(_ connection: ConnectionState, phase: GameflowPhase? = nil) -> GameflowModel
    {
        var machine = MitoStateMachine()
        machine.apply(connection)
        if let phase { machine.apply(phase) }
        return GameflowModel(connection: DisconnectedLCUConnection(), machine: machine)
    }
}

#Preview("Buscando") {
    GameflowStatusRow(model: .preview(.searching)).padding()
}

#Preview("Conectando") {
    GameflowStatusRow(model: .preview(.connecting)).padding()
}

#Preview("Sin partida") {
    GameflowStatusRow(model: .preview(.connected, phase: GameflowPhase.none)).padding()
}

#Preview("Lobby") {
    GameflowStatusRow(model: .preview(.connected, phase: .lobby)).padding()
}

#Preview("Buscando partida") {
    GameflowStatusRow(model: .preview(.connected, phase: .matchmaking)).padding()
}

#Preview("Partida encontrada") {
    GameflowStatusRow(model: .preview(.connected, phase: .readyCheck)).padding()
}

#Preview("Champ select") {
    GameflowStatusRow(model: .preview(.connected, phase: .champSelect)).padding()
}

#Preview("En partida") {
    GameflowStatusRow(model: .preview(.connected, phase: .inProgress)).padding()
}
