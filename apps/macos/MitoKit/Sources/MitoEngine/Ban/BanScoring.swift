public import MitoCore

/// `ban_score(e) = presencia(e) · amenaza(e)` for the user in one role; the rules §18.5 leaves
/// open are written there.
public enum BanScoring {
    /// `λ`: the weight of the enemy team outside your lane in `presencia`.
    public static let globalPresenceWeight = 0.3
    /// "Top 3 de tu pool": how many of `myPicks` `amenaza` averages over.
    public static let likelyPickCount = 3
    /// "Mostrar el top 5".
    public static let defaultLimit = 5

    /// `myPicks` is the user's pool for `role`, most likely first; none of it is ever suggested.
    /// Candidates are champions with a `champ_role` sample in `role` at or above the minimum,
    /// ranked by score, then by champion ID. Empty without a snapshot `meta`.
    public static func recommendations(
        for context: DraftContext,
        role: Role,
        myPicks: [ChampionID],
        stats: some StatsProvider,
        limit: Int = defaultLimit
    ) -> [BanRecommendation] {
        guard let meta = stats.meta, limit > 0 else { return [] }
        let statsByRole = Role.allCases.map { stats.championRoleStats(in: $0) }
        let roleStats = stats.championRoleStats(in: role)
        let likelyPicks = myPicks.prefix(likelyPickCount)
        let excluded = Set(myPicks).union(context.bans).union(
            (context.allies + context.enemies).flatMap { [$0.champion, $0.hover] }
                .compactMap { $0 })

        let ranked = roleStats.compactMap { champion, row -> BanRecommendation? in
            guard !excluded.contains(champion),
                let confidence = meta.sampleLevel(.championRole, games: row.games),
                confidence != .belowMinimum
            else { return nil }

            let globalGames = statsByRole.reduce(0) { $0 + ($1[champion]?.games ?? 0) }
            let banRate = meta.pickRate(games: stats.bans(of: champion) ?? 0)
            let presence =
                meta.pickRate(games: row.games) * (1 - banRate)
                + globalPresenceWeight * meta.pickRate(games: globalGames)

            let threats = likelyPicks.compactMap { pick in
                threat(
                    of: champion, to: pick, role: role, roleStats: roleStats, stats: stats,
                    meta: meta)
            }
            let threatGames = threats.reduce(0) { $0 + $1.games }
            let matchupThreat =
                threatGames > 0
                ? threats.reduce(0) { $0 - Double($1.games) * $1.delta } / Double(threatGames)
                : 0
            let metaWinrate = meta.priors.championRoleWinrate(wins: row.wins, games: row.games)
            let threat = matchupThreat + metaWinrate - 0.5

            var reasons =
                threats
                .filter { $0.delta < 0 }
                .sorted { ($0.delta, $0.pick.rawValue) < ($1.delta, $1.pick.rawValue) }
                .map {
                    Reason(
                        kind: .threatens(pick: $0.pick, delta: $0.delta, games: $0.games),
                        sample: $0.sample)
                }
            if let tier = meta.tier(for: row) {
                reasons.append(
                    Reason(kind: .meta(tier: tier, games: row.games), sample: confidence))
            }

            return BanRecommendation(
                champion: champion,
                score: presence * threat,
                components: [.presence: presence, .threat: threat],
                reasons: reasons,
                confidence: confidence)
        }

        return Array(
            ranked.sorted {
                $0.score != $1.score
                    ? $0.score > $1.score : $0.champion.rawValue < $1.champion.rawValue
            }
            .prefix(limit))
    }

    private struct PickThreat {
        let pick: ChampionID
        /// `matchup_delta(pick, role, enemy)`; negative when the enemy wins the lane.
        let delta: Double
        let games: Int
        let sample: SampleLevel
    }

    /// `nil` when the matchup row is missing or below the `matchup` minimum.
    private static func threat(
        of enemy: ChampionID, to pick: ChampionID, role: Role,
        roleStats: [ChampionID: ChampionRoleStats], stats: some StatsProvider, meta: SnapshotMeta
    ) -> PickThreat? {
        guard let matchup = stats.matchup(for: pick, role: role, against: enemy),
            let sample = meta.sampleLevel(.matchup, games: matchup.games),
            sample != .belowMinimum
        else { return nil }
        let pickRow = roleStats[pick]
        let baseline = meta.priors.championRoleWinrate(
            wins: pickRow?.wins ?? 0, games: pickRow?.games ?? 0)
        let delta =
            meta.priors.relationWinrate(
                wins: matchup.wins, games: matchup.games, baseline: baseline)
            - baseline
        return PickThreat(pick: pick, delta: delta, games: matchup.games, sample: sample)
    }
}
