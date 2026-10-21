import SwiftUI

/// "Buscar actualizaciones…" for the app menu and the menu bar extra (§22.4).
struct CheckForUpdatesButton: View {
    let updates: UpdaterModel

    var body: some View {
        Button {
            updates.checkForUpdates()
        } label: {
            Text("Buscar actualizaciones…", tableName: "Shell")
        }
        .disabled(!updates.canCheckForUpdates)
        .help(
            updates.isConfigured
                ? Text("Busca una versión nueva de Mito.", tableName: "Shell")
                : Text("Las actualizaciones todavía no están configuradas.", tableName: "Shell"))
    }
}

#Preview("Sin configurar") {
    CheckForUpdatesButton(updates: UpdaterModel())
        .padding()
}
