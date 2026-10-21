public struct Champion: Hashable, Sendable {
    public let id: ChampionID
    /// The locale-independent key, e.g. `Ahri`.
    public let alias: String
    /// In the client's locale.
    public let name: String
    public let iconPath: String

    public init(id: ChampionID, alias: String, name: String, iconPath: String) {
        self.id = id
        self.alias = alias
        self.name = name
        self.iconPath = iconPath
    }
}
