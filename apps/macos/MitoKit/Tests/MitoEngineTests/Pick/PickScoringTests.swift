import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

struct PickScoringTests {
    private let ahri = ChampionID(rawValue: 103)
    private let syndra = ChampionID(rawValue: 134)
    private let zed = ChampionID(rawValue: 238)
    private let lux = ChampionID(rawValue: 99)
    private let jarvan = ChampionID(rawValue: 59)
    private let garen = ChampionID(rawValue: 86)
    private let thresh = ChampionID(rawValue: 412)
    private let jinx = ChampionID(rawValue: 222)

    /// wr_smoothed = (games/2 + 50) / (games + 100) = 0.5 for any even `games`.
    private func even(_ games: Int) -> ChampionRoleStats {
        ChampionRoleStats(games: games, wins: games / 2, timelineGames: 0)
    }

    /// (1050 + 50) / (1900 + 100) = 0.55, so meta is 0.05; tier S, reliable.
    private let strong = ChampionRoleStats(games: 1_900, wins: 1_050, timelineGames: 0)

    private func lane(games: Int, wins: Int) -> MatchupStats {
        MatchupStats(
            games: games, wins: wins, timelineGames: 0, goldDiffAt15: nil, csDiffAt15: nil)
    }

    private func relation(games: Int, wins: Int) -> RelationStats {
        RelationStats(games: games, wins: wins)
    }

    /// Ahri's rows are in `role`, at a 0.5 baseline unless `rows` overrides her.
    private func provider(
        role: Role = .middle,
        rows: [ChampionID: ChampionRoleStats]? = nil,
        matchups: [ChampionID: MatchupStats] = [:],
        versusTeam: [ChampionID: RelationStats] = [:],
        synergies: [ChampionID: [Role: RelationStats]] = [:],
        roleGames: [ChampionID: [Role: Int]] = [:],
        profiles: [ChampionID: [Role: ChampionProfile]] = [:],
        meta: SnapshotMeta? = .example()
    ) -> InMemoryStatsProvider {
        InMemoryStatsProvider(
            roleGamesByChampion: roleGames,
            meta: meta,
            championRoleStatsByRole: [role: rows ?? [ahri: even(1_000)]],
            matchupsByChampion: [ahri: [role: matchups]],
            synergiesByChampion: [ahri: [role: synergies]],
            versusTeamByChampion: [ahri: [role: versusTeam]],
            championProfilesByChampion: profiles)
    }

    private func context(
        role: Role = .middle, allies: [DraftSlot] = [], enemies: [DraftSlot] = [],
        bans: Set<ChampionID> = []
    ) -> DraftContext {
        DraftContext(
            queue: .rankedSolo, patch: Patch(rawValue: "16.21"), myRole: role, myCellId: 0,
            allies: [slot(0, nil, role)] + allies, enemies: enemies, bans: bans, pickable: [],
            phase: .banPick, isMyTurnToPick: true, isMyTurnToBan: false)
    }

    private func recommend(
        _ stats: InMemoryStatsProvider,
        role: Role = .middle,
        context: DraftContext? = nil,
        mode: ChampSelectSettings.Candidates = .all,
        pool: Set<ChampionID> = [],
        owned: Set<ChampionID> = [],
        personal: (ChampionID, Role) -> Double? = { _, _ in nil },
        limit: Int = PickScoring.defaultLimit
    ) -> [PickRecommendation] {
        PickScoring.recommendations(
            for: context ?? self.context(role: role), role: role, mode: mode, pool: pool,
            owned: owned, stats: stats, personal: personal, limit: limit)
    }

    private func ahriIn(_ ranked: [PickRecommendation]) -> PickRecommendation? {
        ranked.first { $0.champion == ahri }
    }

    /// Deltas and shares to nine decimals, so hand-computed fractions compare exactly.
    private func rounded(_ reasons: [Reason]) -> [Reason] {
        func round(_ value: Double) -> Double { (value * 1e9).rounded() / 1e9 }
        return reasons.map { reason in
            let kind: Reason.Kind =
                switch reason.kind {
                case .matchup(let opponent, let delta, let games):
                    .matchup(opponent: opponent, delta: round(delta), games: games)
                case .versusEnemy(let enemy, let delta, let games):
                    .versusEnemy(enemy: enemy, delta: round(delta), games: games)
                case .synergy(let ally, let allyRole, let delta, let games):
                    .synergy(ally: ally, allyRole: allyRole, delta: round(delta), games: games)
                case .fillsDamageGap(let adds, let alliedShare):
                    .fillsDamageGap(adds: adds, alliedShare: round(alliedShare))
                default: reason.kind
                }
            return Reason(kind: kind, sample: reason.sample)
        }
    }

