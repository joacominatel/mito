import MitoCore
import MitoEngine
import MitoTestSupport
import Testing

/// Seeded by hand from `fixtures/snapshot/emerald_plus.sqlite` (general rows, `opp_id = 0`)
/// until the P6-02 reader lands; its `meta` matches `SnapshotMeta.example`.
struct GeneralLoadoutFixtureTests {
    private let meta = SnapshotMeta.example(matches: 20_000)

    @Test func choosesAhriMiddleFromTheContractFixture() {
        let stats = provider(
            row: ChampionRoleStats(games: 991, wins: 463, timelineGames: 247),
            meta: meta,
            runes: [
                RunePageCandidate(
                    page: page(8100, 8300, [8112, 8143, 8138, 8135, 8345, 8347, 5008, 5008, 5011]),
                    games: 743, wins: 336),
                RunePageCandidate(
                    page: page(8200, 8300, [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011]),
                    games: 248, wins: 134),
            ],
            spells: [pair(4, 12, games: 301, wins: 161), pair(4, 14, games: 690, wins: 379)],
            items: [
                build(.boots, [3020], games: 133, wins: 65),
                build(.core, [6655, 3157, 3089], games: 189, wins: 85),
                build(.fifth, [3033], games: 208, wins: 111),
                build(.fourth, [3031], games: 186, wins: 96),
                build(.sixth, [3046], games: 136, wins: 63),
                build(.start, [1056, 2003, 2003], games: 223, wins: 101),
            ],
            skills: [skill("QWE", "QWEQQRQQWWRWWEEREE", games: 247, wins: 127)])

        let result = LoadoutSelection.general(for: ahri, role: .middle, stats: stats)

        // Sorcery wins on smoothed winrate (0.493 against 0.459) with 25 % usage.
        #expect(
            result.loadout.runes
                == page(8200, 8300, [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011]))
        #expect(result.loadout.spells == spellPair(4, 14))
        #expect(
            result.loadout.itemSet?.blocks.map(\.items) == [
                [item(1056), item(2003, count: 2)],
                [item(6655), item(3157), item(3089)],
                [item(3020)], [item(3031)], [item(3033)], [item(3046)],
            ])
        #expect(
            result.loadout.skillOrder
                == SkillOrder(maxOrder: abilities("QWE"), sequence: abilities("QWEQQRQQWWRWWEEREE"))
        )
        #expect(result.sampleLevels.runes == .usable)
        #expect(result.sampleLevels.spells == .reliable)
        #expect(result.sampleLevels.itemSet == .usable)
        #expect(result.sampleLevels.skillOrder == .usable)
    }

    /// `tl_games = 40` is under the `build_layer` minimum: core and boots come from final items.
    @Test func choosesZedJungleFromTheContractFixtureThroughTheFinalItemsFallback() {
        let zed = ChampionID(rawValue: 238)
        let stats = provider(
            champion: zed,
            role: .jungle,
            row: ChampionRoleStats(games: 2_249, wins: 1_062, timelineGames: 40),
            meta: meta,
            runes: [
                RunePageCandidate(
                    page: page(8000, 8400, [8010, 9111, 9104, 8299, 8444, 8451, 5005, 5008, 5011]),
                    games: 1_686, wins: 823),
                RunePageCandidate(
                    page: page(8100, 8000, [8128, 8143, 8138, 8135, 9104, 9111, 5008, 5008, 5011]),
                    games: 563, wins: 285),
            ],
            spells: [pair(4, 11, games: 2_249, wins: 1_234)],
            items: [
                build(.boots, [3158], games: 1_312, wins: 604),
                build(.core, [3142, 6692, 3071], games: 1_777, wins: 852),
                build(.fifth, [3089], games: 1_828, wins: 959),
                build(.fourth, [3075], games: 1_372, wins: 649),
                build(.sixth, [3094], games: 2_050, wins: 1_025),
                build(.start, [1101], games: 1_399, wins: 724),
            ],
            skills: [
                skill("QEW", "QEWQQRQQEEREEWWRWW", games: 28, wins: 14),
                skill("QWE", "QWEQQRQQWWRWWEEREE", games: 12, wins: 6),
            ])

        let result = LoadoutSelection.general(for: zed, role: .jungle, stats: stats)

        #expect(
            result.loadout.runes
                == page(8100, 8000, [8128, 8143, 8138, 8135, 9104, 9111, 5008, 5008, 5011]))
        #expect(result.loadout.spells == spellPair(4, 11))
        #expect(
            result.loadout.itemSet?.blocks.map(\.items) == [
                [item(1101)], [item(3142), item(6692), item(3071)], [item(3158)],
                [item(3075)], [item(3089)], [item(3094)],
            ])
        #expect(result.sampleLevels.itemSet == .reliable)
        // Both orders are under the skill_order minimum: the most played one, marked.
        #expect(
            result.loadout.skillOrder
                == SkillOrder(maxOrder: abilities("QEW"), sequence: abilities("QEWQQRQQEEREEWWRWW"))
        )
        #expect(result.sampleLevels.skillOrder == .belowMinimum)
    }

    private func page(_ primary: Int, _ sub: Int, _ perks: [Int]) -> RunePage {
        RunePage(
            primaryStyle: PerkStyleID(rawValue: primary), subStyle: PerkStyleID(rawValue: sub),
            perks: perks.map(PerkID.init(rawValue:)))
    }
}
