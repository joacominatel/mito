import Foundation
import MitoCore
import MitoEngine
import MitoStore
import Testing

@testable import Mito

/// The Composición tab's mapping from the analysis subject (§20.2).
@Suite(.timeLimit(.minutes(1)))
struct CompositionSummaryTests {
    static let garen = ChampionID(rawValue: 86)
    static let leeSin = ChampionID(rawValue: 64)
    static let ahri = ChampionID(rawValue: 103)
    static let jinx = ChampionID(rawValue: 222)
    static let leona = ChampionID(rawValue: 89)
    static let zed = ChampionID(rawValue: 238)
    static let darius = ChampionID(rawValue: 122)
    static let lux = ChampionID(rawValue: 99)

    static let allyLineup: [(ChampionID, Role)] = [
        (garen, .top), (leeSin, .jungle), (ahri, .middle), (jinx, .bottom), (leona, .utility),
    ]

    // MARK: Draft states

    @Test func aFullDraftReadsBothTeamsWhole() {
        let stats = CompositionTestStats(
            profiles: [
                Self.garen: [.top: .physical], Self.leeSin: [.jungle: .physical],
                Self.ahri: [.middle: .magic], Self.jinx: [.bottom: .physical],
                Self.leona: [.utility: .magic], Self.zed: [.middle: .physical],
                Self.darius: [.top: .physical], Self.lux: [.utility: .magic],
            ],
            roleGames: [
                Self.zed: [.middle: 3000], Self.darius: [.top: 3000], Self.lux: [.utility: 3000],
            ])

        let summary = Self.summary(
            allies: Self.allyLineup.map { ($0.0, $0.1, nil) }, me: 2,
            enemies: [Self.zed, Self.darius, Self.lux], stats: stats)

        #expect(summary.hasData)
        #expect(summary.allies.profiled == 5)
        #expect(!summary.allies.isPartial)
        #expect(summary.allies.read.profile.physicalShare == 0.6)
        #expect(summary.enemies.profiled == 3)
        #expect(summary.enemies.size == 3)
        #expect(summary.assumedPick == nil)
        #expect(summary.showsTiming)
        #expect(summary.enemyProfile == [.heavyAD])
    }

    @Test func aPartialDraftSaysHowManyHaveData() {
        let stats = CompositionTestStats(profiles: [
            Self.garen: [.top: .physical], Self.leeSin: [.jungle: .physical],
        ])

        let summary = Self.summary(
            allies: [
                (Self.garen, .top, nil), (Self.leeSin, .jungle, nil), (nil, .middle, nil),
                (Self.jinx, .bottom, nil), (nil, .utility, nil),
            ],
            me: 2, enemies: [], stats: stats)

        #expect(summary.allies.profiled == 2)
        #expect(summary.allies.size == 5)
        #expect(summary.allies.isPartial)
        #expect(CompositionText.coverage(summary.allies) == "2 de 5 con datos")
        #expect(summary.enemies.read.frontline == nil)
        #expect(summary.winConditions.isEmpty)
    }

