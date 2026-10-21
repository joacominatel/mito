import Foundation
import MitoCore
import MitoEngine

/// The es-AR words of the Mi historial tab (§20.2).
enum HistoryText {
    /// Below this many games a record shows wins as "2 de 3", never as a rate.
    static let minimumGamesForRate = 5

    /// "2 de 3", or "6 de 10 · 60 %" from `minimumGamesForRate` games.
    static func wins(_ record: HistoryRecord, locale: Locale = .current) -> String {
        let wins = record.wins.countText(locale: locale)
        let games = record.games.countText(locale: locale)
        guard record.games >= minimumGamesForRate else {
            return String(localized: "\(wins) de \(games)", table: "History")
        }
        let rate = (Double(record.wins) / Double(record.games)).percentText(locale: locale)
        return String(localized: "\(wins) de \(games) · \(rate)", table: "History")
    }

    /// One decimal; with an average and enough games, the difference too: "3,2 (+12 % vs.
    /// promedio)".
    static func ratio(
        _ value: Double, versusAverage: Double?, games: Int, locale: Locale = .current
    ) -> String {
        let text = value.formatted(.number.precision(.fractionLength(1)).locale(locale))
        guard let versusAverage, games >= minimumGamesForRate else { return text }
        return String(
            localized: "\(text) (\(signedPercent(versusAverage - 1, locale: locale)) vs. promedio)",
            table: "History")
    }

    /// Whole percent, signed; zero after rounding has no sign. The minus is U+2212.
    static func signedPercent(_ delta: Double, locale: Locale = .current) -> String {
        let percent = (delta * 100).rounded()
        let magnitude = (abs(percent) / 100).percentText(locale: locale)
        if percent > 0 { return "+" + magnitude }
        if percent < 0 { return "\u{2212}" + magnitude }
        return magnitude
    }

    static func lastPlayed(_ date: Date, now: Date, locale: Locale = .current) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    static func mastery(_ points: Int, locale: Locale = .current) -> String {
        String(localized: "\(points.countText(locale: locale)) puntos", table: "History")
    }

    // MARK: Titles and empty lines

    static func championTitle(_ name: String, isARAM: Bool) -> String {
        isARAM
            ? String(localized: "Con \(name) en ARAM", table: "History")
            : String(localized: "Con \(name)", table: "History")
    }

    static func neverPlayed(_ name: String, isARAM: Bool) -> String {
        isARAM
            ? String(localized: "Nunca jugaste \(name) en ARAM", table: "History")
            : String(localized: "Nunca jugaste \(name)", table: "History")
    }

    /// An inferred rival is never shown as fact (§12.3).
    static func opponentTitle(_ name: String, isInferred: Bool) -> String {
        isInferred
            ? String(localized: "vs \(name) (rival probable)", table: "History")
            : String(localized: "vs \(name)", table: "History")
    }

    static func neverAgainst(_ champion: String, opponent: String) -> String {
        String(localized: "Nunca jugaste \(champion) contra \(opponent)", table: "History")
    }

    static func roleTitle(_ role: Role) -> String {
        String(localized: "De \(String(localized: role.name))", table: "History")
    }

    static func withChampion(_ name: String) -> String {
        String(localized: "Con \(name)", table: "History")
    }

    static func recommended(_ name: String) -> String {
        String(
            localized: "Si elegís \(name) (el pick recomendado): tu historial con ese campeón.",
            table: "History")
    }
}
