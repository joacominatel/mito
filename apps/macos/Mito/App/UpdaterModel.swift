import Foundation
import MitoCore
import Observation

/// What `UpdaterModel` hands Sparkle when it starts.
struct UpdaterHooks {
    /// Read on every check.
    let allowedChannels: () -> Set<String>
    /// Sparkle's own answer: `false` until it starts and while a check is in progress.
    let canCheckChanged: @MainActor (Bool) -> Void
    /// Read before a scheduled check's alert; `false` keeps it from showing now. Never asked for a
    /// user-initiated check.
    let showsScheduledUpdateNow: () -> Bool
    /// A scheduled update was found and held back: Mito has to bring it up later.
    let scheduledUpdateDeferred: () -> Void
    /// The user looked at the update, or its session ended.
    let updateHandled: () -> Void
}

/// `SparkleUpdater` in the app; a double in tests.
protocol SoftwareUpdater: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    func start(_ hooks: UpdaterHooks)
    /// Also brings a held-back update up in focus.
    func checkForUpdates()
    /// Applies a channel change to the next scheduled check without waiting a full cycle.
    func resetUpdateCycle()
}

/// "Buscar actualizaciones…" and the two update toggles (§21.1, §22.4, §24). Without an updater
/// (Debug, not configured yet, under XCTest) it does nothing and never touches the network.
/// A scheduled update found during a game waits until the game ends (§24).
@Observable
final class UpdaterModel {
    @ObservationIgnored private let updater: (any SoftwareUpdater)?
    @ObservationIgnored private let settings: SettingsModel
    /// Sparkle's own answer: `false` until it starts and while a check is in progress.
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private(set) var hasDeferredUpdate = false

    /// `AppModel` keeps it in step with the gameflow phase.
    @ObservationIgnored var isInGame = false {
        didSet {
            guard !isInGame, hasDeferredUpdate else { return }
            hasDeferredUpdate = false
            updater?.checkForUpdates()
        }
    }

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
            UpdaterHooks(
                allowedChannels: { [weak self] in
                    Self.allowedChannels(receivingBetas: self?.receivesBetaUpdates ?? false)
                },
                canCheckChanged: { [weak self] in self?.canCheckForUpdates = $0 },
                showsScheduledUpdateNow: { [weak self] in !(self?.isInGame ?? false) },
                scheduledUpdateDeferred: { [weak self] in self?.hasDeferredUpdate = true },
                updateHandled: { [weak self] in self?.hasDeferredUpdate = false }))
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        updater?.checkForUpdates()
    }
}
