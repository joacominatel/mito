import LCUKit
import Observation

/// The main window's sidebar selection, and when champ select brings the window up (§20.1).
@Observable
final class MainWindowModel {
    var destination: SidebarDestination? = .now

    @ObservationIgnored private var isArmed = true

    /// Call on every change of either input; `true` means open the window now. Fires once per
    /// champ select: a draft that drops and returns while the phase is still champ select does
    /// not reopen it, and neither does turning `enabled` on midway.
    func shouldOpen(isInChampSelect: Bool, phase: MitoState, enabled: Bool) -> Bool {
        guard isInChampSelect else {
            if phase != .champSelect { isArmed = true }
            return false
        }
        guard isArmed else { return false }
        isArmed = false
        guard enabled else { return false }
        destination = .now
        return true
    }
}
