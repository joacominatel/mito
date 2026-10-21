import MitoCore
import MitoEngine
import MitoTestSupport
import Testing

/// Smoothed winrates in the comments are `(wins + 250) / (games + 500)` (see `evenRow`).
struct GeneralLoadoutTests {
    private func general(_ stats: some StatsProvider, role: Role = .middle) -> GeneralLoadout {
        LoadoutSelection.general(for: ahri, role: role, stats: stats)
    }

    // MARK: Runes (§18.6)

    @Test func runesPreferTheHigherWinrateOverTheMorePlayedPage() {
        let result = general(
            provider(runes: [
                page(keystone: 8112, games: 1_500, wins: 750),  // 0.500, 75 % usage
                page(keystone: 8128, games: 400, wins: 240),  // 0.544, 20 % usage
            ]))

        #expect(result.loadout.runes == runePage(keystone: 8128))
    }

    @Test func runesAcceptAPageAtExactlyFivePercentUsage() {
        let result = general(
            provider(runes: [
                page(keystone: 8112, games: 1_500, wins: 750),
                page(keystone: 8128, games: 100, wins: 90),  // 100 / 2000 = 5 %
            ]))

        #expect(result.loadout.runes == runePage(keystone: 8128))
    }

    @Test func runesSkipAWinningPageUnderFivePercentUsage() {
        let result = general(
            provider(
                row: evenRow(games: 2_020),
                runes: [
                    page(keystone: 8112, games: 1_500, wins: 750),
                    page(keystone: 8128, games: 100, wins: 90),  // 100 / 2020 < 5 %
                ]))

        #expect(result.loadout.runes == runePage(keystone: 8112))
    }

    @Test func runesBelowEveryMinimumFallBackToTheMostPlayedPageMarkedBelowMinimum() {
        let result = general(
            provider(runes: [
                page(keystone: 8112, games: 80, wins: 30),
                page(keystone: 8128, games: 60, wins: 50),
            ]))

        #expect(result.loadout.runes == runePage(keystone: 8112))
        #expect(result.sampleLevels.runes == .belowMinimum)
    }

    @Test func anIncompleteRunePageIsNeverChosen() {
        let incomplete = RunePageCandidate(
            page: runePage(perks: [8112, 8139, 8138, 8135, 8226, 8210, 5008, 5008]),
            games: 600, wins: 400)

        let result = general(
            provider(runes: [incomplete, page(keystone: 8128, games: 1_400, wins: 700)]))

        #expect(result.loadout.runes == runePage(keystone: 8128))
    }

    @Test func onlyIncompleteRunePagesGiveNoRunes() {
        let incomplete = RunePageCandidate(
            page: runePage(perks: [8112, 8139, 8138, 8135, 8226, 8210]), games: 1_400, wins: 700)

        let result = general(provider(runes: [incomplete]))

        #expect(result.loadout.runes == nil)
        #expect(result.sampleLevels.runes == nil)
    }

    // MARK: Spells (§18.8)

    @Test func spellsPreferTheHigherWinrateAmongPairsAboveTenPercent() {
        let result = general(
            provider(spells: [
                pair(4, 14, games: 1_400, wins: 700),  // 0.500
                pair(4, 12, games: 300, wins: 180),  // 0.5375, 15 % usage
            ]))

        #expect(result.loadout.spells == spellPair(4, 12))
    }

    @Test func spellsSkipAWinningPairUnderTenPercent() {
        let result = general(
            provider(spells: [
                pair(4, 14, games: 1_400, wins: 700),
                pair(4, 12, games: 190, wins: 150),  // 9.5 % usage
            ]))

        #expect(result.loadout.spells == spellPair(4, 14))
    }

    @Test func aJunglerAlwaysGetsSmiteInAscendingIDOrder() {
        let result = general(
            provider(
                role: .jungle,
                spells: [
                    pair(4, 14, games: 1_000, wins: 700),
                    pair(4, 11, games: 1_000, wins: 500),
                ]),
            role: .jungle)

        #expect(result.loadout.spells == spellPair(4, 11))
    }

