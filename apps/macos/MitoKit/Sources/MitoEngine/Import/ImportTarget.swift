public import MitoCore

/// A part the importer sends; the skill order is not one (§13.1).
public enum ImportPart: CaseIterable, Hashable, Sendable {
    case runes
    case spells
    case items
}

/// Where a part's choice came from, when it was not the engine's loadout alone.
public enum ImportOrigin: Hashable, Sendable {
    /// The override's fixed page, spells, or set, or its "no importar".
    case override
    /// A fixed choice was asked for but none is saved: the general one went instead.
    case noFixedChoice
}

/// The override's choices over the adapted loadout, with the settings' toggles (§13.1, §21.5).
public struct ImportPlan: Hashable, Sendable {
    public var loadout: Loadout
    public var origins: [ImportPart: ImportOrigin]
    /// Parts sent from the general loadout instead of the adapted one.
    public var general: Set<ImportPart>
    /// The override's "no importar": no item set is sent, and the old Mito set stays.
    public var skipsItems: Bool

    public init(
        loadout: Loadout, origins: [ImportPart: ImportOrigin] = [:], general: Set<ImportPart> = [],
        skipsItems: Bool = false
    ) {
        self.loadout = loadout
        self.origins = origins
        self.general = general
        self.skipsItems = skipsItems
    }

    /// No runes, spells, or item set to send.
    public var isEmpty: Bool {
        loadout.runes == nil && loadout.spells == nil && loadout.itemSet == nil
    }
}

/// What the importer sends for one champion, and what the Build tab shows of it (§13.1, §20.2).
public struct ImportTarget: Hashable, Sendable {
    public struct LaneOpponent: Hashable, Sendable {
        public let champion: ChampionID
        /// Inferred among the enemies without a client role (§12.3): a guess, never a fact.
        public let isInferred: Bool

        public init(champion: ChampionID, isInferred: Bool) {
            self.champion = champion
            self.isInferred = isInferred
        }
    }

    /// `nil` in ARAM.
    public let role: Role?
    public let opponent: LaneOpponent?
    public let enemyProfile: Set<EnemyProfile>
    public let override: ChampionOverride?
    /// Empty in ARAM, which has no stats (§20.3).
    public let general: GeneralLoadout
    public let adapted: GeneralLoadout
    public let plan: ImportPlan

    /// At least even odds, so a coin-toss guess never picks the matchup (§12.3).
    public static let minimumLaneOdds = 0.5

    /// `role` is the champ-select selector's (§20.3); without one, the most played role. ARAM
    /// ignores it and sends only fixed choices. `nil` when no role has data.
    public static func decide(
        for champion: ChampionID, queue: QueueType, role: Role?, enemies: [DraftSlot],
        stats: some StatsProvider, overrides: [ChampionOverride], settings: ImportSettings
    ) -> ImportTarget? {
        let mine = overrides.filter { $0.champion == champion }
        if queue == .aram { return aram(mine, settings: settings) }
        guard let role = role ?? mostPlayedRole(of: champion, in: stats) else { return nil }
        let opponent = laneOpponent(among: enemies, in: role, stats: stats)
        let profile = Composition.enemyProfile(
            of: Composition.teamProfile(
                of: Composition.members(of: enemies, stats: stats), stats: stats),
            rules: stats.meta?.profileRules)
        let general = LoadoutSelection.general(for: champion, role: role, stats: stats)
        let adapted = LoadoutSelection.adapted(
            for: champion, role: role, opponent: opponent?.champion, enemyProfile: profile,
            enemies: enemies.compactMap(\.champion), stats: stats)
        let override = mine.first { $0.role == role }
        return ImportTarget(
            role: role, opponent: opponent, enemyProfile: profile, override: override,
            general: general, adapted: adapted,
            plan: plan(
                general: general.loadout, adapted: adapted.loadout, override: override,
                settings: settings))
    }

