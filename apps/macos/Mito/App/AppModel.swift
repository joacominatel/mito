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
    /// The one personal database; features that read or write it get it in their `init`.
    let personal: any PersonalStore

    private let lifecycle: @Sendable () async -> Void

    init(
        connection lcu: any LCUConnection,
        lifecycle: @escaping @Sendable () async -> Void = {},
        settings: SettingsModel = SettingsModel(),
        snapshots: SnapshotModel = SnapshotModel(),
        personal: any PersonalStore = UnavailablePersonalStore(),
        poster: any NotificationPosting = SystemNotificationPoster(),
        appIsActive: @escaping @MainActor () -> Bool = { NSApplication.shared.isActive }
    ) {
        connection = ConnectionModel(connection: lcu)
        let clientData = ClientDataModel(connection: lcu)
        self.clientData = clientData
        self.snapshots = snapshots
        gameflow = GameflowModel(
            connection: lcu, settings: { settings.value.game }, poster: poster)
        let champSelect = ChampSelectModel(
            connection: lcu, settings: { settings.value.champSelect },
            patch: { clientData.patch }, gameData: clientData.gameData,
            stats: { snapshots.provider }, store: personal)
        self.champSelect = champSelect
        let onboarding = OnboardingModel(store: personal, gameData: clientData.gameData)
        self.onboarding = onboarding
        importing = ImportModel(
            connection: lcu, catalog: clientData.catalog, settings: { settings.value.importing },
            stats: { snapshots.provider }, store: personal,
            detectedFlash: {
                switch onboarding.resolvedFlashSlot(.auto) {
                case .d: .d
                case .f: .f
                case nil: nil
                }
            }, scoringRole: { champSelect.scoringRole }, poster: poster, appIsActive: appIsActive)
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
    }

    /// The client `MitoApp` runs. In Debug, `-MitoLCULockfilePath <path>` makes it discover only
    /// through that lockfile, the one `tools/lcu-mock` writes (§10.2).
    static func liveClient(defaults: UserDefaults = .standard) -> LCUClient {
        lockfileOverride(in: defaults).map(LCUClient.init(lockfilePath:)) ?? LCUClient()
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
        await withDiscardingTaskGroup { group in
            group.addTask { await self.lifecycle() }
            group.addTask { await self.connection.run() }
            group.addTask { await self.clientData.run() }
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
}
