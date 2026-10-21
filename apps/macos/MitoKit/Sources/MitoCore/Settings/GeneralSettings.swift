/// `MITO_CONTEXT.md` §21.1.
public struct GeneralSettings: Codable, Hashable, Sendable {
    public enum Language: String, Codable, Hashable, Sendable {
        case system
        case spanish = "es-AR"
        case english = "en"
    }

    public enum DiamondPlusData: String, Codable, Hashable, Sendable {
        /// On when the user's own rank is Diamond or above.
        case auto
        case on
        case off
    }

    public var launchAtLogin: Bool
    public var showWindowOnChampSelect: Bool
    public var showMenuBarIcon: Bool
    public var showDockIcon: Bool
    public var language: Language
    /// `nil` means auto-detect.
    public var leagueInstallPath: String?
    public var diamondPlusData: DiamondPlusData
    public var automaticallyCheckForUpdates: Bool
    /// Adds Sparkle's `beta` channel to the default one.
    public var receiveBetaUpdates: Bool

    public init(
        launchAtLogin: Bool = false,
        showWindowOnChampSelect: Bool = true,
        showMenuBarIcon: Bool = true,
        showDockIcon: Bool = false,
        language: Language = .system,
        leagueInstallPath: String? = nil,
        diamondPlusData: DiamondPlusData = .auto,
        automaticallyCheckForUpdates: Bool = true,
        receiveBetaUpdates: Bool = false
    ) {
        self.launchAtLogin = launchAtLogin
        self.showWindowOnChampSelect = showWindowOnChampSelect
        self.showMenuBarIcon = showMenuBarIcon
        self.showDockIcon = showDockIcon
        self.language = language
        self.leagueInstallPath = leagueInstallPath
        self.diamondPlusData = diamondPlusData
        self.automaticallyCheckForUpdates = automaticallyCheckForUpdates
        self.receiveBetaUpdates = receiveBetaUpdates
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        launchAtLogin = container.decode(.launchAtLogin, default: defaults.launchAtLogin)
        showWindowOnChampSelect = container.decode(
            .showWindowOnChampSelect, default: defaults.showWindowOnChampSelect)
        showMenuBarIcon = container.decode(.showMenuBarIcon, default: defaults.showMenuBarIcon)
        showDockIcon = container.decode(.showDockIcon, default: defaults.showDockIcon)
        language = container.decode(.language, default: defaults.language)
        leagueInstallPath = container.decode(
            .leagueInstallPath, default: defaults.leagueInstallPath)
        diamondPlusData = container.decode(.diamondPlusData, default: defaults.diamondPlusData)
        automaticallyCheckForUpdates = container.decode(
            .automaticallyCheckForUpdates, default: defaults.automaticallyCheckForUpdates)
        receiveBetaUpdates = container.decode(
            .receiveBetaUpdates, default: defaults.receiveBetaUpdates)
    }
}
