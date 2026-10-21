public struct RunePage: Hashable, Sendable {
    public let primaryStyle: PerkStyleID
    public let subStyle: PerkStyleID
    /// LCU order: keystone + 3 primary, 2 secondary, then the offense, flex and defense shards.
    public let perks: [PerkID]

    public init(primaryStyle: PerkStyleID, subStyle: PerkStyleID, perks: [PerkID]) {
        self.primaryStyle = primaryStyle
        self.subStyle = subStyle
        self.perks = perks
    }
}
