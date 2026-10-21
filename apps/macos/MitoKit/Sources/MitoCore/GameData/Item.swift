public struct Item: Hashable, Sendable {
    public let id: ItemID
    public let name: String
    public let totalGold: Int
    public let iconPath: String
    /// From the snapshot's `item_classes`, not the client; `nil` until a snapshot is joined in.
    public let itemClass: ItemClass?

    public init(id: ItemID, name: String, totalGold: Int, iconPath: String, itemClass: ItemClass?) {
        self.id = id
        self.name = name
        self.totalGold = totalGold
        self.iconPath = iconPath
        self.itemClass = itemClass
    }
}
