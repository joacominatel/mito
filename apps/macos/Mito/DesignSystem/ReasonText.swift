import Foundation
import MitoCore

/// How a reason names champions and items; the feature passes the client's names.
struct ReasonNames {
    var champion: (ChampionID) -> String
    var item: (ItemID) -> String

    /// Before the client's data loads.
    static let ids = ReasonNames(
        champion: { String(localized: "Campeón \($0.rawValue)", table: "DesignSystem") },
        item: { String(localized: "Ítem \($0.rawValue)", table: "DesignSystem") })
}

/// The es-AR line, symbol, and tone of every `Reason.Kind` (§18.3, §22.3).
enum ReasonText {
    static func text(_ reason: Reason, names: ReasonNames, locale: Locale = .current) -> String {
        func points(_ delta: Double) -> String { WinratePoints.text(delta, locale: locale) }
        func percent(_ share: Double) -> String { share.percentText(locale: locale) }
        func count(_ games: Int) -> String { games.countText(locale: locale) }

        switch reason.kind {
        case .matchup(let opponent, let delta, let games):
            return String(
                localized:
                    "\(points(delta)) vs \(names.champion(opponent)) (\(count(games)) partidas)",
                table: "DesignSystem")
        case .versusEnemy(let enemy, let delta, let games):
            return String(
                localized:
                    "\(points(delta)) contra \(names.champion(enemy)) en el equipo rival (\(count(games)) partidas)",
                table: "DesignSystem")
        case .synergy(let ally, _, let delta, let games):
            return String(
                localized:
                    "\(points(delta)) con \(names.champion(ally)) (\(count(games)) partidas)",
                table: "DesignSystem")
        case .meta(let tier, let games):
            return String(
                localized: "Tier \(tier.rawValue) del parche (\(count(games)) partidas)",
                table: "DesignSystem")
        case .fillsDamageGap(.magic, let alliedShare):
            return String(
                localized: "Tu equipo es \(percent(alliedShare)) AD: aporta AP",
                table: "DesignSystem")
        case .fillsDamageGap(.physical, let alliedShare):
            return String(
                localized: "Tu equipo es \(percent(alliedShare)) AP: aporta AD",
                table: "DesignSystem")
        case .addsFrontline(let tankiness):
            return String(
                localized:
                    "Aporta la frontline que le falta al equipo (más tanque que el \(percent(tankiness)) del rol)",
                table: "DesignSystem")
        case .addsCrowdControl(let ccScore):
            return String(
                localized:
                    "Suma el CC que le falta al equipo (más CC que el \(percent(ccScore)) del rol)",
                table: "DesignSystem")
        case .addsEngage:
            return String(localized: "Aporta el engage que no tiene nadie", table: "DesignSystem")
        case .powerCurve(let early, let teamEarly):
            return String(
                localized: "Curva de poder: early \(points(early)), tu equipo \(points(teamEarly))",
                table: "DesignSystem")
        case .threatens(let pick, let delta, let games):
            return String(
                localized:
                    "\(points(delta)) para tu \(names.champion(pick)) (\(count(games)) partidas)",
                table: "DesignSystem")
        case .generalChoice(let part, let usage, let winrate, let games):
            return String(
                localized:
                    "\(partName(part)): la elige el \(percent(usage)), gana el \(percent(winrate)) (\(count(games)) partidas)",
                table: "DesignSystem")
        case .adaptedToOpponent(let part, let opponent, let games):
            return String(
                localized:
                    "\(partName(part)): adaptado a \(names.champion(opponent)) (\(count(games)) partidas)",
                table: "DesignSystem")
        case .adaptedToProfile(let part, let profile, let games):
            return String(
                localized:
                    "\(partName(part)): adaptado a un rival de \(profileName(profile)) (\(count(games)) partidas)",
                table: "DesignSystem")
        case .countersFlag(let item, let flag, let enemies):
            return String(
                localized:
                    "\(names.item(item)) contra \(flagName(flag)) (\(count(enemies)) en el equipo rival)",
                table: "DesignSystem")
        case .situationalItem(let item, let profile, let buyRate, let baselineBuyRate, let delta):
            return String(
                localized:
                    "\(names.item(item)) vs \(profileName(profile)): se compra en el \(percent(buyRate)) (\(percent(baselineBuyRate)) en general), \(points(delta))",
                table: "DesignSystem")
        }
    }

