import MitoAssets
import MitoCore
import MitoEngine
import Observation
import Testing

@testable import Mito

struct ChampionsModelTests {
    // m = 100, p0 = 0.5, so wr = (wins + 50) / (games + 100); matches = 10 000.
    static let meta = SnapshotMeta(
        patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420), bracket: .emeraldPlus,
        matches: 10_000, blendPatches: [Patch(rawValue: "16.21")],
        thresholds: [.championRole: SampleThreshold(minimum: 200, reliable: 1_000)],
        priors: SmoothingPriors(
            championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
            loadoutStrength: 500),
        tierCutoffs: [.s: 0.53, .a: 0.515, .b: 0.5, .c: 0.485])

    static let ahri = ChampionID(rawValue: 103)
    static let syndra = ChampionID(rawValue: 134)
    static let zed = ChampionID(rawValue: 238)
    static let galio = ChampionID(rawValue: 3)
    static let yasuo = ChampionID(rawValue: 157)
    static let garen = ChampionID(rawValue: 86)

    let stats = ChampionsTestStats(
        meta: Self.meta,
        byRole: [
            .middle: [
                Self.zed: ChampionRoleStats(games: 500, wins: 240, timelineGames: 0),
                Self.galio: ChampionRoleStats(games: 150, wins: 100, timelineGames: 0),
                Self.ahri: ChampionRoleStats(games: 2_000, wins: 1_100, timelineGames: 0),
                Self.syndra: ChampionRoleStats(games: 1_000, wins: 520, timelineGames: 0),
                Self.yasuo: ChampionRoleStats(games: 4_000, wins: 2_200, timelineGames: 0),
            ],
            .top: [
                Self.garen: ChampionRoleStats(games: 3_000, wins: 1_560, timelineGames: 0),
                Self.ahri: ChampionRoleStats(games: 180, wins: 90, timelineGames: 0),
            ],
        ])

    @Test func rowsCarryTheTierSmoothedWinrateAndPickRateOfEachChampion() throws {
        let model = makeModel()
        model.role = .middle

        let rows = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.champion, $0) })

        let ahri = try #require(rows[Self.ahri])
        #expect(ahri.tier == .s)  // 1150 / 2100 ≈ 0.548
        #expect(ahri.winrate == 1_150.0 / 2_100.0)
        #expect(ahri.pickRate == 0.2)
        #expect(ahri.games == 2_000)
        #expect(!ahri.isLowSample)

        let syndra = try #require(rows[Self.syndra])
        #expect(syndra.tier == .a)  // 570 / 1100 ≈ 0.518
        #expect(syndra.winrate == 570.0 / 1_100.0)
        #expect(syndra.pickRate == 0.1)
        #expect(!syndra.isLowSample)  // the reliable threshold is inclusive

        let zed = try #require(rows[Self.zed])
        #expect(zed.tier == .d)  // 290 / 600 ≈ 0.483, under C
        #expect(zed.pickRate == 0.05)
        #expect(zed.isLowSample)
    }

    @Test func rowsSortByTierThenSmoothedWinrate() {
        let model = makeModel()
        model.role = .middle

        // Yasuo (2250 / 4100 ≈ 0.549) edges Ahri inside S.
        #expect(
            model.rows.map(\.champion) == [
                Self.yasuo, Self.ahri, Self.syndra, Self.zed,
            ])
    }

    @Test func rowsUnderTheMinimumAreLeftOutOfTheTierList() throws {
        let model = makeModel()
        model.role = .middle

        // Galio's 150 games are under the champ_role minimum: §18.2 says such data is not used.
        #expect(!model.rows.map(\.champion).contains(Self.galio))
        let page = try #require(model.roles(of: Self.galio).first)
        #expect(page.tier == nil)
        #expect(page.isLowSample)
    }

    @Test func noSnapshotLeavesTheTabEmpty() {
        let model = ChampionsModel(stats: { ChampionsTestStats(meta: nil, byRole: stats.byRole) })
        model.role = .middle

        #expect(model.meta == nil)
        #expect(model.rows.isEmpty)
        #expect(model.roles(of: Self.ahri).isEmpty)
    }

    @Test func theDefaultModelHasNoStats() {
        let model = ChampionsModel()

        #expect(model.meta == nil)
        #expect(model.rows.isEmpty)
    }

    @Test func switchingRoleShowsThatRolesTierList() {
        let model = makeModel()
        model.role = .middle
        #expect(model.rows.count == 4)

        model.role = .top

        #expect(model.rows.map(\.champion) == [Self.garen])
        #expect(model.rows.allSatisfy { $0.role == .top })
        #expect(model.rows.first?.tier == .a)  // 1610 / 3100 ≈ 0.519
    }

    @Test func theChampionPageListsEveryRoleTheChampionIsPlayedIn() {
        let model = makeModel()

        let roles = model.roles(of: Self.ahri)

        #expect(roles.map(\.role) == [.top, .middle])
        #expect(roles.map(\.tier) == [nil, .s])
        #expect(roles.map(\.games) == [180, 2_000])
        #expect(model.roles(of: ChampionID(rawValue: 1)).isEmpty)
    }

    @Test func namesComeFromTheSharedDataWithAFallback() {
        let shared = SharedData()
        let model = ChampionsModel(stats: { [stats] in stats }, gameData: shared.gameData)
        model.role = .top
        #expect(model.rows.map(\.name) == ["Campeón 86"])

        shared.gameData = GameData(champions: [
            Champion(id: Self.garen, alias: "Garen", name: "Garen", iconPath: "")
        ])

        #expect(model.rows.map(\.name) == ["Garen"])
        #expect(model.championName(Self.ahri) == "Campeón 103")
    }

    private func makeModel() -> ChampionsModel {
        ChampionsModel(stats: { [stats] in stats })
    }
}

struct ChampionsTestStats: StatsProvider {
    let meta: SnapshotMeta?
    let byRole: [Role: [ChampionID: ChampionRoleStats]]

    func roleGames(for champion: ChampionID) -> [Role: Int] {
        byRole.compactMapValues { $0[champion]?.games }
    }

    func championRoleStats(in role: Role) -> [ChampionID: ChampionRoleStats] {
        byRole[role] ?? [:]
    }
}

/// Stands in for the shell's `ClientDataModel`.
@Observable
private final class SharedData {
    var gameData: GameData?
}
