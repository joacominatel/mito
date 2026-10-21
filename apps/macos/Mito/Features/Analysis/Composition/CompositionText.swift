import Foundation
import MitoCore
import MitoEngine

/// The es-AR words of the Composición tab (§20.2).
enum CompositionText {
    static func coverage(_ team: CompositionSummary.Team) -> String {
        String(localized: "\(team.profiled) de \(team.size) con datos", table: "Composition")
    }

    static func damage(_ profile: TeamProfile, locale: Locale = .current) -> String {
        String(
            localized:
                "\(profile.physicalShare.percentText(locale: locale)) AD · \(profile.magicShare.percentText(locale: locale)) AP",
            table: "Composition")
    }

    static func damageAccessibility(_ profile: TeamProfile, locale: Locale = .current) -> String {
        String(
            localized:
                "\(profile.physicalShare.percentText(locale: locale)) físico, \(profile.magicShare.percentText(locale: locale)) mágico",
            table: "Composition")
    }

    static func level(_ level: CompositionLevel) -> String {
        switch level {
        case .low: String(localized: "baja", table: "Composition")
        case .medium: String(localized: "media", table: "Composition")
        case .high: String(localized: "alta", table: "Composition")
        }
    }

    static func curve(_ curve: TeamCurve?, locale: Locale = .current) -> String {
        guard let curve, let phase = curve.phase else {
            return String(localized: "Pocos datos", table: "Composition")
        }
        switch phase {
        case .early:
            return String(
                localized: "Más fuerte early (\(WinratePoints.text(curve.early, locale: locale)))",
                table: "Composition")
        case .late:
            return String(
                localized: "Más fuerte late (\(WinratePoints.text(curve.late, locale: locale)))",
                table: "Composition")
        case .even:
            return String(localized: "Pareja", table: "Composition")
        }
    }

    /// "Nivel 6 en 7:20 · legendarios 9:40, 16:10, —".
    static func spikes(_ spikes: TeamSpikes, locale: Locale = .current) -> String {
        func time(_ seconds: Int?) -> String {
            guard let seconds else { return "—" }
            return Duration.seconds(seconds).formatted(
                .time(pattern: .minuteSecond).locale(locale))
        }
        return String(
            localized:
                "Nivel 6 en \(time(spikes.levelSix)) · legendarios \(time(spikes.firstItem)), \(time(spikes.secondItem)), \(time(spikes.thirdItem))",
            table: "Composition")
    }

    static func enemyProfile(_ profiles: [EnemyProfile], locale: Locale = .current) -> String {
        let labels = profiles.map(ReasonText.profileName).formatted(
            .list(type: .and).locale(locale))
        return String(localized: "Perfil del rival: \(labels)", table: "Composition")
    }

    static func assumedPick(_ pick: CompositionSummary.AssumedPick) -> String {
        switch pick {
        case .recommended(let name):
            String(
                localized: "Si elegís \(name) (el pick recomendado), tu equipo queda así.",
                table: "Composition")
        case .hovered(let name):
            String(
                localized: "Si elegís \(name) (en hover), tu equipo queda así.",
                table: "Composition")
        }
    }

    static func winCondition(_ condition: WinCondition, locale: Locale = .current) -> String {
        switch condition {
        case .closeEarly(.allies, let minute):
            String(
                localized: "Ustedes: early fuerte, buscar cerrar antes del minuto \(minute)",
                table: "Composition")
        case .closeEarly(.enemies, let minute):
            String(
                localized: "Ellos: early fuerte, no regalar peleas antes del minuto \(minute)",
                table: "Composition")
        case .scaleLate(.allies, let minute):
            String(
                localized: "Ustedes: escalan mejor, jugar seguro hasta el minuto \(minute)",
                table: "Composition")
        case .scaleLate(.enemies, let minute):
            String(
                localized: "Ellos: escalan mejor, sacar ventaja antes del minuto \(minute)",
                table: "Composition")
        case .frontline(.allies):
            String(
                localized: "Ustedes: más frontline, buscar peleas de frente en grupo",
                table: "Composition")
        case .frontline(.enemies):
            String(
                localized: "Ellos: más frontline, evitar pelear de frente y buscar flancos",
                table: "Composition")
        case .crowdControl(.allies):
            String(
                localized: "Ustedes: más CC, buscar enganchar y pelear agrupados",
                table: "Composition")
        case .crowdControl(.enemies):
            String(
                localized: "Ellos: más CC, no agruparse sin visión", table: "Composition")
        case .oneSidedEnemyDamage(.physical, let share):
            String(
                localized: "Ellos: \(share.percentText(locale: locale)) AD, la armadura rinde más",
                table: "Composition")
        case .oneSidedEnemyDamage(.magic, let share):
            String(
                localized:
                    "Ellos: \(share.percentText(locale: locale)) AP, la resistencia mágica rinde más",
                table: "Composition")
        }
    }
}
