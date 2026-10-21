import MitoCore
import MitoEngine
import MitoTestSupport
import Testing

/// Ahri MIDDLE seeded by hand from `fixtures/snapshot/emerald_plus.sqlite` (mito-data `927a3b3`):
/// general rows as in `GeneralLoadoutFixtureTests`, plus her rows against Zed and the profiles.
struct AdaptedLoadoutFixtureTests {
    private let darius = ChampionID(rawValue: 122)
    private let soraka = ChampionID(rawValue: 16)

    private let electrocute = RunePage(
        primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8300),
        perks: [8112, 8143, 8140, 8135, 8345, 8347, 5008, 5008, 5011].map(PerkID.init(rawValue:)))
    private let phaseRush = RunePage(
        primaryStyle: PerkStyleID(rawValue: 8200), subStyle: PerkStyleID(rawValue: 8300),
        perks: [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011].map(PerkID.init(rawValue:)))

    private var stats: InMemoryStatsProvider {
        provider(
            row: ChampionRoleStats(games: 2_824, wins: 1_466, timelineGames: 706),
            meta: .example(matches: 20_000),
            runes: [
                RunePageCandidate(page: electrocute, games: 2_118, wins: 1_105),
                RunePageCandidate(page: phaseRush, games: 706, wins: 374),
            ],
            spells: [pair(4, 12, games: 1_305, wins: 591), pair(4, 14, games: 1_519, wins: 695)],
            items: [
                build(.boots, [3020], games: 321, wins: 174),
                build(.core, [6655, 3157, 3089], games: 235, wins: 129),
                build(.fifth, [3142], games: 503, wins: 230),
                build(.fourth, [3107], games: 150, wins: 77),
                build(.sixth, [3157], games: 373, wins: 188),
                build(.start, [1056, 2003, 2003], games: 572, wins: 301),
            ],
            skills: [skill("QWE", "QWEQQRQQWWRWWEEREE", games: 706, wins: 367)]
        )
        .versus(
            matchup: MatchupStats(
                games: 497, wins: 237, timelineGames: 124, goldDiffAt15: -309.3, csDiffAt15: -5.9),
            runes: [
                RunePageCandidate(page: electrocute, games: 198, wins: 95),
                RunePageCandidate(page: phaseRush, games: 198, wins: 107),
            ],
            spells: [pair(4, 14, games: 248, wins: 121)],
            items: [
                build(.boots, [3020], games: 101, wins: 46),
                build(.core, [6655, 3157, 3089], games: 106, wins: 48),
                build(.start, [1056, 2003, 2003], games: 124, wins: 63),
            ]
        )
        .baseline([
            final(3020, games: 1_694, wins: 804), final(3047, games: 339, wins: 178),
            final(3089, games: 1_959, wins: 1_053), final(3157, games: 226, wins: 103),
            final(3165, games: 226, wins: 119), final(6655, games: 1_693, wins: 789),
        ])
        .against(
            .heavyAD, games: 614,
            runes: [
                RunePageCandidate(page: electrocute, games: 449, wins: 235),
                RunePageCandidate(page: phaseRush, games: 159, wins: 86),
            ],
            finalItems: [
                final(3020, games: 368, wins: 177), final(3047, games: 221, wins: 128),
                final(3089, games: 426, wins: 224), final(3157, games: 123, wins: 63),
                final(6655, games: 368, wins: 176),
            ]
        )
        .flagged([soraka: [.highHeal], darius: [.highHeal]])
    }

    @Test func adaptsAhriMiddleToZedInAHeavyADTeamWithTwoHealers() {
        let result = LoadoutSelection.adapted(
            for: ahri, role: .middle, opponent: zed, enemyProfile: [.heavyAD],
            enemies: [zed, darius, soraka], stats: stats)

        // Two pages of 198 games against Zed: Phase Rush wins 107 to Electrocute's 95.
        #expect(result.loadout.runes == phaseRush)
        #expect(result.loadout.spells == spellPair(4, 14))
        // Zhonya's rises 2.5× against heavy_ad but is already in the core against Zed, so the
        // last block is only the antiheal for Darius and Soraka.
        #expect(
            result.loadout.itemSet?.blocks == [
                ItemSet.Block(title: "start", items: [item(1056), item(2003, count: 2)]),
                ItemSet.Block(title: "core", items: [item(6655), item(3157), item(3089)]),
                ItemSet.Block(title: "boots", items: [item(3020)]),
                ItemSet.Block(title: "fourth", items: [item(3107)]),
                ItemSet.Block(title: "fifth", items: [item(3142)]),
                ItemSet.Block(
                    title: LoadoutSelection.situationalBlockTitle, items: [item(3165)]),
            ])
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToOpponent(part: .runes, opponent: zed, games: 198),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .spells, opponent: zed, games: 248),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .items(.start), opponent: zed, games: 124),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .items(.core), opponent: zed, games: 106),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .items(.boots), opponent: zed, games: 101),
                    sample: .usable),
                Reason(
                    kind: .countersFlag(item: ItemID(rawValue: 3165), flag: .highHeal, enemies: 2),
                    sample: nil),
            ])
    }

    @Test func adaptsAhriMiddleToAHeavyADTeamWithoutAKnownOpponent() {
        let result = LoadoutSelection.adapted(
            for: ahri, role: .middle, opponent: nil, enemyProfile: [.heavyAD], enemies: [],
            stats: stats)

        // Phase Rush: 0.5239 against Electrocute's 0.5208 over heavy_ad's 614 games.
        #expect(result.loadout.runes == phaseRush)
        // Plated Steelcaps: 36 % of heavy_ad games against 12 %, at 0.537 against 0.521.
        #expect(
            result.loadout.itemSet?.blocks[2] == ItemSet.Block(title: "boots", items: [item(3047)]))
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToProfile(part: .runes, profile: .heavyAD, games: 159),
                    sample: .usable),
                Reason(
                    kind: .adaptedToProfile(part: .items(.boots), profile: .heavyAD, games: 221),
                    sample: .usable),
            ])
        #expect(result.sampleLevels.itemLayers[.boots] == .usable)
    }
}
