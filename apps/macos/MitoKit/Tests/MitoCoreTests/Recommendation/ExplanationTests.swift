import MitoCore
import Testing

struct ExplanationTests {
    @Test func aLoadoutBuiltWithoutReasonsHasAnEmptyExplanation() {
        #expect(Loadout(runes: nil, spells: nil, itemSet: nil, skillOrder: nil).explanation == [])
    }

    @Test func aSnapshotMetaBuiltWithoutProfileRulesHasNone() {
        let meta = SnapshotMeta(
            patch: Patch(rawValue: "16.21"), queue: QueueID(rawValue: 420),
            bracket: .emeraldPlus, matches: 20_000, blendPatches: [Patch(rawValue: "16.21")],
            thresholds: [:],
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                loadoutStrength: 500),
            tierCutoffs: [:])
        #expect(meta.profileRules == nil)
    }

    @Test func aRecommendationIsIdentifiedByItsChampion() {
        let ahri = ChampionID(rawValue: 103)
        let pick = PickRecommendation(
            champion: ahri, score: 0.038, components: [.meta: 0.018, .matchup: 0.02],
            reasons: [
                Reason(
                    kind: .matchup(opponent: ChampionID(rawValue: 238), delta: 0.021, games: 497),
                    sample: .usable)
            ],
            confidence: .reliable)
        #expect(pick.id == ahri)
    }
}

/// §5: recommendations analyse champions and roles, never who plays them.
struct RecommendationPrivacyTests {
    private static let identityMarkers = [
        "puuid", "summoner", "account", "name", "riotid", "tag", "player",
    ]

    private static func labels(of value: Any) -> [String] {
        Mirror(reflecting: value).children.flatMap { child -> [String] in
            let nested = Mirror(reflecting: child.value).children.compactMap(\.label)
            return [child.label].compactMap { $0 } + nested
        }
    }

    @Test func recommendationsAndReasonsHoldNoPlayerIdentity() {
        let ahri = ChampionID(rawValue: 103)
        let zed = ChampionID(rawValue: 238)
        let kinds: [Reason.Kind] = [
            .matchup(opponent: zed, delta: -0.02, games: 497),
            .profileMatchup(
                opponent: zed, profiles: [.heavyAD, .heavyCC], delta: -0.01, games: 900),
            .comfort(poolRank: 3, games: 41, winrate: 0.56),
            .versusEnemy(enemy: zed, delta: 0.01, games: 661),
            .synergy(ally: zed, allyRole: .jungle, delta: 0.01, games: 247),
            .meta(tier: .a, games: 2_824),
            .fillsDamageGap(adds: .magic, alliedShare: 0.78),
            .addsFrontline(tankiness: 0.9), .addsCrowdControl(ccScore: 0.8), .addsEngage,
            .powerCurve(early: 0.01, teamEarly: 0.02),
            .threatens(pick: ahri, delta: -0.042, games: 456),
            .generalChoice(part: .runes, usage: 0.58, winrate: 0.539, games: 2_118),
            .adaptedToOpponent(part: .spells, opponent: zed, games: 248),
            .adaptedToProfile(part: .items(.boots), profile: .heavyAD, games: 614),
            .countersFlag(item: ItemID(rawValue: 3165), flag: .highHeal, enemies: 2),
            .situationalItem(
                item: ItemID(rawValue: 3157), profile: .heavyAD, buyRate: 0.2,
                baselineBuyRate: 0.08, winrateDelta: 0.01),
        ]
        let ban = BanRecommendation(
            champion: zed, score: 0.01, components: [.presence: 0.3, .threat: 0.03],
            reasons: kinds.map { Reason(kind: $0, sample: .usable) }, confidence: .usable)

        let found = ([ban] + ban.reasons as [Any] + kinds as [Any]).flatMap(Self.labels)
        // The scan reaches associated values, or it would prove nothing.
        #expect(found.contains("opponent") && found.contains("allyRole"))
        #expect(
            found.filter { label in
                Self.identityMarkers.contains { label.lowercased().contains($0) }
            } == [])
    }
}
