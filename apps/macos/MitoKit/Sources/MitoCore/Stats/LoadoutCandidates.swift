/// A general (`opp_id = 0`) row of `rune_pages`, with its page resolved from `rune_page_defs`.
public struct RunePageCandidate: Hashable, Sendable {
    public let page: RunePage
    /// Games played with this page.
    public let games: Int
    public let wins: Int

    public init(page: RunePage, games: Int, wins: Int) {
        self.page = page
        self.games = games
        self.wins = wins
    }
}

/// A general (`opp_id = 0`) row of `spell_pairs`.
public struct SpellPairCandidate: Hashable, Sendable {
    /// Normalized so `spellA < spellB`; slot order is the engine's call.
    public let spellA: SummonerSpellID
    public let spellB: SummonerSpellID
    /// Games played with this pair.
    public let games: Int
    public let wins: Int

    public init(spellA: SummonerSpellID, spellB: SummonerSpellID, games: Int, wins: Int) {
        self.spellA = spellA
        self.spellB = spellB
        self.games = games
        self.wins = wins
    }
}

/// A general (`opp_id = 0`) row of `item_builds`.
public struct ItemBuildCandidate: Hashable, Sendable {
    public let layer: BuildLayer
    /// Empty slots dropped: `start` sorted by id with repeats, `core` in purchase order, one
    /// item otherwise.
    public let items: [ItemID]
    /// Games that built this option for this layer.
    public let games: Int
    public let wins: Int

    public init(layer: BuildLayer, items: [ItemID], games: Int, wins: Int) {
        self.layer = layer
        self.items = items
        self.games = games
        self.wins = wins
    }
}

/// Raw values are the `item_builds.layer` encoding (§17).
public enum BuildLayer: String, CaseIterable, Hashable, Sendable {
    case start
    case core
    case boots
    case fourth
    case fifth
    case sixth
}

/// A row of `skill_orders`; the table is general only.
public struct SkillOrderCandidate: Hashable, Sendable {
    /// The max order and the most common full sequence for it.
    public let order: SkillOrder
    /// Games that maxed abilities in this order.
    public let games: Int
    public let wins: Int

    public init(order: SkillOrder, games: Int, wins: Int) {
        self.order = order
        self.games = games
        self.wins = wins
    }
}