    static func symbol(_ kind: Reason.Kind) -> String {
        switch kind {
        case .matchup: "person.line.dotted.person"
        case .versusEnemy: "person.3"
        case .synergy: "link"
        case .meta: "chart.bar"
        case .fillsDamageGap: "flame"
        case .addsFrontline: "shield"
        case .addsCrowdControl: "tornado"
        case .addsEngage: "bolt"
        case .powerCurve: "chart.line.uptrend.xyaxis"
        case .threatens: "exclamationmark.triangle"
        case .generalChoice: "star"
        case .adaptedToOpponent: "scope"
        case .adaptedToProfile: "person.3.sequence"
        case .countersFlag: "flag"
        case .situationalItem: "bag"
        }
    }

    /// For the user's pick: a threat is bad news even when it argues for a ban.
    static func tone(_ kind: Reason.Kind) -> Tone {
        switch kind {
        case .matchup(_, let delta, _), .versusEnemy(_, let delta, _),
            .synergy(_, _, let delta, _), .threatens(_, let delta, _):
            WinratePoints.tone(delta)
        case .situationalItem(_, _, _, _, let delta):
            WinratePoints.tone(delta)
        case .meta(let tier, _):
            switch tier {
            case .s, .a: .favorable
            case .b: .neutral
            case .c, .d: .unfavorable
            }
        case .fillsDamageGap, .addsFrontline, .addsCrowdControl, .addsEngage: .favorable
        case .powerCurve, .generalChoice, .adaptedToOpponent, .adaptedToProfile, .countersFlag:
            .neutral
        }
    }

    static func partName(_ part: LoadoutPart) -> String {
        switch part {
        case .runes: String(localized: "Runas", table: "DesignSystem")
        case .spells: String(localized: "Spells", table: "DesignSystem")
        case .items(let layer):
            String(localized: "Ítems (\(layerName(layer)))", table: "DesignSystem")
        case .skillOrder: String(localized: "Orden de habilidades", table: "DesignSystem")
        }
    }

    static func layerName(_ layer: BuildLayer) -> String {
        switch layer {
        case .start: String(localized: "inicio", table: "DesignSystem")
        case .core: String(localized: "core", table: "DesignSystem")
        case .boots: String(localized: "botas", table: "DesignSystem")
        case .fourth: String(localized: "4.º", table: "DesignSystem")
        case .fifth: String(localized: "5.º", table: "DesignSystem")
        case .sixth: String(localized: "6.º", table: "DesignSystem")
        }
    }

    static func profileName(_ profile: EnemyProfile) -> String {
        switch profile {
        case .heavyAD: String(localized: "mucho AD", table: "DesignSystem")
        case .heavyAP: String(localized: "mucho AP", table: "DesignSystem")
        case .mixed: String(localized: "daño mixto", table: "DesignSystem")
        case .heavyCC: String(localized: "mucho CC", table: "DesignSystem")
        case .unknown(let raw): raw
        }
    }

    static func flagName(_ flag: ChampionFlag) -> String {
        switch flag {
        case .highHeal: String(localized: "mucha curación", table: "DesignSystem")
        case .pointClickCC: String(localized: "CC dirigido", table: "DesignSystem")
        case .autoAttacker: String(localized: "ataques básicos", table: "DesignSystem")
        case .poke: String(localized: "poke", table: "DesignSystem")
        case .engage: String(localized: "engage", table: "DesignSystem")
        case .unknown(let raw): raw
        }
    }
}
