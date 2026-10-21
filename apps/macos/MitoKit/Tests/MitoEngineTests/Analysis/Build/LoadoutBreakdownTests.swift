import MitoCore
import MitoEngine
import MitoTestSupport
import Testing

/// Smoothed winrates in the comments are `(wins + 250) / (games + 500)` (see `evenRow`): the row
/// has 2,000 games and 1,000 timeline games, the matchup 1,000 games and 500 timeline games.
struct LoadoutBreakdownTests {
    private func breakdown(
        _ stats: InMemoryStatsProvider, opponent: ChampionID? = nil,
        profiles: Set<EnemyProfile> = []
    ) -> LoadoutBreakdown {
        let loadout = LoadoutSelection.adapted(
            for: ahri, role: .middle, opponent: opponent, enemyProfile: profiles, enemies: [],
            stats: stats)
        return LoadoutSelection.breakdown(
            of: loadout, for: ahri, role: .middle, enemyProfile: profiles, stats: stats)
    }

    @Test func generalRunesListTheChosenPageAndTheAlternativesPastTheMinimum() throws {
        let runes = try #require(
            breakdown(
                provider(runes: [
                    page(keystone: 8112, games: 1_500, wins: 900),
                    page(keystone: 8128, games: 400, wins: 230),
                    page(keystone: 8010, games: 300, wins: 140),
                    page(keystone: 8021, games: 99, wins: 99),
                ])
            ).runes)

