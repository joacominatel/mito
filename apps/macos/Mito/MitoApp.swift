import LCUKit
import MitoCore
import MitoStore
import SwiftUI

@main
struct MitoApp: App {
    static let mainWindowID = "main"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app: AppModel

    init() {
        // MitoTests run inside this app; they must never reach a live League client, the real
        // settings file, the snapshot cache and its download, the personal database, icons, the
        // update feed, login items, or the activation policy.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let settings = SettingsModel(persistence: underTest ? nil : SettingsStore())
        let client = AppModel.liveClient(installPath: {
            await settings.value.general.leagueInstallPath
        })
        let app = AppModel(
            connection: client,
            lifecycle: AppModel.lifecycle(running: client, underTest: underTest),
            settings: settings,
            snapshots: SnapshotModel(origin: .live(underTest: underTest)),
            personal: UnavailablePersonalStore.live(underTest: underTest),
            iconLoader: IconSource.liveLoader(connection: client, underTest: underTest),
            updates: { UpdaterModel.live(settings: $0, underTest: underTest) },
            loginItem: { LoginItemModel.live(settings: $0, underTest: underTest) },
            setActivationPolicy: AppPresenceModel.livePolicySetter(underTest: underTest))
        _app = State(initialValue: app)
        AppDelegate.reopen = { app.presence.openMainWindow() }
        // The app lives in the menu bar with no window guaranteed open, so no view can own these.
        Task { await app.start() }
        Task { await app.react() }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: Bindable(app.presence).isMenuBarExtraInserted) {
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
