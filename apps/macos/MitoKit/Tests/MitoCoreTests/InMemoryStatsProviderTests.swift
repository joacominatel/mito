import MitoCore
import MitoTestSupport
import Testing

/// Phase 7 rows are Ahri (103) MIDDLE in `fixtures/snapshot/emerald_plus.sqlite`.
struct InMemoryStatsProviderTests {
    private let ahri = ChampionID(rawValue: 103)
    private let zed = ChampionID(rawValue: 238)
    private let leeSin = ChampionID(rawValue: 64)

    @Test func servesTheGivenRoleGames() {
        let stats = InMemoryStatsProvider(roleGamesByChampion: [ahri: [.middle: 900, .top: 12]])
        #expect(stats.roleGames(for: ahri) == [.middle: 900, .top: 12])
    }

    @Test func aChampionWithoutRowsHasNoRoleGames() {
        #expect(InMemoryStatsProvider().roleGames(for: ChampionID(rawValue: 950)).isEmpty)
    }

    @Test func servesTheGivenMeta() {
        let meta = SnapshotMeta(
            patch: Patch(rawValue: "16.21"),
            queue: QueueID(rawValue: 420),
            bracket: .emeraldPlus,
            matches: 20_000,
            blendPatches: [Patch(rawValue: "16.21")],
            thresholds: [.championRole: SampleThreshold(minimum: 200, reliable: 1_000)],
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                loadoutStrength: 500),
            tierCutoffs: [.s: 0.53, .a: 0.515, .b: 0.5, .c: 0.485])
        #expect(InMemoryStatsProvider(meta: meta).meta == meta)
    }

    @Test func servesChampionRoleStatsOnlyForTheirRole() {
        let row = ChampionRoleStats(games: 1_933, wins: 1_053, timelineGames: 483)
        let stats = InMemoryStatsProvider(championRoleStatsByRole: [.middle: [ahri: row]])
        #expect(stats.championRoleStats(in: .middle) == [ahri: row])
        #expect(stats.championRoleStats(in: .top).isEmpty)
    }

    @Test func servesLoadoutCandidatesOnlyForTheirChampionAndRole() {
        let page = RunePageCandidate(
            page: RunePage(
                primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8200),
                perks: [8112, 8143, 8138, 8135, 8226, 8237, 5008, 5008, 5011].map(PerkID.init)),
            games: 484, wins: 222)
        let spells = SpellPairCandidate(
            spellA: SummonerSpellID(rawValue: 4), spellB: SummonerSpellID(rawValue: 14),
            games: 627, wins: 294)
        let build = ItemBuildCandidate(
            layer: .core, items: [3031, 3046, 3094].map(ItemID.init), games: 426, wins: 208)
        let skills = SkillOrderCandidate(
            order: SkillOrder(maxOrder: [.q, .w, .e], sequence: [.q, .w, .e, .q]),
            games: 336, wins: 154)
        let stats = InMemoryStatsProvider(
            runePagesByChampion: [ahri: [.middle: [page]]],
            spellPairsByChampion: [ahri: [.middle: [spells]]],
            itemBuildsByChampion: [ahri: [.middle: [build]]],
            skillOrdersByChampion: [ahri: [.middle: [skills]]])

        #expect(stats.runePages(for: ahri, role: .middle) == [page])
        #expect(stats.spellPairs(for: ahri, role: .middle) == [spells])
        #expect(stats.itemBuilds(for: ahri, role: .middle) == [build])
        #expect(stats.skillOrders(for: ahri, role: .middle) == [skills])
        #expect(stats.runePages(for: ahri, role: .top).isEmpty)
        #expect(stats.itemBuilds(for: ChampionID(rawValue: 238), role: .middle).isEmpty)
    }

    @Test func servesAMatchupOnlyAgainstItsOpponent() {
        let row = MatchupStats(
            games: 497, wins: 237, timelineGames: 124, goldDiffAt15: -309.3, csDiffAt15: -5.9)
        let stats = InMemoryStatsProvider(matchupsByChampion: [ahri: [.middle: [zed: row]]])
        #expect(stats.matchup(for: ahri, role: .middle, against: zed) == row)
        #expect(stats.matchup(for: ahri, role: .middle, against: leeSin) == nil)
        #expect(stats.matchup(for: ahri, role: .top, against: zed) == nil)
    }

    @Test func servesASynergyOnlyForTheAllyInItsRole() {
        let row = RelationStats(games: 247, wins: 132)
        let stats = InMemoryStatsProvider(
            synergiesByChampion: [ahri: [.middle: [leeSin: [.jungle: row]]]])
        #expect(stats.synergy(for: ahri, role: .middle, with: leeSin, allyRole: .jungle) == row)
        #expect(stats.synergy(for: ahri, role: .middle, with: leeSin, allyRole: .top) == nil)
    }

    @Test func servesVersusTeamOnlyAgainstItsEnemy() {
        let row = RelationStats(games: 661, wins: 307)
        let stats = InMemoryStatsProvider(versusTeamByChampion: [ahri: [.middle: [zed: row]]])
        #expect(stats.versusTeam(for: ahri, role: .middle, against: zed) == row)
        #expect(stats.versusTeam(for: ahri, role: .middle, against: leeSin) == nil)
    }

    @Test func servesTheChampionProfileOfItsRole() {
        let profile = ChampionProfile(
            physicalShare: 0.157, magicShare: 0.834, trueShare: 0.009, damagePerMinute: 771.2,
            tankiness: 0.333, ccScore: 0.333, timelineGames: 706, goldDiffAt15: 163.1,
            levelSixSeconds: 367, firstItemSeconds: 636, secondItemSeconds: 1025,
            thirdItemSeconds: 1322)
        let stats = InMemoryStatsProvider(championProfilesByChampion: [ahri: [.middle: profile]])
        #expect(stats.championProfile(for: ahri, role: .middle) == profile)
        #expect(stats.championProfile(for: ahri, role: .top) == nil)
    }

    @Test func servesProfileStatsOnlyForTheirProfile() {
        let row = RelationStats(games: 614, wins: 306)
        let stats = InMemoryStatsProvider(
            profileStatsByChampion: [ahri: [.middle: [.heavyAD: row]]])
        #expect(stats.profileStats(for: ahri, role: .middle, against: .heavyAD) == row)
        #expect(stats.profileStats(for: ahri, role: .middle, against: .heavyAP) == nil)
    }

    @Test func servesPerOpponentLoadoutsApartFromTheGeneralOnes() {
        let page = RunePageCandidate(
            page: RunePage(
                primaryStyle: PerkStyleID(rawValue: 8200), subStyle: PerkStyleID(rawValue: 8300),
                perks: [8229, 8226, 8210, 8237, 8304, 8347, 5007, 5008, 5011].map(PerkID.init)),
            games: 198, wins: 107)
        let spells = SpellPairCandidate(
            spellA: SummonerSpellID(rawValue: 4), spellB: SummonerSpellID(rawValue: 14),
            games: 248, wins: 121)
        let build = ItemBuildCandidate(
            layer: .start, items: [1056, 2003, 2003].map(ItemID.init), games: 124, wins: 63)
        let stats = InMemoryStatsProvider(
            opponentRunePagesByChampion: [ahri: [.middle: [zed: [page]]]],
            opponentSpellPairsByChampion: [ahri: [.middle: [zed: [spells]]]],
            opponentItemBuildsByChampion: [ahri: [.middle: [zed: [build]]]])

        #expect(stats.runePages(for: ahri, role: .middle, against: zed) == [page])
        #expect(stats.spellPairs(for: ahri, role: .middle, against: zed) == [spells])
        #expect(stats.itemBuilds(for: ahri, role: .middle, against: zed) == [build])
        #expect(stats.runePages(for: ahri, role: .middle).isEmpty)
        #expect(stats.itemBuilds(for: ahri, role: .middle, against: leeSin).isEmpty)
    }

    @Test func servesProfileRunePagesOnlyForTheirProfile() {
        let page = RunePageCandidate(
            page: RunePage(
                primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8300),
                perks: [8112, 8143, 8140, 8135, 8345, 8347, 5008, 5008, 5011].map(PerkID.init)),
            games: 449, wins: 235)
        let stats = InMemoryStatsProvider(
            profileRunePagesByChampion: [ahri: [.middle: [.heavyAD: [page]]]])
        #expect(stats.runePages(for: ahri, role: .middle, against: .heavyAD) == [page])
        #expect(stats.runePages(for: ahri, role: .middle, against: .mixed).isEmpty)
    }

    @Test func servesTheFinalItemBaselineApartFromEachProfile() {
        let luden = ItemID(rawValue: 3157)
        let baseline = FinalItemCandidate(item: luden, games: 226, wins: 103)
        let heavyAD = FinalItemCandidate(item: luden, games: 123, wins: 63)
        let stats = InMemoryStatsProvider(
            baselineFinalItemsByChampion: [ahri: [.middle: [baseline]]],
            profileFinalItemsByChampion: [ahri: [.middle: [.heavyAD: [heavyAD]]]])
        #expect(stats.finalItems(for: ahri, role: .middle) == [baseline])
        #expect(stats.finalItems(for: ahri, role: .middle, against: .heavyAD) == [heavyAD])
        #expect(stats.finalItems(for: ahri, role: .middle, against: .heavyAP).isEmpty)
    }

    @Test func servesBansAndFlagsPerChampion() {
        let soraka = ChampionID(rawValue: 16)
        let stats = InMemoryStatsProvider(
            bansByChampion: [soraka: 2_061], flagsByChampion: [soraka: [.highHeal]])
        #expect(stats.bans(of: soraka) == 2_061)
        #expect(stats.flags(of: soraka) == [.highHeal])
        #expect(stats.bans(of: ahri) == nil)
        #expect(stats.flags(of: ahri).isEmpty)
    }

    @Test func servesDurationCurvesOnlyForTheirChampionAndRole() {
        let curve: [DurationBucket: RelationStats] = [
            .under20: RelationStats(games: 717, wins: 355),
            .over40: RelationStats(games: 566, wins: 309),
        ]
        let stats = InMemoryStatsProvider(durationCurvesByChampion: [ahri: [.middle: curve]])
        #expect(stats.durationCurves(for: ahri, role: .middle) == curve)
        #expect(stats.durationCurves(for: ahri, role: .top).isEmpty)
        #expect(stats.durationCurves(for: zed, role: .middle).isEmpty)
    }

    @Test func servesItemClassesAndAntihealApart() {
        let morello = ItemID(rawValue: 3165)
        let tabis = ItemID(rawValue: 3047)
        let stats = InMemoryStatsProvider(
            itemClasses: [morello: .legendary, tabis: .bootsT2], antihealItems: [morello])
        #expect(stats.itemClass(of: tabis) == .bootsT2)
        #expect(stats.itemClass(of: ItemID(rawValue: 1001)) == nil)
        #expect(stats.isAntiheal(morello))
        #expect(!stats.isAntiheal(tabis))
    }
}
