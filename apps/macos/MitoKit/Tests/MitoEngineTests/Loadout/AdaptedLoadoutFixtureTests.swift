import MitoCore
import MitoEngine
import MitoTestSupport
import Testing

/// Ahri MIDDLE seeded by hand from `fixtures/snapshot/emerald_plus.sqlite` (mito-data `8ded78e`):
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
            row: ChampionRoleStats(games: 2_824, wins: 1_420, timelineGames: 706),
            meta: .example(matches: 20_000),
            runes: [
                RunePageCandidate(page: electrocute, games: 2_118, wins: 1_014),
                RunePageCandidate(page: phaseRush, games: 706, wins: 332),
            ],
            spells: [pair(4, 12, games: 1_733, wins: 891), pair(4, 14, games: 1_091, wins: 501)],
            items: [
                build(.boots, [3020], games: 123, wins: 64),
                build(.core, [6655, 3157, 3089], games: 535, wins: 248),
                build(.fifth, [3033], games: 688, wins: 333),
                build(.fourth, [3031], games: 251, wins: 124),
                build(.sixth, [3046], games: 199, wins: 104),
                build(.start, [1056, 2003, 2003], games: 194, wins: 87),
            ],
            skills: [skill("QWE", "QWEQQRQQWWRWWEEREE", games: 706, wins: 356)]
        )
        .versus(
            matchup: MatchupStats(
                games: 518, wins: 263, timelineGames: 129, goldDiffAt15: -206.3, csDiffAt15: 3.4),
            runes: [
                RunePageCandidate(page: electrocute, games: 207, wins: 99),
                RunePageCandidate(page: phaseRush, games: 207, wins: 112),
            ],
            spells: [pair(4, 14, games: 259, wins: 130)],
            items: [
                build(.boots, [3020], games: 103, wins: 48),
                build(.core, [6655, 3157, 3089], games: 129, wins: 64),
                build(.start, [1056, 2003, 2003], games: 129, wins: 61),
            ]
        )
        .baseline([
            final(3020, games: 1_695, wins: 844), final(3047, games: 339, wins: 182),
            final(3089, games: 2_140, wins: 1_072), final(3157, games: 2_140, wins: 1_170),
            final(3165, games: 226, wins: 106), final(6655, games: 2_140, wins: 1_008),
        ])
        .against(
            .heavyAD, games: 752,
            runes: [
                RunePageCandidate(page: electrocute, games: 510, wins: 234),
                RunePageCandidate(page: phaseRush, games: 236, wins: 128),
            ],
            finalItems: [
                final(3020, games: 452, wins: 221), final(3047, games: 271, wins: 156),
                final(3089, games: 570, wins: 276), final(3157, games: 752, wins: 426),
                final(3165, games: 61, wins: 28), final(6655, games: 570, wins: 305),
            ]
        )
        .flagged([soraka: [.highHeal], darius: [.highHeal]])
    }

    @Test func adaptsAhriMiddleToZedInAHeavyADTeamWithTwoHealers() {
        let result = LoadoutSelection.adapted(
            for: ahri, role: .middle, opponent: zed, enemyProfile: [.heavyAD],
            enemies: [zed, darius, soraka], stats: stats)

        // Two pages of 207 games against Zed: Phase Rush wins 112 to Electrocute's 99.
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
                    kind: .adaptedToOpponent(part: .runes, opponent: zed, games: 207),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .spells, opponent: zed, games: 259),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .items(.start), opponent: zed, games: 129),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .items(.core), opponent: zed, games: 129),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .items(.boots), opponent: zed, games: 103),
                    sample: .usable),
            ])
    }

    @Test func adaptsAhriMiddleToAHeavyADTeamWithoutAKnownOpponent() {
        let result = LoadoutSelection.adapted(
            for: ahri, role: .middle, opponent: nil, enemyProfile: [.heavyAD], enemies: [],
            stats: stats)

        // Phase Rush: 0.5154 against Electrocute's 0.4806 over heavy_ad's 752 games.
        #expect(result.loadout.runes == phaseRush)
        // Plated Steelcaps: 36 % of heavy_ad games against 12 %, at 0.528 against 0.517.
        #expect(
            result.loadout.itemSet?.blocks[2] == ItemSet.Block(title: "boots", items: [item(3047)]))
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToProfile(part: .runes, profile: .heavyAD, games: 236),
                    sample: .usable),
                Reason(
                    kind: .adaptedToProfile(part: .items(.boots), profile: .heavyAD, games: 271),
                    sample: .usable),
            ])
        #expect(result.sampleLevels.itemLayers[.boots] == .usable)
    }
}
