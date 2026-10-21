public struct MitoSettings: Codable, Hashable, Sendable {
    public var general: GeneralSettings
    public var game: GameSettings
    public var champSelect: ChampSelectSettings
    public var importing: ImportSettings

    public init(
        general: GeneralSettings = GeneralSettings(),
        game: GameSettings = GameSettings(),
        champSelect: ChampSelectSettings = ChampSelectSettings(),
        importing: ImportSettings = ImportSettings()
    ) {
        self.general = general
        self.game = game
        self.champSelect = champSelect
        self.importing = importing
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        general = container.decode(.general, default: defaults.general)
        game = container.decode(.game, default: defaults.game)
        champSelect = container.decode(.champSelect, default: defaults.champSelect)
        importing = container.decode(.importing, default: defaults.importing)
    }
}
