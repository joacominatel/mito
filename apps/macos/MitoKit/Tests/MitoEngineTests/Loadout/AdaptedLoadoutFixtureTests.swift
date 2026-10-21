import MitoCore
import MitoEngine
import MitoTestSupport
import Testing

/// Ahri MIDDLE seeded by hand from `fixtures/snapshot/emerald_plus.sqlite` (mito-data `fb793ac`):
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
            row: ChampionRoleStats(games: 2_824, wins: 1_489, timelineGames: 706),
            meta: .example(matches: 20_000),
            runes: [
                RunePageCandidate(page: electrocute, games: 2_118, wins: 1_093),
                RunePageCandidate(page: phaseRush, games: 706, wins: 336),
            ],
            spells: [pair(4, 12, games: 174, wins: 80), pair(4, 14, games: 2_650, wins: 1_325)],
            items: [
                build(.boots, [3020], games: 688, wins: 354),
                build(.core, [6655, 3157, 3089], games: 303, wins: 152),
                build(.fifth, [3033], games: 415, wins: 225),
                build(.fourth, [3031], games: 305, wins: 148),
                build(.sixth, [3046], games: 650, wins: 341),
                build(.start, [1056, 2003, 2003], games: 373, wins: 188),
            ],
            skills: [skill("QWE", "QWEQQRQQWWRWWEEREE", games: 706, wins: 338)]
        )
        .versus(
            matchup: MatchupStats(
                games: 463, wins: 246, timelineGames: 115, goldDiffAt15: 123.1, csDiffAt15: -6.6),
            runes: [
                RunePageCandidate(page: electrocute, games: 185, wins: 89),
                RunePageCandidate(page: phaseRush, games: 185, wins: 100),
            ],
            spells: [pair(4, 14, games: 231, wins: 118)],
            items: [
                build(.boots, [3020], games: 107, wins: 54),
                build(.core, [6655, 3157, 3089], games: 110, wins: 51),
                build(.start, [1056, 2003, 2003], games: 115, wins: 63),
            ]
        )
        .baseline([
            final(3020, games: 2_752, wins: 1_418), final(3047, games: 339, wins: 168),
            final(3089, games: 1_815, wins: 892), final(3157, games: 1_588, wins: 769),
            final(3165, games: 226, wins: 105), final(6655, games: 1_991, wins: 1_051),
        ])
        .against(
            .heavyAD, games: 797,
            runes: [
                RunePageCandidate(page: electrocute, games: 573, wins: 309),
                RunePageCandidate(page: phaseRush, games: 220, wins: 108),
            ],
            finalItems: [
                final(3020, games: 777, wins: 378), final(3047, games: 287, wins: 144),
                final(3089, games: 513, wins: 238), final(3157, games: 797, wins: 391),
                final(3165, games: 64, wins: 30), final(6655, games: 562, wins: 302),
            ]
        )
        .flagged([soraka: [.highHeal], darius: [.highHeal]])
    }

    @Test func adaptsAhriMiddleToZedInAHeavyADTeamWithTwoHealers() {
        let result = LoadoutSelection.adapted(
            for: ahri, role: .middle, opponent: zed, enemyProfile: [.heavyAD],
            enemies: [zed, darius, soraka], stats: stats)

        // Two pages of 185 games against Zed: Phase Rush wins 100 to Electrocute's 89.
        #expect(result.loadout.runes == phaseRush)
        #expect(result.loadout.spells == spellPair(4, 14))
        // Mortal Reminder (3033) is already the fifth item, so Darius and Soraka add no antiheal
        // block, and Zhonya's, which rises against heavy_ad, is already in the core.
        #expect(
            result.loadout.itemSet?.blocks == [
                ItemSet.Block(title: "start", items: [item(1056), item(2003, count: 2)]),
                ItemSet.Block(title: "core", items: [item(6655), item(3157), item(3089)]),
                ItemSet.Block(title: "boots", items: [item(3020)]),
                ItemSet.Block(title: "fourth", items: [item(3031)]),
                ItemSet.Block(title: "fifth", items: [item(3033)]),
                ItemSet.Block(title: "sixth", items: [item(3046)]),
            ])
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToOpponent(part: .runes, opponent: zed, games: 185),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .spells, opponent: zed, games: 231),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .items(.start), opponent: zed, games: 115),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .items(.core), opponent: zed, games: 110),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .items(.boots), opponent: zed, games: 107),
                    sample: .usable),
            ])
    }

    @Test func adaptsAhriMiddleToAHeavyADTeamWithoutAKnownOpponent() {
        let result = LoadoutSelection.adapted(
            for: ahri, role: .middle, opponent: nil, enemyProfile: [.heavyAD], enemies: [],
            stats: stats)

        // Electrocute: 0.5332 against Phase Rush's 0.5155 over heavy_ad's 797 games.
        #expect(result.loadout.runes == electrocute)
        // Plated Steelcaps: 36 % of heavy_ad games against 12 %, at 0.517 against 0.514.
        #expect(
            result.loadout.itemSet?.blocks[2] == ItemSet.Block(title: "boots", items: [item(3047)]))
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToProfile(part: .runes, profile: .heavyAD, games: 573),
                    sample: .usable),
                Reason(
                    kind: .adaptedToProfile(part: .items(.boots), profile: .heavyAD, games: 287),
                    sample: .usable),
            ])
        #expect(result.sampleLevels.itemLayers[.boots] == .usable)
    }
}
