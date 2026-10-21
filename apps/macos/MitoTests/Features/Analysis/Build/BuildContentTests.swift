import Foundation
import MitoAssets
import MitoCore
import MitoEngine
import MitoStore
import Testing

@testable import Mito

/// The Build tab's content follows the importer: Ahri MID's general loadout, adapted to Zed or a
/// heavy AD team, with the champion's override and the import settings applied (§20.2).
@Suite(.timeLimit(.minutes(1)))
struct BuildContentTests {
    typealias Stats = BuildTestStats

    // MARK: States

    @Test func withoutAChampionThereIsNothingToShow() {
        let content = derive(champion: nil)

        #expect(content.state == .noChampion)
    }

    @Test func aChampionWithoutStatsInAnyRoleHasNoData() {
        let content = derive(champion: ChampionID(rawValue: 1), role: nil)

        #expect(content.state == .noData)
        #expect(content.role == nil)
    }

    @Test func aramWithoutAFixedPageSaysThereIsNoBuild() {
        let content = derive(queue: .aram, role: nil)

        #expect(content.state == .aram([]))
    }

    @Test func aramShowsTheFixedPageOfTheChampionsOverride() {
        let personal = PersonalInputs(overrides: [
            ChampionOverride(
                champion: Stats.ahri, role: .middle, runeMode: .fixed, fixedPage: Stats.conqueror)
        ])
        let content = derive(queue: .aram, role: nil, personal: personal)

        guard case .aram(let parts) = content.state, let page = parts.first?.chosen.first else {
            Issue.record("Expected the fixed page, got \(content.state)")
            return
        }
        #expect(parts.map(\.id) == [.runes])
        #expect(parts.first?.source == .override)
        #expect(page.title == "Runa 8010")
        #expect(page.level == nil)
    }

    @Test func aramLeavesOutAPageSavedUnderAnotherMode() {
        // Saved under "adaptativo", the importer does not send it in ARAM.
        let personal = PersonalInputs(overrides: [
            ChampionOverride(champion: Stats.ahri, role: .middle, fixedPage: Stats.conqueror)
        ])

        #expect(derive(queue: .aram, role: nil, personal: personal).state == .aram([]))
    }

    // MARK: No snapshot

    @Test func withoutASnapshotTheRolesFixedChoicesShow() {
        let personal = PersonalInputs(overrides: [
            ChampionOverride(
                champion: Stats.ahri, role: .middle, runeMode: .fixed, fixedPage: Stats.conqueror,
                spellMode: .fixed, fixedSpells: nil)
        ])
        let content = derive(personal: personal, stats: ChampSelectModel.NoStats())

        guard case .fixed(let parts) = content.state else {
            Issue.record("Expected the fixed page, got \(content.state)")
            return
        }
        #expect(content.role == .middle)
        // The spells' fixed mode has nothing saved: nothing goes, so nothing shows.
        #expect(parts.map(\.id) == [.runes])
        #expect(parts.map(\.source) == [.override])
        #expect(parts.first?.chosen.first?.title == "Runa 8010")
    }

