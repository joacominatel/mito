public import MitoCore

/// A locked champion and the role its `champion_profiles` row is read for.
public struct TeamMember: Hashable, Sendable {
    public let champion: ChampionID
    public let role: Role

    public init(champion: ChampionID, role: Role) {
        self.champion = champion
        self.role = role
    }
}

/// A team's profile of `MITO_CONTEXT.md` §18.4 over the members with a profile.
public struct TeamProfile: Hashable, Sendable {
    /// Members with a `champion_profiles` row; the rest are skipped, as the pipeline does.
    public let profiledMembers: Int
    /// `team_phys`; 0 when the profiled members deal no damage.
    public let physicalShare: Double
    /// `team_magic`; 0 when the profiled members deal no damage.
    public let magicShare: Double
    /// `team_tank`.
    public let tankiness: Double
    /// `team_cc`.
    public let ccScore: Double
    /// The highest member `tankiness`, 0 without profiled members: the frontline rule reads it.
    public let topTankiness: Double
    /// Some member, profiled or not, carries the `engage` flag.
    public let hasEngage: Bool

    public init(
        profiledMembers: Int, physicalShare: Double, magicShare: Double, tankiness: Double,
        ccScore: Double, topTankiness: Double, hasEngage: Bool
    ) {
        self.profiledMembers = profiledMembers
        self.physicalShare = physicalShare
        self.magicShare = magicShare
        self.tankiness = tankiness
        self.ccScore = ccScore
        self.topTankiness = topTankiness
        self.hasEngage = hasEngage
    }

    /// The mean `cc_score` that `heavy_cc` compares; 0 without profiled members.
    public var meanCCScore: Double {
        profiledMembers > 0 ? ccScore / Double(profiledMembers) : 0
    }
}

/// Team profiles, the enemy profile, and comp fit (§18.4).
public enum Composition {
    /// The locked slots in draft order, each in its assigned role or, without one, the role
    /// inferred among the locked slots without a role (§12.3). A slot left without a role is
    /// dropped.
    public static func members(of slots: [DraftSlot], stats: some StatsProvider) -> [TeamMember] {
        let locked = slots.filter { $0.champion != nil }
        let unassigned = locked.filter { $0.role == nil }.compactMap(\.champion)
        let inferred = RoleInference.infer(
            enemies: unassigned, takenRoles: Set(slots.compactMap(\.role)), stats: stats)
        var inferredRoles = inferred.makeIterator()

        return locked.compactMap { slot in
            guard let champion = slot.champion else { return nil }
            if let role = slot.role { return TeamMember(champion: champion, role: role) }
            return inferredRoles.next()?.role.map { TeamMember(champion: champion, role: $0) }
        }
    }

    public static func teamProfile(of members: [TeamMember], stats: some StatsProvider)
        -> TeamProfile
    {
        let profiles = members.compactMap {
            stats.championProfile(for: $0.champion, role: $0.role)
        }
        let damage = profiles.reduce(0) { $0 + $1.damagePerMinute }
        let physical = profiles.reduce(0) { $0 + $1.physicalShare * $1.damagePerMinute }
        let magic = profiles.reduce(0) { $0 + $1.magicShare * $1.damagePerMinute }

        return TeamProfile(
            profiledMembers: profiles.count,
            physicalShare: damage > 0 ? physical / damage : 0,
            magicShare: damage > 0 ? magic / damage : 0,
            tankiness: profiles.reduce(0) { $0 + $1.tankiness },
            ccScore: profiles.reduce(0) { $0 + $1.ccScore },
            topTankiness: profiles.map(\.tankiness).max() ?? 0,
            hasEngage: members.contains { stats.flags(of: $0.champion).contains(.engage) })
    }

    /// Multi-label; empty without `rules` or with fewer than `min_champions` profiled members.
    /// The thresholds are inclusive minimums, as the pipeline classifies matches (§14.10).
    public static func enemyProfile(of team: TeamProfile, rules: ProfileRules?)
        -> Set<EnemyProfile>
    {
        guard let rules, team.profiledMembers >= rules.minimumChampions else { return [] }
        var labels: Set<EnemyProfile> = []
        if team.physicalShare >= rules.heavyADPhysicalShare { labels.insert(.heavyAD) }
        if team.magicShare >= rules.heavyAPMagicShare { labels.insert(.heavyAP) }
        if team.meanCCScore >= rules.heavyCCScore { labels.insert(.heavyCC) }
        if labels.isDisjoint(with: rules.mixedExcludes) { labels.insert(.mixed) }
        return labels
    }

    /// The profile of the locked enemies, with the rules of the open snapshot.
    public static func enemyProfile(in draft: DraftContext, stats: some StatsProvider)
        -> Set<EnemyProfile>
    {
        enemyProfile(
            of: teamProfile(of: members(of: draft.enemies, stats: stats), stats: stats),
            rules: stats.meta?.profileRules)
    }
}
