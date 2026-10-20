import SwiftUI

@main
struct MitoApp: App {
    var body: some Scene {
        MenuBarExtra("Mito", systemImage: "circle.dashed") {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)

        Window("Mito", id: "main") {
            MainWindowView()
        }
        .defaultSize(width: 1100, height: 720)

        Settings {
            SettingsView()
        }
    }
}
