import MitoCore
import MitoEngine
import MitoTestSupport
import Testing

/// Seeded by hand from `fixtures/snapshot/emerald_plus.sqlite` (general rows, `opp_id = 0`),
/// since MitoEngineTests cannot link the MitoStore reader; its `meta` matches
/// `SnapshotMeta.example`.
struct GeneralLoadoutFixtureTests {
    private let meta = SnapshotMeta.example(matches: 20_000)

    @Test func choosesAhriMiddleFromTheContractFixture() {
        let stats = provider(
            row: ChampionRoleStats(games: 2_824, wins: 1_466, timelineGames: 706),
            meta: meta,
            runes: [
                RunePageCandidate(
                    page: page(8100, 8300, [8112, 8143, 8140, 8135, 8345, 8347, 5008, 5008, 5011]),
                    games: 2_118, wins: 1_105),
                RunePageCandidate(
                    page: page(8200, 8300, [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011]),
                    games: 706, wins: 374),
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
            skills: [skill("QWE", "QWEQQRQQWWRWWEEREE", games: 706, wins: 367)])

        let result = LoadoutSelection.general(for: ahri, role: .middle, stats: stats)

        // Sorcery wins on smoothed winrate (0.5251 against 0.5211) with 25 % usage.
        #expect(
            result.loadout.runes
                == page(8200, 8300, [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011]))
        #expect(result.loadout.spells == spellPair(4, 14))
        // The only sixth item (3157) is already in the core, so the set ends at the fifth.
        #expect(
            result.loadout.itemSet?.blocks.map(\.items) == [
                [item(1056), item(2003, count: 2)],
                [item(6655), item(3157), item(3089)],
                [item(3020)], [item(3107)], [item(3142)],
            ])
        #expect(
            result.loadout.skillOrder
                == SkillOrder(maxOrder: abilities("QWE"), sequence: abilities("QWEQQRQQWWRWWEEREE"))
        )
        #expect(result.sampleLevels.runes == .usable)
        #expect(result.sampleLevels.spells == .reliable)
        #expect(result.sampleLevels.itemSet == .usable)
        #expect(result.sampleLevels.skillOrder == .reliable)
    }

    /// `tl_games = 40` is under the `build_layer` minimum: core and boots come from final items.
    @Test func choosesZedJungleFromTheContractFixtureThroughTheFinalItemsFallback() {
        let zed = ChampionID(rawValue: 238)
        let stats = provider(
            champion: zed,
            role: .jungle,
            row: ChampionRoleStats(games: 2_746, wins: 1_340, timelineGames: 40),
            meta: meta,
            runes: [
                RunePageCandidate(
                    page: page(8000, 8400, [8010, 9111, 9104, 8299, 8444, 8451, 5005, 5008, 5011]),
                    games: 2_059, wins: 1_018),
                RunePageCandidate(
                    page: page(8100, 8000, [8128, 8143, 8140, 8135, 9104, 9111, 5008, 5008, 5011]),
                    games: 687, wins: 355),
            ],
            spells: [pair(4, 11, games: 2_746, wins: 1_248)],
            items: [
                build(.boots, [3158], games: 886, wins: 467),
                build(.core, [3142, 6692, 3071], games: 1_776, wins: 853),
                build(.start, [1101], games: 32, wins: 14),
            ],
            skills: [skill("QEW", "QEWQQRQQEEREEWWRWW", games: 40, wins: 21)])

        let result = LoadoutSelection.general(for: zed, role: .jungle, stats: stats)

        #expect(
            result.loadout.runes
                == page(8100, 8000, [8128, 8143, 8140, 8135, 9104, 9111, 5008, 5008, 5011]))
        #expect(result.loadout.spells == spellPair(4, 11))
        #expect(
            result.loadout.itemSet?.blocks.map(\.items) == [
                [item(1101)], [item(3142), item(6692), item(3071)], [item(3158)],
            ])
        // The start has 32 timeline games, under the build_layer minimum; no 4th–6th rows.
        #expect(result.sampleLevels.itemSet == .belowMinimum)
        #expect(result.sampleLevels.itemLayers[.core] == .reliable)
        // The only order is under the skill_order minimum: kept, marked.
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