    @Test func aJunglerWithoutASmitePairGetsNoSpells() {
        let result = general(
            provider(role: .jungle, spells: [pair(4, 14, games: 2_000, wins: 1_200)]),
            role: .jungle)

        #expect(result.loadout.spells == nil)
    }

    @Test func flashStaysOverAWinningPairWithoutItThatIsNotDominant() {
        let result = general(
            provider(spells: [
                pair(6, 14, games: 800, wins: 600),  // 0.654, 40 % usage
                pair(4, 14, games: 1_200, wins: 600),  // 0.500
            ]))

        #expect(result.loadout.spells == spellPair(4, 14))
    }

    @Test func aDominantPairWithoutFlashCanWin() {
        let result = general(
            provider(spells: [
                pair(6, 14, games: 1_200, wins: 700),  // 0.559, exactly 60 % usage
                pair(4, 14, games: 800, wins: 400),  // 0.500
            ]))

        #expect(result.loadout.spells == spellPair(6, 14))
    }

    @Test func aChampionWithoutAnyFlashPairStillGetsSpells() {
        let result = general(
            provider(spells: [
                pair(6, 14, games: 1_200, wins: 600),
                pair(12, 14, games: 800, wins: 500),  // 0.577
            ]))

        #expect(result.loadout.spells == spellPair(12, 14))
    }

    // MARK: Items (§18.7)

    @Test func buildLayersMeasureUsageAgainstTimelineGames() {
        let result = general(
            provider(
                row: evenRow(games: 5_000, timelineGames: 1_000),
                items: [
                    build(.start, [1055, 2003], games: 800, wins: 400),  // 0.500
                    build(.start, [1054, 2003], games: 150, wins: 100),  // 0.538, 15 % of tl
                ]))

        #expect(result.loadout.itemSet?.blocks.first?.items == [item(1054), item(2003)])
    }

