import Foundation
import MitoCore
import ServiceManagement
import os

nonisolated enum LoginItemStatus: Sendable {
    case notRegistered
    case enabled
    /// Registered, but the user has to allow it in System Settings → Login Items.
    case requiresApproval
    case notFound
}

/// `SMAppService.mainApp` in the app; a double in tests.
protocol LoginItemService: AnyObject {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

final class SystemLoginItemService: LoginItemService {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// "Abrir Mito al iniciar sesión" (§21.1). The system owns the real state and the user can change
/// it in System Settings, so the toggle shows what `refresh()` last read, never the saved copy.
@Observable
final class LoginItemModel {
    enum Note: Equatable {
        /// Debug and test builds never register: Debug's own bundle ID would add a dev login item.
        case unavailable
        case requiresApproval
        case failed
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.joacominatel.mito", category: "App")

    @ObservationIgnored private let service: (any LoginItemService)?
    @ObservationIgnored private let settings: SettingsModel
    private(set) var isEnabled = false
    private(set) var note: Note?

    init(service: (any LoginItemService)? = nil, settings: SettingsModel = SettingsModel()) {
        self.service = service
        self.settings = settings
        note = service == nil ? .unavailable : nil
    }

    static func live(
        settings: SettingsModel, underTest: Bool,
        isDebugBuild: Bool = UpdaterConfiguration.isDebugBuild,
        makeService: () -> any LoginItemService = { SystemLoginItemService() }
    ) -> LoginItemModel {
        guard !underTest, !isDebugBuild else { return LoginItemModel(settings: settings) }
        return LoginItemModel(service: makeService(), settings: settings)
    }

    var isAvailable: Bool { service != nil }

    var launchesAtLogin: Bool {
        get { isEnabled }
        set { setEnabled(newValue) }
    }

    /// Reads the system's state and mirrors it into the saved setting.
    func refresh() {
        guard let service else { return }
        let status = service.status
        isEnabled = status == .enabled || status == .requiresApproval
        note = status == .requiresApproval ? .requiresApproval : nil
        if settings.value.general.launchAtLogin != isEnabled {
            settings.value.general.launchAtLogin = isEnabled
        }
    }

    func openSystemSettings() {
        service?.openSystemSettings()
    }

    private func setEnabled(_ enabled: Bool) {
        guard let service else { return }
        refresh()
        guard enabled != isEnabled else { return }
        do {
            if enabled { try service.register() } else { try service.unregister() }
            refresh()
        } catch {
            Self.logger.error(
                "Login item change failed: \(error.localizedDescription, privacy: .public)")
            refresh()
            note = .failed
        }
    }
}
