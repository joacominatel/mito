import Foundation
import Sparkle

/// The only file that imports Sparkle. `UpdaterModel` creates it only when the build is
/// configured, so an unconfigured build never instantiates Sparkle.
final class SparkleUpdater: SoftwareUpdater {
    private let delegate = Delegate()
    private let controller: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?

    init() {
        // Sparkle holds its delegates weakly; `delegate` keeps this one alive.
        controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: delegate, userDriverDelegate: delegate)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func start(_ hooks: UpdaterHooks) {
        delegate.hooks = hooks
        // Sparkle changes this property on the main thread.
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial])
        { updater, _ in
            MainActor.assumeIsolated { hooks.canCheckChanged(updater.canCheckForUpdates) }
        }
        controller.startUpdater()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func resetUpdateCycle() {
        controller.updater.resetUpdateCycleAfterShortDelay()
    }

    private final class Delegate: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
        var hooks: UpdaterHooks?

        func allowedChannels(for updater: SPUUpdater) -> Set<String> {
            hooks?.allowedChannels() ?? []
        }

        /// A menu-bar app: scheduled update alerts open behind the active app instead of taking
        /// focus (Sparkle's gentle reminders).
        nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

        func standardUserDriverShouldHandleShowingScheduledUpdate(
            _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
        ) -> Bool {
            hooks?.showsScheduledUpdateNow() ?? true
        }

        func standardUserDriverWillHandleShowingUpdate(
            _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
            state: SPUUserUpdateState
        ) {
            if !handleShowingUpdate { hooks?.scheduledUpdateDeferred() }
        }

        func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
            hooks?.updateHandled()
        }

        func standardUserDriverWillFinishUpdateSession() {
            hooks?.updateHandled()
        }
    }
}
