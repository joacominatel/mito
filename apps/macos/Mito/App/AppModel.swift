import AppKit
import Foundation
import LCUKit
import MitoCore
import Observation

/// One slot per feature (ADR 0007). Each feature model subscribes to its own LCU topics in
/// `run()`; there is no central event loop.
@Observable
final class AppModel {
    #if DEBUG
        static let lockfileOverrideKey = "MitoLCULockfilePath"
    #endif

    let connection: ConnectionModel
    let clientData: ClientDataModel
    /// Views read it from the environment (`\.iconSource`); no feature model loads icons.
    let icons: IconSource
    let snapshots: SnapshotModel
    let mainWindow = MainWindowModel()
    let gameflow: GameflowModel
    let champSelect: ChampSelectModel
    let importing: ImportModel
    let champions: ChampionsModel
    let analysis: AnalysisModel
    let profile: ProfileModel
    let onboarding: OnboardingModel
    let overrides: OverridesModel
    let settingsModel: SettingsModel
    let updates: UpdaterModel
    let loginItem: LoginItemModel
    let presence: AppPresenceModel
    /// The one personal database; features that read or write it get it in their `init`.
    let personal: any PersonalStore

    private let lifecycle: @Sendable () async -> Void
    @ObservationIgnored private var lifecycleRun: Task<Void, Never>?
    @ObservationIgnored private var restartsLifecycle = false

    init(
        connection lcu: any LCUConnection,
        lifecycle: @escaping @Sendable () async -> Void = {},
        settings: SettingsModel = SettingsModel(),
        snapshots: SnapshotModel = SnapshotModel(),
        personal: any PersonalStore = UnavailablePersonalStore(),
        iconLoader: (any IconLoading)? = nil,
        poster: any NotificationPosting = SystemNotificationPoster(),
        appIsActive: @escaping @MainActor () -> Bool = { NSApplication.shared.isActive },
        updates: (SettingsModel) -> UpdaterModel = { UpdaterModel(settings: $0) },
        loginItem: (SettingsModel) -> LoginItemModel = { LoginItemModel(settings: $0) },
        setActivationPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { _ in }
    ) {
        connection = ConnectionModel(connection: lcu)
        let clientData = ClientDataModel(connection: lcu)
        self.clientData = clientData
        icons = IconSource(
            connection: lcu, loader: iconLoader, gameData: { clientData.gameData },
            gameVersion: { clientData.gameVersion })
        self.snapshots = snapshots
        gameflow = GameflowModel(
            connection: lcu, settings: { settings.value.game }, poster: poster)
        let champSelect = Self.champSelectModel(
            connection: lcu, clientData: clientData, settings: settings, snapshots: snapshots,
            personal: personal)
        self.champSelect = champSelect
        let onboarding = OnboardingModel(store: personal, gameData: clientData.gameData)
        self.onboarding = onboarding
        importing = Self.importModel(
            connection: lcu, clientData: clientData, settings: settings, snapshots: snapshots,
            personal: personal, onboarding: onboarding, champSelect: champSelect, poster: poster,
            appIsActive: appIsActive)
        champions = ChampionsModel(stats: { snapshots.provider }, gameData: clientData.gameData)
        analysis = AnalysisModel(
            champSelect: champSelect, stats: { snapshots.provider }, tips: { snapshots.tips })
        self.personal = personal
        // Re-detecting after each sync keeps the import's Flash slot current (§21.4).
        profile = ProfileModel(
            connection: lcu,
            store: HistoryNotifyingStore(base: personal) { await onboarding.detectFlash() },
            stats: { snapshots.provider })
        overrides = OverridesModel(store: personal)
        self.lifecycle = lifecycle
        settingsModel = settings
        self.updates = updates(settings)
        self.loginItem = loginItem(settings)
        presence = AppPresenceModel(settings: settings, setPolicy: setActivationPolicy)
    }

    private static func champSelectModel(
        connection: any LCUConnection, clientData: ClientDataModel, settings: SettingsModel,
        snapshots: SnapshotModel, personal: any PersonalStore
    ) -> ChampSelectModel {
        ChampSelectModel(
            connection: connection, settings: { settings.value.champSelect },
            patch: { clientData.patch }, gameData: clientData.gameData,
            stats: { snapshots.provider }, store: personal)
    }

    private static func importModel(
        connection: any LCUConnection, clientData: ClientDataModel, settings: SettingsModel,
        snapshots: SnapshotModel, personal: any PersonalStore, onboarding: OnboardingModel,
        champSelect: ChampSelectModel, poster: any NotificationPosting,
        appIsActive: @escaping @MainActor () -> Bool
    ) -> ImportModel {
        ImportModel(
            connection: connection, catalog: clientData.catalog,
            settings: { settings.value.importing }, stats: { snapshots.provider }, store: personal,
            detectedFlash: {
                switch onboarding.resolvedFlashSlot(.auto) {
                case .d: .d
                case .f: .f
                case nil: nil
                }
            }, scoringRole: { champSelect.scoringRole }, poster: poster, appIsActive: appIsActive)
    }

