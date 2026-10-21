public import MitoCore

extension LoadoutSelection {
    /// The loadout adapted to the draft (§18.6–§18.8); `enemies` are the locked enemies whose
    /// `champion_flags` the flag rules count. With nothing to adapt to, it equals `general`.
    public static func adapted(
        for champion: ChampionID,
        role: Role,
        opponent: ChampionID?,
        enemyProfile: Set<EnemyProfile>,
        enemies: [ChampionID],
        stats: some StatsProvider
    ) -> GeneralLoadout {
        guard let meta = stats.meta, let row = stats.championRoleStats(in: role)[champion] else {
            return .empty
        }
        let selection = AdaptedSelection(
            champion: champion, role: role, row: row, stats: stats,
            context: ChoiceContext(meta: meta, row: row),
            lane: opponent.flatMap { opponent in
                stats.matchup(for: champion, role: role, against: opponent).map {
                    Lane(opponent: opponent, stats: $0)
                }
            },
            profiles: enemyProfile.sorted { $0.rawValue < $1.rawValue }, enemies: enemies)

        let runes = selection.runes()
        let spells = selection.spells()
        let items = selection.items()
        let skillOrder = selection.context.choose(
            stats.skillOrders(for: champion, role: role), kind: .skillOrder,
            rule: .mostPlayedWithGoodWinrate)

        var blocks = items.layers.map { block($0.option) }
        if !items.situational.isEmpty {
            blocks.append(
                ItemSet.Block(
                    title: situationalBlockTitle,
                    items: items.situational.map { ItemSet.Block.Item(id: $0) }))
        }
        return GeneralLoadout(
            loadout: Loadout(
                runes: runes?.option.page,
                spells: spells.map { SpellPair(first: $0.option.spellA, second: $0.option.spellB) },
                itemSet: blocks.isEmpty ? nil : ItemSet(blocks: blocks),
                skillOrder: skillOrder?.option.order,
                explanation: (runes?.reasons ?? []) + (spells?.reasons ?? []) + items.reasons),
            sampleLevels: LoadoutSampleLevels(
                runes: runes?.level,
                spells: spells?.level,
                itemLayers: Dictionary(
                    uniqueKeysWithValues: items.layers.map { ($0.option.layer, $0.level) }),
                skillOrder: skillOrder?.level))
    }

    /// The last block: flag counters, then situational items. The app supplies the copy.
    public static let situationalBlockTitle = "situational"
}

private struct Lane {
    let opponent: ChampionID
    /// The denominator of every per-opponent layer.
    let stats: MatchupStats
}

private struct PartChoice<Option> {
    let option: Option
    let level: SampleLevel
    let reasons: [Reason]
}

/// An `item_vs_profile` row whose buy rate and winrate rise against `profile` (§18.7).
private struct ProfileSignal {
    let item: ItemID
    let profile: EnemyProfile
    let games: Int
    let wins: Int
    let buyRate: Double
    let baselineBuyRate: Double
    let winrateDelta: Double
    let level: SampleLevel

    var lift: Double { baselineBuyRate > 0 ? buyRate / baselineBuyRate : .infinity }
}

private struct AdaptedSelection<Stats: StatsProvider> {
    let champion: ChampionID
    let role: Role
    let row: ChampionRoleStats
    let stats: Stats
    let context: ChoiceContext
    let lane: Lane?
    /// Sorted by raw value, so ties and reasons never depend on set order.
    let profiles: [EnemyProfile]
    let enemies: [ChampionID]

    // MARK: Runes (§18.6)

    func runes() -> PartChoice<RunePageCandidate>? {
        if let lane,
            let choice = context.choose(
                complete(stats.runePages(for: champion, role: role, against: lane.opponent)),
                kind: .runePage,
                rule: .highestWinrate(minimumUsagePercent: 5, of: lane.stats.games),
                fallsBackToMostPlayed: false)
        {
            return PartChoice(
                option: choice.option, level: choice.level,
                reasons: [
                    Reason(
                        kind: .adaptedToOpponent(
                            part: .runes, opponent: lane.opponent, games: choice.option.games),
                        sample: choice.level)
                ])
        }
        if let choice = profileRunes() { return choice }
        return context.choose(
            complete(stats.runePages(for: champion, role: role)), kind: .runePage,
            rule: .highestWinrate(minimumUsagePercent: 5, of: row.games)
        ).map { PartChoice(option: $0.option, level: $0.level, reasons: []) }
    }

