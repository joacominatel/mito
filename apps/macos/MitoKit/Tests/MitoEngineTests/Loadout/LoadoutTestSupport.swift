import MitoCore
import MitoTestSupport

let ahri = ChampionID(rawValue: 103)

/// `wins = games / 2` keeps `wr_smoothed(champ, role)` at exactly 0.5 with the §17 priors, so a
/// loadout row's smoothed winrate is `(wins + 250) / (games + 500)`.
func evenRow(games: Int = 2_000, timelineGames: Int = 1_000) -> ChampionRoleStats {
    ChampionRoleStats(games: games, wins: games / 2, timelineGames: timelineGames)
}

func provider(
    champion: ChampionID = ahri,
    role: Role = .middle,
    row: ChampionRoleStats? = evenRow(),
    meta: SnapshotMeta? = .example(),
    runes: [RunePageCandidate] = [],
    spells: [SpellPairCandidate] = [],
    items: [ItemBuildCandidate] = [],
    skills: [SkillOrderCandidate] = []
) -> InMemoryStatsProvider {
    InMemoryStatsProvider(
        meta: meta,
        championRoleStatsByRole: row.map { [role: [champion: $0]] } ?? [:],
        runePagesByChampion: [champion: [role: runes]],
        spellPairsByChampion: [champion: [role: spells]],
        itemBuildsByChampion: [champion: [role: items]],
        skillOrdersByChampion: [champion: [role: skills]])
}

/// A Domination/Sorcery page whose keystone tells pages apart.
func runePage(keystone: Int = 8112, perks: [Int]? = nil) -> RunePage {
    RunePage(
        primaryStyle: PerkStyleID(rawValue: 8100),
        subStyle: PerkStyleID(rawValue: 8200),
        perks: (perks ?? [keystone, 8139, 8138, 8135, 8226, 8210, 5008, 5008, 5011])
            .map(PerkID.init(rawValue:)))
}

func page(keystone: Int = 8112, games: Int, wins: Int) -> RunePageCandidate {
    RunePageCandidate(page: runePage(keystone: keystone), games: games, wins: wins)
}

func pair(_ spellA: Int, _ spellB: Int, games: Int, wins: Int) -> SpellPairCandidate {
    SpellPairCandidate(
        spellA: SummonerSpellID(rawValue: spellA), spellB: SummonerSpellID(rawValue: spellB),
        games: games, wins: wins)
}

func build(_ layer: BuildLayer, _ items: [Int], games: Int, wins: Int) -> ItemBuildCandidate {
    ItemBuildCandidate(
        layer: layer, items: items.map(ItemID.init(rawValue:)), games: games, wins: wins)
}

func abilities(_ letters: String) -> [SkillOrder.Ability] {
    letters.compactMap { SkillOrder.Ability(rawValue: String($0)) }
}

func skill(_ maxOrder: String, _ sequence: String = "", games: Int, wins: Int)
    -> SkillOrderCandidate
{
    SkillOrderCandidate(
        order: SkillOrder(maxOrder: abilities(maxOrder), sequence: abilities(sequence)),
        games: games, wins: wins)
}

func spellPair(_ first: Int, _ second: Int) -> SpellPair {
    SpellPair(first: SummonerSpellID(rawValue: first), second: SummonerSpellID(rawValue: second))
}

func item(_ id: Int, count: Int = 1) -> ItemSet.Block.Item {
    ItemSet.Block.Item(id: ItemID(rawValue: id), count: count)
}
