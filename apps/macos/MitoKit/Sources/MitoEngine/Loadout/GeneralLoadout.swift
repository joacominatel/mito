public import MitoCore

/// The general (`opp_id = 0`) loadout of one (champ, role) and how far each part can be trusted.
public struct GeneralLoadout: Hashable, Sendable {
    public let loadout: Loadout
    public let sampleLevels: LoadoutSampleLevels

    public init(loadout: Loadout, sampleLevels: LoadoutSampleLevels) {
        self.loadout = loadout
        self.sampleLevels = sampleLevels
    }

    static let empty = GeneralLoadout(
        loadout: Loadout(runes: nil, spells: nil, itemSet: nil, skillOrder: nil),
        sampleLevels: LoadoutSampleLevels(
            runes: nil, spells: nil, itemLayers: [:], skillOrder: nil))
}

/// `nil` exactly where the loadout part is `nil`; anything short of `.reliable` is "muestra baja".
public struct LoadoutSampleLevels: Hashable, Sendable {
    public let runes: SampleLevel?
    public let spells: SampleLevel?
    /// One entry per block of the item set.
    public let itemLayers: [BuildLayer: SampleLevel]
    public let skillOrder: SampleLevel?

    public init(
        runes: SampleLevel?, spells: SampleLevel?, itemLayers: [BuildLayer: SampleLevel],
        skillOrder: SampleLevel?
    ) {
        self.runes = runes
        self.spells = spells
        self.itemLayers = itemLayers
        self.skillOrder = skillOrder
    }

    /// The weakest layer of the item set.
    public var itemSet: SampleLevel? { itemLayers.values.min() }
}

/// General loadout selection; the rules per part are in `MITO_CONTEXT.md` §18.6–§18.9.
public enum LoadoutSelection {
    /// Empty without an open snapshot or a `champ_role_stats` row for (`champion`, `role`).
    public static func general(
        for champion: ChampionID, role: Role, stats: some StatsProvider
    ) -> GeneralLoadout {
        guard let meta = stats.meta, let row = stats.championRoleStats(in: role)[champion] else {
            return .empty
        }
        let context = ChoiceContext(
            meta: meta,
            baseline: meta.priors.championRoleWinrate(wins: row.wins, games: row.games),
            isChampionRoleBelowMinimum: meta.sampleLevel(.championRole, games: row.games)
                == .belowMinimum)

        let runes = context.choose(
            stats.runePages(for: champion, role: role).filter { $0.page.perks.count == 9 },
            kind: .runePage, rule: .highestWinrate(minimumUsagePercent: 5, of: row.games))
        let spells = context.choose(
            spellOptions(stats.spellPairs(for: champion, role: role), role: role, row: row),
            kind: .spells, rule: .highestWinrate(minimumUsagePercent: 10, of: row.games))
        let layers = itemLayers(stats.itemBuilds(for: champion, role: role), row: row, context)
        let skillOrder = context.choose(
            stats.skillOrders(for: champion, role: role), kind: .skillOrder,
            rule: .mostPlayedWithGoodWinrate)

        return GeneralLoadout(
            loadout: Loadout(
                runes: runes?.option.page,
                spells: spells.map {
                    SpellPair(first: $0.option.spellA, second: $0.option.spellB)
                },
                itemSet: layers.isEmpty
                    ? nil : ItemSet(blocks: layers.map { block($0.option) }),
                skillOrder: skillOrder?.option.order),
            sampleLevels: LoadoutSampleLevels(
                runes: runes?.level,
                spells: spells?.level,
                itemLayers: Dictionary(
                    uniqueKeysWithValues: layers.map { ($0.option.layer, $0.level) }),
                skillOrder: skillOrder?.level))
    }

    private static let flash = SummonerSpellID(rawValue: 4)
    private static let smite = SummonerSpellID(rawValue: 11)

    /// §18.8: Smite is mandatory in the jungle, and Flash stays unless a pair without it is
    /// dominant (≥ 60 % usage).
    private static func spellOptions(
        _ pairs: [SpellPairCandidate], role: Role, row: ChampionRoleStats
    ) -> [SpellPairCandidate] {
        let pairs = role == .jungle ? pairs.filter { $0.contains(smite) } : pairs
        guard pairs.contains(where: { $0.contains(flash) }) else { return pairs }
        return pairs.filter { $0.contains(flash) || $0.games * 100 >= 60 * row.games }
    }

    /// One choice per layer in `BuildLayer` order; a layer never repeats an earlier layer's item.
    private static func itemLayers(
        _ builds: [ItemBuildCandidate], row: ChampionRoleStats, _ context: ChoiceContext
    ) -> [(option: ItemBuildCandidate, level: SampleLevel)] {
        // §14.12: below the build_layer minimum, core and boots come from final items, which
        // are counted per match.
        let fromFinalItems =
            row.timelineGames < (context.meta.thresholds[.buildLayer]?.minimum ?? 0)
        var taken: Set<ItemID> = []
        var chosen: [(option: ItemBuildCandidate, level: SampleLevel)] = []
        for layer in BuildLayer.allCases {
            let options = builds.filter {
                $0.layer == layer && taken.isDisjoint(with: $0.items)
            }
            let usageGames =
                fromFinalItems && (layer == .core || layer == .boots)
                ? row.games : row.timelineGames
            let rule: ChoiceRule =
                layer == .core
                ? .mostPlayedWithGoodWinrate
                : .highestWinrate(minimumUsagePercent: 10, of: usageGames)
            guard let choice = context.choose(options, kind: .buildLayer, rule: rule) else {
                continue
            }
            taken.formUnion(choice.option.items)
            chosen.append(choice)
        }
        return chosen
    }

    /// Titled with the layer's `item_builds.layer` value; the app supplies the copy.
    private static func block(_ build: ItemBuildCandidate) -> ItemSet.Block {
        var items: [ItemSet.Block.Item] = []
        for id in build.items {
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index] = ItemSet.Block.Item(id: id, count: items[index].count + 1)
            } else {
                items.append(ItemSet.Block.Item(id: id))
            }
        }
        return ItemSet.Block(title: build.layer.rawValue, items: items)
    }
}

extension SpellPairCandidate {
    fileprivate func contains(_ spell: SummonerSpellID) -> Bool {
        spellA == spell || spellB == spell
    }
}
