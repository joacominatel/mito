public struct PerkStyle: Hashable, Sendable {
    public struct Slot: Hashable, Sendable {
        /// Every style carries the shard rows too, so a page takes its shards from the primary.
        public enum Kind: Hashable, Sendable {
            case keystone
            /// Selectable from the primary or as the secondary style.
            case regular
            case statMod
            case unknown(String)
        }

        public let kind: Kind
        public let perks: [PerkID]

        public init(kind: Kind, perks: [PerkID]) {
            self.kind = kind
            self.perks = perks
        }
    }

    public let id: PerkStyleID
    public let name: String
    public let iconPath: String
    /// In client order: keystone, regular rows, then shard rows.
    public let slots: [Slot]

    public init(id: PerkStyleID, name: String, iconPath: String, slots: [Slot]) {
        self.id = id
        self.name = name
        self.iconPath = iconPath
        self.slots = slots
    }
}
