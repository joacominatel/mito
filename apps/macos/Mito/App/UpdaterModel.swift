import Foundation
import MitoCore
import Observation

/// `SparkleUpdater` in the app; a double in tests.
protocol SoftwareUpdater: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    /// `allowedChannels` is read on every check; `canCheckChanged` reports Sparkle's state.
    func start(
        allowedChannels: @escaping () -> Set<String>,
        canCheckChanged: @escaping @MainActor (Bool) -> Void)
    func checkForUpdates()
    /// Applies a channel change to the next scheduled check without waiting a full cycle.
    func resetUpdateCycle()
}

/// "Buscar actualizaciones…" and the two update toggles (§21.1, §22.4, §24). Without an updater
/// (Debug, not configured yet, under XCTest) it does nothing and never touches the network.
@Observable
final class UpdaterModel {
    @ObservationIgnored private let updater: (any SoftwareUpdater)?
    @ObservationIgnored private let settings: SettingsModel
    /// Sparkle's own answer: `false` until it starts and while a check is in progress.
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var isStarted = false

    init(updater: (any SoftwareUpdater)? = nil, settings: SettingsModel = SettingsModel()) {
        self.updater = updater
        self.settings = settings
    }

    /// The updater runs only when not under test and Info.plist has a real feed and key.
    static func live(
        settings: SettingsModel, underTest: Bool, info: [String: Any]? = Bundle.main.infoDictionary,
        makeUpdater: () -> any SoftwareUpdater = { SparkleUpdater() }
    ) -> UpdaterModel {
        guard !underTest, UpdaterConfiguration.isComplete(info: info) else {
            return UpdaterModel(settings: settings)
        }
        return UpdaterModel(updater: makeUpdater(), settings: settings)
    }

    var isConfigured: Bool { updater != nil }

    var automaticallyChecksForUpdates: Bool {
        get { settings.value.general.automaticallyCheckForUpdates }
        set {
            settings.value.general.automaticallyCheckForUpdates = newValue
            if isStarted { updater?.automaticallyChecksForUpdates = newValue }
        }
    }

    var receivesBetaUpdates: Bool {
        get { settings.value.general.receiveBetaUpdates }
        set {
            settings.value.general.receiveBetaUpdates = newValue
            if isStarted { updater?.resetUpdateCycle() }
        }
    }

    static func allowedChannels(receivingBetas: Bool) -> Set<String> {
        receivingBetas ? ["beta"] : []
    }

    /// Call once the persisted settings are loaded, so Sparkle starts with the user's choice.
    func start() {
        guard let updater, !isStarted else { return }
        isStarted = true
        // Sparkle persists its own copy; writing an unchanged value would still reset its cycle.
        if updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates {
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
        updater.start(
            allowedChannels: { [weak self] in
                Self.allowedChannels(receivingBetas: self?.receivesBetaUpdates ?? false)
            },
            canCheckChanged: { [weak self] in self?.canCheckForUpdates = $0 })
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updater?.checkForUpdates()
    }
}