    @Test func theTopRecommendationCountsAsYourPickAndIsMarked() {
        let stats = CompositionTestStats(profiles: [Self.ahri: [.middle: .magic]])

        let summary = Self.summary(
            allies: [(Self.garen, .top, nil), (nil, .middle, nil)], me: 1, enemies: [],
            topPick: Self.ahri, stats: stats)

        #expect(summary.allies.profiled == 1)
        #expect(summary.allies.read.profile.magicShare == 1)
        #expect(summary.assumedPick == .recommended("Ahri"))
        #expect(
            CompositionText.assumedPick(.recommended("Ahri"))
                == "Si elegís Ahri (el pick recomendado), tu equipo queda así.")
    }

    @Test func aHoveredPickCountsAndIsMarkedAsAHover() {
        let stats = CompositionTestStats(profiles: [Self.ahri: [.middle: .magic]])

        let summary = Self.summary(
            allies: [(nil, .middle, Self.ahri)], me: 0, enemies: [], stats: stats)

        #expect(summary.allies.profiled == 1)
        #expect(summary.assumedPick == .hovered("Ahri"))
    }

    @Test func anotherAllysHoverDoesNotCount() {
        let stats = CompositionTestStats(profiles: [Self.garen: [.top: .physical]])

        let summary = Self.summary(
            allies: [(nil, .top, Self.garen), (nil, .middle, nil)], me: 1, enemies: [],
            stats: stats)

        #expect(!summary.hasData)
        #expect(summary.hasNoMembers)
    }

    @Test func blindPickReadsYourPickInTheChosenRole() {
        let stats = CompositionTestStats(profiles: [Self.ahri: [.top: .magic]])

        let summary = Self.summary(
            allies: [(Self.ahri, nil, nil)], me: 0, enemies: [], role: .top, stats: stats)

        #expect(summary.allies.profiled == 1)
    }

    // MARK: Enemy roles

    @Test func inferredEnemiesCountInTheirInferredRoleAndAreFlagged() {
        // Zed infers to MID, where he has a profile; his jungle profile is never read.
        let stats = CompositionTestStats(
            profiles: [Self.zed: [.middle: .physical, .jungle: .magic]],
            roleGames: [Self.zed: [.middle: 3000, .jungle: 100]])

        let summary = Self.summary(allies: [], me: 0, enemies: [Self.zed], stats: stats)

        #expect(summary.enemies.profiled == 1)
        #expect(summary.enemies.read.profile.physicalShare == 1)
        #expect(summary.hasInferredEnemyRoles)
    }

    @Test func anEnemyWithoutAProfileInItsInferredRoleIsSkipped() {
        let stats = CompositionTestStats(
            profiles: [Self.zed: [.jungle: .physical], Self.darius: [.top: .physical]],
            roleGames: [Self.zed: [.middle: 3000], Self.darius: [.top: 3000]])

        let summary = Self.summary(
            allies: [], me: 0, enemies: [Self.zed, Self.darius], stats: stats)

        #expect(summary.enemies.profiled == 1)
        #expect(summary.enemies.isPartial)
    }

    // MARK: ARAM

    @Test func aramReadsDamageFromInferredRolesWithoutTiming() {
        let stats = CompositionTestStats(
            profiles: [Self.ahri: [.middle: .magic], Self.garen: [.top: .physical]],
            roleGames: [Self.ahri: [.middle: 3000], Self.garen: [.top: 3000]],
            curve: true)

        let summary = Self.summary(
            allies: [(Self.ahri, nil, nil), (Self.garen, nil, nil)], me: 0, enemies: [],
            role: nil, queue: .aram, stats: stats)

        #expect(summary.allies.profiled == 2)
        #expect(summary.allies.read.profile.magicShare == 0.5)
        #expect(!summary.showsTiming)
        #expect(summary.allies.read.curve == nil)
    }

    @Test func aramWithoutProfileRowsIsEmptyButNotWaiting() {
        let stats = CompositionTestStats(roleGames: [Self.ahri: [.middle: 3000]])

        let summary = Self.summary(
            allies: [(Self.ahri, nil, nil)], me: 0, enemies: [], role: nil, queue: .aram,
            stats: stats)

        #expect(!summary.hasData)
        #expect(!summary.hasNoMembers)
    }

    // MARK: Copy

    @Test func winConditionsReadInSpanish() {
        let locale = Locale(identifier: "es_AR")

        #expect(
            CompositionText.winCondition(.closeEarly(.allies, byMinute: 25), locale: locale)
                == "Ustedes: early fuerte, buscar cerrar antes del minuto 25")
        #expect(
            CompositionText.winCondition(
                .oneSidedEnemyDamage(.physical, share: 0.78), locale: locale)
                == "Ellos: \(0.78.percentText(locale: locale)) AD, la armadura rinde más")
    }

    @Test func spikesReadAsMinutesWithADashForTheMissing() {
        let spikes = TeamSpikes(levelSix: 440, firstItem: 580, secondItem: 965, thirdItem: nil)

        #expect(
            CompositionText.spikes(spikes, locale: Locale(identifier: "es_AR"))
                == "Nivel 6 en 7:20 · legendarios 9:40, 16:05, —")
    }

    @Test func assignedEnemyRolesAreNotFlaggedAsInferred() {
        let stats = CompositionTestStats(profiles: [Self.zed: [.middle: .physical]])
        let subject = Self.subject(
            enemies: [
                AnalysisSubject.Slot(
                    id: 5, champion: Self.zed, hover: nil, role: .assigned(.middle), isMe: false)
            ], stats: stats)

        let summary = CompositionSummary(subject: subject)

        #expect(summary.enemies.profiled == 1)
        #expect(!summary.hasInferredEnemyRoles)
    }

    @Test(arguments: [
        AnalysisSubject.SlotRole.inferred(.middle, probability: 0.8),
        .guessed(.middle, probability: 0.2),
    ])
    func aLockedEnemyInAnInferredOrGuessedRoleIsFlagged(_ role: AnalysisSubject.SlotRole) {
        let subject = Self.subject(
            enemies: [
                AnalysisSubject.Slot(id: 5, champion: Self.zed, hover: nil, role: role, isMe: false)
            ], stats: CompositionTestStats())

        #expect(CompositionSummary(subject: subject).hasInferredEnemyRoles)
    }

    @Test func anEnemyWithoutAChampionIsNeverFlagged() {
        let subject = Self.subject(
            enemies: [
                AnalysisSubject.Slot(
                    id: 5, champion: nil, hover: nil, role: .inferred(.middle, probability: 0.8),
                    isMe: false)
            ], stats: CompositionTestStats())

        #expect(!CompositionSummary(subject: subject).hasInferredEnemyRoles)
    }

    @Test func aLockedAllyWithoutARoleCountsInItsInferredRole() {
        let stats = CompositionTestStats(
            profiles: [Self.garen: [.top: .physical], Self.ahri: [.middle: .magic]],
            roleGames: [Self.garen: [.top: 3000]])

        let summary = Self.summary(
            allies: [(Self.garen, nil, nil), (Self.ahri, .middle, nil)], me: 1, enemies: [],
            stats: stats)

        #expect(summary.allies.profiled == 2)
        #expect(summary.allies.read.profile.physicalShare == 0.5)
    }

    // MARK: Copy edges

    @Test(arguments: [
        (WinCondition.closeEarly(.allies, byMinute: 25), "Ustedes:"),
        (.closeEarly(.enemies, byMinute: 25), "Ellos:"),
        (.scaleLate(.allies, fromMinute: 35), "Ustedes:"),
        (.scaleLate(.enemies, fromMinute: 35), "Ellos:"),
        (.frontline(.allies), "Ustedes:"), (.frontline(.enemies), "Ellos:"),
        (.crowdControl(.allies), "Ustedes:"), (.crowdControl(.enemies), "Ellos:"),
        (.oneSidedEnemyDamage(.physical, share: 0.78), "Ellos:"),
        (.oneSidedEnemyDamage(.magic, share: 0.78), "Ellos:"),
    ])
    func eachWinConditionNamesItsSide(_ condition: WinCondition, side: String) {
        let text = CompositionText.winCondition(condition, locale: Locale(identifier: "es_AR"))

        #expect(text.hasPrefix(side))
        switch condition {
        case .closeEarly(_, let minute), .scaleLate(_, let minute):
            #expect(text.contains("minuto \(minute)"))
        default:
            break
        }
    }

    @Test func aOneSidedMagicEnemyPointsToMagicResist() {
        let locale = Locale(identifier: "es_AR")

        #expect(
            CompositionText.winCondition(.oneSidedEnemyDamage(.magic, share: 0.78), locale: locale)
                == "Ellos: \(0.78.percentText(locale: locale)) AP, la resistencia mágica rinde más")
    }

    @Test(arguments: [
        (TeamCurve?.none, "Pocos datos"),
        (TeamCurve(early: 0.05, late: -0.05, members: 2), "Pocos datos"),
        (TeamCurve(early: 0.001, late: 0, members: 3), "Pareja"),
        (TeamCurve(early: 0.012, late: -0.01, members: 3), "Más fuerte early (+1,2)"),
        (TeamCurve(early: -0.01, late: 0.02, members: 4), "Más fuerte late (+2,0)"),
    ])
    func theTeamCurveReadsAsItsPhaseOrFewData(curve: TeamCurve?, text: String) {
        #expect(CompositionText.curve(curve, locale: Locale(identifier: "es_AR")) == text)
    }

    @Test func damageReadsAsADAndAPShares() {
        let locale = Locale(identifier: "es_AR")
        let profile = TeamProfile(
            profiledMembers: 3, physicalShare: 0.6, magicShare: 0.35, tankiness: 0.5,
            ccScore: 0.5, topTankiness: 0.5, hasEngage: false)
        let ad = 0.6.percentText(locale: locale)
        let ap = 0.35.percentText(locale: locale)

        #expect(CompositionText.damage(profile, locale: locale) == "\(ad) AD · \(ap) AP")
        #expect(
            CompositionText.damageAccessibility(profile, locale: locale)
                == "\(ad) físico, \(ap) mágico")
    }

    @Test(arguments: [
        (CompositionLevel.low, "baja"), (.medium, "media"), (.high, "alta"),
    ])
    func levelsReadInSpanish(level: CompositionLevel, text: String) {
        #expect(CompositionText.level(level) == text)
    }

    @Test func aHoveredPickIsPhrasedAsAHover() {
        #expect(
            CompositionText.assumedPick(.hovered("Ahri"))
                == "Si elegís Ahri (en hover), tu equipo queda así.")
    }

    @Test func theEnemyProfileListsItsLabels() {
        #expect(
            CompositionText.enemyProfile([.heavyAD, .heavyCC], locale: Locale(identifier: "es_AR"))
                == "Perfil del rival: mucho AD y mucho CC")
    }

    @Test func theEnemyProfileIsListedInAStableOrder() {
        let stats = CompositionTestStats(
            profiles: [
                Self.zed: [.middle: .heavyCCPhysical], Self.darius: [.top: .heavyCCPhysical],
                Self.lux: [.utility: .heavyCCPhysical],
            ],
            roleGames: [
                Self.zed: [.middle: 3000], Self.darius: [.top: 3000], Self.lux: [.utility: 3000],
            ])

        let summary = Self.summary(
            allies: [], me: 0, enemies: [Self.zed, Self.darius, Self.lux], stats: stats)

        #expect(summary.enemyProfile == [.heavyAD, .heavyCC])
    }

    // MARK: Helpers

    /// Allies are (locked, assigned role, hover) from cell 0; enemies lock cells 5 onward
    /// without a role, inferred as champ select does.
    private static func summary(
        allies: [(ChampionID?, Role?, ChampionID?)], me: Int, enemies: [ChampionID],
        role: Role? = .middle, queue: QueueType = .rankedSolo, topPick: ChampionID? = nil,
        stats: CompositionTestStats
    ) -> CompositionSummary {
        let allySlots = allies.enumerated().map { index, ally in
            DraftSlot(
                cellId: index, champion: ally.0, hover: ally.2, role: ally.1,
                roleConfidence: ally.1 == nil ? 0 : 1)
        }
        let enemySlots = enemies.enumerated().map { index, enemy in
            DraftSlot(cellId: index + 5, champion: enemy, hover: nil, role: nil, roleConfidence: 0)
        }
        let draft = DraftContext(
            queue: queue, patch: Patch(rawValue: "16.21"), myRole: role, myCellId: me,
            allies: allySlots, enemies: enemySlots, bans: [], pickable: [], phase: .banPick,
            isMyTurnToPick: true, isMyTurnToBan: false)
        let inferred = RoleInference.infer(enemies: enemies, stats: stats)
        let enemyRoles = Dictionary(
            uniqueKeysWithValues: zip(enemySlots.map(\.cellId), inferred))
        let subject = AnalysisSubject.derive(
            draft: draft, role: role, enemyRoles: enemyRoles, topPick: { topPick }, stats: stats,
            personal: PersonalInputs(), names: names)
        return CompositionSummary(subject: subject)
    }

    /// You lock Ahri MID at cell 0; `enemies` as given.
    private static func subject(enemies: [AnalysisSubject.Slot], stats: CompositionTestStats)
        -> AnalysisSubject
    {
        AnalysisSubject(
            queue: .rankedSolo, champion: AnalysisSubject.Champion(id: ahri, source: .locked),
            role: .middle, laneOpponent: nil,
            allies: [
                AnalysisSubject.Slot(
                    id: 0, champion: ahri, hover: nil, role: .assigned(.middle), isMe: true)
            ],
            enemies: enemies, stats: stats, tips: .empty, personal: PersonalInputs(),
            names: names, gameData: nil)
    }

    private static let names = ReasonNames(
        champion: { [103: "Ahri", 238: "Zed"][$0.rawValue] ?? "Campeón \($0.rawValue)" },
        item: { "Ítem \($0.rawValue)" })
}

