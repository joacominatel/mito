import LCUKit
import MitoStore
import SwiftUI

@main
struct MitoApp: App {
    static let mainWindowID = "main"

    @State private var app: AppModel

    init() {
        let client = AppModel.liveClient()
        // MitoTests run inside this app; they must never reach a live League client, the real
        // settings file, the snapshot cache and its download, the personal database, icons, or
        // the update feed.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let app = AppModel(
            connection: client,
            lifecycle: AppModel.lifecycle(running: client, underTest: underTest),
            settings: SettingsModel(persistence: underTest ? nil : SettingsStore()),
            snapshots: SnapshotModel(origin: .live(underTest: underTest)),
            personal: UnavailablePersonalStore.live(underTest: underTest),
            iconLoader: IconSource.liveLoader(connection: client, underTest: underTest),
            updates: { UpdaterModel.live(settings: $0, underTest: underTest) })
        _app = State(initialValue: app)
        // The app lives in the menu bar with no window guaranteed open, so no view can own this.
        Task { await app.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(app)
                .environment(\.iconSource, app.icons)
        } label: {
            MenuBarLabel()
                .environment(app)
        }
        .menuBarExtraStyle(.window)

        Window(Text(verbatim: "Mito"), id: Self.mainWindowID) {
            MainWindowView()
                .environment(app)
                .environment(\.iconSource, app.icons)
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updates: app.updates)
            }
        }

        Settings {
            SettingsView()
                .environment(app)
        }
    }
}
