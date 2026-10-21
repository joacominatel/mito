import Foundation
import LCUKit
import MitoCore
import Observation

/// One slot per feature (ADR 0007). Each feature model subscribes to its own LCU topics in
/// `run()`; there is no central event loop.
@Observable
final class AppModel {
    static let lockfileOverrideKey = "MitoLCULockfilePath"

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

    #if DEBUG
        /// Set with `-MitoLCULockfilePath <path>` to point discovery at `tools/lcu-mock`.
        let lockfileOverridePath: String?
    #endif

    init(
        connection lcu: any LCUConnection,
        lifecycle: @escaping @Sendable () async -> Void = {},
        settings: SettingsModel = SettingsModel(),
        snapshots: SnapshotModel = SnapshotModel(),
        personal: any PersonalStore = UnavailablePersonalStore(),
        defaults: UserDefaults = .standard
    ) {
        connection = ConnectionModel(connection: lcu)
        let clientData = ClientDataModel(connection: lcu)
        self.clientData = clientData
        self.snapshots = snapshots
        gameflow = GameflowModel(connection: lcu, settings: { settings.value.game })
        champSelect = ChampSelectModel(
            connection: lcu, settings: { settings.value.champSelect },
            patch: { clientData.patch }, gameData: clientData.gameData)
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
            })
        champions = ChampionsModel(stats: { snapshots.provider }, gameData: clientData.gameData)
        analysis = AnalysisModel()
        self.personal = personal
        // Re-detecting after each sync keeps the import's Flash slot current (§21.4).
        profile = ProfileModel(
            connection: lcu,
            store: HistoryNotifyingStore(base: personal) { await onboarding.detectFlash() },
            stats: { snapshots.provider })
        overrides = OverridesModel(store: personal)
        self.lifecycle = lifecycle
        settingsModel = settings
        #if DEBUG
            lockfileOverridePath = defaults.string(forKey: Self.lockfileOverrideKey)
        #endif
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
            group.addTask { await self.analysis.run() }
            group.addTask { await self.profile.run() }
            group.addTask { await self.onboarding.run() }
            group.addTask { await self.overrides.run() }
        }
    }
}
