public struct Loadout: Hashable, Sendable {
    public let runes: RunePage?
    public let spells: SpellPair?
    public let itemSet: ItemSet?
    public let skillOrder: SkillOrder?
    /// Why each part was chosen (§13.5, §18.6–§18.9); empty when nothing explains it.
    public let explanation: [Reason]

    public init(
        runes: RunePage?, spells: SpellPair?, itemSet: ItemSet?, skillOrder: SkillOrder?,
        explanation: [Reason] = []
    ) {
        self.runes = runes
        self.spells = spells
        self.itemSet = itemSet
        self.skillOrder = skillOrder
        self.explanation = explanation
    }
}
