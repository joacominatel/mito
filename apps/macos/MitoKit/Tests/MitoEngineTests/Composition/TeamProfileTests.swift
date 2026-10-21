import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

struct TeamProfileTests {
    private let garen = ChampionID(rawValue: 86)
    private let ahri = ChampionID(rawValue: 103)
    private let jinx = ChampionID(rawValue: 222)
    private let leona = ChampionID(rawValue: 89)
    private let leeSin = ChampionID(rawValue: 64)

    private func members(_ pairs: [(ChampionID, Role)]) -> [TeamMember] {
        pairs.map { TeamMember(champion: $0.0, role: $0.1) }
    }

    // MARK: - Team profile

    @Test func damageSharesAreWeightedByDamagePerMinute() {
        let stats = InMemoryStatsProvider(championProfilesByChampion: [
            garen: [.top: championProfile(physical: 1, magic: 0, damage: 600)],
            ahri: [.middle: championProfile(physical: 0, magic: 1, damage: 200)],
            jinx: [.bottom: championProfile(physical: 0.5, magic: 0.5, damage: 200)],
        ])

        let profile = Composition.teamProfile(
            of: members([(garen, .top), (ahri, .middle), (jinx, .bottom)]), stats: stats)

        // (1·600 + 0·200 + 0.5·200) / 1000; the unweighted mean would be 0.5.
        #expect(isClose(profile.physicalShare, 0.7))
        #expect(isClose(profile.magicShare, 0.3))
    }

    @Test func tankinessAndCrowdControlAreSummedAndTheTopTankIsKept() {
        let stats = InMemoryStatsProvider(championProfilesByChampion: [
            garen: [.top: championProfile(tankiness: 0.75, cc: 0.25)],
            ahri: [.middle: championProfile(tankiness: 0.125, cc: 0.5)],
        ])

        let profile = Composition.teamProfile(
            of: members([(garen, .top), (ahri, .middle)]), stats: stats)

        #expect(profile.tankiness == 0.875)
        #expect(profile.ccScore == 0.75)
        #expect(profile.topTankiness == 0.75)
        #expect(profile.meanCCScore == 0.375)
    }

    @Test func membersWithoutAProfileAreSkipped() {
        let stats = InMemoryStatsProvider(championProfilesByChampion: [
            garen: [.top: championProfile(physical: 1, magic: 0, damage: 100, cc: 0.5)],
            // Ahri has a mid profile only, so Ahri top is unprofiled.
            ahri: [.middle: championProfile(physical: 0, magic: 1, damage: 100, cc: 1)],
        ])

        let profile = Composition.teamProfile(
            of: members([(garen, .top), (ahri, .top), (jinx, .bottom)]), stats: stats)

        #expect(profile.profiledMembers == 1)
        #expect(profile.physicalShare == 1)
        #expect(profile.meanCCScore == 0.5)
    }

    @Test func aTeamWithoutDamageHasZeroShares() {
        let stats = InMemoryStatsProvider(championProfilesByChampion: [
            garen: [.top: championProfile(physical: 1, magic: 0, damage: 0)]
        ])

        let profile = Composition.teamProfile(of: members([(garen, .top)]), stats: stats)

        #expect(profile.physicalShare == 0)
        #expect(profile.magicShare == 0)
    }