    private let neutralMeta = Reason(kind: .meta(tier: .b, games: 1_000), sample: .reliable)

    private func component(_ key: PickComponent, _ ranked: [PickRecommendation]) -> Double {
        ahriIn(ranked)?.components[key] ?? .nan
    }

    // MARK: - meta

    @Test func metaIsTheSmoothedWinrateAboveHalf() {
        let ranked = recommend(provider(rows: [ahri: strong]))

        #expect(isClose(component(.meta, ranked), 0.05))
    }

    // MARK: - matchup

    @Test func matchupIsTheWeightedDeltaAgainstAnAssignedLaneOpponent() {
        // (200 + 100)/(300 + 200) − 0.5 = 0.1; 1.2 · 0.1.
        let stats = provider(matchups: [zed: lane(games: 300, wins: 200)])
        let draft = context(enemies: [slot(5, zed, .middle)])

        #expect(isClose(component(.matchup, recommend(stats, context: draft)), 0.12))
    }

    @Test func theLaneOpponentDoesNotCountAsTeam() {
        let stats = provider(
            matchups: [zed: lane(games: 300, wins: 200)],
            versusTeam: [zed: relation(games: 300, wins: 100)])
        let draft = context(enemies: [slot(5, zed, .middle)])

        #expect(component(.counter, recommend(stats, context: draft)) == 0)
    }

