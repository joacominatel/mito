import Foundation
import MitoCore
import MitoImport

/// Why the editor cannot save yet.
enum OverrideIssue: Equatable {
    case incompleteRunePage
    case invalidRunePage(RunePageValidationError)
    case incompleteSpells
    case emptyItemSet
}

/// A `ChampionOverride` being edited. Fixed values are kept while their mode is not fixed, so
/// switching modes back and forth loses nothing; only the fixed mode requires them.
struct OverrideDraft: Equatable {
    let champion: ChampionID
    let role: Role
    var runeMode: ChampionOverride.RuneMode
    var runes: RunePageDraft
    var spellMode: ChampionOverride.SpellMode
    var spells: SpellDraft
    var itemMode: ChampionOverride.ItemMode
    var items: ItemSetDraft
    var isFavorite: Bool
    var isExcludedFromPool: Bool

    init(_ override: ChampionOverride, styles: [PerkStyle]) {
        champion = override.champion
        role = override.role
        runeMode = override.runeMode
        runes = override.fixedPage.map { RunePageDraft($0, styles: styles) } ?? RunePageDraft()
        spellMode = override.spellMode
        spells = SpellDraft(override.fixedSpells)
        itemMode = override.itemMode
        items = ItemSetDraft(override.fixedItems)
        isFavorite = override.isFavorite
        isExcludedFromPool = override.isExcludedFromPool
    }

    func issues(styles: [PerkStyle]) -> [OverrideIssue] {
        var issues: [OverrideIssue] = []
        if runeMode == .fixed {
            if let page = runes.page {
                if let error = page.validationError(against: styles) {
                    issues.append(.invalidRunePage(error))
                }
            } else {
                issues.append(.incompleteRunePage)
            }
        }
        if spellMode == .fixed, spells.pair == nil { issues.append(.incompleteSpells) }
        if itemMode == .fixedSet, items.itemSet == nil { issues.append(.emptyItemSet) }
        return issues
    }

    /// `nil` while there are issues. A page that does not validate is never stored.
    func override(styles: [PerkStyle]) -> ChampionOverride? {
        guard issues(styles: styles).isEmpty else { return nil }
        let page = runes.page.flatMap { $0.validationError(against: styles) == nil ? $0 : nil }
        return ChampionOverride(
            champion: champion, role: role, runeMode: runeMode, fixedPage: page,
            spellMode: spellMode, fixedSpells: spells.pair, itemMode: itemMode,
            fixedItems: items.itemSet, isFavorite: isFavorite,
            isExcludedFromPool: isExcludedFromPool)
    }
}

struct SpellDraft: Equatable {
    var first: SummonerSpellID?
    var second: SummonerSpellID?

    init(_ pair: SpellPair?) {
        first = pair?.first
        second = pair?.second
    }

    /// Two different spells, or `nil`.
    var pair: SpellPair? {
        guard let first, let second, first != second else { return nil }
        return SpellPair(first: first, second: second)
    }
}

struct ItemSetDraft: Equatable {
    struct Block: Equatable, Identifiable {
        let id = UUID()
        var title: String
        var items: [ItemSet.Block.Item]
    }

    private(set) var blocks: [Block]

    init(_ set: ItemSet?) {
        blocks = set?.blocks.map { Block(title: $0.title, items: $0.items) } ?? []
    }

    /// `nil` when no block holds an item: an empty set would import nothing.
    var itemSet: ItemSet? {
        guard blocks.contains(where: { !$0.items.isEmpty }) else { return nil }
        return ItemSet(blocks: blocks.map { ItemSet.Block(title: $0.title, items: $0.items) })
    }

    mutating func addBlock(title: String) {
        blocks.append(Block(title: title, items: []))
    }

    mutating func removeBlock(_ id: Block.ID) {
        blocks.removeAll { $0.id == id }
    }

    mutating func setTitle(_ title: String, of id: Block.ID) {
        update(id) { $0.title = title }
    }

    /// Adding an item already in the block raises its count.
    mutating func add(_ item: ItemID, to id: Block.ID) {
        update(id) { block in
            if let index = block.items.firstIndex(where: { $0.id == item }) {
                block.items[index] = ItemSet.Block.Item(
                    id: item, count: block.items[index].count + 1)
            } else {
                block.items.append(ItemSet.Block.Item(id: item))
            }
        }
    }

    /// A count under 1 removes the item.
    mutating func setCount(_ count: Int, of item: ItemID, in id: Block.ID) {
        update(id) { block in
            guard let index = block.items.firstIndex(where: { $0.id == item }) else { return }
            if count < 1 {
                block.items.remove(at: index)
            } else {
                block.items[index] = ItemSet.Block.Item(id: item, count: count)
            }
        }
    }

    private mutating func update(_ id: Block.ID, _ change: (inout Block) -> Void) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        change(&blocks[index])
    }
}
