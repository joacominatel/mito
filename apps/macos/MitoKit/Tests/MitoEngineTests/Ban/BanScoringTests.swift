import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

struct BanScoringTests {
    private let ahri = ChampionID(rawValue: 103)
    private let syndra = ChampionID(rawValue: 134)
    private let orianna = ChampionID(rawValue: 61)
    private let viktor = ChampionID(rawValue: 112)
    private let malzahar = ChampionID(rawValue: 90)
    private let lux = ChampionID(rawValue: 99)
    private let zed = ChampionID(rawValue: 238)

    /// wr_smoothed = (games/2 + 50) / (games + 100) = 0.5 for any even `games`.
    private func even(_ games: Int) -> ChampionRoleStats {
        ChampionRoleStats(games: games, wins: games / 2, timelineGames: 0)
    }

    private func matchup(games: Int, wins: Int) -> MatchupStats {
        MatchupStats(
            games: games, wins: wins, timelineGames: 0, goldDiffAt15: nil, csDiffAt15: nil)
    }

    /// The user's four picks sit at a 0.5 baseline unless `middle` overrides them.
    private func provider(
        middle: [ChampionID: ChampionRoleStats],
        top: [ChampionID: ChampionRoleStats] = [:],
        matchups: [ChampionID: [ChampionID: MatchupStats]] = [:],
        bans: [ChampionID: Int] = [:],
        meta: SnapshotMeta? = .example(matches: 10_000)
    ) -> InMemoryStatsProvider {
        let picks = [ahri: even(1_000), syndra: even(900), orianna: even(1_100), viktor: even(800)]
        return InMemoryStatsProvider(
            meta: meta,
            championRoleStatsByRole: [
                .middle: picks.merging(middle) { $1 }, .top: top,
            ],
            matchupsByChampion: matchups.mapValues { [.middle: $0] },
            bansByChampion: bans)
    }

    private func context(
        allies: [DraftSlot] = [], enemies: [DraftSlot] = [], bans: Set<ChampionID> = []
    ) -> DraftContext {
        DraftContext(
            queue: .rankedSolo, patch: Patch(rawValue: "16.21"), myRole: .middle, myCellId: 0,
            allies: allies, enemies: enemies, bans: bans, pickable: [], phase: .banPick,
            isMyTurnToPick: false, isMyTurnToBan: true)
    }

    private func slot(_ cell: Int, champion: ChampionID? = nil, hover: ChampionID? = nil)
        -> DraftSlot
    {
        DraftSlot(cellId: cell, champion: champion, hover: hover, role: nil, roleConfidence: 0)
    }

    private func recommend(
        _ stats: InMemoryStatsProvider,
        picks: [ChampionID]? = nil,
        context: DraftContext? = nil,
        limit: Int = BanScoring.defaultLimit
    ) -> [BanRecommendation] {
        BanScoring.recommendations(
            for: context ?? self.context(), role: .middle,
            myPicks: picks ?? [ahri, syndra, orianna, viktor],
            stats: stats, limit: limit)
    }

    private func only(_ champion: ChampionID, in recommendations: [BanRecommendation])
        -> BanRecommendation?
    {
        recommendations.first { $0.champion == champion }
    }

    private struct Threat {
        let pick: ChampionID
        let delta: Double
        let games: Int
        let sample: SampleLevel?
    }

    private func threatened(_ reasons: [Reason]) -> [Threat] {
        reasons.compactMap {
            guard case .threatens(let pick, let delta, let games) = $0.kind else { return nil }
            return Threat(pick: pick, delta: delta, games: games, sample: $0.sample)
        }
    }

    // MARK: - presencia

    @Test func presenceIsTheUnbannedLanePickRatePlusTheWeightedGlobalPickRate() {
        // 1900/10000 · (1 − 1000/10000) + 0.3 · (1900 + 100)/10000 = 0.171 + 0.06.
        let stats = provider(
            middle: [malzahar: even(1_900)], top: [malzahar: even(100)], bans: [malzahar: 1_000])

        let recommendation = only(malzahar, in: recommend(stats))

        #expect(isClose(recommendation?.components[.presence] ?? 0, 0.231))
    }

    @Test func higherPresenceRanksFirstAtEqualThreat() {
        // All at wr 0.55 (threat 0.05). Malzahar 0.19 + 0.057; Lux 0.19 · 0.5 + 0.057;
        // Zed 0.1 + 0.03.
        let stats = provider(
            middle: [
                malzahar: ChampionRoleStats(games: 1_900, wins: 1_050, timelineGames: 0),
                lux: ChampionRoleStats(games: 1_900, wins: 1_050, timelineGames: 0),
                zed: ChampionRoleStats(games: 1_000, wins: 555, timelineGames: 0),
            ],
            bans: [lux: 5_000])

        let ranked = recommend(stats)

        #expect(ranked.map(\.champion) == [malzahar, lux, zed])
        #expect(isClose(ranked[1].components[.presence] ?? 0, 0.152))
    }

