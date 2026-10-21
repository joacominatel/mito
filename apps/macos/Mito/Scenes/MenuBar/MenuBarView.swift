import SwiftUI

/// The §22.4 sections, in order.
struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ConnectionMenuSection()
            Divider()
            GameflowMenuSection()
            RecommendationMenuSection()
            Divider()
            QuickTogglesMenuSection()
            Divider()
            Button {
                openWindow(id: MitoApp.mainWindowID)
            } label: {
                Text("Abrir Mito", tableName: "Shell")
            }
            .keyboardShortcut("o")
            SettingsLink {
                Text("Settings…", tableName: "Shell")
            }
            .keyboardShortcut(",")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Salir", tableName: "Shell")
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 280)
    }
}

#Preview {
    MenuBarView()
        .environment(AppModel(connection: DisconnectedLCUConnection()))
}
