import LCUKit
import MitoCore
import SwiftUI

/// §21.2.
struct GameflowSettingsTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        let game = $app.settings.game
        Form {
            Section {
                Picker(selection: game.autoAccept) {
                    Text("Desactivado", tableName: "Gameflow")
                        .tag(GameSettings.AutoAccept.off)
                    Text("Siempre", tableName: "Gameflow")
                        .tag(GameSettings.AutoAccept.always)
                    Text("Solo colas elegidas", tableName: "Gameflow")
                        .tag(GameSettings.AutoAccept.selectedQueues)
                } label: {
                    Text("Auto-accept", tableName: "Gameflow")
                }
                Stepper(value: game.autoAcceptDelaySeconds, in: AutoAcceptPolicy.delayRange) {
                    Text(
                        "Demora: \(app.settings.game.autoAcceptDelaySeconds) s",
                        tableName: "Gameflow")
                }
                .disabled(app.settings.game.autoAccept == .off)
            }

            if app.settings.game.autoAccept == .selectedQueues {
                Section {
                    ForEach(Self.queues, id: \.type) { queue in
                        Toggle(isOn: game[autoAccepts: queue.type.queueID]) {
                            Text(queue.title)
                        }
                    }
                } header: {
                    Text("Colas", tableName: "Gameflow")
                }
            }

            Section {
                Toggle(isOn: game.notifyMatchFound) {
                    Text("Notificar partida encontrada", tableName: "Gameflow")
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let queues: [(type: QueueType, title: LocalizedStringResource)] = [
        (.rankedSolo, LocalizedStringResource("Clasificatoria solo/dúo", table: "Gameflow")),
        (.rankedFlex, LocalizedStringResource("Clasificatoria flexible", table: "Gameflow")),
        (.normalDraft, LocalizedStringResource("Normal de reclutamiento", table: "Gameflow")),
        (.normalBlind, LocalizedStringResource("Normal a ciegas", table: "Gameflow")),
        (.aram, LocalizedStringResource("ARAM", table: "Gameflow")),
    ]
}

#Preview {
    GameflowSettingsTab()
        .environment(
            AppModel(
                connection: DisconnectedLCUConnection(),
                settings: SettingsModel(
                    value: MitoSettings(
                        game: GameSettings(
                            autoAccept: .selectedQueues, autoAcceptQueues: [QueueID(rawValue: 420)])
                    )))
        )
        .frame(width: 520, height: 420)
}