    // MARK: - amenaza

    @Test func threatIsTheGamesWeightedMeanOfNegatedMatchupDeltas() {
        // Ahri vs Malzahar (100 + 100)/(300 + 200) − 0.5 = −0.1 over 300 games;
        // Syndra (40 + 100)/(100 + 200) − 0.5 = −1/30 over 100: (30 + 10/3)/400 = 1/12.
        let stats = provider(
            middle: [malzahar: even(1_900)],
            matchups: [
                ahri: [malzahar: matchup(games: 300, wins: 100)],
                syndra: [malzahar: matchup(games: 100, wins: 40)],
            ])

        let recommendation = only(malzahar, in: recommend(stats))

        #expect(isClose(recommendation?.components[.threat] ?? 0, 1.0 / 12.0))
    }

    @Test func matchupDeltaIsAgainstThePicksOwnSmoothedWinrate() {
        // Ahri wr_s 650/1100; a raw 50 % matchup smooths to (150 + 200·b)/500, a delta of
        // 0.3 − 0.6·b = −60/1100.
        let stats = provider(
            middle: [
                ahri: ChampionRoleStats(games: 1_000, wins: 600, timelineGames: 0),
                malzahar: even(1_900),
            ],
            matchups: [ahri: [malzahar: matchup(games: 300, wins: 150)]])

        let recommendation = only(malzahar, in: recommend(stats))

        #expect(isClose(recommendation?.components[.threat] ?? 0, 60.0 / 1_100.0))
    }

    @Test func smoothingPullsASmallMatchupSampleTowardZero() {
        // 0/30 raw is −0.5; (0 + 100)/(30 + 200) − 0.5 = −15/230.
        let stats = provider(
            middle: [malzahar: even(1_900)],
            matchups: [ahri: [malzahar: matchup(games: 30, wins: 0)]])

        let threat = only(malzahar, in: recommend(stats))?.components[.threat] ?? 0

        #expect(isClose(threat, 15.0 / 230.0))
        #expect(threat < 0.1)
    }

    @Test func threatAddsTheCandidateMetaWinrateAboveHalf() {
        // (1050 + 50)/(1900 + 100) − 0.5.
        let stats = provider(
            middle: [malzahar: ChampionRoleStats(games: 1_900, wins: 1_050, timelineGames: 0)])

        let recommendation = only(malzahar, in: recommend(stats))

        #expect(isClose(recommendation?.components[.threat] ?? 0, 0.05))
    }

    @Test func onlyTheFirstThreePicksFeedTheThreat() {
        let stats = provider(
            middle: [malzahar: even(1_900)],
            matchups: [viktor: [malzahar: matchup(games: 300, wins: 0)]])

        let recommendation = only(malzahar, in: recommend(stats))

        #expect(recommendation?.components[.threat] == 0)
        let threats = threatened(recommendation?.reasons ?? [])
        #expect(threats.isEmpty)
    }

    @Test func aBelowMinimumMatchupIsIgnored() {
        let stats = provider(
            middle: [malzahar: even(1_900)],
            matchups: [ahri: [malzahar: matchup(games: 29, wins: 0)]])

        let recommendation = only(malzahar, in: recommend(stats))

        #expect(recommendation?.components[.threat] == 0)
        let threats = threatened(recommendation?.reasons ?? [])
        #expect(threats.isEmpty)
    }

    // MARK: - ban_score

    @Test func scoreIsPresenceTimesThreat() {
        // 0.231 · 1/12.
        let stats = provider(
            middle: [malzahar: even(1_900)], top: [malzahar: even(100)],
            matchups: [
                ahri: [malzahar: matchup(games: 300, wins: 100)],
                syndra: [malzahar: matchup(games: 100, wins: 40)],
            ],
            bans: [malzahar: 1_000])

        let recommendation = only(malzahar, in: recommend(stats))

        #expect(isClose(recommendation?.score ?? 0, 0.231 / 12.0))
    }

    @Test func aChampionYourPicksBeatRanksBelowANeutralOne() {
        // Ahri vs Lux (200 + 100)/500 − 0.5 = +0.1, so Lux's threat is −0.1.
        let stats = provider(
            middle: [malzahar: even(1_900), lux: even(1_900)],
            matchups: [ahri: [lux: matchup(games: 300, wins: 200)]])

        let ranked = recommend(stats)

        #expect(ranked.map(\.champion) == [malzahar, lux])
        #expect(isClose(ranked[1].score, 0.247 * -0.1))
    }

