public struct SummonerSpell: Hashable, Sendable {
    public let id: SummonerSpellID
    public let name: String
    public let iconPath: String
    /// Client game mode keys, e.g. `CLASSIC`, `ARAM`.
    public let gameModes: Set<String>

    public init(id: SummonerSpellID, name: String, iconPath: String, gameModes: Set<String>) {
        self.id = id
        self.name = name
        self.iconPath = iconPath
        self.gameModes = gameModes
    }
}
