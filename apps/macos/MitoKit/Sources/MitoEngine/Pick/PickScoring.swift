public import MitoCore

/// The weights of `score(c)` (§18.3); the Meta ↔ Comfort slider moves `personal` and `meta`.
public struct PickWeights: Hashable, Sendable {
    public var meta: Double
    public var matchup: Double
    public var counter: Double
    public var synergy: Double
    public var composition: Double
    public var personal: Double

    public init(
        meta: Double = 1.0, matchup: Double = 1.2, counter: Double = 0.3, synergy: Double = 0.6,
        composition: Double = 0.8, personal: Double = 1.0
    ) {
        self.meta = meta
        self.matchup = matchup
        self.counter = counter
        self.synergy = synergy
        self.composition = composition
        self.personal = personal
    }
}

/// `score(c)` of §18.3 for the user in one role; the rules §18.3 leaves open are written there.
public enum PickScoring {
    /// "El top 10".
    public static let defaultLimit = 10
    /// The synergy of a strong pair (bot + support, jungle + mid) counts this many times.
    public static let strongPairMultiplier = 1.5
    /// With no lane opponent, the matchup is expected over this many of the role's most played.
    public static let likelyOpponentCount = 10

    /// `personal` returns `personal(c, r)` with its comfort facts, `nil` without personal data.
    public static func recommendations(
        for context: DraftContext,
        role: Role,
        mode: ChampSelectSettings.Candidates,
        pool: Set<ChampionID> = [],
        owned: Set<ChampionID> = [],
        stats: some StatsProvider,
        weights: PickWeights = PickWeights(),
        personal: (ChampionID, Role) -> PersonalTerm? = { _, _ in nil },
        limit: Int = defaultLimit
    ) -> [PickRecommendation] {
        guard let meta = stats.meta, limit > 0 else { return [] }
        let excluded = context.bans.union((context.allies + context.enemies).compactMap(\.champion))
        let allies = Composition.members(
            of: context.allies.filter { $0.cellId != context.myCellId }, stats: stats)
        let enemies = laneOdds(of: context.enemies, in: role, stats: stats)
        let enemyProfile = Composition.enemyProfile(in: context, stats: stats)
            .sorted { $0.rawValue < $1.rawValue }
        let likelyOpponents =
            enemies.contains { $0.lane > 0 }
            ? []
            : likeliestOpponents(
                in: role,
                excluding: excluded.union((context.allies + context.enemies).compactMap(\.hover)),
                stats: stats, meta: meta)

        let ranked = stats.championRoleStats(in: role).compactMap {
            champion, row -> PickRecommendation? in
            guard !excluded.contains(champion),
                isCandidate(champion, mode: mode, pool: pool, owned: owned),
                let confidence = meta.sampleLevel(.championRole, games: row.games),
                confidence != .belowMinimum
            else { return nil }

            func delta(_ relation: (wins: Int, games: Int)?, _ kind: SampleKind) -> MatchupDelta? {
                relation.flatMap {
                    MatchupDelta(
                        wins: $0.wins, games: $0.games, kind: kind, championStats: row, meta: meta)
                }
            }
            let profileBackoff = profileDelta(
                of: enemyProfile.compactMap { profile in
                    delta(
                        stats.profileStats(for: champion, role: role, against: profile).map {
                            ($0.wins, $0.games)
                        }, .profile
                    ).map { (profile, $0) }
                })

            func laneTerm(against opponent: ChampionID) -> LaneTerm? {
                let row = stats.matchup(for: champion, role: role, against: opponent)
                return delta(row.map { ($0.wins, $0.games) }, .matchup).map {
                    LaneTerm(delta: $0.delta, games: $0.games, sample: $0.sample, profiles: nil)
                } ?? profileBackoff
            }

            var reasons: [(impact: Double, reason: Reason)] = []
            var matchup = 0.0
            var counter = 0.0
            if let expected = expectedMatchup(
                of: champion, over: likelyOpponents, laneTerm: laneTerm)
            {
                matchup = expected.delta
                reasons.append(
                    (
                        weights.matchup * expected.delta,
                        Reason(
                            kind: .expectedMatchup(
                                role: role, delta: expected.delta, opponents: expected.opponents),
                            sample: expected.sample)
                    ))
            }
            for enemy in enemies {
                if enemy.lane > 0, let lane = laneTerm(against: enemy.champion) {
                    matchup += enemy.lane * lane.delta
                    let kind: Reason.Kind =
                        if let profiles = lane.profiles {
                            .profileMatchup(
                                opponent: enemy.champion, profiles: profiles, delta: lane.delta,
                                games: lane.games)
                        } else {
                            .matchup(
                                opponent: enemy.champion, delta: lane.delta, games: lane.games)
                        }
                    reasons.append(
                        (
                            weights.matchup * enemy.lane * lane.delta,
                            Reason(kind: kind, sample: lane.sample)
                        ))
                }
                let teamRow = stats.versusTeam(for: champion, role: role, against: enemy.champion)
                if enemy.lane < 1, let team = delta(teamRow.map { ($0.wins, $0.games) }, .vsTeam) {
                    counter += (1 - enemy.lane) * team.delta
                    reasons.append(
                        (
                            weights.counter * (1 - enemy.lane) * team.delta,
                            Reason(
                                kind: .versusEnemy(
                                    enemy: enemy.champion, delta: team.delta, games: team.games),
                                sample: team.sample)
                        ))
                }
            }

            var synergy = 0.0
            for ally in allies {
                let pairRow = stats.synergy(
                    for: champion, role: role, with: ally.champion, allyRole: ally.role)
                guard let pair = delta(pairRow.map { ($0.wins, $0.games) }, .synergy) else {
                    continue
                }
                let multiplier = isStrongPair(role, ally.role) ? strongPairMultiplier : 1
                synergy += multiplier * pair.delta
                reasons.append(
                    (
                        weights.synergy * multiplier * pair.delta,
                        Reason(
                            kind: .synergy(
                                ally: ally.champion, allyRole: ally.role, delta: pair.delta,
                                games: pair.games),
                            sample: pair.sample)
                    ))
            }

            let metaValue = meta.priors.championRoleWinrate(wins: row.wins, games: row.games) - 0.5
            if let tier = meta.tier(for: row) {
                reasons.append(
                    (
                        weights.meta * metaValue,
                        Reason(kind: .meta(tier: tier, games: row.games), sample: confidence)
                    ))
            }

            let compFit = Composition.compFit(
                candidate: champion, role: role, allies: allies, stats: stats)
            reasons += compFit.bonuses.map { (weights.composition * $0.value, $0.reason) }

            let personalTerm = personal(champion, role)
            if let personalTerm, personalTerm.points != 0, personalTerm.games > 0 {
                reasons.append(
                    (
                        weights.personal * personalTerm.points,
                        Reason(
                            kind: .comfort(
                                poolRank: personalTerm.poolRank, games: personalTerm.games,
                                winrate: Double(personalTerm.wins) / Double(personalTerm.games)),
                            sample: nil)
                    ))
            }

            let components: [PickComponent: Double] = [
                .meta: weights.meta * metaValue,
                .matchup: weights.matchup * matchup,
                .counter: weights.counter * counter,
                .synergy: weights.synergy * synergy,
                .composition: weights.composition * compFit.value,
                .personal: weights.personal * (personalTerm?.points ?? 0),
                .penalties: 0,
            ]
            let ordered = reasons.enumerated().sorted {
                abs($0.element.impact) != abs($1.element.impact)
                    ? abs($0.element.impact) > abs($1.element.impact) : $0.offset < $1.offset
            }

            return PickRecommendation(
                champion: champion,
                score: PickComponent.allCases.reduce(0) { $0 + (components[$1] ?? 0) },
                components: components,
                reasons: ordered.map(\.element.reason),
                confidence: confidence)
        }

        return Array(
            ranked.sorted {
                $0.score != $1.score
                    ? $0.score > $1.score : $0.champion.rawValue < $1.champion.rawValue
            }
            .prefix(limit))
    }

