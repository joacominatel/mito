import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Desconectado")
                .font(.headline)
            Divider()
            Button("Abrir Mito") { openWindow(id: "main") }
                .keyboardShortcut("o")
            SettingsLink { Text("Settings…") }
                .keyboardShortcut(",")
            Button("Salir") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 280)
    }
}
