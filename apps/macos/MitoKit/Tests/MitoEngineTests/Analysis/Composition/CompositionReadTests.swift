import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

/// The Composición tab's read of both teams (§20.2).
struct CompositionReadTests {
    private static let roles: [Role] = [.top, .jungle, .middle, .bottom, .utility]

    /// Champions 1…n for allies and 101…n for enemies, one per role in order.
    private static func members(_ count: Int, from first: Int) -> [TeamMember] {
        (0..<count).map {
            TeamMember(champion: ChampionID(rawValue: first + $0), role: roles[$0])
        }
    }

    private static func stats(
        _ members: [TeamMember], profile: (Int) -> ChampionProfile,
        curve: [DurationBucket: RelationStats]? = nil
    ) -> InMemoryStatsProvider {
        var stats = InMemoryStatsProvider(meta: compositionMeta())
        for (index, member) in members.enumerated() {
            stats.championProfilesByChampion[member.champion] = [member.role: profile(index)]
            if let curve {
                stats.durationCurvesByChampion[member.champion] = [member.role: curve]
            }
        }
        return stats
    }

    private static func merged(_ lhs: InMemoryStatsProvider, _ rhs: InMemoryStatsProvider)
        -> InMemoryStatsProvider
    {
        var stats = lhs
        stats.championProfilesByChampion.merge(rhs.championProfilesByChampion) { $1 }
        stats.durationCurvesByChampion.merge(rhs.durationCurvesByChampion) { $1 }
        return stats
    }

    // MARK: - Levels

    @Test(arguments: [(0, CompositionLevel.low), (1, .medium), (2, .high), (5, .high)])
    func levelsCountTheMembersInTheRolesTopThirtyPercent(count: Int, level: CompositionLevel) {
        let team = Self.members(5, from: 1)
        let stats = Self.stats(team) {
            championProfile(tankiness: $0 < count ? 0.7 : 0.69, cc: $0 < count ? 0.9 : 0.2)
        }

        let read = Composition.teamRead(of: team, stats: stats, timing: true)

        #expect(read.frontline == level)
        #expect(read.crowdControl == level)
    }

    @Test func frontlineAndCrowdControlAreReadSeparately() {
        let team = Self.members(3, from: 1)
        let stats = Self.stats(team) { _ in championProfile(tankiness: 0.9, cc: 0.1) }

        let read = Composition.teamRead(of: team, stats: stats, timing: true)

        #expect(read.frontline == .high)
        #expect(read.crowdControl == .low)
    }

    @Test func withoutProfiledMembersThereIsNoLevel() {
        let read = Composition.teamRead(
            of: Self.members(3, from: 1), stats: InMemoryStatsProvider(meta: compositionMeta()),
            timing: true)

        #expect(read.profile.profiledMembers == 0)
        #expect(read.frontline == nil)
        #expect(read.crowdControl == nil)
    }

    // MARK: - Early vs late

    @Test func theTeamCurveAveragesItsMembersStrengths() throws {
        let team = Self.members(2, from: 1)
        var stats = Self.stats(team) { _ in championProfile() }
        stats.durationCurvesByChampion = [
            team[0].champion: [team[0].role: earlyCurve],
            team[1].champion: [team[1].role: lateCurve],
        ]

        let curve = try #require(
            Composition.teamRead(of: team, stats: stats, timing: true).curve)

