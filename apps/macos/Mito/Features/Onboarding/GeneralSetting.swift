import Foundation

/// The §21.1 rows of Settings → General, and which of them do something yet.
enum GeneralSetting: CaseIterable {
    case launchAtLogin
    case showWindowOnChampSelect
    case showMenuBarIcon
    case showDockIcon
    case language
    case leagueInstallPath
    case diamondPlusData

    var title: LocalizedStringResource {
        switch self {
        case .launchAtLogin:
            LocalizedStringResource("Abrir Mito al iniciar sesión", table: "Onboarding")
        case .showWindowOnChampSelect:
            LocalizedStringResource(
                "Mostrar ventana al entrar en champ select", table: "Onboarding")
        case .showMenuBarIcon:
            LocalizedStringResource("Ícono en la barra de menú", table: "Onboarding")
        case .showDockIcon: LocalizedStringResource("Ícono en el Dock", table: "Onboarding")
        case .language: LocalizedStringResource("Idioma", table: "Onboarding")
        case .leagueInstallPath:
            LocalizedStringResource("Ruta de instalación de LoL", table: "Onboarding")
        case .diamondPlusData: LocalizedStringResource("Datos Diamante+", table: "Onboarding")
        }
    }

    /// Only es-AR copy exists, and the diamond_plus bracket is not published yet.
    var takesEffect: Bool {
        switch self {
        case .language, .diamondPlusData: false
        default: true
        }
    }

    /// Names exactly the settings that are saved but do nothing yet.
    static let pendingFooter = LocalizedStringResource(
        "«Idioma» y «Datos Diamante+» todavía no tienen efecto: por ahora Mito está solo en español y usa solo datos Esmeralda+.",
        table: "Onboarding")
}
