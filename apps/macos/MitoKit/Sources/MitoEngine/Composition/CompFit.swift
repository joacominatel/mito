public import MitoCore

/// `comp_fit` of one (champ, role) against its allied team, with the rules that fired (§18.4).
public struct CompFit: Hashable, Sendable {
    /// One rule that fired and what it adds.
    public struct Bonus: Hashable, Sendable {
        public let reason: Reason
        /// In winrate points as a fraction, before `w_comp`.
        public let value: Double

        public init(reason: Reason, value: Double) {
            self.reason = reason
            self.value = value
        }
    }

    /// The sum of the bonuses, in winrate points as fractions, before `w_comp`.
    public let value: Double
    /// Strongest first; equal bonuses keep the order of the §18.4 rules.
    public let bonuses: [Bonus]

    public init(value: Double, bonuses: [Bonus]) {
        self.value = value
        self.bonuses = bonuses
    }

    public var reasons: [Reason] { bonuses.map(\.reason) }
}

extension CompFit {
    /// Fewest profiled allies before the team is judged at all.
    static let minimumAllies = 3
    /// `team_phys` or `team_magic` above this is a damage gap.
    static let damageGapShare = 0.7
    /// A candidate's share of the missing damage type from which it fills the gap.
    static let fillingShare = 0.5
    /// The top 30 % of a 0–1 percentile, for `tankiness` and `cc_score`.
    static let topPercentile = 0.7
    /// `team_cc` is low below this mean `cc_score` per profiled ally, the role median.
    static let lowCCMean = 0.5

    static let damageGapBonus = 0.015
    static let frontlineBonus = 0.015
    /// Frontline from a mid or a bot lane counts less: "sobre todo en top, jungla y support".
    static let offRoleFrontlineBonus = 0.0075
    static let crowdControlBonus = 0.01
    static let engageBonus = 0.01

    static let frontlineRoles: Set<Role> = [.top, .jungle, .utility]
}

extension Composition {
    /// `allies` are the locked allies, without the candidate's own slot. Zero, with no reasons,
    /// below `CompFit.minimumAllies` profiled allies.
    public static func compFit(
        candidate: ChampionID, role: Role, allies: [TeamMember], stats: some StatsProvider
    ) -> CompFit {
        let team = teamProfile(of: allies, stats: stats)
        guard team.profiledMembers >= CompFit.minimumAllies else {
            return CompFit(value: 0, bonuses: [])
        }
        let profile = stats.championProfile(for: candidate, role: role)
        let sample = stats.championRoleStats(in: role)[candidate].flatMap {
            stats.meta?.sampleLevel(.championRole, games: $0.games)
        }
        var bonuses: [(value: Double, reason: Reason)] = []

        if let profile {
            if team.physicalShare > CompFit.damageGapShare,
                profile.magicShare >= CompFit.fillingShare
            {
                bonuses.append(
                    (
                        CompFit.damageGapBonus,
                        Reason(
                            kind: .fillsDamageGap(adds: .magic, alliedShare: team.physicalShare),
                            sample: sample)
                    ))
            } else if team.magicShare > CompFit.damageGapShare,
                profile.physicalShare >= CompFit.fillingShare
            {
                bonuses.append(
                    (
                        CompFit.damageGapBonus,
                        Reason(
                            kind: .fillsDamageGap(adds: .physical, alliedShare: team.magicShare),
                            sample: sample)
                    ))
            }

            if team.topTankiness < CompFit.topPercentile,
                profile.tankiness >= CompFit.topPercentile
            {
                bonuses.append(
                    (
                        CompFit.frontlineRoles.contains(role)
                            ? CompFit.frontlineBonus : CompFit.offRoleFrontlineBonus,
                        Reason(kind: .addsFrontline(tankiness: profile.tankiness), sample: sample)
                    ))
            }
        }

        let lacksControl =
            team.meanCCScore < CompFit.lowCCMean && !team.hasEngage
        if lacksControl, let profile, profile.ccScore >= CompFit.topPercentile {
            bonuses.append(
                (
                    CompFit.crowdControlBonus,
                    Reason(kind: .addsCrowdControl(ccScore: profile.ccScore), sample: sample)
                ))
        }
        if lacksControl, stats.flags(of: candidate).contains(.engage) {
            bonuses.append((CompFit.engageBonus, Reason(kind: .addsEngage, sample: nil)))
        }

        let ranked = bonuses.enumerated().sorted {
            $0.element.value != $1.element.value
                ? $0.element.value > $1.element.value : $0.offset < $1.offset
        }
        return CompFit(
            value: bonuses.reduce(0) { $0 + $1.value },
            bonuses: ranked.map {
                CompFit.Bonus(reason: $0.element.reason, value: $0.element.value)
            })
    }

    /// The comp fit for the local player: the locked allies other than `draft.myCellId`.
    public static func compFit(
        candidate: ChampionID, role: Role, in draft: DraftContext, stats: some StatsProvider
    ) -> CompFit {
        compFit(
            candidate: candidate, role: role,
            allies: members(of: draft.allies.filter { $0.cellId != draft.myCellId }, stats: stats),
            stats: stats)
    }
}