/// Profiles by champion and role, role games for inference, and optionally the same early
/// curve for everyone with a profile.
nonisolated struct CompositionTestStats: StatsProvider {
    var profiles: [ChampionID: [Role: ChampionProfile]] = [:]
    var roleGames: [ChampionID: [Role: Int]] = [:]
    var curve = false

    var meta: SnapshotMeta? {
        SnapshotMeta(
            patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420),
            bracket: .emeraldPlus, matches: 20_000, blendPatches: [Patch(rawValue: "16.21")],
            thresholds: [:],
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                loadoutStrength: 500),
            tierCutoffs: [:],
            profileRules: ProfileRules(
                minimumChampions: 3, heavyADPhysicalShare: 0.625, heavyAPMagicShare: 0.5625,
                heavyCCScore: 0.75, mixedExcludes: [.heavyAD, .heavyAP]))
    }

    func roleGames(for champion: ChampionID) -> [Role: Int] { roleGames[champion] ?? [:] }

    func championProfile(for champion: ChampionID, role: Role) -> ChampionProfile? {
        profiles[champion]?[role]
    }

    func durationCurves(for champion: ChampionID, role: Role) -> [DurationBucket: RelationStats] {
        guard curve, profiles[champion]?[role] != nil else { return [:] }
        return [.under20: RelationStats(games: 100, wins: 60)]
    }
}

extension ChampionProfile {
    static let physical = ChampionProfile(
        physicalShare: 1, magicShare: 0, trueShare: 0, damagePerMinute: 100, tankiness: 0.5,
        ccScore: 0.5, timelineGames: 0)
    static let magic = ChampionProfile(
        physicalShare: 0, magicShare: 1, trueShare: 0, damagePerMinute: 100, tankiness: 0.5,
        ccScore: 0.5, timelineGames: 0)
    static let heavyCCPhysical = ChampionProfile(
        physicalShare: 1, magicShare: 0, trueShare: 0, damagePerMinute: 100, tankiness: 0.5,
        ccScore: 0.9, timelineGames: 0)
}