    private static func isCandidate(
        _ champion: ChampionID, mode: ChampSelectSettings.Candidates, pool: Set<ChampionID>,
        owned: Set<ChampionID>
    ) -> Bool {
        switch mode {
        case .myPool: pool.contains(champion) && owned.contains(champion)
        case .owned: owned.contains(champion)
        case .all: true
        }
    }

    private static func isStrongPair(_ lhs: Role, _ rhs: Role) -> Bool {
        let pair: Set<Role> = [lhs, rhs]
        return pair == [.bottom, .utility] || pair == [.jungle, .middle]
    }

    private struct LockedEnemy {
        let champion: ChampionID
        /// The probability that this enemy is the lane opponent.
        let lane: Double
    }

    /// A slot with a role holds it; the rest get `roleProbabilities` over the roles left (§12.3).
    private static func laneOdds(of slots: [DraftSlot], in role: Role, stats: some StatsProvider)
        -> [LockedEnemy]
    {
        let inferred = RoleInference.infer(
            enemies: slots.filter { $0.role == nil }.compactMap(\.champion),
            takenRoles: Set(slots.compactMap(\.role)), stats: stats)
        var odds = inferred.makeIterator()

        return slots.compactMap { slot in
            guard let champion = slot.champion else { return nil }
            if let assigned = slot.role {
                return LockedEnemy(champion: champion, lane: assigned == role ? 1 : 0)
            }
            return LockedEnemy(champion: champion, lane: odds.next()?.roleProbabilities[role] ?? 0)
        }
    }

