public struct Loadout: Hashable, Sendable {
    public let runes: RunePage?
    public let spells: SpellPair?
    public let itemSet: ItemSet?
    public let skillOrder: SkillOrder?

    public init(runes: RunePage?, spells: SpellPair?, itemSet: ItemSet?, skillOrder: SkillOrder?) {
        self.runes = runes
        self.spells = spells
        self.itemSet = itemSet
        self.skillOrder = skillOrder
    }
}
