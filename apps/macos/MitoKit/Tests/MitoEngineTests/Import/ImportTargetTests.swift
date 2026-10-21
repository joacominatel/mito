import MitoCore
import MitoEngine
import MitoTestSupport
import Testing

/// One decision for the importer and the Build tab: role, lane opponent, profile, override, and
/// plan (§13.1, §20.2, §20.3).
struct ImportTargetTests {
    private let zed = ChampionID(rawValue: 238)
    private let electrocute = runePage(keystone: 8112)
    private let fixedPage = runePage(keystone: 8010)
    private let fixedSpells = spellPair(12, 4)

    /// Ahri with an Electrocute page in MIDDLE and TOP, most played in TOP.
    private var stats: InMemoryStatsProvider {
        var stats = provider(
            row: evenRow(), runes: [page(keystone: 8112, games: 1_000, wins: 500)])
        stats.championRoleStatsByRole[.top] = [ahri: evenRow()]
        stats.runePagesByChampion[ahri]?[.top] = [page(keystone: 8112, games: 1_000, wins: 500)]
        stats.roleGamesByChampion = [ahri: [.top: 3_000, .middle: 2_000], zed: [.middle: 900]]
        return stats
    }

    private func decide(
        queue: QueueType = .normalBlind, role: Role?, enemies: [DraftSlot] = [],
        overrides: [ChampionOverride] = [], settings: ImportSettings = ImportSettings()
    ) -> ImportTarget? {
        ImportTarget.decide(
            for: ahri, queue: queue, role: role, enemies: enemies, stats: stats,
            overrides: overrides, settings: settings)
    }

    private func enemy(_ champion: ChampionID, _ role: Role? = nil) -> DraftSlot {
        DraftSlot(
            cellId: 5, champion: champion, hover: nil, role: role,
            roleConfidence: role == nil ? 0 : 1)
    }

    // MARK: Role

    @Test func theSelectorsRoleBeatsTheMostPlayedOne() {
        let target = decide(role: .middle)

        #expect(target?.role == .middle)
        #expect(target?.plan.loadout.runes == electrocute)
    }

    @Test func withoutASelectorRoleTheMostPlayedOneGoes() {
        #expect(decide(role: nil)?.role == .top)
    }

    @Test func noRoleWithDataDecidesNothing() {
        let target = ImportTarget.decide(
            for: ChampionID(rawValue: 1), queue: .normalBlind, role: nil, enemies: [],
            stats: stats, overrides: [], settings: ImportSettings())

        #expect(target == nil)
    }

    @Test func theOverrideIsTheOneOfTheRole() {
        let top = ChampionOverride(
            champion: ahri, role: .top, runeMode: .fixed, fixedPage: fixedPage)

        #expect(decide(role: .middle, overrides: [top])?.override == nil)
        #expect(decide(role: .top, overrides: [top])?.plan.loadout.runes == fixedPage)
    }

    // MARK: Lane opponent

    @Test func anAssignedOpponentIsAFactAndAnInferredOneAGuess() {
        #expect(
            decide(role: .middle, enemies: [enemy(zed, .middle)])?.opponent
                == ImportTarget.LaneOpponent(champion: zed, isInferred: false))
        #expect(
            decide(role: .middle, enemies: [enemy(zed)])?.opponent
                == ImportTarget.LaneOpponent(champion: zed, isInferred: true))
        #expect(decide(role: .top, enemies: [enemy(zed)])?.opponent == nil)
    }

    // MARK: ARAM

    @Test func aramSendsOnlyTheFixedChoicesAndNothingFromTheStats() throws {
        let override = ChampionOverride(
            champion: ahri, role: .middle, runeMode: .fixed, fixedPage: fixedPage,
            spellMode: .recommended, fixedSpells: fixedSpells)
        let target = try #require(decide(queue: .aram, role: .middle, overrides: [override]))

        #expect(target.role == nil)
        #expect(target.override == override)
        #expect(
            target.plan
                == ImportPlan(
                    loadout: Loadout(runes: fixedPage, spells: nil, itemSet: nil, skillOrder: nil),
                    origins: [.runes: .override]))
    }

    @Test func aramTakesTheFirstRoleWithAFixedChoice() throws {
        let overrides = [
            ChampionOverride(
                champion: ahri, role: .middle, spellMode: .fixed, fixedSpells: fixedSpells),
            ChampionOverride(champion: ahri, role: .top, fixedPage: fixedPage),
            ChampionOverride(champion: zed, role: .top, runeMode: .fixed, fixedPage: electrocute),
        ]
        let target = try #require(decide(queue: .aram, role: nil, overrides: overrides))

        // TOP's page is saved under "adaptativo", so it is not sent: MIDDLE's spells are.
        #expect(target.override?.role == .middle)
        #expect(target.plan.loadout.spells == fixedSpells)
        #expect(target.plan.loadout.runes == nil)
    }

    @Test func aramWithoutAFixedChoiceSendsNothing() throws {
        let fallback = ChampionOverride(champion: ahri, role: .middle, runeMode: .fixed)
        let target = try #require(
            decide(
                queue: .aram, role: nil, overrides: [fallback],
                settings: ImportSettings(runeMode: .fixedPerChampion)))

        #expect(target.plan.isEmpty)
        #expect(target.plan.origins.isEmpty)
        #expect(target.override == nil)
        #expect(decide(queue: .aram, role: nil)?.plan.isEmpty == true)
    }

    @Test func aramKeepsTheSettingsToggles() throws {
        let override = ChampionOverride(
            champion: ahri, role: .middle, runeMode: .fixed, fixedPage: fixedPage)
        let target = try #require(
            decide(
                queue: .aram, role: nil, overrides: [override],
                settings: ImportSettings(importRunes: false)))

        #expect(target.plan.isEmpty)
    }
}