    /// Active profiles are pooled by sample (§18.1): games and wins per page, over the sum of
    /// their `champ_vs_profile` games.
    private func profileRunes() -> PartChoice<RunePageCandidate>? {
        var contextGames = 0
        var rows: [(profile: EnemyProfile, pages: [RunePageCandidate])] = []
        for profile in profiles {
            guard let profileStats = stats.profileStats(for: champion, role: role, against: profile)
            else { continue }
            contextGames += profileStats.games
            rows.append(
                (profile, complete(stats.runePages(for: champion, role: role, against: profile))))
        }
        let pooled = Dictionary(grouping: rows.flatMap(\.pages), by: \.page).map { page, rows in
            RunePageCandidate(
                page: page, games: rows.reduce(0) { $0 + $1.games },
                wins: rows.reduce(0) { $0 + $1.wins })
        }
        guard
            let choice = context.choose(
                pooled, kind: .runePage,
                rule: .highestWinrate(minimumUsagePercent: 5, of: contextGames),
                fallsBackToMostPlayed: false)
        else { return nil }

        let reasons = rows.compactMap { profile, pages in
            pages.first { $0.page == choice.option.page }.map {
                Reason(
                    kind: .adaptedToProfile(part: .runes, profile: profile, games: $0.games),
                    sample: context.level(.runePage, games: $0.games))
            }
        }
        return PartChoice(option: choice.option, level: choice.level, reasons: reasons)
    }

    private func complete(_ pages: [RunePageCandidate]) -> [RunePageCandidate] {
        pages.filter { $0.page.perks.count == 9 }
    }

    // MARK: Spells (§18.8)

    func spells() -> PartChoice<SpellPairCandidate>? {
        if let lane,
            let choice = context.choose(
                LoadoutSelection.spellOptions(
                    stats.spellPairs(for: champion, role: role, against: lane.opponent),
                    role: role, games: lane.stats.games),
                kind: .spells, rule: .highestWinrate(minimumUsagePercent: 10, of: lane.stats.games),
                fallsBackToMostPlayed: false)
        {
            return PartChoice(
                option: choice.option, level: choice.level,
                reasons: [
                    Reason(
                        kind: .adaptedToOpponent(
                            part: .spells, opponent: lane.opponent, games: choice.option.games),
                        sample: choice.level)
                ])
        }
        return context.choose(
            LoadoutSelection.spellOptions(
                stats.spellPairs(for: champion, role: role), role: role, games: row.games),
            kind: .spells, rule: .highestWinrate(minimumUsagePercent: 10, of: row.games)
        ).map { PartChoice(option: $0.option, level: $0.level, reasons: []) }
    }

    // MARK: Items (§18.7)

    func items() -> (
        layers: [(option: ItemBuildCandidate, level: SampleLevel)], situational: [ItemID],
        reasons: [Reason]
    ) {
        let signals = profileSignals()
        let general = stats.itemBuilds(for: champion, role: role)
        let opponentBuilds = lane.map {
            stats.itemBuilds(for: champion, role: role, against: $0.opponent)
        }
        var taken: Set<ItemID> = []
        var layers: [(option: ItemBuildCandidate, level: SampleLevel)] = []
        var reasons: [Reason] = []

        for layer in BuildLayer.allCases {
            let choice: (option: ItemBuildCandidate, level: SampleLevel)?
            if let lane, let opponentBuilds,
                let opponentChoice = context.choose(
                    opponentBuilds.filter { $0.layer == layer && taken.isDisjoint(with: $0.items) },
                    kind: .buildLayer,
                    rule: LoadoutSelection.layerRule(layer, usageGames: lane.stats.timelineGames),
                    fallsBackToMostPlayed: false)
            {
                choice = opponentChoice
                reasons.append(
                    Reason(
                        kind: .adaptedToOpponent(
                            part: .items(layer), opponent: lane.opponent,
                            games: opponentChoice.option.games),
                        sample: opponentChoice.level))
            } else if layer == .boots,
                let boots = signals.first(where: {
                    ItemFallbacks.tierTwoBoots.contains($0.item) && !taken.contains($0.item)
                })
            {
                choice = (
                    ItemBuildCandidate(
                        layer: .boots, items: [boots.item], games: boots.games, wins: boots.wins),
                    boots.level
                )
                reasons.append(
                    Reason(
                        kind: .adaptedToProfile(
                            part: .items(.boots), profile: boots.profile, games: boots.games),
                        sample: boots.level))
            } else {
                choice = LoadoutSelection.generalLayer(
                    layer, from: general, excluding: taken, row: row, context)
            }
            guard let choice else { continue }
            taken.formUnion(choice.option.items)
            layers.append(choice)
        }

        var situational: [ItemID] = []
        for counter in flagCounters(excluding: taken) {
            situational.append(counter.item)
            taken.insert(counter.item)
            reasons.append(
                Reason(
                    kind: .countersFlag(
                        item: counter.item, flag: counter.flag, enemies: counter.enemies),
                    sample: nil))
        }
        for signal in signals
        where !ItemFallbacks.tierTwoBoots.contains(signal.item) && !taken.contains(signal.item) {
            situational.append(signal.item)
            taken.insert(signal.item)
            reasons.append(
                Reason(
                    kind: .situationalItem(
                        item: signal.item, profile: signal.profile, buyRate: signal.buyRate,
                        baselineBuyRate: signal.baselineBuyRate,
                        winrateDelta: signal.winrateDelta),
                    sample: signal.level))
        }
        return (layers, situational, reasons)
    }

