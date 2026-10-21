import SwiftUI

/// The status-item label. It appears at launch, so it hands `AppModel` the action that opens the
/// main window when champ select starts (§20.1) or the Dock icon is clicked (§24).
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label {
            Text(verbatim: "Mito")
        } icon: {
            Image(systemName: app.menuBarSymbol)
        }
        .onAppear {
            app.presence.setMainWindowOpener { [openWindow] in
                openWindow(id: MitoApp.mainWindowID)
            }
        }
    }
}
