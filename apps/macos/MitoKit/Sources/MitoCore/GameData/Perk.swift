public struct Perk: Hashable, Sendable {
    public let id: PerkID
    public let name: String
    public let iconPath: String

    public init(id: PerkID, name: String, iconPath: String) {
        self.id = id
        self.name = name
        self.iconPath = iconPath
    }
}
