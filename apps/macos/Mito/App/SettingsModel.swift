import MitoCore
import MitoStore
import Observation

/// `SettingsStore` in the app; a fake in tests.
nonisolated protocol SettingsPersistence: Sendable {
    func load() async -> MitoSettings
    func save(_ settings: MitoSettings) async throws(StoreError)
}

extension SettingsStore: SettingsPersistence {}

/// The live `MitoSettings`, loaded once at start and saved after every change (§21).
@Observable
final class SettingsModel {
    var value: MitoSettings {
        didSet { scheduleSave() }
    }

    @ObservationIgnored private let persistence: (any SettingsPersistence)?
    @ObservationIgnored private let saveDelay: Duration
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private(set) var pendingSave: Task<Void, Never>?

    /// Without `persistence` (previews, tests) nothing is loaded or saved.
    init(
        value: MitoSettings = MitoSettings(),
        persistence: (any SettingsPersistence)? = nil,
        saveDelay: Duration = .milliseconds(300)
    ) {
        self.value = value
        self.persistence = persistence
        self.saveDelay = saveDelay
    }

    /// Changes made before loading finishes are replaced by the persisted value, never saved.
    func load() async {
        guard let persistence else { return }
        value = await persistence.load()
        isLoaded = true
    }

    private func scheduleSave() {
        guard isLoaded, let persistence else { return }
        pendingSave?.cancel()
        let snapshot = value
        let delay = saveDelay
        pendingSave = Task {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            // SettingsStore logs the failure without the contents; memory keeps the user's value.
            try? await persistence.save(snapshot)
        }
    }
}