    @Test func withoutASnapshotOrAFixedChoiceTheTabHasNoStats() {
        let favorite = PersonalInputs(overrides: [
            ChampionOverride(champion: Stats.ahri, role: .middle, isFavorite: true)
        ])

        #expect(derive(stats: ChampSelectModel.NoStats()).state == .noSnapshot)
        #expect(
            derive(personal: favorite, stats: ChampSelectModel.NoStats()).state == .noSnapshot)
    }

    @Test func withoutASnapshotOrARoleTheTabHasNoStats() {
        let personal = PersonalInputs(overrides: [
            ChampionOverride(
                champion: Stats.ahri, role: .middle, runeMode: .fixed, fixedPage: Stats.conqueror)
        ])

        #expect(
            derive(role: nil, personal: personal, stats: ChampSelectModel.NoStats()).state
                == .noSnapshot)
    }

    @Test func aramShowsItsFixedChoicesWithoutASnapshot() {
        let personal = PersonalInputs(overrides: [
            ChampionOverride(
                champion: Stats.ahri, role: .middle, runeMode: .fixed, fixedPage: Stats.conqueror)
        ])
        let content = derive(
            queue: .aram, role: nil, personal: personal, stats: ChampSelectModel.NoStats())

        guard case .aram(let parts) = content.state else {
            Issue.record("Expected the fixed page, got \(content.state)")
            return
        }
        #expect(parts.map(\.id) == [.runes])
    }

    @Test func blindPickShowsTheSelectorsRoleOverTheMostPlayedOne() {
        let content = derive(role: nil, selectorRole: .top)

        #expect(content.role == .top)
    }

    // MARK: General and adapted

    @Test func withNothingToAdaptToTheBuildIsGeneral() throws {
        let content = derive()
        let runes = try part(.runes, in: content)

        #expect(content.role == .middle)
        #expect(content.opponent == nil)
        #expect(content.profiles.isEmpty)
        #expect(runes.source == .general)
        #expect(runes.chosen.map(\.id) == [Stats.id(of: Stats.electrocute)])
        #expect(runes.alternatives.map(\.id) == [Stats.id(of: Stats.phaseRush)])
        #expect(
            runes.chosen.first?.reasons == [
                Reason(
                    kind: .generalChoice(
                        part: .runes, usage: 0.75, winrate: 1_050.0 / 2_000, games: 1_500),
                    sample: nil)
            ])
        #expect(try part(.items(.core), in: content).chosen.isEmpty == false)
        #expect(try part(.skillOrder, in: content).isImported == false)
    }

    @Test func anAssignedLaneOpponentAdaptsTheRunesAsAFact() throws {
        let content = derive(enemies: [enemy(Stats.zed, .assigned(.middle))])
        let runes = try part(.runes, in: content)

        #expect(content.opponent == BuildContent.Opponent(name: "Campeón 238", isInferred: false))
        #expect(runes.source == .adaptedToOpponent)
        #expect(runes.chosen.map(\.id) == [Stats.id(of: Stats.phaseRush)])
        // Spells have no Zed rows: they stay general.
        #expect(try part(.spells, in: content).source == .general)
    }

    @Test func anInferredLaneOpponentIsMarkedAsInferred() {
        let content = derive(enemies: [enemy(Stats.zed, .inferred(.middle, probability: 0.9))])

        #expect(content.opponent == BuildContent.Opponent(name: "Campeón 238", isInferred: true))
    }

    @Test func aHeavyADEnemyTeamAdaptsToItsProfile() throws {
        let content = derive(enemies: [
            enemy(Stats.darius, .assigned(.top)), enemy(Stats.vi, .assigned(.jungle)),
            enemy(Stats.draven, .assigned(.bottom)),
        ])
        let runes = try part(.runes, in: content)

        #expect(content.opponent == nil)
        #expect(content.profiles == [.heavyAD])
        #expect(runes.source == .adaptedToProfiles([.heavyAD]))
        #expect(runes.chosen.map(\.id) == [Stats.id(of: Stats.conqueror)])
    }

    @Test func twoHealersInTheEnemyTeamAddTheirCounterAsASituationalItem() throws {
        let situational = try part(
            .situational,
            in: derive(enemies: [
                enemy(Stats.darius, .assigned(.top)), enemy(Stats.vi, .assigned(.jungle)),
            ]))

        #expect(situational.source == .situational)
        #expect(situational.chosen.map(\.id) == ["3033"])
        #expect(
            situational.chosen.first?.reasons == [
                Reason(
                    kind: .countersFlag(item: ItemID(rawValue: 3033), flag: .highHeal, enemies: 2),
                    sample: nil)
            ])
    }

    // MARK: Overrides and settings

    @Test func aFixedOverridePageIsShownWithoutStats() throws {
        let personal = PersonalInputs(overrides: [
            ChampionOverride(
                champion: Stats.ahri, role: .middle, runeMode: .fixed, fixedPage: Stats.conqueror)
        ])
        let runes = try part(.runes, in: derive(personal: personal))

        #expect(runes.source == .override)
        #expect(runes.chosen.map(\.id) == [Stats.id(of: Stats.conqueror)])
        #expect(runes.chosen.first?.level == nil)
        #expect(runes.alternatives.isEmpty)
    }

    @Test func aFixedModeWithNothingSavedFallsBackToTheGeneralPage() throws {
        let personal = PersonalInputs(overrides: [
            ChampionOverride(champion: Stats.ahri, role: .middle, runeMode: .fixed)
        ])
        let runes = try part(
            .runes,
            in: derive(enemies: [enemy(Stats.zed, .assigned(.middle))], personal: personal))

        #expect(runes.source == .generalWithoutFixed)
        #expect(runes.chosen.map(\.id) == [Stats.id(of: Stats.electrocute)])
    }

    @Test func anOverrideThatSkipsItemsShowsNoItemSet() throws {
        let personal = PersonalInputs(overrides: [
            ChampionOverride(champion: Stats.ahri, role: .middle, itemMode: .skip)
        ])
        let content = derive(personal: personal)

        #expect(try part(.skippedItems, in: content).source == .skippedByOverride)
        #expect(throws: (any Error).self) { try part(.items(.core), in: content) }
    }

    @Test func theGlobalGeneralRuneModeKeepsTheGeneralPageAgainstAnOpponent() throws {
        let runes = try part(
            .runes,
            in: derive(
                enemies: [enemy(Stats.zed, .assigned(.middle))],
                settings: ImportSettings(runeMode: .general)))

        #expect(runes.source == .general)
        #expect(runes.chosen.map(\.id) == [Stats.id(of: Stats.electrocute)])
    }

    @Test func aPartSwitchedOffInSettingsIsShownAsNotImported() throws {
        let content = derive(settings: ImportSettings(importRunes: false))

        #expect(try part(.runes, in: content).isImported == false)
        #expect(try part(.spells, in: content).isImported)
    }

    @Test func anOpponentAdaptationThatIsNotImportedIsNotAnnounced() throws {
        let content = derive(
            enemies: [enemy(Stats.zed, .assigned(.middle))],
            settings: ImportSettings(importRunes: false))

        #expect(try part(.runes, in: content).isImported == false)
        #expect(content.opponent == nil)
    }

    @Test func aProfileAdaptationThatIsNotImportedIsNotAnnounced() throws {
        let content = derive(
            enemies: [
                enemy(Stats.darius, .assigned(.top)), enemy(Stats.vi, .assigned(.jungle)),
                enemy(Stats.draven, .assigned(.bottom)),
            ],
            settings: ImportSettings(importRunes: false))

        #expect(try part(.runes, in: content).source == .adaptedToProfiles([.heavyAD]))
        #expect(content.profiles.isEmpty)
    }

    // MARK: Phrasing

    @Test(arguments: [
        (AnalysisSubject.Champion.Source.locked, false, BuildContent.Framing.imports),
        (.hovered, false, .importsOnLock),
        (.hovered, true, .imports),
        (.recommended, false, .ifYouPick),
    ])
    func theFramingFollowsHowTheChampionWasChosen(
        source: AnalysisSubject.Champion.Source, onHover: Bool, framing: BuildContent.Framing
    ) {
        let content = derive(
            champion: Stats.ahri, source: source, settings: ImportSettings(importOnHover: onHover))

        #expect(content.framing == framing)
    }

    // MARK: Names and samples

    @Test func withoutGameDataNamesFallBackToIDs() throws {
        let content = derive()

        #expect(content.champion == "Campeón 103")
        #expect(try part(.runes, in: content).chosen.first?.title == "Runa 8112")
        #expect(try part(.spells, in: content).chosen.first?.title == "Spell 4 + Spell 14")
        #expect(
            try part(.items(.boots), in: content).chosen.first?.title
                == ReasonNames.ids.item(ItemID(rawValue: 3020)))
    }

    @Test func gameDataNamesTheOptions() throws {
        let gameData = GameData(
            items: [
                Item(
                    id: ItemID(rawValue: 3020), name: "Botas del hechicero", totalGold: 1100,
                    iconPath: "", itemClass: nil)
            ],
            perks: [Perk(id: PerkID(rawValue: 8112), name: "Electrocutar", iconPath: "")],
            spells: [
                SummonerSpell(
                    id: SummonerSpellID(rawValue: 4), name: "Destello", iconPath: "", gameModes: []),
                SummonerSpell(
                    id: SummonerSpellID(rawValue: 14), name: "Prender", iconPath: "", gameModes: []),
            ])
        let content = derive(gameData: gameData)

        #expect(try part(.runes, in: content).chosen.first?.title == "Electrocutar")
        #expect(try part(.spells, in: content).chosen.first?.title == "Destello + Prender")
        #expect(
            try part(.items(.boots), in: content).chosen.first?.title == "Botas del hechicero")
    }

    @Test func eachOptionCarriesItsOwnSampleLevel() throws {
        let runes = try part(.runes, in: derive())

        #expect(runes.chosen.first?.level == .reliable)
        #expect(runes.alternatives.first?.level == .usable)
    }

    @Test func belowTheChampionRoleMinimumEveryOptionIsBelowMinimum() throws {
        let content = derive(champion: Stats.lux)

        #expect(try part(.runes, in: content).chosen.first?.level == .belowMinimum)
    }

    // MARK: Helpers

    private struct MissingPart: Error {}

    private func part(_ id: BuildPart.ID, in content: BuildContent) throws -> BuildPart {
        guard case .loadout(let parts) = content.state,
            let part = parts.first(where: { $0.id == id })
        else { throw MissingPart() }
        return part
    }

    private func enemy(_ champion: ChampionID, _ role: AnalysisSubject.SlotRole)
        -> AnalysisSubject.Slot
    {
        AnalysisSubject.Slot(
            id: 5 + champion.rawValue % 5, champion: champion, hover: nil, role: role, isMe: false)
    }

    private func derive(
        queue: QueueType = .rankedSolo,
        champion: ChampionID? = Stats.ahri,
        source: AnalysisSubject.Champion.Source = .locked,
        role: Role? = .middle,
        /// Blind pick: the selector's role, with no role assigned to you.
        selectorRole: Role? = nil,
        enemies: [AnalysisSubject.Slot] = [],
        personal: PersonalInputs = PersonalInputs(),
        gameData: GameData? = nil,
        settings: ImportSettings = ImportSettings(),
        stats: any StatsProvider = Stats()
    ) -> BuildContent {
        let me = AnalysisSubject.Slot(
            id: 2, champion: source == .locked ? champion : nil,
            hover: source == .hovered ? champion : nil, role: role.map { .assigned($0) },
            isMe: true)
        let subject = AnalysisSubject(
            queue: queue,
            champion: champion.map { AnalysisSubject.Champion(id: $0, source: source) },
            role: selectorRole ?? role, laneOpponent: nil, allies: [me], enemies: enemies,
            stats: stats, tips: .empty,
            personal: personal, names: .ids, gameData: gameData)
        return BuildContent.derive(subject, settings: settings)
    }
}