    @Test func anEmptyTeamHasAnEmptyProfile() {
        let profile = Composition.teamProfile(of: [], stats: InMemoryStatsProvider())

        #expect(
            profile
                == TeamProfile(
                    profiledMembers: 0, physicalShare: 0, magicShare: 0, tankiness: 0,
                    ccScore: 0, topTankiness: 0, hasEngage: false))
        #expect(profile.meanCCScore == 0)
    }

    @Test func engageCountsMembersWithoutAProfile() {
        let stats = InMemoryStatsProvider(flagsByChampion: [leona: [.engage]])

        let profile = Composition.teamProfile(of: members([(leona, .utility)]), stats: stats)

        #expect(profile.profiledMembers == 0)
        #expect(profile.hasEngage)
    }

    // MARK: - Members from the draft

    @Test func membersAreTheLockedSlotsInTheirAssignedRoles() {
        let slots = [slot(0, garen, .top), slot(1, nil, .jungle), slot(2, ahri, .middle)]

        let result = Composition.members(of: slots, stats: InMemoryStatsProvider())

        #expect(result == members([(garen, .top), (ahri, .middle)]))
    }

    @Test func lockedSlotsWithoutARoleGetTheInferredRole() {
        let stats = InMemoryStatsProvider(roleGamesByChampion: [
            jinx: [.bottom: 900, .middle: 50],
            leona: [.utility: 900, .top: 50],
        ])
        let slots = [slot(5, leona, nil), slot(6, garen, .top), slot(7, jinx, nil)]

        let result = Composition.members(of: slots, stats: stats)

        #expect(result == members([(leona, .utility), (garen, .top), (jinx, .bottom)]))
    }

    // MARK: - Enemy profile

    @Test func heavyADStartsExactlyAtItsThreshold() {
        #expect(
            Composition.enemyProfile(of: team(physical: 0.625), rules: exactRules) == [.heavyAD])
        #expect(
            !Composition.enemyProfile(of: team(physical: 0.625.nextDown), rules: exactRules)
                .contains(.heavyAD))
    }

    @Test func heavyAPStartsExactlyAtItsThreshold() {
        #expect(
            Composition.enemyProfile(of: team(physical: 0, magic: 0.5625), rules: exactRules)
                == [.heavyAP])
        #expect(
            !Composition.enemyProfile(
                of: team(physical: 0, magic: 0.5625.nextDown), rules: exactRules
            )
            .contains(.heavyAP))
    }

    @Test func heavyCCStartsExactlyAtItsMeanThreshold() {
        // Four members: a mean of 0.5 is a sum of 2.
        #expect(
            Composition.enemyProfile(of: team(ccScore: 2), rules: exactRules)
                .contains(.heavyCC))
        #expect(
            !Composition.enemyProfile(of: team(ccScore: 2.0.nextDown), rules: exactRules)
                .contains(.heavyCC))
    }

    @Test func aTeamNeitherHeavyADNorHeavyAPIsMixed() {
        #expect(Composition.enemyProfile(of: team(), rules: exactRules) == [.mixed])
    }

    @Test func aHeavyTeamIsNotMixed() {
        #expect(
            !Composition.enemyProfile(of: team(physical: 0.75, magic: 0.25), rules: exactRules)
                .contains(.mixed))
        #expect(
            !Composition.enemyProfile(of: team(physical: 0.25, magic: 0.75), rules: exactRules)
                .contains(.mixed))
    }

    @Test func mixedExcludesOnlyTheProfilesTheRulesName() {
        let rules = ProfileRules(
            minimumChampions: 3, heavyADPhysicalShare: 0.625, heavyAPMagicShare: 0.5625,
            heavyCCScore: 0.5, mixedExcludes: [.heavyAD])

        let labels = Composition.enemyProfile(of: team(physical: 0.25, magic: 0.75), rules: rules)

        #expect(labels == [.heavyAP, .mixed])
    }

    @Test func aTeamCanCarrySeveralProfiles() {
        let labels = Composition.enemyProfile(
            of: team(physical: 0.75, magic: 0.25, ccScore: 3), rules: exactRules)

        #expect(labels == [.heavyAD, .heavyCC])
    }

    @Test func fewerProfiledMembersThanTheMinimumGiveNoProfile() {
        let labels = Composition.enemyProfile(
            of: team(members: 2, physical: 1, magic: 0, ccScore: 2), rules: exactRules)

        #expect(labels.isEmpty)
    }

    @Test func withoutProfileRulesNoTeamHasAProfile() {
        #expect(Composition.enemyProfile(of: team(physical: 1, magic: 0), rules: nil).isEmpty)
    }

    @Test func theDraftEnemyProfileUsesTheSnapshotRules() {
        let profiles: [ChampionID: [Role: ChampionProfile]] = [
            garen: [.top: championProfile(physical: 1, magic: 0)],
            leeSin: [.jungle: championProfile(physical: 1, magic: 0)],
            jinx: [.bottom: championProfile(physical: 1, magic: 0)],
        ]
        let enemies = [slot(5, garen, .top), slot(6, leeSin, .jungle), slot(7, jinx, .bottom)]

        let withRules = InMemoryStatsProvider(
            meta: compositionMeta(), championProfilesByChampion: profiles)
        let withoutRules = InMemoryStatsProvider(
            meta: compositionMeta(rules: nil), championProfilesByChampion: profiles)

        #expect(
            Composition.enemyProfile(in: draft(enemies: enemies), stats: withRules) == [
                .heavyAD,
                .heavyCC,
            ])
        #expect(Composition.enemyProfile(in: draft(enemies: enemies), stats: withoutRules).isEmpty)
    }

    @Test func theDraftEnemyProfileSkipsUnprofiledEnemiesBeforeTheMinimum() {
        let stats = InMemoryStatsProvider(
            meta: compositionMeta(),
            championProfilesByChampion: [
                garen: [.top: championProfile(physical: 1, magic: 0)],
                jinx: [.bottom: championProfile(physical: 1, magic: 0)],
            ])
        let enemies = [slot(5, garen, .top), slot(6, leeSin, .jungle), slot(7, jinx, .bottom)]

        #expect(Composition.enemyProfile(in: draft(enemies: enemies), stats: stats).isEmpty)
    }
}