        #expect(runes.chosen.value == runePage(keystone: 8112))
        #expect(runes.chosen.games == 1_500)
        #expect(abs(runes.chosen.winrate - 1_150.0 / 2_000) < 1e-9)
        #expect(runes.chosen.usage == 0.75)
        #expect(runes.chosen.level == .reliable)
        // 8128 at 480/900 beats 8010 at 390/800; 8021 is under the 100-game minimum.
        #expect(
            runes.alternatives.map(\.value) == [runePage(keystone: 8128), runePage(keystone: 8010)])
        #expect(runes.alternatives.map(\.level) == [.usable, .usable])
    }

    @Test func opponentRunesComeFromTheMatchupRows() throws {
        let runes = try #require(
            breakdown(
                provider(runes: [page(keystone: 8112, games: 1_500, wins: 750)])
                    .versus(runes: [
                        page(keystone: 8128, games: 300, wins: 180),
                        page(keystone: 8112, games: 200, wins: 90),
                    ]),
                opponent: zed
            ).runes)

        #expect(runes.chosen.value == runePage(keystone: 8128))
        #expect(runes.chosen.usage == 0.3)
        #expect(runes.alternatives.map(\.value) == [runePage(keystone: 8112)])
        #expect(runes.alternatives.first?.games == 200)
    }

    @Test func profileRunesArePooledOverTheActiveProfiles() throws {
        let runes = try #require(
            breakdown(
                provider(runes: [page(keystone: 8112, games: 1_500, wins: 750)])
                    .against(.heavyAD, runes: [page(keystone: 8010, games: 400, wins: 220)])
                    .against(.heavyCC, runes: [page(keystone: 8010, games: 200, wins: 120)]),
                profiles: [.heavyAD, .heavyCC]
            ).runes)

        #expect(runes.chosen.value == runePage(keystone: 8010))
        #expect(runes.chosen.games == 600)
        #expect(runes.chosen.usage == 0.3)
    }

    @Test func spellsInTheJungleOnlyListPairsWithSmite() throws {
        let stats = provider(
            role: .jungle,
            spells: [
                pair(4, 11, games: 1_800, wins: 900), pair(4, 14, games: 150, wins: 150),
                pair(6, 11, games: 150, wins: 80),
            ])
        let loadout = LoadoutSelection.general(for: ahri, role: .jungle, stats: stats)
        let spells = try #require(
            LoadoutSelection.breakdown(
                of: loadout, for: ahri, role: .jungle, enemyProfile: [], stats: stats
            ).spells)

        #expect(spells.chosen.value == spellPair(4, 11))
        // Ghost/Smite has no Flash and is far from dominant, so it is filtered like the engine does.
        #expect(spells.alternatives.isEmpty)
    }

    @Test func itemLayersSkipAlternativesThatRepeatAnEarlierLayer() throws {
        let layers = breakdown(
            provider(items: [
                build(.start, [1056, 2003, 2003], games: 600, wins: 300),
                build(.core, [6655, 3157], games: 500, wins: 260),
                build(.core, [3157, 3089], games: 300, wins: 200),
                build(.core, [3089, 4645], games: 200, wins: 110),
                build(.fourth, [3157], games: 300, wins: 200),
                build(.fourth, [3135], games: 250, wins: 130),
            ])
        ).itemLayers

        let start = try #require(layers[.start])
        #expect(start.chosen.value == [item(1056), item(2003, count: 2)])
        #expect(start.chosen.usage == 0.6)

        let core = try #require(layers[.core])
        #expect(core.chosen.value == [item(6655), item(3157)])
        #expect(
            core.alternatives.map(\.value) == [
                [item(3157), item(3089)], [item(3089), item(4645)],
            ])

        // 3157 is in the core, so the fourth item can only be 3135, with no alternative left.
        let fourth = try #require(layers[.fourth])
        #expect(fourth.chosen.value == [item(3135)])
        #expect(fourth.alternatives.isEmpty)
    }

    @Test func opponentLayersUseTheMatchupTimelineGames() throws {
        let layers = breakdown(
            provider(items: [build(.boots, [3020], games: 500, wins: 250)])
                .versus(items: [build(.boots, [3111], games: 200, wins: 120)]),
            opponent: zed
        ).itemLayers

        let boots = try #require(layers[.boots])
        #expect(boots.chosen.value == [item(3111)])
        #expect(boots.chosen.usage == 0.4)
    }

    @Test func profileBootsComeFromTheProfileFinalItems() throws {
        let layers = breakdown(
            provider(items: [build(.boots, [3020], games: 500, wins: 250)])
                .against(.heavyAD, finalItems: [final(3047, games: 300, wins: 170)])
                .baseline([final(3047, games: 200, wins: 100)]),
            profiles: [.heavyAD]
        ).itemLayers

        let boots = try #require(layers[.boots])
        #expect(boots.chosen.value == [item(3047)])
        #expect(boots.chosen.games == 300)
        #expect(boots.chosen.usage == 0.3)
        #expect(boots.chosen.level == .reliable)
        #expect(boots.alternatives.isEmpty)
    }

    @Test func skillOrderListsTheTimelineShare() throws {
        let skills = try #require(
            breakdown(
                provider(skills: [
                    skill("QWE", games: 700, wins: 360), skill("QEW", games: 200, wins: 110),
                ])
            ).skillOrder)

        #expect(skills.chosen.value.maxOrder == abilities("QWE"))
        #expect(skills.chosen.usage == 0.7)
        #expect(skills.alternatives.map(\.value.maxOrder) == [abilities("QEW")])
    }

    @Test func belowTheChampionRoleMinimumEveryOptionIsBelowMinimum() throws {
        let runes = try #require(
            breakdown(
                provider(
                    row: evenRow(games: 150, timelineGames: 80),
                    runes: [page(keystone: 8112, games: 120, wins: 70)])
            ).runes)

        #expect(runes.chosen.level == .belowMinimum)
    }

    @Test func withoutAChampionRoleRowThereIsNothing() {
        let stats = provider(
            runes: [page(games: 1_500, wins: 750)],
            items: [build(.core, [6655, 3157], games: 500, wins: 260)])
        let loadout = LoadoutSelection.general(for: ahri, role: .middle, stats: stats)
        var withoutRow = stats
        withoutRow.championRoleStatsByRole = [:]

        let result = LoadoutSelection.breakdown(
            of: loadout, for: ahri, role: .middle, enemyProfile: [], stats: withoutRow)

        #expect(loadout.loadout.runes != nil)
        #expect(loadout.loadout.itemSet != nil)
        #expect(result.runes == nil)
        #expect(result.itemLayers.isEmpty)
    }

    @Test func atMostTwoAlternativesAreListedBestWinrateFirst() throws {
        let runes = try #require(
            breakdown(
                provider(runes: [
                    page(keystone: 8112, games: 1_500, wins: 900),
                    page(keystone: 8010, games: 300, wins: 150),
                    page(keystone: 8128, games: 300, wins: 200),
                    page(keystone: 8021, games: 300, wins: 180),
                    page(keystone: 8229, games: 300, wins: 165),
                ])
            ).runes)

        // 450/800, 430/800, 415/800, 400/800.
        #expect(
            runes.alternatives.map(\.value) == [runePage(keystone: 8128), runePage(keystone: 8021)])
    }

    @Test func alternativesTiedOnWinrateListTheMorePlayedFirst() throws {
        let runes = try #require(
            breakdown(
                provider(runes: [
                    page(keystone: 8112, games: 1_500, wins: 900),
                    page(keystone: 8010, games: 300, wins: 150),
                    page(keystone: 8128, games: 500, wins: 250),
                ])
            ).runes)

        // Both at exactly 0.5.
        #expect(
            runes.alternatives.map(\.value) == [runePage(keystone: 8128), runePage(keystone: 8010)])
    }

    @Test func aPageWithoutNineRunesIsNeverAnAlternative() throws {
        let short = RunePageCandidate(
            page: runePage(perks: [8128, 8139, 8138, 8135, 8226, 8210, 5008, 5008]), games: 400,
            wins: 300)
        let runes = try #require(
            breakdown(
                provider(runes: [page(keystone: 8112, games: 1_500, wins: 900)])
                    .adding(runes: [short])
            ).runes)

        #expect(runes.alternatives.isEmpty)
    }

    @Test func usageNeverExceedsTheWholeContext() throws {
        let runes = try #require(
            breakdown(
                provider(runes: [page(keystone: 8112, games: 1_500, wins: 750)])
                    .versus(
                        matchup: lane(games: 200, timelineGames: 100),
                        runes: [page(keystone: 8128, games: 300, wins: 200)]),
                opponent: zed
            ).runes)

        #expect(runes.chosen.value == runePage(keystone: 8128))
        #expect(runes.chosen.usage == 1)
    }

    @Test func aProfileWithoutItsRowAddsNothingToThePool() throws {
        let runes = try #require(
            breakdown(
                provider(runes: [page(keystone: 8112, games: 1_500, wins: 750)])
                    .against(.heavyAD, runes: [page(keystone: 8010, games: 400, wins: 220)])
                    .against(
                        .heavyCC, games: nil, runes: [page(keystone: 8010, games: 300, wins: 300)]),
                profiles: [.heavyAD, .heavyCC]
            ).runes)

        #expect(runes.chosen.value == runePage(keystone: 8010))
        #expect(runes.chosen.games == 400)
        #expect(runes.chosen.usage == 0.4)
    }

    @Test func belowTheBuildLayerMinimumCoreAndBootsShareAllTheChampionsGames() throws {
        let layers = breakdown(
            provider(
                row: evenRow(games: 2_000, timelineGames: 50),
                items: [
                    build(.core, [6655, 3157], games: 600, wins: 320),
                    build(.boots, [3020], games: 500, wins: 260),
                ])
        ).itemLayers

        #expect(layers[.core]?.chosen.usage == 0.3)
        #expect(layers[.boots]?.chosen.usage == 0.25)
    }

    @Test func withoutASnapshotThereIsNothingToBreakDown() {
        let stats = provider(runes: [page(games: 1_500, wins: 750)])
        let loadout = LoadoutSelection.general(for: ahri, role: .middle, stats: stats)
        var closed = stats
        closed.meta = nil

        let result = LoadoutSelection.breakdown(
            of: loadout, for: ahri, role: .middle, enemyProfile: [], stats: closed)

        #expect(loadout.loadout.runes != nil)
        #expect(result.runes == nil)
        #expect(result.itemLayers.isEmpty)
    }
}

extension InMemoryStatsProvider {
    fileprivate func adding(
        runes: [RunePageCandidate], champion: ChampionID = ahri, role: Role = .middle
    ) -> InMemoryStatsProvider {
        var stats = self
        stats.runePagesByChampion[champion, default: [:]][role, default: []] += runes
        return stats
    }
}