    @Test func coreTakesTheMostPlayedComboWithAGoodWinrate() {
        let result = general(
            provider(items: [
                build(.core, [6655, 3157, 3089], games: 500, wins: 200),  // 0.450
                build(.core, [6655, 4645, 3089], games: 300, wins: 160),  // 0.5125
                build(.core, [3118, 4645, 3089], games: 200, wins: 150),  // 0.571
            ]))

        #expect(
            result.loadout.itemSet?.blocks.first?.items == [item(6655), item(4645), item(3089)])
    }

    @Test func coreFallsBackToTheMostPlayedComboWhenNoneHasAGoodWinrate() {
        let result = general(
            provider(items: [
                build(.core, [6655, 4645, 3089], games: 300, wins: 100),
                build(.core, [6655, 3157, 3089], games: 500, wins: 200),
            ]))

        #expect(
            result.loadout.itemSet?.blocks.first?.items == [item(6655), item(3157), item(3089)])
    }

    @Test func itemSetHasOneBlockPerLayerInBuildOrderTitledByLayer() {
        let result = general(
            provider(items: [
                build(.sixth, [3135], games: 300, wins: 150),
                build(.start, [1056, 2003, 2003], games: 700, wins: 350),
                build(.fourth, [3089], games: 400, wins: 200),
                build(.core, [6655, 4645, 3157], games: 500, wins: 250),
                build(.fifth, [3102], games: 350, wins: 175),
                build(.boots, [3020], games: 600, wins: 300),
            ]))

        #expect(
            result.loadout.itemSet
                == ItemSet(blocks: [
                    ItemSet.Block(title: "start", items: [item(1056), item(2003, count: 2)]),
                    ItemSet.Block(title: "core", items: [item(6655), item(4645), item(3157)]),
                    ItemSet.Block(title: "boots", items: [item(3020)]),
                    ItemSet.Block(title: "fourth", items: [item(3089)]),
                    ItemSet.Block(title: "fifth", items: [item(3102)]),
                    ItemSet.Block(title: "sixth", items: [item(3135)]),
                ]))
    }

    @Test func aLaterLayerSkipsAnItemAlreadyInTheSet() {
        let result = general(
            provider(items: [
                build(.core, [6655, 3157, 3089], games: 500, wins: 250),
                build(.fourth, [3157], games: 400, wins: 300),
                build(.fourth, [3135], games: 300, wins: 150),
            ]))

        #expect(result.loadout.itemSet?.blocks.last?.items == [item(3135)])
    }

    @Test func belowTheBuildLayerMinimumBootsMeasureUsageAgainstMatchGames() {
        let result = general(
            provider(
                row: evenRow(games: 2_000, timelineGames: 50),
                items: [
                    build(.boots, [3020], games: 1_500, wins: 750),  // 0.500
                    build(.boots, [3158], games: 150, wins: 100),  // 0.538, 7.5 % of games
                ]))

        #expect(
            result.loadout.itemSet?.blocks == [ItemSet.Block(title: "boots", items: [item(3020)])])
    }

    // MARK: Skill order (§18.9)

    @Test func skillOrderTakesTheMostPlayedOrderWithAGoodWinrate() {
        let result = general(
            provider(skills: [
                skill("QWE", games: 500, wins: 200),  // 0.450
                skill("QEW", "QEWQQRQQEEREEWWRWW", games: 300, wins: 160),  // 0.5125
                skill("EQW", games: 200, wins: 150),  // 0.571
            ]))

        #expect(
            result.loadout.skillOrder
                == SkillOrder(maxOrder: abilities("QEW"), sequence: abilities("QEWQQRQQEEREEWWRWW"))
        )
    }

    // MARK: Sample levels

    @Test func eachPartCarriesTheLevelOfItsChosenRow() {
        let result = general(
            provider(
                runes: [page(games: 900, wins: 450)],
                spells: [pair(4, 14, games: 300, wins: 150)],
                items: [
                    build(.start, [1056, 2003, 2003], games: 700, wins: 350),
                    build(.core, [6655, 4645, 3157], games: 150, wins: 75),
                ]))

        #expect(
            result.sampleLevels
                == LoadoutSampleLevels(
                    runes: .reliable, spells: .usable,
                    itemLayers: [.start: .reliable, .core: .usable], skillOrder: nil))
        #expect(result.sampleLevels.itemSet == .usable)
    }

    @Test func aChampionRoleBelowItsMinimumStillChoosesButMarksEveryPartBelowMinimum() {
        let result = general(
            provider(
                row: evenRow(games: 150, timelineGames: 150),
                runes: [page(games: 140, wins: 70)],
                spells: [pair(4, 14, games: 150, wins: 75)],
                items: [build(.start, [1056, 2003, 2003], games: 140, wins: 70)],
                skills: [skill("QWE", games: 140, wins: 70)]))

        #expect(result.loadout.runes == runePage())
        #expect(
            result.sampleLevels
                == LoadoutSampleLevels(
                    runes: .belowMinimum, spells: .belowMinimum,
                    itemLayers: [.start: .belowMinimum], skillOrder: .belowMinimum))
    }

    @Test func aKindMissingFromTheFileIsChosenButNotReliable() {
        let result = general(
            provider(
                meta: .example(thresholds: [:]), runes: [page(games: 1_900, wins: 950)]))

        #expect(result.loadout.runes == runePage())
        #expect(result.sampleLevels.runes == .usable)
    }

    // MARK: Missing data

    @Test func anEmptyProviderGivesAnEmptyLoadout() {
        let result = LoadoutSelection.general(
            for: ahri, role: .middle, stats: InMemoryStatsProvider())

        #expect(result == Self.empty)
    }

    @Test func noChampionRoleRowGivesAnEmptyLoadout() {
        let result = general(provider(row: nil, runes: [page(games: 1_900, wins: 950)]))

        #expect(result == Self.empty)
    }

    @Test func noSnapshotMetaGivesAnEmptyLoadout() {
        let result = general(provider(meta: nil, runes: [page(games: 1_900, wins: 950)]))

        #expect(result == Self.empty)
    }

    @Test func aPartWithoutCandidatesIsNilWhileTheOthersAreChosen() {
        let result = general(provider(runes: [page(games: 1_900, wins: 950)]))

        #expect(
            result.loadout
                == Loadout(runes: runePage(), spells: nil, itemSet: nil, skillOrder: nil))
        #expect(
            result.sampleLevels
                == LoadoutSampleLevels(
                    runes: .reliable, spells: nil, itemLayers: [:], skillOrder: nil))
        #expect(result.sampleLevels.itemSet == nil)
    }

    // MARK: Determinism

    @Test(arguments: [false, true])
    func anExactTieGoesToTheLowerContentRegardlessOfOrder(reversed: Bool) {
        let candidates = [
            page(keystone: 8128, games: 1_000, wins: 500),
            page(keystone: 8112, games: 1_000, wins: 500),
        ]

        let result = general(provider(runes: reversed ? candidates.reversed() : candidates))

        #expect(result.loadout.runes == runePage(keystone: 8112))
    }

    @Test(arguments: [false, true])
    func exactTiesInSpellsItemsAndSkillOrderGoToTheLowerContent(reversed: Bool) {
        func ordered<T>(_ values: [T]) -> [T] { reversed ? values.reversed() : values }

        let result = general(
            provider(
                spells: ordered([
                    pair(4, 14, games: 1_000, wins: 500), pair(4, 12, games: 1_000, wins: 500),
                ]),
                items: ordered([
                    build(.start, [1055], games: 500, wins: 250),
                    build(.start, [1054], games: 500, wins: 250),
                ]),
                skills: ordered([
                    skill("QEW", games: 500, wins: 250), skill("QWE", games: 500, wins: 250),
                ])))

        #expect(result.loadout.spells == spellPair(4, 12))
        #expect(result.loadout.itemSet?.blocks.first?.items == [item(1054)])
        #expect(result.loadout.skillOrder?.maxOrder == abilities("QWE"))
    }

    @Test func aWinrateTieGoesToTheMorePlayedOption() {
        let result = general(
            provider(runes: [
                page(keystone: 8112, games: 500, wins: 250),  // 0.500
                page(keystone: 8128, games: 1_000, wins: 500),  // 0.500
            ]))

        #expect(result.loadout.runes == runePage(keystone: 8128))
    }

    // MARK: End to end

    @Test func choosesEveryPartOfAGeneralLoadout() {
        let result = general(
            provider(
                runes: [
                    page(keystone: 8112, games: 1_500, wins: 750),
                    page(keystone: 8128, games: 400, wins: 240),
                ],
                spells: [
                    pair(4, 14, games: 1_400, wins: 750),
                    pair(4, 12, games: 500, wins: 240),
                ],
                items: [
                    build(.start, [1056, 2003, 2003], games: 900, wins: 470),
                    build(.core, [6655, 4645, 3157], games: 700, wins: 360),
                    build(.boots, [3020], games: 800, wins: 400),
                    build(.fourth, [3089], games: 400, wins: 210),
                ],
                skills: [skill("QWE", "QWEQQRQQWWRWWEEREE", games: 900, wins: 460)]))

        #expect(
            result
                == GeneralLoadout(
                    loadout: Loadout(
                        runes: runePage(keystone: 8128),
                        spells: spellPair(4, 14),
                        itemSet: ItemSet(blocks: [
                            ItemSet.Block(
                                title: "start", items: [item(1056), item(2003, count: 2)]),
                            ItemSet.Block(
                                title: "core", items: [item(6655), item(4645), item(3157)]),
                            ItemSet.Block(title: "boots", items: [item(3020)]),
                            ItemSet.Block(title: "fourth", items: [item(3089)]),
                        ]),
                        skillOrder: SkillOrder(
                            maxOrder: abilities("QWE"),
                            sequence: abilities("QWEQQRQQWWRWWEEREE"))),
                    sampleLevels: LoadoutSampleLevels(
                        runes: .usable, spells: .reliable,
                        itemLayers: [
                            .start: .reliable, .core: .reliable, .boots: .reliable,
                            .fourth: .usable,
                        ],
                        skillOrder: .reliable)))
    }

    private static let empty = GeneralLoadout(
        loadout: Loadout(runes: nil, spells: nil, itemSet: nil, skillOrder: nil),
        sampleLevels: LoadoutSampleLevels(
            runes: nil, spells: nil, itemLayers: [:], skillOrder: nil))
}
