import MitoCore
import MitoEngine
import MitoTestSupport
import Testing

/// Smoothed winrates in the comments are `(wins + 250) / (games + 500)` (see `evenRow`); the
/// matchup has 1,000 games and 500 timeline games, each profile 1,000 games.
struct AdaptedLoadoutTests {
    private func adapted(
        _ stats: some StatsProvider, opponent: ChampionID? = zed, profiles: Set<EnemyProfile> = [],
        enemies: [ChampionID] = [], role: Role = .middle
    ) -> GeneralLoadout {
        LoadoutSelection.adapted(
            for: ahri, role: role, opponent: opponent, enemyProfile: profiles, enemies: enemies,
            stats: stats)
    }

    private func situational(_ items: ItemSet.Block.Item...) -> ItemSet.Block {
        ItemSet.Block(title: LoadoutSelection.situationalBlockTitle, items: items)
    }

    // MARK: Runes (§18.6)

    @Test func runesFollowTheOpponentPagesThatPassTheMinimum() {
        let result = adapted(
            provider(runes: [page(keystone: 8112, games: 1_500, wins: 750)])
                .versus(runes: [page(keystone: 8128, games: 300, wins: 180)]))

        #expect(result.loadout.runes == runePage(keystone: 8128))
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToOpponent(part: .runes, opponent: zed, games: 300),
                    sample: .usable)
            ])
        #expect(result.sampleLevels.runes == .usable)
    }

    @Test(arguments: [(150, 8128), (149, 8112)])
    func opponentRunesNeedFivePercentOfTheMatchupGames(games: Int, keystone: Int) {
        let result = adapted(
            provider(runes: [page(keystone: 8112, games: 1_500, wins: 750)])
                .versus(
                    matchup: lane(games: 3_000),
                    runes: [page(keystone: 8128, games: games, wins: games)]))

        #expect(result.loadout.runes == runePage(keystone: keystone))
    }

    @Test func opponentRunesUnderTheirMinimumBackOffToTheProfilePages() {
        let result = adapted(
            provider(runes: [page(keystone: 8112, games: 1_500, wins: 750)])
                .versus(runes: [page(keystone: 8128, games: 90, wins: 80)])
                .against(.heavyAD, runes: [page(keystone: 8010, games: 400, wins: 220)]),
            profiles: [.heavyAD])

        #expect(result.loadout.runes == runePage(keystone: 8010))
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToProfile(part: .runes, profile: .heavyAD, games: 400),
                    sample: .usable)
            ])
    }

    @Test func runesWithoutAPassingAdaptedPageAreTheGeneralPage() {
        let result = adapted(
            provider(runes: [page(keystone: 8112, games: 1_500, wins: 750)])
                .versus(runes: [page(keystone: 8128, games: 90, wins: 80)])
                .against(.heavyAD, runes: [page(keystone: 8010, games: 99, wins: 90)]),
            profiles: [.heavyAD])

        #expect(result.loadout.runes == runePage(keystone: 8112))
        #expect(result.loadout.explanation.isEmpty)
        #expect(result.sampleLevels.runes == .reliable)
    }

    @Test func activeProfilesArePooledBySample() {
        // Alone, heavy_ad would take 8128 (0.543 against 0.500). Pooled over 2,000 games: 8112
        // is 600/350 (0.545) and 8128 is 300/180 (0.5375).
        let result = adapted(
            provider()
                .against(
                    .heavyAD,
                    runes: [
                        page(keystone: 8112, games: 300, wins: 150),
                        page(keystone: 8128, games: 200, wins: 130),
                    ]
                )
                .against(
                    .heavyCC,
                    runes: [
                        page(keystone: 8112, games: 300, wins: 200),
                        page(keystone: 8128, games: 100, wins: 50),
                    ]),
            opponent: nil, profiles: [.heavyCC, .heavyAD])

        #expect(result.loadout.runes == runePage(keystone: 8112))
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToProfile(part: .runes, profile: .heavyAD, games: 300),
                    sample: .usable),
                Reason(
                    kind: .adaptedToProfile(part: .runes, profile: .heavyCC, games: 300),
                    sample: .usable),
            ])
        #expect(result.sampleLevels.runes == .usable)
    }

    @Test func aProfileWithoutChampVsProfileGamesIsSkipped() {
        let result = adapted(
            provider(runes: [page(keystone: 8112, games: 1_500, wins: 750)])
                .against(
                    .heavyAD, games: nil, runes: [page(keystone: 8010, games: 400, wins: 220)]),
            opponent: nil, profiles: [.heavyAD])

        #expect(result.loadout.runes == runePage(keystone: 8112))
    }

    // MARK: Spells (§18.8)

    @Test func spellsFollowTheOpponentPairsThatPassTheMinimum() {
        let result = adapted(
            provider(spells: [pair(4, 14, games: 1_400, wins: 700)])
                .versus(spells: [
                    pair(4, 14, games: 700, wins: 350),  // 0.500
                    pair(4, 12, games: 200, wins: 120),  // 0.529, 20 % of the matchup
                ]))

        #expect(result.loadout.spells == spellPair(4, 12))
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToOpponent(part: .spells, opponent: zed, games: 200),
                    sample: .usable)
            ])
        #expect(result.sampleLevels.spells == .usable)
    }

    @Test func opponentSpellsUnderTheMinimumFallBackToTheGeneralPair() {
        let result = adapted(
            provider(spells: [pair(4, 14, games: 1_400, wins: 700)])
                .versus(spells: [pair(4, 12, games: 90, wins: 80)]))

        #expect(result.loadout.spells == spellPair(4, 14))
        #expect(result.loadout.explanation.isEmpty)
    }

    @Test func aDominantOpponentPairWithoutFlashIsMeasuredAgainstTheMatchup() {
        // 600 games are 60 % of the matchup, but only 30 % of the champion's 2,000.
        let result = adapted(
            provider(spells: [pair(4, 14, games: 1_400, wins: 700)])
                .versus(spells: [
                    pair(6, 14, games: 600, wins: 400),  // 0.591
                    pair(4, 14, games: 400, wins: 200),  // 0.500
                ]))

        #expect(result.loadout.spells == spellPair(6, 14))
    }

    @Test func anOpponentPairWithoutSmiteBacksOffInTheJungle() {
        let result = adapted(
            provider(role: .jungle, spells: [pair(4, 11, games: 2_000, wins: 1_000)])
                .versus(role: .jungle, spells: [pair(4, 14, games: 600, wins: 400)]),
            role: .jungle)

        #expect(result.loadout.spells == spellPair(4, 11))
        #expect(result.loadout.explanation.isEmpty)
    }

    // MARK: Item layers (§18.7)

    @Test func startCoreAndBootsFollowTheOpponentRows() {
        let result = adapted(
            provider(items: [
                build(.start, [1056, 2003, 2003], games: 900, wins: 450),
                build(.core, [6655, 4645, 3089], games: 700, wins: 350),
                build(.boots, [3158], games: 800, wins: 400),
                build(.fourth, [3135], games: 400, wins: 200),
            ])
            .versus(items: [
                build(.start, [1055, 2003], games: 200, wins: 110),
                build(.core, [6655, 3157, 3089], games: 150, wins: 80),
                build(.boots, [3020], games: 300, wins: 150),
            ]))

        #expect(
            result.loadout.itemSet?.blocks.map(\.items) == [
                [item(1055), item(2003)], [item(6655), item(3157), item(3089)], [item(3020)],
                [item(3135)],
            ])
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToOpponent(part: .items(.start), opponent: zed, games: 200),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .items(.core), opponent: zed, games: 150),
                    sample: .usable),
                Reason(
                    kind: .adaptedToOpponent(part: .items(.boots), opponent: zed, games: 300),
                    sample: .usable),
            ])
        #expect(
            result.sampleLevels.itemLayers == [
                .start: .usable, .core: .usable, .boots: .usable, .fourth: .usable,
            ])
    }

    @Test func anOpponentLayerUnderTheMinimumBacksOffToTheGeneralLayer() {
        let result = adapted(
            provider(items: [build(.start, [1056, 2003, 2003], games: 900, wins: 450)])
                .versus(items: [build(.start, [1055, 2003], games: 90, wins: 80)]))

        #expect(
            result.loadout.itemSet?.blocks.map(\.items) == [[item(1056), item(2003, count: 2)]])
        #expect(result.loadout.explanation.isEmpty)
    }

    @Test func anOpponentLayerUnderTenPercentOfTheMatchupTimelineGamesBacksOff() {
        let result = adapted(
            provider(items: [build(.start, [1056, 2003, 2003], games: 900, wins: 450)])
                .versus(
                    matchup: lane(games: 4_000, timelineGames: 2_000),
                    items: [build(.start, [1055, 2003], games: 150, wins: 100)]))  // 7.5 %

        #expect(
            result.loadout.itemSet?.blocks.map(\.items) == [[item(1056), item(2003, count: 2)]])
    }

    @Test func aGeneralLayerNeverRepeatsAnItemOfTheOpponentCore() {
        let result = adapted(
            provider(items: [
                build(.core, [6655, 4645, 3089], games: 700, wins: 350),
                build(.fourth, [3157], games: 500, wins: 300),
                build(.fourth, [3135], games: 300, wins: 150),
            ])
            .versus(items: [build(.core, [6655, 3157, 3089], games: 150, wins: 80)]))

        #expect(result.loadout.itemSet?.blocks.last?.items == [item(3135)])
    }

    // MARK: Boots blend (§18.7)

    /// 3047 is bought in 25 % of heavy_ad games against 10 % overall, at 0.527 against 0.500.
    private let risingBoots = provider(items: [build(.boots, [3020], games: 800, wins: 400)])
        .baseline([final(3047, games: 200, wins: 100)])
        .against(.heavyAD, finalItems: [final(3047, games: 250, wins: 145)])

    @Test func bootsTakeTheProfileTierTwoBootsThatRiseAgainstTheBaseline() {
        let result = adapted(risingBoots, opponent: nil, profiles: [.heavyAD])

        #expect(
            result.loadout.itemSet?.blocks == [ItemSet.Block(title: "boots", items: [item(3047)])])
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToProfile(part: .items(.boots), profile: .heavyAD, games: 250),
                    sample: .usable)
            ])
        #expect(result.sampleLevels.itemLayers == [.boots: .usable])
    }

    @Test func opponentBootsWinOverProfileBoots() {
        let result = adapted(
            risingBoots.versus(items: [build(.boots, [3158], games: 300, wins: 150)]),
            profiles: [.heavyAD])

        #expect(result.loadout.itemSet?.blocks.map(\.items) == [[item(3158)]])
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .adaptedToOpponent(part: .items(.boots), opponent: zed, games: 300),
                    sample: .usable)
            ])
    }

    @Test func profileBootsThatDoNotRiseClearlyKeepTheGeneralBoots() {
        let result = adapted(
            provider(items: [build(.boots, [3020], games: 800, wins: 400)])
                .baseline([final(3047, games: 200, wins: 100)])
                .against(.heavyAD, finalItems: [final(3047, games: 149, wins: 90)]),  // 1.49×
            opponent: nil, profiles: [.heavyAD])

        #expect(result.loadout.itemSet?.blocks.map(\.items) == [[item(3020)]])
        #expect(result.loadout.explanation.isEmpty)
    }

    @Test func otherRisingBootsNeverJoinTheSituationalBlock() {
        let result = adapted(
            risingBoots
                .baseline([final(3047, games: 200, wins: 100), final(3111, games: 100, wins: 50)])
                .against(
                    .heavyAD,
                    finalItems: [
                        final(3047, games: 250, wins: 145),  // 2.5×
                        final(3111, games: 120, wins: 70),  // 2.4×
                    ]),
            opponent: nil, profiles: [.heavyAD])

        #expect(result.loadout.itemSet?.blocks.map(\.items) == [[item(3047)]])
    }

    @Test func bootsAreWhateverItemClassesCallsTierTwoBoots() {
        let result = adapted(
            provider(
                items: [build(.boots, [3020], games: 800, wins: 400)],
                itemClasses: [ItemID(rawValue: 9001): .bootsT2]
            )
            .baseline([final(9001, games: 200, wins: 100)])
            .against(.heavyAD, finalItems: [final(9001, games: 250, wins: 145)]),
            opponent: nil, profiles: [.heavyAD])

        #expect(result.loadout.itemSet?.blocks.map(\.items) == [[item(9001)]])
    }

    @Test(arguments: [nil, ItemClass.bootsT1, .legendary, .unknown("boots_t3")])
    func risingItemsOutsideTheTierTwoBootsClassAreSituational(itemClass: ItemClass?) {
        let result = adapted(
            provider(
                items: [build(.boots, [3020], games: 800, wins: 400)],
                itemClasses: itemClass.map { [ItemID(rawValue: 3047): $0] } ?? [:]
            )
            .baseline([final(3047, games: 200, wins: 100)])
            .against(.heavyAD, finalItems: [final(3047, games: 250, wins: 145)]),
            opponent: nil, profiles: [.heavyAD])

        #expect(
            result.loadout.itemSet?.blocks == [
                ItemSet.Block(title: "boots", items: [item(3020)]), situational(item(3047)),
            ])
    }

    // MARK: Situational items (§18.7)

    /// Zhonya's (3157) in 10 % of all 2,000 games at 0.500.
    private func zhonya(games: Int, wins: Int, baselineGames: Int = 200, profileGames: Int = 1_000)
        -> GeneralLoadout
    {
        adapted(
            provider()
                .baseline([final(3157, games: baselineGames, wins: baselineGames / 2)])
                .against(
                    .heavyAD, games: profileGames,
                    finalItems: [final(3157, games: games, wins: wins)]),
            opponent: nil, profiles: [.heavyAD])
    }

    @Test(arguments: [(150, true), (149, false)])
    func aSituationalItemNeedsOneAndAHalfTimesTheBaselineBuyRate(games: Int, isChosen: Bool) {
        let result = zhonya(games: games, wins: 90)

        #expect((result.loadout.itemSet?.blocks == [situational(item(3157))]) == isChosen)
    }

    @Test(arguments: [(150, false), (151, true)])
    func aSituationalItemNeedsAHigherSmoothedWinrate(wins: Int, isChosen: Bool) {
        let result = zhonya(games: 300, wins: wins)  // 150 wins is 0.500, the baseline's

        #expect((result.loadout.itemSet?.blocks == [situational(item(3157))]) == isChosen)
    }

    @Test(arguments: [(99, false), (100, true)])
    func aSituationalItemNeedsTenPercentOfTheProfileGames(games: Int, isChosen: Bool) {
        let result = zhonya(games: games, wins: 60, baselineGames: 30)

        #expect((result.loadout.itemSet?.blocks == [situational(item(3157))]) == isChosen)
    }

    @Test(arguments: [(49, false), (50, true)])
    func aSituationalItemNeedsTheItemVsProfileMinimum(games: Int, isChosen: Bool) {
        let result = zhonya(games: games, wins: 30, baselineGames: 0, profileGames: 400)

        #expect((result.loadout.itemSet?.blocks == [situational(item(3157))]) == isChosen)
    }

    @Test func aSituationalReasonCarriesBothBuyRatesTheWinrateDeltaAndTheSample() {
        let result = zhonya(games: 250, wins: 150)

        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .situationalItem(
                        item: ItemID(rawValue: 3157), profile: .heavyAD, buyRate: 0.25,
                        baselineBuyRate: 0.1, winrateDelta: 400.0 / 750.0 - 0.5),
                    sample: .usable)
            ])
    }

    @Test func situationalItemsGoFromTheStrongestLift() {
        let result = adapted(
            provider()
                .baseline([final(3157, games: 200, wins: 100), final(3135, games: 200, wins: 100)])
                .against(
                    .heavyAD,
                    finalItems: [
                        final(3157, games: 250, wins: 150),  // 2.5×
                        final(3135, games: 300, wins: 170),  // 3×
                    ]),
            opponent: nil, profiles: [.heavyAD])

        #expect(result.loadout.itemSet?.blocks == [situational(item(3135), item(3157))])
    }

    @Test func anItemRisingAgainstTwoProfilesAppearsOnceUnderTheStrongerLift() {
        let result = adapted(
            provider()
                .baseline([final(3157, games: 200, wins: 100)])
                .against(.heavyAD, finalItems: [final(3157, games: 250, wins: 150)])  // 2.5×
                .against(.heavyCC, finalItems: [final(3157, games: 300, wins: 170)]),  // 3×
            opponent: nil, profiles: [.heavyAD, .heavyCC])

        #expect(result.loadout.itemSet?.blocks == [situational(item(3157))])
        #expect(
            result.loadout.explanation.map(\.kind) == [
                .situationalItem(
                    item: ItemID(rawValue: 3157), profile: .heavyCC, buyRate: 0.3,
                    baselineBuyRate: 0.1, winrateDelta: 420.0 / 800.0 - 0.5)
            ])
    }

    @Test func aSituationalItemAlreadyInTheBuildIsNotRepeated() {
        let result = adapted(
            provider(items: [build(.core, [6655, 3157, 3089], games: 700, wins: 350)])
                .baseline([final(3157, games: 200, wins: 100)])
                .against(.heavyAD, finalItems: [final(3157, games: 250, wins: 150)]),
            opponent: nil, profiles: [.heavyAD])

        #expect(
            result.loadout.itemSet?.blocks.map(\.items) == [[item(6655), item(3157), item(3089)]])
        #expect(result.loadout.explanation.isEmpty)
    }

    // MARK: Flag counters (§18.7)

    private let soraka = ChampionID(rawValue: 16)
    private let darius = ChampionID(rawValue: 122)

    private func healers(_ stats: InMemoryStatsProvider = provider()) -> InMemoryStatsProvider {
        stats.baseline([final(3165, games: 300, wins: 150), final(3033, games: 100, wins: 50)])
            .flagged([soraka: [.highHeal], darius: [.highHeal]])
    }

    @Test func antihealJoinsTheSetAgainstTwoHighHealEnemies() {
        let result = adapted(healers(), opponent: nil, enemies: [soraka, darius, zed])

        #expect(result.loadout.itemSet?.blocks == [situational(item(3165))])
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .countersFlag(item: ItemID(rawValue: 3165), flag: .highHeal, enemies: 2),
                    sample: nil)
            ])
    }

    @Test func oneHighHealEnemyAddsNoAntiheal() {
        let result = adapted(healers(), opponent: nil, enemies: [soraka, zed])

        #expect(result.loadout.itemSet == nil)
        #expect(result.loadout.explanation.isEmpty)
    }

    @Test func anAntihealItemAlreadyInTheBuildAddsNothing() {
        let result = adapted(
            healers(provider(items: [build(.core, [6655, 3033, 3089], games: 700, wins: 350)])),
            opponent: nil, enemies: [soraka, darius])

        #expect(
            result.loadout.itemSet?.blocks.map(\.items) == [[item(6655), item(3033), item(3089)]])
    }

    @Test func anAntihealItemTheChampionRarelyFinishesIsNotRecommended() {
        let result = adapted(
            provider().baseline([final(3165, games: 49, wins: 25)])
                .flagged([soraka: [.highHeal], darius: [.highHeal]]),
            opponent: nil, enemies: [soraka, darius])

        #expect(result.loadout.itemSet == nil)
    }

    @Test func antihealIsWhateverItemClassesMarksAntiheal() {
        let result = adapted(
            provider(antiheal: [ItemID(rawValue: 9002)])
                .baseline([final(3165, games: 300, wins: 150), final(9002, games: 100, wins: 50)])
                .flagged([soraka: [.highHeal], darius: [.highHeal]]),
            opponent: nil, enemies: [soraka, darius])

        #expect(result.loadout.itemSet?.blocks == [situational(item(9002))])
    }

    @Test func anItemNotMarkedAntihealNeverCountersHealers() {
        let result = adapted(
            healers(provider(itemClasses: [:], antiheal: [])), opponent: nil,
            enemies: [soraka, darius])

        #expect(result.loadout.itemSet == nil)
        #expect(result.loadout.explanation.isEmpty)
    }

    @Test func anyAntihealItemInTheBuildSatisfiesTheRule() {
        // Thornmail (3075) is not the one Ahri finishes most, but it is antiheal.
        let result = adapted(
            healers(provider(items: [build(.fourth, [3075], games: 500, wins: 250)])),
            opponent: nil, enemies: [soraka, darius])

        #expect(result.loadout.itemSet?.blocks.map(\.items) == [[item(3075)]])
    }

    @Test func bansheeJoinsTheSetAgainstTwoPointAndClickCCEnemies() {
        let lissandra = ChampionID(rawValue: 127)
        let malzahar = ChampionID(rawValue: 90)

        let result = adapted(
            provider().baseline([final(3102, games: 100, wins: 50)])
                .flagged([lissandra: [.pointClickCC], malzahar: [.pointClickCC]]),
            opponent: nil, enemies: [lissandra, malzahar])

        #expect(result.loadout.itemSet?.blocks == [situational(item(3102))])
        #expect(
            result.loadout.explanation == [
                Reason(
                    kind: .countersFlag(
                        item: ItemID(rawValue: 3102), flag: .pointClickCC, enemies: 2),
                    sample: nil)
            ])
    }

    @Test func onlyBansheeCountersPointAndClickCCWhateverItsClass() {
        let lissandra = ChampionID(rawValue: 127)
        let malzahar = ChampionID(rawValue: 90)

        // Edge of Night (3814) is unclassified here and Banshee's Veil is a legendary: the rule
        // names the item, not a class.
        let result = adapted(
            provider(itemClasses: [ItemID(rawValue: 3102): .legendary])
                .baseline([final(3814, games: 300, wins: 150), final(3102, games: 100, wins: 50)])
                .flagged([lissandra: [.pointClickCC], malzahar: [.pointClickCC]]),
            opponent: nil, enemies: [lissandra, malzahar])

        #expect(result.loadout.itemSet?.blocks == [situational(item(3102))])
    }

    @Test func aBansheeAlreadyInTheBuildAddsNothing() {
        let lissandra = ChampionID(rawValue: 127)
        let malzahar = ChampionID(rawValue: 90)

        let result = adapted(
            provider(items: [build(.fourth, [3102], games: 500, wins: 250)])
                .baseline([final(3102, games: 100, wins: 50)])
                .flagged([lissandra: [.pointClickCC], malzahar: [.pointClickCC]]),
            opponent: nil, enemies: [lissandra, malzahar])

        #expect(result.loadout.itemSet?.blocks.map(\.items) == [[item(3102)]])
        #expect(result.loadout.explanation.isEmpty)
    }

    // MARK: Explanation and samples

    @Test func reasonsFollowThePartsWithFlagCountersBeforeSituationalItems() {
        let result = adapted(
            healers(provider(runes: [page(keystone: 8112, games: 1_500, wins: 750)]))
                .baseline([
                    final(3165, games: 300, wins: 150), final(3157, games: 200, wins: 100),
                ])
                .against(.heavyAD, finalItems: [final(3157, games: 250, wins: 150)])
                .versus(
                    runes: [page(keystone: 8128, games: 300, wins: 180)],
                    spells: [pair(4, 14, games: 900, wins: 450)],
                    items: [build(.start, [1055, 2003], games: 200, wins: 110)]),
            profiles: [.heavyAD], enemies: [soraka, darius])

        #expect(
            result.loadout.explanation.map(\.kind) == [
                .adaptedToOpponent(part: .runes, opponent: zed, games: 300),
                .adaptedToOpponent(part: .spells, opponent: zed, games: 900),
                .adaptedToOpponent(part: .items(.start), opponent: zed, games: 200),
                .countersFlag(item: ItemID(rawValue: 3165), flag: .highHeal, enemies: 2),
                .situationalItem(
                    item: ItemID(rawValue: 3157), profile: .heavyAD, buyRate: 0.25,
                    baselineBuyRate: 0.1, winrateDelta: 400.0 / 750.0 - 0.5),
            ])
        #expect(result.loadout.itemSet?.blocks.last == situational(item(3165), item(3157)))
        #expect(result.sampleLevels.spells == .reliable)
    }

    @Test func aChampionRoleBelowItsMinimumMarksAdaptedPartsAndTheirReasonsBelowMinimum() {
        let result = adapted(
            provider(row: evenRow(games: 150, timelineGames: 150))
                .versus(runes: [page(keystone: 8128, games: 300, wins: 180)]))

        #expect(result.loadout.runes == runePage(keystone: 8128))
        #expect(result.sampleLevels.runes == .belowMinimum)
        #expect(result.loadout.explanation.map(\.sample) == [.belowMinimum])
    }

    // MARK: Fallback to the general loadout

    private let general = provider(
        runes: [
            page(keystone: 8112, games: 1_500, wins: 750),
            page(keystone: 8128, games: 400, wins: 240),
        ],
        spells: [pair(4, 14, games: 1_400, wins: 750), pair(4, 12, games: 500, wins: 240)],
        items: [
            build(.start, [1056, 2003, 2003], games: 900, wins: 470),
            build(.core, [6655, 4645, 3157], games: 700, wins: 360),
            build(.boots, [3020], games: 800, wins: 400),
            build(.fourth, [3089], games: 400, wins: 210),
        ],
        skills: [skill("QWE", "QWEQQRQQWWRWWEEREE", games: 900, wins: 460)])

    @Test func withNothingToAdaptToTheLoadoutIsTheGeneralOne() {
        let stats = general.versus(runes: [page(keystone: 8010, games: 900, wins: 600)])

        #expect(
            adapted(stats, opponent: nil)
                == LoadoutSelection.general(for: ahri, role: .middle, stats: stats))
    }

    @Test func anOpponentWithoutMatchupStatsIsIgnored() {
        let stats = general.versus(
            matchup: nil, runes: [page(keystone: 8010, games: 900, wins: 600)])

        #expect(adapted(stats) == LoadoutSelection.general(for: ahri, role: .middle, stats: stats))
    }

    @Test func theSkillOrderStaysGeneralWhenEverythingElseAdapts() {
        let result = adapted(
            general.versus(runes: [page(keystone: 8010, games: 900, wins: 600)]))

        #expect(result.loadout.runes == runePage(keystone: 8010))
        #expect(
            result.loadout.skillOrder
                == SkillOrder(maxOrder: abilities("QWE"), sequence: abilities("QWEQQRQQWWRWWEEREE"))
        )
        #expect(result.sampleLevels.skillOrder == .reliable)
    }

    @Test func anEmptyProviderGivesAnEmptyLoadout() {
        let result = adapted(InMemoryStatsProvider(), profiles: [.heavyAD], enemies: [zed])

        #expect(result.loadout == Loadout(runes: nil, spells: nil, itemSet: nil, skillOrder: nil))
        #expect(result.sampleLevels.itemLayers.isEmpty)
    }
}