        #expect(curve.members == 2)
        #expect(isClose(curve.early, 0))
        #expect(isClose(curve.late, 0))
    }

    @Test(arguments: [
        (earlyCurve, TeamCurve.Phase.early), (lateCurve, .late), (flatCurve, .even),
    ])
    func threeMembersWithACurveGiveTheTeamAPhase(
        curve: [DurationBucket: RelationStats], phase: TeamCurve.Phase
    ) {
        let team = Self.members(3, from: 1)
        let stats = Self.stats(team, profile: { _ in championProfile() }, curve: curve)

        #expect(Composition.teamRead(of: team, stats: stats, timing: true).curve?.phase == phase)
    }

    @Test func theCompFitsThresholdsDecideThePhase() {
        #expect(TeamCurve(early: 0.005, late: 0, members: 3).phase == .early)
        #expect(TeamCurve(early: 0.0049, late: 0, members: 3).phase == .even)
        #expect(TeamCurve(early: -0.005, late: 0, members: 3).phase == .late)
        #expect(TeamCurve(early: 0.05, late: 0, members: 2).phase == nil)
    }

    @Test func withoutTimingThereIsNoCurveAndNoSpike() {
        let team = Self.members(3, from: 1)
        let stats = Self.stats(team, profile: { _ in spikes(levelSix: 400) }, curve: earlyCurve)

        let read = Composition.teamRead(of: team, stats: stats, timing: false)

        #expect(read.curve == nil)
        #expect(
            read.spikes
                == TeamSpikes(levelSix: nil, firstItem: nil, secondItem: nil, thirdItem: nil))
        #expect(read.frontline != nil)
    }

    // MARK: - Spikes

    @Test func spikesAverageTheMembersWithEachTiming() {
        let team = Self.members(3, from: 1)
        let stats = Self.stats(team) {
            [
                spikes(levelSix: 400, firstItem: 600, secondItem: 900),
                spikes(levelSix: 431, firstItem: 700),
                spikes(),
            ][$0]
        }

        let read = Composition.teamRead(of: team, stats: stats, timing: true)

        #expect(
            read.spikes
                == TeamSpikes(levelSix: 416, firstItem: 650, secondItem: 900, thirdItem: nil))
    }

    // MARK: - Win conditions

    @Test func anEarlyTeamAgainstALateOneClosesEarlyAndTheOtherScales() {
        let read = Self.read(allyCurve: earlyCurve, enemyCurve: lateCurve)

        #expect(
            read.winConditions == [
                .closeEarly(.allies, byMinute: 25), .scaleLate(.enemies, fromMinute: 35),
            ])
    }

    @Test func twoTeamsInTheSamePhaseHaveNoCurveCondition() {
        #expect(Self.read(allyCurve: earlyCurve, enemyCurve: earlyCurve).winConditions.isEmpty)
        #expect(Self.read(allyCurve: flatCurve, enemyCurve: flatCurve).winConditions.isEmpty)
    }

    @Test func aLateTeamAgainstAnEvenOneScales() {
        #expect(
            Self.read(allyCurve: lateCurve, enemyCurve: flatCurve).winConditions == [
                .scaleLate(.allies, fromMinute: 35)
            ])
    }

    @Test func aTeamALevelAboveInFrontlineOrCCHasTheEdge() {
        let read = Self.read(
            ally: { _ in championProfile(tankiness: 0.9, cc: 0.1) },
            enemy: { championProfile(tankiness: 0.1, cc: $0 < 2 ? 0.9 : 0.1) })

        #expect(read.winConditions == [.frontline(.allies), .crowdControl(.enemies)])
    }

    @Test func aOneSidedEnemyDealsMoreThanSeventyPercentOfOneType() {
        func enemy(physical: Double) -> CompositionRead {
            Self.read(enemy: { _ in
                championProfile(physical: physical, magic: 1 - physical, tankiness: 0.5, cc: 0.5)
            })
        }

        #expect(
            enemy(physical: 0.75).winConditions == [.oneSidedEnemyDamage(.physical, share: 0.75)])
        #expect(enemy(physical: 0.25).winConditions == [.oneSidedEnemyDamage(.magic, share: 0.75)])
        #expect(enemy(physical: 0.6875).winConditions.isEmpty)
    }

    @Test func belowThreeProfiledMembersOnASideNothingIsCompared() {
        let read = Self.read(
            allies: 2, allyCurve: earlyCurve, enemyCurve: lateCurve,
            ally: { _ in championProfile(tankiness: 0.9) },
            enemy: { _ in championProfile(physical: 0.9, magic: 0.1, tankiness: 0.1) })

        #expect(read.winConditions == [.oneSidedEnemyDamage(.physical, share: 0.9)])
    }

    @Test func theEnemyProfileUsesTheSnapshotsRules() {
        let read = Self.read(enemy: { _ in championProfile(physical: 0.8, magic: 0.2, cc: 0.6) })

        #expect(read.enemyProfile == [.heavyAD, .heavyCC])
    }

    @Test func emptyTeamsReadAsNothing() {
        let read = Composition.read(
            allies: [], enemies: [], stats: InMemoryStatsProvider(meta: compositionMeta()))

        #expect(read.allies.profile.profiledMembers == 0)
        #expect(read.enemyProfile.isEmpty)
        #expect(read.winConditions.isEmpty)
    }

    @Test func withoutASnapshotThereIsNoTeamCurve() {
        let team = Self.members(3, from: 1)
        var stats = Self.stats(team, profile: { _ in championProfile() }, curve: earlyCurve)
        stats.meta = nil

        let read = Composition.teamRead(of: team, stats: stats, timing: true)

        #expect(read.curve == nil)
        #expect(read.frontline != nil)
    }

    @Test(arguments: [(0.7, false), (0.71, true)])
    func oneSidedDamageNeedsMoreThanSeventyPercent(share: Double, isOneSided: Bool) {
        let even = TeamRead(
            profile: team(members: 3), frontline: .low, crowdControl: .low, curve: nil,
            spikes: TeamSpikes(levelSix: nil, firstItem: nil, secondItem: nil, thirdItem: nil))
        let enemies = TeamRead(
            profile: team(members: 3, physical: share, magic: 1 - share), frontline: .low,
            crowdControl: .low, curve: nil, spikes: even.spikes)

        let conditions = Composition.winConditions(allies: even, enemies: enemies)

        #expect(conditions == (isOneSided ? [.oneSidedEnemyDamage(.physical, share: share)] : []))
    }

    @Test func curveConditionsNeedThreeMembersWithACurveOnTheOtherSideToo() {
        let allies = Self.members(3, from: 1)
        let enemies = Self.members(3, from: 101)
        var stats = Self.merged(
            Self.stats(
                allies, profile: { _ in championProfile(tankiness: 0.5, cc: 0.5) },
                curve: earlyCurve),
            Self.stats(
                enemies, profile: { _ in championProfile(tankiness: 0.5, cc: 0.5) },
                curve: lateCurve))
        stats.durationCurvesByChampion[enemies[2].champion] = nil

        let read = Composition.read(allies: allies, enemies: enemies, stats: stats)

        #expect(read.enemies.curve?.members == 2)
        #expect(read.winConditions.isEmpty)
    }

    @Test func withoutTimingTheCurvesMakeNoCondition() {
        let allies = Self.members(3, from: 1)
        let enemies = Self.members(3, from: 101)
        let stats = Self.merged(
            Self.stats(
                allies, profile: { _ in championProfile(tankiness: 0.5, cc: 0.5) },
                curve: earlyCurve),
            Self.stats(
                enemies, profile: { _ in championProfile(tankiness: 0.5, cc: 0.5) },
                curve: lateCurve))

        let read = Composition.read(allies: allies, enemies: enemies, stats: stats, timing: false)

        #expect(read.winConditions.isEmpty)
        #expect(read.allies.spikes.levelSix == nil)
    }

    @Test func aMemberWithAProfileButNoCurveIsLeftOutOfTheTeamCurve() throws {
        let team = Self.members(3, from: 1)
        var stats = Self.stats(team, profile: { _ in championProfile() }, curve: earlyCurve)
        stats.durationCurvesByChampion[team[0].champion] = nil

        let read = Composition.teamRead(of: team, stats: stats, timing: true)

        #expect(read.profile.profiledMembers == 3)
        let curve = try #require(read.curve)
        #expect(curve.members == 2)
        #expect(curve.phase == nil)
    }

    // MARK: - Helpers

    /// Even teams of three unless told otherwise, so only what a test changes fires.
    private static func read(
        allies: Int = 3, allyCurve: [DurationBucket: RelationStats]? = nil,
        enemyCurve: [DurationBucket: RelationStats]? = nil,
        ally: (Int) -> ChampionProfile = { _ in championProfile(tankiness: 0.5, cc: 0.5) },
        enemy: (Int) -> ChampionProfile = { _ in championProfile(tankiness: 0.5, cc: 0.5) }
    ) -> CompositionRead {
        let allied = members(allies, from: 1)
        let enemies = members(3, from: 101)
        return Composition.read(
            allies: allied, enemies: enemies,
            stats: merged(
                stats(allied, profile: ally, curve: allyCurve),
                stats(enemies, profile: enemy, curve: enemyCurve)))
    }
}

private func spikes(
    levelSix: Int? = nil, firstItem: Int? = nil, secondItem: Int? = nil, thirdItem: Int? = nil
) -> ChampionProfile {
    ChampionProfile(
        physicalShare: 0.5, magicShare: 0.5, trueShare: 0, damagePerMinute: 1, tankiness: 0.5,
        ccScore: 0.5, timelineGames: 100, levelSixSeconds: levelSix, firstItemSeconds: firstItem,
        secondItemSeconds: secondItem, thirdItemSeconds: thirdItem)
}