    /// The client `MitoApp` runs, reading `installPath` on every discovery (§10.1). In Debug,
    /// `-MitoLCULockfilePath <path>` wins: discovery goes only through that lockfile, the one
    /// `tools/lcu-mock` writes (§10.2).
    static func liveClient(
        defaults: UserDefaults = .standard,
        installPath: @escaping @Sendable () async -> String? = { nil }
    ) -> LCUClient {
        lockfileOverride(in: defaults).map(LCUClient.init(lockfilePath:))
            ?? LCUClient(installPath: installPath)
    }

    /// Always `nil` in Release, which never reads the key.
    static func lockfileOverride(in defaults: UserDefaults) -> String? {
        #if DEBUG
            defaults.string(forKey: lockfileOverrideKey)
        #else
            nil
        #endif
    }

    /// Under XCTest the client never runs, so tests never reach a client or the mock.
    static func lifecycle(running client: LCUClient, underTest: Bool) -> @Sendable () async -> Void
    {
        { @Sendable in if !underTest { await client.run() } }
    }

    /// Settings tabs bind here; every write is saved (§21).
    var settings: MitoSettings {
        get { settingsModel.value }
        set { settingsModel.value = newValue }
    }

    /// "Ruta de instalación de LoL" (§21.1): a change while no client is connected searches again
    /// right away; a connected client is kept, and the next search uses the new path.
    var leagueInstallPath: String? {
        get { settings.general.leagueInstallPath }
        set {
            guard newValue != settings.general.leagueInstallPath else { return }
            settings.general.leagueInstallPath = newValue
            if connection.state != .connected { restartLifecycle() }
        }
    }

    /// §22.4: gameflow overrides the connection symbol once it knows the phase.
    var menuBarSymbol: String {
        gameflow.menuBarSymbol ?? connection.menuBarSymbol
    }

    /// §20.1: `true` when champ select should bring the main window up now. The menu-bar label
    /// asks on every change of `champSelectPresence`, since it is the only view always alive.
    func shouldOpenWindowForChampSelect() -> Bool {
        mainWindow.shouldOpen(
            isInChampSelect: champSelect.isInChampSelect, phase: gameflow.state,
            enabled: settings.general.showWindowOnChampSelect)
    }

    var champSelectPresence: ChampSelectPresence {
        ChampSelectPresence(isInChampSelect: champSelect.isInChampSelect, phase: gameflow.state)
    }

    struct ChampSelectPresence: Equatable {
        let isInChampSelect: Bool
        let phase: MitoState
    }

    /// Slots start once the persisted settings are in, so none acts on the defaults.
    func start() async {
        await settingsModel.load()
        updates.start()
        loginItem.refresh()
        presence.applyPolicy()
        await withDiscardingTaskGroup { group in
            group.addTask { await self.runLifecycle() }
            group.addTask { await self.connection.run() }
            group.addTask { await self.clientData.run() }
            group.addTask { await self.icons.run() }
            group.addTask { await self.snapshots.run() }
            group.addTask { await self.gameflow.run() }
            group.addTask { await self.champSelect.run() }
            group.addTask { await self.importing.run() }
            group.addTask { await self.champions.run() }
            group.addTask { await self.profile.run() }
            group.addTask { await self.onboarding.run() }
            group.addTask { await self.overrides.run() }
        }
    }

    /// Reactions that must run with no window and no menu bar icon open: champ select brings the
    /// main window up (§20.1), and a held-back update shows once the game ends (§24). Runs until
    /// cancelled.
    func react() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.openWindowForChampSelect() }
            group.addTask { await self.followGameForUpdates() }
        }
    }

    private func openWindowForChampSelect() async {
        await observeChanges(
            of: { self.champSelectPresence },
            apply: { _ in
                if shouldOpenWindowForChampSelect() { presence.openMainWindow() }
            })
    }

    private func followGameForUpdates() async {
        await observeChanges(
            of: { self.gameflow.state == .inGame }, apply: { updates.isInGame = $0 })
    }

    /// Runs `lifecycle` until it returns on its own or `start()` is cancelled; a restart cancels
    /// the current run and starts a new one, which searches immediately (§10.2).
    private func runLifecycle() async {
        repeat {
            restartsLifecycle = false
            let run = Task { await lifecycle() }
            lifecycleRun = run
            await withTaskCancellationHandler {
                await run.value
            } onCancel: {
                run.cancel()
            }
            lifecycleRun = nil
        } while restartsLifecycle && !Task.isCancelled
    }

    private func restartLifecycle() {
        guard let lifecycleRun else { return }
        restartsLifecycle = true
        lifecycleRun.cancel()
    }
}
