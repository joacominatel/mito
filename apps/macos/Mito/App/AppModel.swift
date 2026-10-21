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
    let gameflow: GameflowModel
    let champSelect: ChampSelectModel
    let importing: ImportModel
    let champions: ChampionsModel
    let analysis: AnalysisModel
    let profile: ProfileModel
    let onboarding: OnboardingModel
    let overrides: OverridesModel
    var settings: MitoSettings

    #if DEBUG
        /// Set with `-MitoLCULockfilePath <path>` to point discovery at `tools/lcu-mock`.
        let lockfileOverridePath: String?
    #endif

    init(
        connection lcu: any LCUConnection,
        settings: MitoSettings = MitoSettings(),
        defaults: UserDefaults = .standard
    ) {
        connection = ConnectionModel(connection: lcu)
        gameflow = GameflowModel(connection: lcu)
        champSelect = ChampSelectModel(connection: lcu)
        importing = ImportModel(connection: lcu)
        champions = ChampionsModel()
        analysis = AnalysisModel()
        profile = ProfileModel(connection: lcu)
        onboarding = OnboardingModel(connection: lcu)
        overrides = OverridesModel()
        self.settings = settings
        #if DEBUG
            lockfileOverridePath = defaults.string(forKey: Self.lockfileOverrideKey)
        #endif
    }

    /// §22.4: gameflow overrides the connection symbol once it knows the phase.
    var menuBarSymbol: String {
        gameflow.menuBarSymbol ?? connection.menuBarSymbol
    }

    func start() async {
        await withDiscardingTaskGroup { group in
            group.addTask { await self.connection.run() }
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