    @Test func tiesBreakByChampionID() {
        let stats = provider(middle: [zed: even(1_900), lux: even(1_900), malzahar: even(1_900)])

        #expect(recommend(stats).map(\.champion) == [malzahar, lux, zed])
    }

    @Test func returnsAtMostTheLimit() {
        let candidates = (1...7).map { ChampionID(rawValue: 500 + $0) }
        let stats = provider(
            middle: Dictionary(uniqueKeysWithValues: candidates.map { ($0, even(400)) }))

        #expect(recommend(stats).map(\.champion) == Array(candidates.prefix(5)))
        #expect(recommend(stats, limit: 2).count == 2)
    }

    // MARK: - Exclusions

    @Test func excludesBannedPickedHoveredAndOwnPoolChampions() {
        let banned = ChampionID(rawValue: 1)
        let allyLocked = ChampionID(rawValue: 2)
        let allyHover = ChampionID(rawValue: 3)
        let myHover = ChampionID(rawValue: 4)
        let enemyLocked = ChampionID(rawValue: 5)
        let notPickable = ChampionID(rawValue: 6)
        let rows = [banned, allyLocked, allyHover, myHover, enemyLocked, notPickable]
        let stats = provider(middle: Dictionary(uniqueKeysWithValues: rows.map { ($0, even(400)) }))
        let draft = context(
            allies: [
                slot(0, hover: myHover), slot(1, champion: allyLocked), slot(2, hover: allyHover),
            ],
            enemies: [slot(5, champion: enemyLocked)],
            bans: [banned])

        let ranked = recommend(stats, context: draft)

        #expect(ranked.map(\.champion) == [notPickable])
    }

    // MARK: - Sample rules

    @Test func aBelowMinimumCandidateIsNotRanked() {
        let stats = provider(middle: [malzahar: even(198), lux: even(200)])

        let ranked = recommend(stats)

        #expect(ranked.map(\.champion) == [lux])
    }

    @Test func confidenceIsTheCandidateChampRoleLevel() {
        let stats = provider(middle: [malzahar: even(500), lux: even(1_000)])

        let ranked = recommend(stats)

        #expect(only(malzahar, in: ranked)?.confidence == .usable)
        #expect(only(lux, in: ranked)?.confidence == .reliable)
    }

    // MARK: - Reasons

    @Test func reasonsListThreatenedPicksStrongestFirstWithTheirSampleThenTheTier() {
        // Syndra −0.1 over 300 (reliable), Ahri −1/30 over 100 (usable), Orianna +0.1 (no
        // reason); Malzahar wr 0.5 is tier B over 1900 games (reliable).
        let stats = provider(
            middle: [malzahar: even(1_900)],
            matchups: [
                ahri: [malzahar: matchup(games: 100, wins: 40)],
                syndra: [malzahar: matchup(games: 300, wins: 100)],
                orianna: [malzahar: matchup(games: 300, wins: 200)],
            ])

        let reasons = only(malzahar, in: recommend(stats))?.reasons ?? []
        let threats = threatened(reasons)

        #expect(threats.map(\.pick) == [syndra, ahri])
        #expect(isClose(threats.first?.delta ?? 0, -0.1))
        #expect(isClose(threats.last?.delta ?? 0, -1.0 / 30.0))
        #expect(threats.map(\.games) == [300, 100])
        #expect(threats.map(\.sample) == [.reliable, .usable])
        #expect(reasons.last == Reason(kind: .meta(tier: .b, games: 1_900), sample: .reliable))
        #expect(reasons.count == 3)
    }

    // MARK: - Empty inputs

    @Test func noSnapshotMetaYieldsNothing() {
        #expect(recommend(provider(middle: [malzahar: even(1_900)], meta: nil)).isEmpty)
    }

    @Test func noRowsInTheRoleYieldsNothing() {
        #expect(recommend(InMemoryStatsProvider(meta: .example(matches: 10_000))).isEmpty)
    }

    @Test func aZeroLimitYieldsNothing() {
        #expect(recommend(provider(middle: [malzahar: even(1_900)]), limit: 0).isEmpty)
    }

    @Test func withoutPicksTheThreatIsTheMetaTermAndTheOnlyReasonIsTheTier() {
        let stats = provider(middle: [malzahar: even(1_900)])

        let recommendation = only(malzahar, in: recommend(stats, picks: []))

        #expect(recommendation?.components[.threat] == 0)
        #expect(
            recommendation?.reasons == [
                Reason(kind: .meta(tier: .b, games: 1_900), sample: .reliable)
            ])
    }
}
