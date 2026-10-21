import SwiftUI

@main
struct MitoApp: App {
    static let mainWindowID = "main"

    @State private var app: AppModel

    init() {
        let app = AppModel(connection: DisconnectedLCUConnection())
        _app = State(initialValue: app)
        // The app lives in the menu bar with no window guaranteed open, so no view can own this.
        Task { await app.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(app)
        } label: {
            Label {
                Text(verbatim: "Mito")
            } icon: {
                Image(systemName: app.menuBarSymbol)
            }
        }
        .menuBarExtraStyle(.window)

        Window(Text(verbatim: "Mito"), id: Self.mainWindowID) {
            MainWindowView()
                .environment(app)
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
