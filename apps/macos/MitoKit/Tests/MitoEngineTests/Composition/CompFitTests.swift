import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

struct CompFitTests {
    private let garen = ChampionID(rawValue: 86)
    private let leeSin = ChampionID(rawValue: 64)
    private let jinx = ChampionID(rawValue: 222)
    private let candidate = ChampionID(rawValue: 1)

    private var allies: [TeamMember] {
        [
            TeamMember(champion: garen, role: .top),
            TeamMember(champion: leeSin, role: .jungle),
            TeamMember(champion: jinx, role: .bottom),
        ]
    }

    /// Three allies with `ally`'s profile, so team values equal the member values; the default
    /// ally is balanced, has a frontline and enough CC, and fires no rule.
    private func stats(
        ally: ChampionProfile = championProfile(),
        candidate profile: ChampionProfile? = nil,
        candidateRole: Role = .top,
        flags: [ChampionID: Set<ChampionFlag>] = [:],
        candidateGames: Int? = nil
    ) -> InMemoryStatsProvider {
        var profiles: [ChampionID: [Role: ChampionProfile]] = [
            garen: [.top: ally], leeSin: [.jungle: ally], jinx: [.bottom: ally],
        ]
        profiles[candidate] = profile.map { [candidateRole: $0] }
        return InMemoryStatsProvider(
            meta: compositionMeta(),
            championRoleStatsByRole: candidateGames.map {
                [
                    candidateRole: [
                        candidate: ChampionRoleStats(games: $0, wins: 0, timelineGames: 0)
                    ]
                ]
            } ?? [:],
            championProfilesByChampion: profiles,
            flagsByChampion: flags)
    }

    private func fit(
        role: Role = .top, allies: [TeamMember]? = nil, _ stats: InMemoryStatsProvider
    ) -> CompFit {
        Composition.compFit(
            candidate: candidate, role: role, allies: allies ?? self.allies, stats: stats)
    }

    // MARK: - Damage balance

