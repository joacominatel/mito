import SwiftUI

/// The status-item label. It lives as long as the app, so it also opens the main window when
/// champ select starts, with or without a window open (§20.1).
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label {
            Text(verbatim: "Mito")
        } icon: {
            Image(systemName: app.menuBarSymbol)
        }
        .onChange(of: app.champSelectPresence, initial: true) {
            if app.shouldOpenWindowForChampSelect() {
                openWindow(id: MitoApp.mainWindowID)
            }
        }
    }
}
