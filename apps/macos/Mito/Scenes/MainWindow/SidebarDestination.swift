import Foundation

/// The §22.2 sidebar, in order.
enum SidebarDestination: CaseIterable, Hashable {
    case now
    case champions
    case profile
    case overrides

    var title: LocalizedStringResource {
        switch self {
        case .now: LocalizedStringResource("Ahora", table: "Shell")
        case .champions: LocalizedStringResource("Campeones", table: "Shell")
        case .profile: LocalizedStringResource("Mi perfil", table: "Shell")
        case .overrides: LocalizedStringResource("Overrides", table: "Shell")
        }
    }

    var systemImage: String {
        switch self {
        case .now: "bolt"
        case .champions: "person.3"
        case .profile: "person.crop.circle"
        case .overrides: "slider.horizontal.3"
        }
    }
}