/// Ahri MID with a general loadout, Zed rows, and heavy AD rows; Lux MID under the minimum.
/// Smoothed winrates are `(wins + 250) / (games + 500)`: the rows sit at an even 50 %.
nonisolated struct BuildTestStats: StatsProvider {
    static let ahri = ChampionID(rawValue: 103)
    static let lux = ChampionID(rawValue: 99)
    static let zed = ChampionID(rawValue: 238)
    static let darius = ChampionID(rawValue: 122)
    static let vi = ChampionID(rawValue: 254)
    static let draven = ChampionID(rawValue: 119)

    static let electrocute = page(8112)
    static let phaseRush = page(8229)
    static let conqueror = page(8010)

    static func id(of page: RunePage) -> String {
        page.perks.map { "\($0.rawValue)" }.joined(separator: "-")
    }

    var meta: SnapshotMeta? {
        SnapshotMeta(
            patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420), bracket: .emeraldPlus,
            matches: 20_000, blendPatches: [Patch(rawValue: "16.21")],
            thresholds: [
                .championRole: SampleThreshold(minimum: 200, reliable: 1000),
                .matchup: SampleThreshold(minimum: 30, reliable: 300),
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
    }

    func roleGames(for champion: ChampionID) -> [Role: Int] {
        switch champion {
        case Self.ahri: [.middle: 2000]
        case Self.lux: [.middle: 150]
        case Self.zed: [.middle: 3000]
        default: [:]
        }
    }

    func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
        guard role == .middle else { return [:] }
        return [
            Self.ahri: ChampionRoleStats(games: 2000, wins: 1000, timelineGames: 1000),
            Self.lux: ChampionRoleStats(games: 150, wins: 75, timelineGames: 100),
        ]
    }

    func runePages(for champion: ChampionID, role: Role) -> [RunePageCandidate] {
        switch champion {
        case Self.ahri:
            [
                RunePageCandidate(page: Self.electrocute, games: 1500, wins: 800),
                RunePageCandidate(page: Self.phaseRush, games: 400, wins: 180),
            ]
        case Self.lux: [RunePageCandidate(page: Self.electrocute, games: 120, wins: 60)]
        default: []
        }
    }

    func spellPairs(for champion: ChampionID, role: Role) -> [SpellPairCandidate] {
        [
            SpellPairCandidate(
                spellA: SummonerSpellID(rawValue: 4), spellB: SummonerSpellID(rawValue: 14),
                games: 1800, wins: 950)
        ]
    }

    func itemBuilds(for champion: ChampionID, role: Role) -> [ItemBuildCandidate] {
        guard champion == Self.ahri else { return [] }
        return [
            ItemBuildCandidate(
                layer: .core, items: [6655, 3157].map(ItemID.init(rawValue:)), games: 500,
                wins: 260),
            ItemBuildCandidate(
                layer: .boots, items: [ItemID(rawValue: 3020)], games: 600, wins: 300),
        ]
    }

    func skillOrders(for champion: ChampionID, role: Role) -> [SkillOrderCandidate] {
        [
            SkillOrderCandidate(
                order: SkillOrder(maxOrder: [.q, .w, .e], sequence: [.q, .w, .e]), games: 700,
                wins: 360)
        ]
    }

    func matchup(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> MatchupStats?
    {
        guard champion == Self.ahri, opponent == Self.zed else { return nil }
        return MatchupStats(
            games: 1000, wins: 500, timelineGames: 500, goldDiffAt15: nil, csDiffAt15: nil)
    }

    func runePages(for champion: ChampionID, role: Role, against opponent: ChampionID)
        -> [RunePageCandidate]
    {
        guard champion == Self.ahri, opponent == Self.zed else { return [] }
        return [RunePageCandidate(page: Self.phaseRush, games: 300, wins: 200)]
    }

    func championProfile(for champion: ChampionID, role: Role) -> ChampionProfile? {
        ChampionProfile(
            physicalShare: 0.8, magicShare: 0.15, trueShare: 0.05, damagePerMinute: 500,
            tankiness: 0.5, ccScore: 0.2, timelineGames: 500)
    }

    func profileStats(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> RelationStats?
    {
        champion == Self.ahri && profile == .heavyAD ? RelationStats(games: 1000, wins: 500) : nil
    }

    func runePages(for champion: ChampionID, role: Role, against profile: EnemyProfile)
        -> [RunePageCandidate]
    {
        guard champion == Self.ahri, profile == .heavyAD else { return [] }
        return [RunePageCandidate(page: Self.conqueror, games: 400, wins: 260)]
    }

    func finalItems(for champion: ChampionID, role: Role) -> [FinalItemCandidate] {
        [FinalItemCandidate(item: ItemID(rawValue: 3033), games: 400, wins: 220)]
    }

    func flags(of champion: ChampionID) -> Set<ChampionFlag> {
        champion == Self.darius || champion == Self.vi ? [.highHeal] : []
    }

    func isAntiheal(_ item: ItemID) -> Bool { item == ItemID(rawValue: 3033) }

    private static func page(_ keystone: Int) -> RunePage {
        RunePage(
            primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8300),
            perks: [keystone, 8143, 8140, 8135, 8345, 8347, 5008, 5008, 5011]
                .map(PerkID.init(rawValue:)))
    }
}
