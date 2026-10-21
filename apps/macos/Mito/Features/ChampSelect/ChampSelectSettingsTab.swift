import MitoCore
import SwiftUI

struct ChampSelectSettingsTab: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            // The value lives in `GeneralSettings` (§21.1); opening the window is the shell's job.
            Toggle(isOn: $app.settings.general.showWindowOnChampSelect) {
                Text("Mostrar la ventana al entrar en champ select", tableName: "ChampSelect")
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    ChampSelectSettingsTab()
        .environment(AppModel(connection: DisconnectedLCUConnection()))
}