    @Test func aMagicCandidateFillsAPhysicalTeam() {
        let result = fit(
            stats(
                ally: championProfile(physical: 0.875, magic: 0.125),
                candidate: championProfile(physical: 0.25, magic: 0.75)))

        #expect(result.value == CompFit.damageGapBonus)
        #expect(
            result.reasons == [
                Reason(kind: .fillsDamageGap(adds: .magic, alliedShare: 0.875), sample: nil)
            ])
    }

    @Test func aPhysicalCandidateFillsAMagicTeam() {
        let result = fit(
            stats(
                ally: championProfile(physical: 0.125, magic: 0.875),
                candidate: championProfile(physical: 0.75, magic: 0.25)))

        #expect(
            result.reasons == [
                Reason(kind: .fillsDamageGap(adds: .physical, alliedShare: 0.875), sample: nil)
            ])
    }

    @Test func aCandidateOfTheSameDamageTypeFillsNoGap() {
        let result = fit(
            stats(
                ally: championProfile(physical: 0.875, magic: 0.125),
                candidate: championProfile(physical: 0.75, magic: 0.25)))

        #expect(result.reasons.isEmpty)
        #expect(result.value == 0)
    }

    // MARK: - Frontline

    @Test func aTankFillsATeamWithoutFrontline() {
        let result = fit(
            stats(
                ally: championProfile(tankiness: 0.5), candidate: championProfile(tankiness: 0.75)))

        #expect(result.value == CompFit.frontlineBonus)
        #expect(result.reasons == [Reason(kind: .addsFrontline(tankiness: 0.75), sample: nil)])
    }

    @Test func aTankOutsideTopJungleAndSupportAddsLessFrontline() {
        let result = fit(
            role: .middle,
            stats(
                ally: championProfile(tankiness: 0.5), candidate: championProfile(tankiness: 0.75),
                candidateRole: .middle))

        #expect(result.value == CompFit.offRoleFrontlineBonus)
        #expect(result.reasons == [Reason(kind: .addsFrontline(tankiness: 0.75), sample: nil)])
    }

    @Test func aTeamWithATopThirtyPercentTankNeedsNoFrontline() {
        let result = fit(
            stats(ally: championProfile(tankiness: 0.7), candidate: championProfile(tankiness: 1)))

        #expect(result.reasons.isEmpty)
    }

    // MARK: - CC and engage

    @Test func aCrowdControlCandidateFillsALowCCTeam() {
        let result = fit(
            stats(ally: championProfile(cc: 0.25), candidate: championProfile(cc: 0.75)))

        #expect(result.value == CompFit.crowdControlBonus)
        #expect(result.reasons == [Reason(kind: .addsCrowdControl(ccScore: 0.75), sample: nil)])
    }

    @Test func anEngageCandidateFillsALowCCTeamWithoutAProfile() {
        let result = fit(stats(ally: championProfile(cc: 0.25), flags: [candidate: [.engage]]))

        #expect(result.value == CompFit.engageBonus)
        #expect(result.reasons == [Reason(kind: .addsEngage, sample: nil)])
    }

    @Test func anAllyWithEngageCoversTheCCRule() {
        let result = fit(
            stats(
                ally: championProfile(cc: 0.25), candidate: championProfile(cc: 1),
                flags: [garen: [.engage], candidate: [.engage]]))

        #expect(result.reasons.isEmpty)
    }

    @Test func aTeamWithEnoughCCNeedsNone() {
        let result = fit(
            stats(
                ally: championProfile(cc: 0.5), candidate: championProfile(cc: 1),
                flags: [candidate: [.engage]]))

        #expect(result.reasons.isEmpty)
    }

    // MARK: - Gates, samples, and order

    @Test func anEmptyTeamGivesNoCompFit() {
        let result = fit(
            allies: [],
            stats(
                candidate: championProfile(magic: 1, tankiness: 1, cc: 1),
                flags: [candidate: [.engage]]))

        #expect(result == CompFit(value: 0, reasons: []))
    }

    @Test func fewerThanThreeProfiledAlliesGiveNoCompFit() {
        let unprofiled = TeamMember(champion: ChampionID(rawValue: 2), role: .middle)
        let result = fit(
            allies: Array(allies.prefix(2)) + [unprofiled],
            stats(
                ally: championProfile(tankiness: 0, cc: 0),
                candidate: championProfile(tankiness: 1, cc: 1)))

        #expect(result == CompFit(value: 0, reasons: []))
    }

    @Test func profileReasonsCarryTheCandidateChampionRoleSampleAndEngageCarriesNone() {
        let result = fit(
            stats(
                ally: championProfile(tankiness: 0, cc: 0),
                candidate: championProfile(tankiness: 1, cc: 1),
                flags: [candidate: [.engage]], candidateGames: 500))

        #expect(result.reasons.map(\.sample) == [.usable, .usable, nil])
    }

    @Test func reasonsGoStrongestFirstAndTiesKeepTheRuleOrder() {
        let gapAlly = championProfile(physical: 0.875, magic: 0.125, tankiness: 0, cc: 0)
        let allRules = championProfile(physical: 0, magic: 1, tankiness: 1, cc: 1)

        let top = fit(stats(ally: gapAlly, candidate: allRules, flags: [candidate: [.engage]]))
        let middle = fit(
            role: .middle,
            stats(
                ally: gapAlly, candidate: allRules, candidateRole: .middle,
                flags: [candidate: [.engage]]))

        let gap = Reason(kind: .fillsDamageGap(adds: .magic, alliedShare: 0.875), sample: nil)
        let frontline = Reason(kind: .addsFrontline(tankiness: 1), sample: nil)
        let cc = Reason(kind: .addsCrowdControl(ccScore: 1), sample: nil)
        let engage = Reason(kind: .addsEngage, sample: nil)
        #expect(top.reasons == [gap, frontline, cc, engage])
        #expect(middle.reasons == [gap, cc, engage, frontline])
        #expect(isClose(top.value, 0.05))
        #expect(isClose(middle.value, 0.0425))
    }

    @Test func theDraftCompFitLeavesOutTheLocalPlayersSlot() {
        let tank = ChampionID(rawValue: 3)
        var withLocalTank = stats(
            ally: championProfile(tankiness: 0.5), candidate: championProfile(tankiness: 1))
        withLocalTank.championProfilesByChampion[tank] = [.middle: championProfile(tankiness: 1)]
        let context = draft(
            myCellId: 3,
            allies: [
                slot(0, garen, .top), slot(1, leeSin, .jungle), slot(2, jinx, .bottom),
                slot(3, tank, .middle),
            ])

        let result = Composition.compFit(
            candidate: candidate, role: .top, in: context, stats: withLocalTank)

        #expect(result.reasons == [Reason(kind: .addsFrontline(tankiness: 1), sample: nil)])
    }
}