    /// ARAM has no role: the first of the champion's overrides, in `Role` order, whose plan sends
    /// a fixed choice. An empty plan without one.
    private static func aram(_ overrides: [ChampionOverride], settings: ImportSettings)
        -> ImportTarget
    {
        let nothing = Loadout(runes: nil, spells: nil, itemSet: nil, skillOrder: nil)
        let fixed = Role.allCases.lazy.compactMap { role -> (ChampionOverride, ImportPlan)? in
            guard let override = overrides.first(where: { $0.role == role }) else { return nil }
            var plan = plan(
                general: nothing, adapted: nothing, override: override, settings: settings)
            // Without stats there is no general part to fall back to.
            plan.general = []
            plan.origins = plan.origins.filter { $0.value == .override }
            return plan.isEmpty ? nil : (override, plan)
        }.first
        return ImportTarget(
            role: nil, opponent: nil, enemyProfile: [], override: fixed?.0, general: .empty,
            adapted: .empty, plan: fixed?.1 ?? ImportPlan(loadout: nothing))
    }

    /// Ties go to the earlier role in `Role.allCases`.
    public static func mostPlayedRole(of champion: ChampionID, in stats: some StatsProvider)
        -> Role?
    {
        let games = stats.roleGames(for: champion)
        return Role.allCases.filter { games[$0, default: 0] > 0 }
            .max { games[$0, default: 0] < games[$1, default: 0] }
    }

    /// The enemy assigned to `role` or, among the locked enemies without a role, the likeliest one
    /// in it, from `minimumLaneOdds` up (§12.3).
    public static func laneOpponent(
        among enemies: [DraftSlot], in role: Role, stats: some StatsProvider
    ) -> LaneOpponent? {
        if let assigned = enemies.first(where: { $0.role == role && $0.champion != nil })?
            .champion
        {
            return LaneOpponent(champion: assigned, isInferred: false)
        }
        let inferred = RoleInference.infer(
            enemies: enemies.filter { $0.role == nil }.compactMap(\.champion),
            takenRoles: Set(enemies.compactMap(\.role)), stats: stats)
        guard
            let likeliest = inferred.max(by: {
                $0.roleProbabilities[role, default: 0] < $1.roleProbabilities[role, default: 0]
            }), likeliest.roleProbabilities[role, default: 0] >= minimumLaneOdds
        else { return nil }
        return LaneOpponent(champion: likeliest.champion, isInferred: true)
    }

    /// The override's modes over the adapted loadout (§13.1, §21.5); a fixed mode with nothing
    /// saved sends the general part. A part switched off in Settings is left alone.
    public static func plan(
        general: Loadout, adapted: Loadout, override: ChampionOverride?, settings: ImportSettings
    ) -> ImportPlan {
        var runes = adapted.runes
        var spells = adapted.spells
        var itemSet = adapted.itemSet
        var plan = ImportPlan(loadout: adapted)

        func useGeneral(_ part: ImportPart, saying origin: ImportOrigin? = nil) {
            plan.general.insert(part)
            plan.origins[part] = origin
            switch part {
            case .runes: runes = general.runes
            case .spells: spells = general.spells
            case .items: itemSet = general.itemSet
            }
        }

        if settings.importRunes {
            // `.adaptive` is the editor's default, "sin preferencia": the global mode decides.
            let mode: ImportSettings.RuneMode =
                switch override?.runeMode {
                case .fixed?: .fixedPerChampion
                case .general?: .general
                case .adaptive?, .unknown?, nil: settings.runeMode
                }
            switch mode {
            case .fixedPerChampion:
                if let page = override?.fixedPage {
                    runes = page
                    plan.origins[.runes] = .override
                } else {
                    useGeneral(.runes, saying: .noFixedChoice)
                }
            case .general: useGeneral(.runes)
            case .adaptive: break
            }
        }

        if settings.importSpells, override?.spellMode == .fixed {
            if let pair = override?.fixedSpells {
                spells = pair
                plan.origins[.spells] = .override
            } else {
                useGeneral(.spells, saying: .noFixedChoice)
            }
        }

        if settings.importItemSets, let override {
            switch override.itemMode {
            case .fixedSet:
                if let set = override.fixedItems {
                    itemSet = set
                    plan.origins[.items] = .override
                } else {
                    useGeneral(.items, saying: .noFixedChoice)
                }
            case .skip:
                itemSet = nil
                plan.skipsItems = true
                plan.origins[.items] = .override
            case .recommended, .unknown:
                break
            }
        }

        plan.loadout = Loadout(
            runes: runes, spells: spells, itemSet: itemSet, skillOrder: adapted.skillOrder)
        return plan
    }
}
