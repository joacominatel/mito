/// A row of `rune_pages` (general or per opponent) or `rune_page_vs_profile`, with its page
/// resolved from `rune_page_defs` (§17).
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

/// A row of `spell_pairs`, general or per opponent (§17).
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

/// A row of `item_builds`, general or per opponent (§17).
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

/// A row of `item_vs_profile` (§17, §18.7): one final item against an enemy profile or the `'any'`
/// baseline. Usage is `games / champ_vs_profile.games`, or `games / champ_role_stats.games` for
/// `'any'`.
public struct FinalItemCandidate: Hashable, Sendable {
    /// `item_id`: a `legendary`, `boots_t2` or `support_upgrade` item.
    public let item: ItemID
    /// Games that ended with the item in the final inventory.
    public let games: Int
    public let wins: Int

    public init(item: ItemID, games: Int, wins: Int) {
        self.item = item
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