    /// Strongest lift first; the cutoffs are in `MITO_CONTEXT.md` §18.7.
    private func profileSignals() -> [ProfileSignal] {
        let minimum = context.meta.thresholds[.itemVsProfile]?.minimum ?? 0
        let baseline = Dictionary(
            stats.finalItems(for: champion, role: role).map { ($0.item, $0) },
            uniquingKeysWith: { first, _ in first })
        var signals: [ProfileSignal] = []
        for profile in profiles {
            guard
                let profileGames = stats.profileStats(
                    for: champion, role: role, against: profile)?.games, profileGames > 0
            else { continue }
            for item in stats.finalItems(for: champion, role: role, against: profile)
            where item.games >= minimum {
                let baselineGames = baseline[item.item]?.games ?? 0
                let delta =
                    context.winrate(wins: item.wins, games: item.games)
                    - context.winrate(wins: baseline[item.item]?.wins ?? 0, games: baselineGames)
                // Integer cross-products keep the 10 % and 1.5× cutoffs exact.
                guard item.games * 100 >= 10 * profileGames,
                    2 * item.games * row.games >= 3 * baselineGames * profileGames,
                    delta > 0
                else { continue }
                signals.append(
                    ProfileSignal(
                        item: item.item, profile: profile, games: item.games, wins: item.wins,
                        buyRate: Double(item.games) / Double(profileGames),
                        baselineBuyRate: row.games > 0
                            ? Double(baselineGames) / Double(row.games) : 0,
                        winrateDelta: delta,
                        level: context.level(.itemVsProfile, games: item.games)))
            }
        }
        return signals.sorted {
            if $0.lift != $1.lift { return $0.lift > $1.lift }
            if $0.winrateDelta != $1.winrateDelta { return $0.winrateDelta > $1.winrateDelta }
            if $0.item != $1.item { return $0.item.rawValue < $1.item.rawValue }
            return $0.profile.rawValue < $1.profile.rawValue
        }
    }

    /// A rule fires with 2+ flagged enemies and none of its items built yet; its item is the one
    /// this champion finishes most often in the `'any'` baseline, from the minimum.
    private func flagCounters(excluding taken: Set<ItemID>) -> [(
        item: ItemID, flag: ChampionFlag, enemies: Int
    )] {
        let minimum = context.meta.thresholds[.itemVsProfile]?.minimum ?? 0
        let finalItems = stats.finalItems(for: champion, role: role)
        return ItemFallbacks.flagRules.compactMap { flag, items in
            let count = enemies.filter { stats.flags(of: $0).contains(flag) }.count
            guard count >= 2, taken.isDisjoint(with: items),
                let best = finalItems.filter({ items.contains($0.item) && $0.games >= minimum })
                    .max(by: {
                        ($0.games, $1.item.rawValue) < ($1.games, $0.item.rawValue)
                    })
            else { return nil }
            return (best.item, flag, count)
        }
    }
}

/// `item_classes` (§16.3) is in the snapshot but not in `StatsProvider`; swap these for it then.
enum ItemFallbacks {
    /// Berserker's, Swiftness, Sorcerer's, Plated Steelcaps, Mercury's, Mobility, Lucidity.
    static let tierTwoBoots: Set<ItemID> = Set(
        [3006, 3009, 3020, 3047, 3111, 3117, 3158].map(ItemID.init(rawValue:)))

    /// Mortal Reminder, Thornmail, Morellonomicon, Chempunk Chainsword.
    static let antiheal: Set<ItemID> = Set([3033, 3075, 3165, 6609].map(ItemID.init(rawValue:)))

    static let banshee: Set<ItemID> = [ItemID(rawValue: 3102)]

    static let flagRules: [(flag: ChampionFlag, items: Set<ItemID>)] = [
        (.highHeal, antiheal), (.pointClickCC, banshee),
    ]
}
