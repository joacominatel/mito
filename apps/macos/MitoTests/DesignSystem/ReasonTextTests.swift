import Foundation
import MitoCore
import Testing

@testable import Mito

/// Every `Reason.Kind` reads as one es-AR line, numbers in the locale's format (§22.3, §22.6).
struct ReasonTextTests {
    nonisolated static let locale = Locale(identifier: "es_AR")
    nonisolated static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(0)).locale(locale))
    }

    static let names = ReasonNames(
        champion: { [238: "Zed", 64: "Lee Sin", 103: "Ahri"][$0.rawValue] ?? "?" },
        item: { [3165: "Morellonomicon"][$0.rawValue] ?? "?" })

    nonisolated static let zed = ChampionID(rawValue: 238)
    nonisolated static let ahri = ChampionID(rawValue: 103)
    nonisolated static let morello = ItemID(rawValue: 3165)

    @Test(arguments: [
        (
            Reason.Kind.matchup(opponent: zed, delta: 0.021, games: 8212),
            "+2,1 vs Zed (8.212 partidas)"
        ),
        (
            .profileMatchup(opponent: zed, profiles: [.heavyAD], delta: -0.012, games: 797),
            "\u{2212}1,2 vs Zed (797 partidas)"
        ),
        (.comfort(poolRank: 3, games: 41, winrate: 0.56), "41 partidas propias"),
        (
            .versusEnemy(enemy: zed, delta: -0.034, games: 412),
            "\u{2212}3,4 contra Zed en el equipo rival (412 partidas)"
        ),
        (
            .synergy(ally: ChampionID(rawValue: 64), allyRole: .jungle, delta: 0.014, games: 96),
            "+1,4 con Lee Sin (96 partidas)"
        ),
        (.meta(tier: .s, games: 3564), "Tier S del parche (3.564 partidas)"),
        (
            .fillsDamageGap(adds: .magic, alliedShare: 0.78),
            "Tu equipo es \(percent(0.78)) AD: aporta AP"
        ),
        (
            .fillsDamageGap(adds: .physical, alliedShare: 0.81),
            "Tu equipo es \(percent(0.81)) AP: aporta AD"
        ),
        (
            .addsFrontline(tankiness: 0.82),
            "Aporta la frontline que le falta al equipo (más tanque que el \(percent(0.82)) del rol)"
        ),
        (
            .addsCrowdControl(ccScore: 0.75),
            "Suma el CC que le falta al equipo (más CC que el \(percent(0.75)) del rol)"
        ),
        (.addsEngage, "Aporta el engage que no tiene nadie"),
        (
            .powerCurve(early: 0.02, teamEarly: -0.01),
            "Curva de poder: early +2,0, tu equipo \u{2212}1,0"
        ),
        (
            .threatens(pick: ahri, delta: -0.042, games: 456),
            "\u{2212}4,2 para tu Ahri (456 partidas)"
        ),
        (
            .generalChoice(part: .runes, usage: 0.34, winrate: 0.521, games: 1200),
            "Runas: la elige el \(percent(0.34)), gana el \(percent(0.521)) (1.200 partidas)"
        ),
        (
            .adaptedToOpponent(part: .items(.core), opponent: zed, games: 310),
            "Ítems (core): adaptado a Zed (310 partidas)"
        ),
        (
            .adaptedToProfile(part: .spells, profile: .heavyAD, games: 150),
            "Spells: adaptado a un rival de mucho AD (150 partidas)"
        ),
        (
            .countersFlag(item: morello, flag: .highHeal, enemies: 2),
            "Morellonomicon contra mucha curación (2 en el equipo rival)"
        ),
        (
            .situationalItem(
                item: morello, profile: .heavyAP, buyRate: 0.34, baselineBuyRate: 0.12,
                winrateDelta: 0.021),
            "Morellonomicon vs mucho AP: se compra en el \(percent(0.34)) (\(percent(0.12)) en general), +2,1"
        ),
    ])
    func readsEveryKind(kind: Reason.Kind, line: String) {
        let reason = Reason(kind: kind, sample: .reliable)

        #expect(ReasonText.text(reason, names: Self.names, locale: Self.locale) == line)
        #expect(!ReasonText.symbol(kind).isEmpty)
    }

    @Test func eachLoadoutPartAndLayerHasItsName() {
        #expect(ReasonText.partName(.skillOrder) == "Orden de habilidades")
        #expect(
            BuildLayer.allCases.map { ReasonText.partName(.items($0)) } == [
                "Ítems (inicio)", "Ítems (core)", "Ítems (botas)", "Ítems (4.º)", "Ítems (5.º)",
                "Ítems (6.º)",
            ])
    }

    @Test func unknownProfilesAndFlagsShowTheirRawValue() {
        #expect(ReasonText.profileName(.unknown("heavy_poke")) == "heavy_poke")
        #expect(ReasonText.flagName(.unknown("shields")) == "shields")
    }

    /// The sign in the text and the tone always agree (§22.1).
    @Test(arguments: [
        (Reason.Kind.matchup(opponent: zed, delta: 0.021, games: 1), Tone.favorable),
        (.matchup(opponent: zed, delta: -0.021, games: 1), .unfavorable),
        (
            .profileMatchup(opponent: zed, profiles: [.heavyAD], delta: -0.021, games: 1),
            .unfavorable
        ),
        (.comfort(poolRank: 1, games: 41, winrate: 0.56), .neutral),
        (.synergy(ally: zed, allyRole: .top, delta: 0.0004, games: 1), .neutral),
        (.threatens(pick: ahri, delta: -0.042, games: 1), .unfavorable),
        (.meta(tier: .a, games: 1), .favorable),
        (.meta(tier: .b, games: 1), .neutral),
        (.meta(tier: .d, games: 1), .unfavorable),
        (.addsEngage, .favorable),
        (.countersFlag(item: morello, flag: .poke, enemies: 1), .neutral),
    ])
    func toneFollowsTheSign(kind: Reason.Kind, tone: Tone) {
        #expect(ReasonText.tone(kind) == tone)
    }

    @Test func championsWithoutDataFallBackToTheirID() {
        let reason = Reason(kind: .matchup(opponent: Self.zed, delta: 0, games: 30), sample: nil)

        #expect(
            ReasonText.text(reason, names: .ids, locale: Self.locale)
                == "0,0 vs Campeón 238 (30 partidas)")
    }
}
