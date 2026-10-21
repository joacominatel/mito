import MitoCore

/// Import tests seed these instead of the snapshot fixture, so each contrast they rely on stays far from a tie.
nonisolated struct ImportStats: StatsProvider {
    private struct Key: Hashable {
        let champion: ChampionID
        let role: Role
    }

    let meta: SnapshotMeta? = SnapshotMeta(
        patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420), bracket: .emeraldPlus,
        matches: 20_000, blendPatches: [Patch(rawValue: "16.21")],
        thresholds: [
            .championRole: SampleThreshold(minimum: 200, reliable: 1000),
            .matchup: SampleThreshold(minimum: 30, reliable: 300),
            .synergy: SampleThreshold(minimum: 50, reliable: 400),
            .vsTeam: SampleThreshold(minimum: 30, reliable: 300),
            .profile: SampleThreshold(minimum: 100, reliable: 500),
            .runePage: SampleThreshold(minimum: 100, reliable: 800),
            .buildLayer: SampleThreshold(minimum: 100, reliable: 600),
            .itemVsProfile: SampleThreshold(minimum: 50, reliable: 300),
            .spells: SampleThreshold(minimum: 100, reliable: 500),
            .skillOrder: SampleThreshold(minimum: 100, reliable: 600),
        ],
        priors: SmoothingPriors(
            championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
            loadoutStrength: 500),
        tierCutoffs: [.s: 0.53, .a: 0.515, .b: 0.5, .c: 0.485],
        profileRules: ProfileRules(
            minimumChampions: 3, heavyADPhysicalShare: 0.65, heavyAPMagicShare: 0.6,
            heavyCCScore: 0.6, mixedExcludes: [.heavyAD, .heavyAP]))

    private static let zed = ChampionID(rawValue: 238)
    private static let ahriID = ChampionID(rawValue: 103)
    private static let ahri = Key(champion: ahriID, role: .middle)
    private static let zedMiddle = Key(champion: zed, role: .middle)
    private static let zedJungle = Key(champion: zed, role: .jungle)

    static let electrocute = RunePage(
        primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8300),
        perks: [8112, 8143, 8140, 8135, 8345, 8347, 5008, 5008, 5011].map(PerkID.init(rawValue:)))
    static let phaseRush = RunePage(
        primaryStyle: PerkStyleID(rawValue: 8200), subStyle: PerkStyleID(rawValue: 8300),
        perks: [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011].map(PerkID.init(rawValue:)))

    private static let roleGames: [ChampionID: [Role: Int]] = [
        ahriID: [.middle: 2824],
        zed: [.jungle: 2746, .middle: 2195],
        ChampionID(rawValue: 122): [.top: 3378, .jungle: 25],
        ChampionID(rawValue: 16): [.utility: 3068],
        ChampionID(rawValue: 64): [.jungle: 3600],
        ChampionID(rawValue: 22): [.bottom: 3344],
        ChampionID(rawValue: 86): [.top: 2053],
        ChampionID(rawValue: 222): [.bottom: 3388],
    ]

    // Every row sits at a smoothed 0.5, so a loadout's winrate is (wins + 250) / (games + 500).
    private static let rows: [Key: ChampionRoleStats] = [
        ahri: ChampionRoleStats(games: 2824, wins: 1412, timelineGames: 700),
        zedMiddle: ChampionRoleStats(games: 2195, wins: 1098, timelineGames: 600),
        zedJungle: ChampionRoleStats(games: 2746, wins: 1373, timelineGames: 40),
    ]

    // Equal damage, so a team's shares are plain means: physical ≥ 0.65 is heavy_ad, CC ≥ 0.6 heavy_cc.
    private static let profiles: [Key: ChampionProfile] = [
        ahri: profile(physical: 0.1, cc: 0.333),
        zedMiddle: profile(physical: 0.6, cc: 0.667),
        zedJungle: profile(physical: 0.8, cc: 0),
        Key(champion: ChampionID(rawValue: 122), role: .top): profile(physical: 0.8, cc: 1),
        Key(champion: ChampionID(rawValue: 16), role: .utility): profile(physical: 0.1, cc: 0),
        Key(champion: ChampionID(rawValue: 64), role: .jungle): profile(physical: 0.8, cc: 0.5),
        Key(champion: ChampionID(rawValue: 22), role: .bottom): profile(physical: 0.8, cc: 1),
        Key(champion: ChampionID(rawValue: 86), role: .top): profile(physical: 0.8, cc: 0),
        Key(champion: ChampionID(rawValue: 222), role: .bottom): profile(physical: 0.8, cc: 0),
    ]

    private static let generalPages: [Key: [RunePageCandidate]] = [
        ahri: [
            RunePageCandidate(page: electrocute, games: 2000, wins: 1100),
            RunePageCandidate(page: phaseRush, games: 800, wins: 360),
        ],
        zedMiddle: [
            RunePageCandidate(page: electrocute, games: 1500, wins: 800),
            RunePageCandidate(page: phaseRush, games: 600, wins: 270),
        ],
        zedJungle: [
            RunePageCandidate(page: phaseRush, games: 2059, wins: 950),
            RunePageCandidate(page: electrocute, games: 687, wins: 360),
        ],
    ]

    private static let generalSpells: [Key: [SpellPairCandidate]] = [
        ahri: [pair(4, 14, games: 2400, wins: 1300), pair(4, 12, games: 400, wins: 180)],
        zedMiddle: [pair(4, 12, games: 1500, wins: 800), pair(4, 14, games: 600, wins: 270)],
        zedJungle: [pair(4, 11, games: 2746, wins: 1373)],
    ]

    private static let generalBuilds: [Key: [ItemBuildCandidate]] = [
        ahri: [
            build(.start, [1056, 2003, 2003], games: 400, wins: 210),
            build(.core, [6655, 3157, 3089], games: 300, wins: 160),
            build(.boots, [3020], games: 500, wins: 260),
            build(.fourth, [3031], games: 300, wins: 150),
            build(.fifth, [3033], games: 400, wins: 220),
            build(.sixth, [3046], games: 300, wins: 160),
        ],
        zedMiddle: [
            build(.start, [1055, 2003], games: 400, wins: 200),
            build(.core, [3142, 6692, 3071], games: 300, wins: 160),
            build(.boots, [3158], games: 300, wins: 150),
        ],
        zedJungle: [
            build(.start, [1101], games: 26, wins: 14),
            build(.core, [3142, 6692, 3071], games: 1332, wins: 700),
            build(.boots, [3158], games: 658, wins: 330),
        ],
    ]

    private static let skillOrders: [Key: [SkillOrderCandidate]] = [
        ahri: [skill("QWE", "QWEQQRQQWWRWWEEREE", games: 700, wins: 360)],
        zedMiddle: [skill("QEW", "QEWQQRQQEEREEWWRWW", games: 600, wins: 310)],
        zedJungle: [skill("QEW", "QEWQQRQQEEREEWWRWW", games: 40, wins: 20)],
    ]

    private static let matchups: [Key: [ChampionID: MatchupStats]] = [
        ahri: [
            zed: MatchupStats(
                games: 500, wins: 260, timelineGames: 120, goldDiffAt15: 100, csDiffAt15: 5)
        ],
        zedMiddle: [
            ahriID: MatchupStats(
                games: 500, wins: 240, timelineGames: 120, goldDiffAt15: -100, csDiffAt15: -5)
        ],
    ]

    private static let opponentPages: [Key: [ChampionID: [RunePageCandidate]]] = [
        ahri: [
            zed: [
                RunePageCandidate(page: electrocute, games: 200, wins: 80),
                RunePageCandidate(page: phaseRush, games: 200, wins: 120),
            ]
        ],
        zedMiddle: [ahriID: [RunePageCandidate(page: phaseRush, games: 200, wins: 110)]],
    ]

    private static let opponentSpells: [Key: [ChampionID: [SpellPairCandidate]]] = [
        ahri: [zed: [pair(4, 14, games: 300, wins: 160)]],
        zedMiddle: [ahriID: [pair(4, 14, games: 300, wins: 160)]],
    ]

    private static let opponentBuilds: [Key: [ChampionID: [ItemBuildCandidate]]] = [
        ahri: [
            zed: [
                build(.start, [1056, 2003, 2003], games: 115, wins: 60),
                build(.core, [6655, 3157, 3089], games: 110, wins: 55),
                build(.boots, [3111], games: 107, wins: 60),
            ]
        ]
    ]

    private static let profileStats: [Key: [EnemyProfile: RelationStats]] = [
        ahri: [
            .heavyAD: RelationStats(games: 800, wins: 400),
            .heavyCC: RelationStats(games: 800, wins: 400),
            .mixed: RelationStats(games: 800, wins: 400),
        ]
    ]

    private static let profilePages: [Key: [EnemyProfile: [RunePageCandidate]]] = [
        ahri: [
            .heavyAD: [
                RunePageCandidate(page: electrocute, games: 500, wins: 300),
                RunePageCandidate(page: phaseRush, games: 200, wins: 100),
            ],
            .heavyCC: [
                RunePageCandidate(page: electrocute, games: 300, wins: 120),
                RunePageCandidate(page: phaseRush, games: 400, wins: 280),
            ],
            .mixed: [
                RunePageCandidate(page: electrocute, games: 300, wins: 120),
                RunePageCandidate(page: phaseRush, games: 400, wins: 280),
            ],
        ]
    ]

    private static let baselineItems: [Key: [FinalItemCandidate]] = [
        ahri: [
            final(3020, games: 2000, wins: 1000), final(3033, games: 400, wins: 220),
            final(3047, games: 350, wins: 175),
        ],
        zedMiddle: [final(3033, games: 200, wins: 100)],
    ]

    private static let profileItems: [Key: [EnemyProfile: [FinalItemCandidate]]] = [
        ahri: [.heavyAD: [final(3047, games: 300, wins: 170)]]
    ]

    private static let flags: [ChampionID: Set<ChampionFlag>] = [
        ChampionID(rawValue: 122): [.highHeal],
        ChampionID(rawValue: 16): [.highHeal],
    ]

    private static let tierTwoBoots = Set(
        [3006, 3020, 3047, 3111, 3158].map(ItemID.init(rawValue:)))
    private static let antiheal = Set([3033, 3075, 3165].map(ItemID.init(rawValue:)))

    func roleGames(for champion: ChampionID) -> [Role: Int] { Self.roleGames[champion] ?? [:] }

    func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
        Dictionary(
            uniqueKeysWithValues: Self.rows.filter { $0.key.role == role }.map {
                ($0.key.champion, $0.value)
            })
    }

    func runePages(for champion: ChampionID, role: Role) -> [RunePageCandidate] {
        Self.generalPages[Key(champion: champion, role: role)] ?? []
    }

    func spellPairs(for champion: ChampionID, role: Role) -> [SpellPairCandidate] {
        Self.generalSpells[Key(champion: champion, role: role)] ?? []
    }

    func itemBuilds(for champion: ChampionID, role: Role) -> [ItemBuildCandidate] {
        Self.generalBuilds[Key(champion: champion, role: role)] ?? []
    }

    func skillOrders(for champion: ChampionID, role: Role) -> [SkillOrderCandidate] {
        Self.skillOrders[Key(champion: champion, role: role)] ?? []
    }

    func matchup(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> MatchupStats?
    {
        Self.matchups[Key(champion: champion, role: role)]?[opponent]
    }

    func championProfile(for champion: ChampionID, role: Role) -> ChampionProfile? {
        Self.profiles[Key(champion: champion, role: role)]
    }

    func profileStats(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> RelationStats?
    {
        Self.profileStats[Key(champion: champion, role: role)]?[profile]
    }

    func runePages(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [RunePageCandidate]
    {
        Self.opponentPages[Key(champion: champion, role: role)]?[opponent] ?? []
    }

    func spellPairs(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [SpellPairCandidate]
    {
        Self.opponentSpells[Key(champion: champion, role: role)]?[opponent] ?? []
    }

    func itemBuilds(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [ItemBuildCandidate]
    {
        Self.opponentBuilds[Key(champion: champion, role: role)]?[opponent] ?? []
    }

    func runePages(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> [RunePageCandidate]
    {
        Self.profilePages[Key(champion: champion, role: role)]?[profile] ?? []
    }

    func finalItems(for champion: ChampionID, role: Role) -> [FinalItemCandidate] {
        Self.baselineItems[Key(champion: champion, role: role)] ?? []
    }

    func finalItems(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> [FinalItemCandidate]
    {
        Self.profileItems[Key(champion: champion, role: role)]?[profile] ?? []
    }

    func flags(of champion: ChampionID) -> Set<ChampionFlag> { Self.flags[champion] ?? [] }

    func itemClass(of item: ItemID) -> ItemClass? {
        if Self.tierTwoBoots.contains(item) { return .bootsT2 }
        return Self.antiheal.contains(item) ? .legendary : nil
    }

    func isAntiheal(_ item: ItemID) -> Bool { Self.antiheal.contains(item) }

    private static func profile(physical: Double, cc: Double) -> ChampionProfile {
        ChampionProfile(
            physicalShare: physical, magicShare: 0.95 - physical, trueShare: 0.05,
            damagePerMinute: 500, tankiness: 0.5, ccScore: cc, timelineGames: 500)
    }

    private static func pair(_ spellA: Int, _ spellB: Int, games: Int, wins: Int)
        -> SpellPairCandidate
    {
        SpellPairCandidate(
            spellA: SummonerSpellID(rawValue: spellA), spellB: SummonerSpellID(rawValue: spellB),
            games: games, wins: wins)
    }

    private static func build(_ layer: BuildLayer, _ items: [Int], games: Int, wins: Int)
        -> ItemBuildCandidate
    {
        ItemBuildCandidate(
            layer: layer, items: items.map(ItemID.init(rawValue:)), games: games, wins: wins)
    }

    private static func final(_ item: Int, games: Int, wins: Int) -> FinalItemCandidate {
        FinalItemCandidate(item: ItemID(rawValue: item), games: games, wins: wins)
    }

    private static func skill(_ maxOrder: String, _ sequence: String, games: Int, wins: Int)
        -> SkillOrderCandidate
    {
        let abilities = { (letters: String) in
            letters.compactMap { SkillOrder.Ability(rawValue: String($0)) }
        }
        return SkillOrderCandidate(
            order: SkillOrder(maxOrder: abilities(maxOrder), sequence: abilities(sequence)),
            games: games, wins: wins)
    }
}