    @Test func anInferredLaneOpponentSplitsBetweenMatchupAndTeamByRoleProbability() {
        // Zed is mid 70 % and top 30 %: matchup 1.2 · 0.7 · 0.1, vs_team 0.3 · 0.3 · −0.1.
        let stats = provider(
            matchups: [zed: lane(games: 300, wins: 200)],
            versusTeam: [zed: relation(games: 300, wins: 100)],
            roleGames: [zed: [.middle: 700, .top: 300]])
        let draft = context(enemies: [slot(5, zed, nil)])

        let ranked = recommend(stats, context: draft)

        #expect(isClose(component(.matchup, ranked), 0.084))
        #expect(isClose(component(.counter, ranked), -0.009))
        #expect(
            rounded(ahriIn(ranked)?.reasons ?? []) == [
                Reason(kind: .matchup(opponent: zed, delta: 0.1, games: 300), sample: .reliable),
                Reason(kind: .versusEnemy(enemy: zed, delta: -0.1, games: 300), sample: .reliable),
                neutralMeta,
            ])
    }

    @Test func anEnemyAssignedToAnotherLaneGivesNoMatchup() {
        let stats = provider(matchups: [zed: lane(games: 300, wins: 200)])
        let draft = context(enemies: [slot(5, zed, .top)])

        let ranked = recommend(stats, context: draft)

        #expect(component(.matchup, ranked) == 0)
        #expect(ahriIn(ranked)?.reasons == [neutralMeta])
    }

    @Test func anEnemyThatNeverPlaysTheLaneGivesNoMatchup() {
        let stats = provider(
            matchups: [zed: lane(games: 300, wins: 200)], roleGames: [zed: [.top: 1_000]])
        let draft = context(enemies: [slot(5, zed, nil)])

        #expect(component(.matchup, recommend(stats, context: draft)) == 0)
    }

    @Test func withoutLockedEnemiesMatchupIsZero() {
        let stats = provider(matchups: [zed: lane(games: 300, wins: 200)])
        let draft = context(enemies: [
            DraftSlot(cellId: 5, champion: nil, hover: zed, role: nil, roleConfidence: 0)
        ])

        #expect(component(.matchup, recommend(stats, context: draft)) == 0)
    }

    // MARK: - vs_team

    @Test func counterSumsTheWeightedDeltasAgainstTheOtherLockedEnemies() {
        // 0.1 and (60 + 100)/(100 + 200) − 0.5 = 1/30; 0.3 · (0.1 + 1/30).
        let stats = provider(
            versusTeam: [zed: relation(games: 300, wins: 200), lux: relation(games: 100, wins: 60)])
        let draft = context(enemies: [slot(5, zed, .top), slot(6, lux, .utility)])

        #expect(isClose(component(.counter, recommend(stats, context: draft)), 0.04))
    }

    @Test func aBelowMinimumRelationIsIgnored() {
        let stats = provider(versusTeam: [zed: relation(games: 29, wins: 29)])
        let draft = context(enemies: [slot(5, zed, .top)])

        let ranked = recommend(stats, context: draft)

        #expect(component(.counter, ranked) == 0)
        #expect(ahriIn(ranked)?.reasons == [neutralMeta])
    }

    // MARK: - synergy

    @Test func synergySumsTheWeightedDeltasWithLockedAllies() {
        // 0.6 · 0.1.
        let stats = provider(synergies: [garen: [.top: relation(games: 300, wins: 200)]])
        let draft = context(allies: [slot(1, garen, .top)])

        #expect(isClose(component(.synergy, recommend(stats, context: draft)), 0.06))
    }

    @Test(arguments: [
        (Role.middle, Role.jungle), (.jungle, .middle), (.bottom, .utility), (.utility, .bottom),
    ])
    func aStrongPairCountsOneAndAHalfTimes(role: Role, allyRole: Role) {
        // 0.6 · 1.5 · 0.1.
        let stats = provider(
            role: role, synergies: [garen: [allyRole: relation(games: 300, wins: 200)]])
        let draft = context(role: role, allies: [slot(1, garen, allyRole)])

        let ranked = recommend(stats, role: role, context: draft)

        #expect(isClose(component(.synergy, ranked), 0.09))
    }

    // MARK: - comp_fit

    @Test func compositionIsTheCompFitTimesPointEight() {
        let ranked = recommend(fullProvider(), context: fullDraft())

        // Damage gap +0.015 · 0.8.
        #expect(isClose(component(.composition, ranked), 0.012))
    }

    // MARK: - personal

    @Test func withoutPersonalDataThePersonalTermIsZero() {
        #expect(component(.personal, recommend(provider())) == 0)
    }

    @Test func personalIsTheClosureValueForTheCandidateInTheRole() {
        let ranked = recommend(provider()) { champion, role in
            champion == ahri && role == .middle ? 0.02 : nil
        }

        #expect(isClose(component(.personal, ranked), 0.02))
    }

    // MARK: - Full score

    /// Ahri mid at wr_s 0.55 (meta 0.05), so a relation delta is (wins + 110)/(games + 200) − 0.55:
    /// Zed mid +0.07, Lux 1/60, Jarvan jungle 2/15 (a strong pair), three physical allies.
    private func fullProvider() -> InMemoryStatsProvider {
        let physical = championProfile(physical: 0.9, magic: 0.1)
        return provider(
            rows: [ahri: strong],
            matchups: [zed: lane(games: 300, wins: 200)],
            versusTeam: [lux: relation(games: 100, wins: 60)],
            synergies: [jarvan: [.jungle: relation(games: 400, wins: 300)]],
            profiles: [
                ahri: [
                    .middle: championProfile(physical: 0.2, magic: 0.8, tankiness: 0.1, cc: 0.1)
                ],
                jarvan: [.jungle: physical], garen: [.top: physical], jinx: [.bottom: physical],
            ])
    }

    private func fullDraft() -> DraftContext {
        context(
            allies: [
                slot(1, jarvan, .jungle), slot(2, garen, .top), slot(3, jinx, .bottom),
                slot(4, thresh, .utility),
            ],
            enemies: [slot(5, zed, .middle), slot(6, lux, .utility)])
    }

    @Test func scoreIsTheSumOfTheWeightedComponents() {
        // 0.05 + 1.2 · 0.07 + 0.3 · 1/60 + 0.6 · 1.5 · 2/15 + 0.8 · 0.015 + 0.02.
        let ranked = recommend(fullProvider(), context: fullDraft()) { _, _ in 0.02 }

        let recommendation = ahriIn(ranked)
        #expect(isClose(recommendation?.score ?? 0, 0.291))
        #expect(Set(recommendation?.components.keys ?? [:].keys) == Set(PickComponent.allCases))
        #expect(recommendation?.components[.penalties] == 0)
    }

    // MARK: - Reasons

    @Test func reasonsRankByWeightedImpactWithTheirSample() {
        // Synergy 0.12, matchup 0.084, meta 0.05, damage gap 0.012, vs_team 0.005.
        let reasons = ahriIn(recommend(fullProvider(), context: fullDraft()))?.reasons ?? []

        #expect(
            rounded(reasons)
                == rounded([
                    Reason(
                        kind: .synergy(
                            ally: jarvan, allyRole: .jungle, delta: 2.0 / 15.0, games: 400),
                        sample: .reliable),
                    Reason(
                        kind: .matchup(opponent: zed, delta: 0.07, games: 300), sample: .reliable),
                    Reason(kind: .meta(tier: .s, games: 1_900), sample: .reliable),
                    Reason(
                        kind: .fillsDamageGap(adds: .magic, alliedShare: 0.9), sample: .reliable),
                    Reason(
                        kind: .versusEnemy(enemy: lux, delta: 1.0 / 60.0, games: 100),
                        sample: .usable),
                ]))
    }

    @Test func aNegativeReasonRanksByItsMagnitude() {
        // (100 + 110)/500 − 0.55 = −0.13 weighs −0.156, ahead of the 0.05 meta.
        let stats = provider(rows: [ahri: strong], matchups: [zed: lane(games: 300, wins: 100)])
        let draft = context(enemies: [slot(5, zed, .middle)])

        let reasons = ahriIn(recommend(stats, context: draft))?.reasons ?? []

        #expect(
            rounded(reasons) == [
                Reason(kind: .matchup(opponent: zed, delta: -0.13, games: 300), sample: .reliable),
                Reason(kind: .meta(tier: .s, games: 1_900), sample: .reliable),
            ])
    }

    // MARK: - Exclusions and candidates

    @Test func excludesBannedAndLockedChampionsButNotHovers() {
        let banned = ChampionID(rawValue: 1)
        let allyLocked = ChampionID(rawValue: 2)
        let enemyLocked = ChampionID(rawValue: 3)
        let allyHover = ChampionID(rawValue: 4)
        let rows = [banned, allyLocked, enemyLocked, allyHover]
        let stats = provider(rows: Dictionary(uniqueKeysWithValues: rows.map { ($0, even(400)) }))
        let draft = context(
            allies: [
                slot(1, allyLocked, .top),
                DraftSlot(
                    cellId: 2, champion: nil, hover: allyHover, role: .jungle, roleConfidence: 1),
            ],
            enemies: [slot(5, enemyLocked, nil)], bans: [banned])

        #expect(recommend(stats, context: draft).map(\.champion) == [allyHover])
    }

    private let inPoolOwned = ChampionID(rawValue: 1)
    private let inPoolNotOwned = ChampionID(rawValue: 2)
    private let ownedOnly = ChampionID(rawValue: 3)
    private let neither = ChampionID(rawValue: 4)

    private func ranked(_ mode: ChampSelectSettings.Candidates) -> [ChampionID] {
        let rows = [inPoolOwned, inPoolNotOwned, ownedOnly, neither]
        return recommend(
            provider(rows: Dictionary(uniqueKeysWithValues: rows.map { ($0, even(400)) })),
            mode: mode, pool: [inPoolOwned, inPoolNotOwned], owned: [inPoolOwned, ownedOnly]
        ).map(\.champion)
    }

    @Test func myPoolKeepsOwnedPoolChampions() {
        #expect(ranked(.myPool) == [inPoolOwned])
    }

    @Test func ownedKeepsEveryOwnedChampion() {
        #expect(ranked(.owned) == [inPoolOwned, ownedOnly])
    }

    @Test func allKeepsEveryChampion() {
        #expect(ranked(.all) == [inPoolOwned, inPoolNotOwned, ownedOnly, neither])
    }

    // MARK: - Sample rules

    @Test func aCandidateBelowTheChampRoleMinimumIsNotRanked() {
        let stats = provider(rows: [lux: even(198), ahri: even(200)])

        #expect(recommend(stats).map(\.champion) == [ahri])
    }

    @Test func confidenceIsTheCandidateChampRoleLevel() {
        let ranked = recommend(provider(rows: [lux: even(500), ahri: even(1_000)]))

        #expect(ranked.first { $0.champion == lux }?.confidence == .usable)
        #expect(ahriIn(ranked)?.confidence == .reliable)
    }

    // MARK: - Ranking

    @Test func higherScoreRanksFirst() {
        let stats = provider(rows: [lux: even(1_000), ahri: strong])

        #expect(recommend(stats).map(\.champion) == [ahri, lux])
    }

    @Test func tiesBreakByChampionID() {
        let stats = provider(rows: [zed: even(1_000), ahri: even(1_000), lux: even(1_000)])

        #expect(recommend(stats).map(\.champion) == [lux, ahri, zed])
    }

    @Test func returnsTheTopTenByDefaultAndAtMostTheLimit() {
        let candidates = (1...12).map { ChampionID(rawValue: 500 + $0) }
        let stats = provider(
            rows: Dictionary(uniqueKeysWithValues: candidates.map { ($0, even(400)) }))

        #expect(recommend(stats).map(\.champion) == Array(candidates.prefix(10)))
        #expect(recommend(stats, limit: 2).count == 2)
    }

    @Test func noSnapshotMetaYieldsNothing() {
        #expect(recommend(provider(meta: nil)).isEmpty)
    }
}