    /// One extra, so each candidate still has `likelyOpponentCount` after leaving itself out.
    private static func likeliestOpponents(
        in role: Role, excluding taken: Set<ChampionID>, stats: some StatsProvider,
        meta: SnapshotMeta
    ) -> [(champion: ChampionID, games: Int)] {
        let ranked = stats.championRoleStats(in: role).compactMap {
            champion, row -> (champion: ChampionID, games: Int)? in
            guard !taken.contains(champion),
                let level = meta.sampleLevel(.championRole, games: row.games),
                level != .belowMinimum
            else { return nil }
            return (champion, row.games)
        }
        return Array(
            ranked.sorted {
                $0.games != $1.games
                    ? $0.games > $1.games : $0.champion.rawValue < $1.champion.rawValue
            }
            .prefix(likelyOpponentCount + 1))
    }

    /// Unrenormalized: an opponent without a usable delta pulls the term toward 0.
    private static func expectedMatchup(
        of champion: ChampionID, over likely: [(champion: ChampionID, games: Int)],
        laneTerm: (ChampionID) -> LaneTerm?
    ) -> (delta: Double, opponents: Int, sample: SampleLevel)? {
        let field = likely.filter { $0.champion != champion }.prefix(likelyOpponentCount)
        let total = field.reduce(0) { $0 + $1.games }
        guard total > 0 else { return nil }
        var delta = 0.0
        var samples: [SampleLevel] = []
        for opponent in field {
            guard let lane = laneTerm(opponent.champion) else { continue }
            delta += Double(opponent.games) / Double(total) * lane.delta
            samples.append(lane.sample)
        }
        guard let sample = samples.min() else { return nil }
        return (delta, samples.count, sample)
    }

    /// A lane matchup term: the `matchup_stats` row or its backoff to the enemy profile.
    private struct LaneTerm {
        let delta: Double
        let games: Int
        let sample: SampleLevel
        /// The labels behind a backoff; `nil` for a `matchup_stats` row.
        let profiles: [EnemyProfile]?
    }

    /// The §18.1 backoff to the enemy profile: the usable `champ_vs_profile` deltas of its
    /// labels, mixed by games. The labels share matches, so the sample is the weakest one.
    private static func profileDelta(of rows: [(profile: EnemyProfile, delta: MatchupDelta)])
        -> LaneTerm?
    {
        let games = rows.reduce(0) { $0 + $1.delta.games }
        guard games > 0, let sample = rows.map(\.delta.sample).min() else { return nil }
        return LaneTerm(
            delta: rows.reduce(0) { $0 + Double($1.delta.games) * $1.delta.delta } / Double(games),
            games: games, sample: sample, profiles: rows.map(\.profile))
    }
}
