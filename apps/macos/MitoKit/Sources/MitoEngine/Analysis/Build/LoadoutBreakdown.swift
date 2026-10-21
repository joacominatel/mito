public import MitoCore

/// One option of a loadout part as the Build tab lists it (§20.2).
public struct LoadoutOptionStats<Value: Hashable & Sendable>: Hashable, Sendable {
    public let value: Value
    public let games: Int
    /// Smoothed toward `wr_smoothed(champ, role)` (§18.1).
    public let winrate: Double
    /// Share of the games of the context the option was chosen in.
    public let usage: Double
    public let level: SampleLevel
}

public struct LoadoutPartOptions<Value: Hashable & Sendable>: Hashable, Sendable {
    public let chosen: LoadoutOptionStats<Value>
    /// From the same context, past its minimum sample; best winrate first, at most two.
    public let alternatives: [LoadoutOptionStats<Value>]
}

/// The stats behind each part a loadout chose, and the alternatives it passed over.
public struct LoadoutBreakdown: Hashable, Sendable {
    public let runes: LoadoutPartOptions<RunePage>?
    public let spells: LoadoutPartOptions<SpellPair>?
    /// One entry per layer block of the item set; the situational block has none.
    public let itemLayers: [BuildLayer: LoadoutPartOptions<[ItemSet.Block.Item]>]
    public let skillOrder: LoadoutPartOptions<SkillOrder>?

    static let empty = LoadoutBreakdown(
        runes: nil, spells: nil, itemLayers: [:], skillOrder: nil)
}

extension LoadoutSelection {
    /// Reads each part's context from `loadout`'s reasons, as `adapted` wrote them: the lane
    /// opponent's rows, the pooled `enemyProfile` rows, or the general rows. A part the loadout
    /// lacks, or that no row of its context holds, has no entry.
    public static func breakdown(
        of loadout: GeneralLoadout, for champion: ChampionID, role: Role,
        enemyProfile: Set<EnemyProfile>, stats: some StatsProvider
    ) -> LoadoutBreakdown {
        guard let meta = stats.meta, let row = stats.championRoleStats(in: role)[champion] else {
            return .empty
        }
        let breakdown = Breakdown(
            champion: champion, role: role, row: row, stats: stats,
            context: ChoiceContext(meta: meta, row: row),
            reasons: loadout.loadout.explanation,
            profiles: enemyProfile.sorted { $0.rawValue < $1.rawValue })
        return LoadoutBreakdown(
            runes: loadout.loadout.runes.flatMap(breakdown.runes),
            spells: loadout.loadout.spells.flatMap(breakdown.spells),
            itemLayers: breakdown.itemLayers(loadout.loadout.itemSet),
            skillOrder: loadout.loadout.skillOrder.flatMap {
                breakdown.options(
                    $0, from: stats.skillOrders(for: champion, role: role),
                    games: row.timelineGames, kind: .skillOrder, value: \.order)
            })
    }
}

private enum PartSource {
    case general
    case opponent(ChampionID, MatchupStats)
    case profile(EnemyProfile)
}

private struct Breakdown<Stats: StatsProvider> {
    let champion: ChampionID
    let role: Role
    let row: ChampionRoleStats
    let stats: Stats
    let context: ChoiceContext
    let reasons: [Reason]
    let profiles: [EnemyProfile]

    func source(of part: LoadoutPart) -> PartSource {
        for reason in reasons {
            switch reason.kind {
            case .adaptedToOpponent(part, let opponent, _):
                if let lane = stats.matchup(for: champion, role: role, against: opponent) {
                    return .opponent(opponent, lane)
                }
            case .adaptedToProfile(part, let profile, _):
                return .profile(profile)
            default:
                continue
            }
        }
        return .general
    }

    func runes(_ page: RunePage) -> LoadoutPartOptions<RunePage>? {
        let pool: (pages: [RunePageCandidate], games: Int) =
            switch source(of: .runes) {
            case .opponent(let opponent, let lane):
                (stats.runePages(for: champion, role: role, against: opponent), lane.games)
            case .profile: pooledProfilePages()
            case .general: (stats.runePages(for: champion, role: role), row.games)
            }
        return options(
            page, from: pool.pages.filter { $0.page.perks.count == 9 }, games: pool.games,
            kind: .runePage, value: \.page)
    }

