import AppKit
import MitoCore
import Observation

/// The menu bar icon, the Dock icon and the activation policy (§21.1, §24). The app always stays
/// reachable: with the menu bar icon off, the Dock icon is on.
@Observable
final class AppPresenceModel {
    enum Window: Hashable {
        case main
        case settings
    }

    @ObservationIgnored private let settings: SettingsModel
    @ObservationIgnored private let setPolicy: (NSApplication.ActivationPolicy) -> Void
    @ObservationIgnored private var appliedPolicy: NSApplication.ActivationPolicy?
    private var openWindows: Set<Window> = []
    /// Set by the first view that can open the main window; the menu bar icon stays until then,
    /// so a launch with it off still gets one.
    private(set) var mainWindowOpener: (() -> Void)?

    init(
        settings: SettingsModel = SettingsModel(),
        setPolicy: @escaping (NSApplication.ActivationPolicy) -> Void = { _ in }
    ) {
        self.settings = settings
        self.setPolicy = setPolicy
    }

    /// Under XCTest the real policy is never touched.
    static func livePolicySetter(underTest: Bool) -> (NSApplication.ActivationPolicy) -> Void {
        underTest ? { _ in } : { _ = NSApplication.shared.setActivationPolicy($0) }
    }

    var showsMenuBarIcon: Bool {
        get { settings.value.general.showMenuBarIcon }
        set {
            settings.value.general.showMenuBarIcon = newValue
            if !newValue { settings.value.general.showDockIcon = true }
            applyPolicy()
        }
    }

    /// Always on while the menu bar icon is off, whatever the saved value says.
    var showsDockIcon: Bool {
        get { settings.value.general.showDockIcon || !showsMenuBarIcon }
        set {
            guard newValue || showsMenuBarIcon else { return }
            settings.value.general.showDockIcon = newValue
            applyPolicy()
        }
    }

    var canHideDockIcon: Bool { showsMenuBarIcon }

    /// `MenuBarExtra(isInserted:)`. The system may set it to `false` when the user drags the
    /// icon out of the menu bar.
    var isMenuBarExtraInserted: Bool {
        get { showsMenuBarIcon || mainWindowOpener == nil }
        set { showsMenuBarIcon = newValue }
    }

    var policy: NSApplication.ActivationPolicy {
        showsDockIcon || !openWindows.isEmpty ? .regular : .accessory
    }

    func windowOpened(_ window: Window) {
        openWindows.insert(window)
        applyPolicy()
    }

    func windowClosed(_ window: Window) {
        openWindows.remove(window)
        applyPolicy()
    }

    func setMainWindowOpener(_ open: @escaping () -> Void) {
        guard mainWindowOpener == nil else { return }
        mainWindowOpener = open
    }

    func openMainWindow() {
        mainWindowOpener?()
    }

    /// Hands the policy to AppKit only when it changes.
    func applyPolicy() {
        let policy = policy
        guard policy != appliedPolicy else { return }
        appliedPolicy = policy
        setPolicy(policy)
    }
}
