public import MitoCore

/// How much of something a team has, for the Composición tab (§20.2).
public enum CompositionLevel: Int, Comparable, Hashable, Sendable {
    case low
    case medium
    case high

    /// How many profiled members reach the role's top 30 %: none is low, one medium, two or more
    /// high.
    init(membersInTopPercentile count: Int) {
        self = count == 0 ? .low : count == 1 ? .medium : .high
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A team's `early_strength` and `late_strength`, averaged over the members with a curve.
public struct TeamCurve: Hashable, Sendable {
    public enum Phase: Hashable, Sendable {
        case early
        case late
        case even
    }

    public let early: Double
    public let late: Double
    /// Members with a curve.
    public let members: Int

    public init(early: Double, late: Double, members: Int) {
        self.early = early
        self.late = late
        self.members = members
    }

    /// The comp fit's reading of `team_early` (§18.4); `nil` below its minimum of members.
    public var phase: Phase? {
        guard members >= CompFit.minimumAllies else { return nil }
        if early >= CompFit.teamStrength { return .early }
        if early <= -CompFit.teamStrength { return .late }
        return .even
    }
}

/// A team's power spikes: the mean of the members' `champion_profiles` medians, in seconds.
/// Each is `nil` when no member has it.
public struct TeamSpikes: Hashable, Sendable {
    public let levelSix: Int?
    public let firstItem: Int?
    public let secondItem: Int?
    public let thirdItem: Int?

    public init(levelSix: Int?, firstItem: Int?, secondItem: Int?, thirdItem: Int?) {
        self.levelSix = levelSix
        self.firstItem = firstItem
        self.secondItem = secondItem
        self.thirdItem = thirdItem
    }
}

/// One team as the Composición tab reads it.
public struct TeamRead: Hashable, Sendable {
    public let profile: TeamProfile
    /// From `tankiness`; `nil` without profiled members.
    public let frontline: CompositionLevel?
    /// From `cc_score`; `nil` without profiled members.
    public let crowdControl: CompositionLevel?
    /// `nil` without timing or without a member with a curve.
    public let curve: TeamCurve?
    public let spikes: TeamSpikes

    public init(
        profile: TeamProfile, frontline: CompositionLevel?, crowdControl: CompositionLevel?,
        curve: TeamCurve?, spikes: TeamSpikes
    ) {
        self.profile = profile
        self.frontline = frontline
        self.crowdControl = crowdControl
        self.curve = curve
        self.spikes = spikes
    }
}

/// Both teams of the Composición tab (§20.2).
public struct CompositionRead: Hashable, Sendable {
    public let allies: TeamRead
    public let enemies: TeamRead
    /// `Composition.enemyProfile` with the snapshot's `profile_rules`.
    public let enemyProfile: Set<EnemyProfile>
    public let winConditions: [WinCondition]
}

extension Composition {
    /// `timing: false` leaves out the curves and the spikes, which measure Summoner's Rift
    /// games; ARAM passes it.
    public static func read(
        allies: [TeamMember], enemies: [TeamMember], stats: some StatsProvider,
        timing: Bool = true
    ) -> CompositionRead {
        let allied = teamRead(of: allies, stats: stats, timing: timing)
        let enemy = teamRead(of: enemies, stats: stats, timing: timing)
        return CompositionRead(
            allies: allied, enemies: enemy,
            enemyProfile: enemyProfile(of: enemy.profile, rules: stats.meta?.profileRules),
            winConditions: winConditions(allies: allied, enemies: enemy))
    }

    static func teamRead(of members: [TeamMember], stats: some StatsProvider, timing: Bool)
        -> TeamRead
    {
        let profiles = members.compactMap {
            stats.championProfile(for: $0.champion, role: $0.role)
        }
        func level(_ value: (ChampionProfile) -> Double) -> CompositionLevel? {
            guard !profiles.isEmpty else { return nil }
            return CompositionLevel(
                membersInTopPercentile: profiles.count(where: { value($0) >= CompFit.topPercentile }
                ))
        }
        func mean(_ seconds: (ChampionProfile) -> Int?) -> Int? {
            let values = timing ? profiles.compactMap(seconds) : []
            guard !values.isEmpty else { return nil }
            return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        }
        return TeamRead(
            profile: teamProfile(of: members, stats: stats),
            frontline: level(\.tankiness), crowdControl: level(\.ccScore),
            curve: timing ? teamCurve(of: members, stats: stats) : nil,
            spikes: TeamSpikes(
                levelSix: mean(\.levelSixSeconds), firstItem: mean(\.firstItemSeconds),
                secondItem: mean(\.secondItemSeconds), thirdItem: mean(\.thirdItemSeconds)))
    }

    static func teamCurve(of members: [TeamMember], stats: some StatsProvider) -> TeamCurve? {
        guard let priors = stats.meta?.priors else { return nil }
        let curves = members.compactMap {
            PowerCurve(stats.durationCurves(for: $0.champion, role: $0.role), priors: priors)
        }
        guard !curves.isEmpty else { return nil }
        let count = Double(curves.count)
        return TeamCurve(
            early: curves.reduce(0) { $0 + $1.early } / count,
            late: curves.reduce(0) { $0 + $1.late } / count, members: curves.count)
    }
}