    /// Pooled as `adapted` pools them (§18.1): games and wins per page over every active profile.
    private func pooledProfilePages() -> (pages: [RunePageCandidate], games: Int) {
        var games = 0
        var pages: [RunePageCandidate] = []
        for profile in profiles {
            guard let profileStats = stats.profileStats(for: champion, role: role, against: profile)
            else { continue }
            games += profileStats.games
            pages += stats.runePages(for: champion, role: role, against: profile)
        }
        let pooled = Dictionary(grouping: pages, by: \.page).map { page, rows in
            RunePageCandidate(
                page: page, games: rows.reduce(0) { $0 + $1.games },
                wins: rows.reduce(0) { $0 + $1.wins })
        }
        return (pooled, games)
    }

    func spells(_ pair: SpellPair) -> LoadoutPartOptions<SpellPair>? {
        let pool: (pairs: [SpellPairCandidate], games: Int) =
            switch source(of: .spells) {
            case .opponent(let opponent, let lane):
                (stats.spellPairs(for: champion, role: role, against: opponent), lane.games)
            case .general, .profile: (stats.spellPairs(for: champion, role: role), row.games)
            }
        return options(
            pair,
            from: LoadoutSelection.spellOptions(pool.pairs, role: role, games: pool.games),
            games: pool.games, kind: .spells,
            value: { SpellPair(first: $0.spellA, second: $0.spellB) })
    }

    func itemLayers(_ itemSet: ItemSet?) -> [BuildLayer: LoadoutPartOptions<[ItemSet.Block.Item]>] {
        var taken: Set<ItemID> = []
        var layers: [BuildLayer: LoadoutPartOptions<[ItemSet.Block.Item]>] = [:]
        for block in itemSet?.blocks ?? [] {
            guard let layer = BuildLayer(rawValue: block.title) else { continue }
            let available = { (builds: [ItemBuildCandidate]) in
                builds.filter { $0.layer == layer && taken.isDisjoint(with: $0.items) }
            }
            let pool: (builds: [ItemBuildCandidate], games: Int, kind: SampleKind)
            switch source(of: .items(layer)) {
            case .opponent(let opponent, let lane):
                pool = (
                    available(stats.itemBuilds(for: champion, role: role, against: opponent)),
                    lane.timelineGames, .buildLayer
                )
            case .profile(let profile):
                // The profile's boots are one final item, with no other boots to compare.
                pool = (
                    stats.finalItems(for: champion, role: role, against: profile)
                        .filter { block.items == [ItemSet.Block.Item(id: $0.item)] }
                        .map {
                            ItemBuildCandidate(
                                layer: layer, items: [$0.item], games: $0.games, wins: $0.wins)
                        },
                    stats.profileStats(for: champion, role: role, against: profile)?.games ?? 0,
                    .itemVsProfile
                )
            case .general:
                pool = (
                    available(stats.itemBuilds(for: champion, role: role)),
                    generalUsageGames(layer),
                    .buildLayer
                )
            }
            taken.formUnion(block.items.map(\.id))
            layers[layer] = options(
                block.items, from: pool.builds, games: pool.games, kind: pool.kind,
                value: { LoadoutSelection.block($0).items })
        }
        return layers
    }

    /// The denominator `generalLayer` uses (§14.12).
    private func generalUsageGames(_ layer: BuildLayer) -> Int {
        let fromFinalItems =
            row.timelineGames < (context.meta.thresholds[.buildLayer]?.minimum ?? 0)
        return fromFinalItems && (layer == .core || layer == .boots)
            ? row.games : row.timelineGames
    }

    func options<Option: LoadoutOption, Value: Hashable & Sendable>(
        _ chosen: Value, from candidates: [Option], games: Int, kind: SampleKind,
        value: (Option) -> Value
    ) -> LoadoutPartOptions<Value>? {
        guard let pick = candidates.first(where: { value($0) == chosen }) else { return nil }
        let minimum = context.meta.thresholds[kind]?.minimum ?? 0
        func stats(_ option: Option) -> LoadoutOptionStats<Value> {
            LoadoutOptionStats(
                value: value(option), games: option.games,
                winrate: context.winrate(wins: option.wins, games: option.games),
                usage: games > 0 ? min(Double(option.games) / Double(games), 1) : 0,
                level: context.level(kind, games: option.games))
        }
        let alternatives = candidates.filter { value($0) != chosen && $0.games >= minimum }
            .map(stats)
            .sorted { ($0.winrate, $0.games) > ($1.winrate, $1.games) }
        return LoadoutPartOptions(chosen: stats(pick), alternatives: Array(alternatives.prefix(2)))
    }
}
