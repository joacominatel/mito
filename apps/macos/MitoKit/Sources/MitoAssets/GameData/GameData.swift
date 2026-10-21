public import MitoCore

/// One load of the client's static data. When an ID repeats, the first entry wins.
public struct GameData: Hashable, Sendable {
    /// In client order.
    public let perkStyles: [PerkStyle]
    private let champions: [ChampionID: Champion]
    private let items: [ItemID: Item]
    private let perks: [PerkID: Perk]
    private let stylesByID: [PerkStyleID: PerkStyle]
    private let spells: [SummonerSpellID: SummonerSpell]

    public init(
        champions: [Champion] = [],
        items: [Item] = [],
        perkStyles: [PerkStyle] = [],
        perks: [Perk] = [],
        spells: [SummonerSpell] = []
    ) {
        self.perkStyles = perkStyles
        self.champions = Self.index(champions, by: \.id)
        self.items = Self.index(items, by: \.id)
        self.perks = Self.index(perks, by: \.id)
        stylesByID = Self.index(perkStyles, by: \.id)
        self.spells = Self.index(spells, by: \.id)
    }

    public func champion(_ id: ChampionID) -> Champion? { champions[id] }
    public func item(_ id: ItemID) -> Item? { items[id] }
    public func perk(_ id: PerkID) -> Perk? { perks[id] }
    public func perkStyle(_ id: PerkStyleID) -> PerkStyle? { stylesByID[id] }
    public func spell(_ id: SummonerSpellID) -> SummonerSpell? { spells[id] }

    private static func index<ID: Hashable, Value>(_ values: [Value], by id: KeyPath<Value, ID>)
        -> [ID: Value]
    {
        Dictionary(values.map { ($0[keyPath: id], $0) }, uniquingKeysWith: { first, _ in first })
    }
}
