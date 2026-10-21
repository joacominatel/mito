import Foundation
import MitoCore
import MitoEngine

/// What the Mi historial tab shows (§20.2): your own games with your champion, against your
/// lane rival, and in your role. Champions and roles only, never another player (§5).
struct HistorySummary: Hashable {
    struct Row: Hashable, Identifiable {
        let label: String
        let value: String

        var id: String { label }
    }

    struct Block: Hashable, Identifiable {
        enum Kind: Hashable {
            case champion
            case opponent
            case role
        }

        let kind: Kind
        let title: String
        /// Says there are no games, above whatever rows there still are.
        let empty: String?
        let rows: [Row]
        /// Yours in the champion block, the rival's in the opponent block.
        var champion: ChampionID?

        var id: Kind { kind }
    }

    enum Content: Hashable {
        case noChampion
        /// Not a single game of yours is stored yet.
        case noHistory
        case blocks([Block])
    }

    let content: Content
    /// What the blocks assume: the recommended pick, ARAM's missing roles.
    let notes: [String]

    init(subject: AnalysisSubject, now: Date = .now, locale: Locale = .current) {
        guard !subject.personal.matches.isEmpty else {
            content = .noHistory
            notes = []
            return
        }
        guard let champion = subject.champion else {
            content = .noChampion
            notes = []
            return
        }

        let isARAM = subject.queue == .aram
        let name = subject.names.champion(champion.id)
        let read = PersonalHistory.read(
            champion: champion.id, role: subject.role,
            opponent: subject.laneOpponent?.champion, queue: subject.queue,
            matches: subject.personal.matches, masteryPoints: subject.personal.masteryPoints,
            stats: subject.stats, now: now)
        let rows = Rows(now: now, locale: locale)

        var blocks = [
            Block(
                kind: .champion, title: HistoryText.championTitle(name, isARAM: isARAM),
                empty: read.champion.games == 0
                    ? HistoryText.neverPlayed(name, isARAM: isARAM) : nil,
                rows: rows.record(read.champion)
                    + (read.masteryPoints.map { [rows.mastery($0)] } ?? []),
                champion: champion.id)
        ]
        if !isARAM {
            blocks.append(
                Self.opponentBlock(
                    subject.laneOpponent, record: read.versusOpponent, champion: name,
                    names: subject.names, rows: rows))
        }
        if let role = subject.role, let inRole = read.championInRole, let all = read.role {
            blocks.append(
                Block(
                    kind: .role, title: HistoryText.roleTitle(role), empty: nil,
                    rows: rows.role(champion: name, inRole: inRole, all: all)))
        }
        content = .blocks(blocks)

        var notes: [String] = []
        if champion.isRecommendation { notes.append(HistoryText.recommended(name)) }
        if isARAM {
            notes.append(
                String(
                    localized: "ARAM no tiene roles: cuentan solo tus partidas de ARAM.",
                    table: "History"))
        }
        self.notes = notes
    }

    private static func opponentBlock(
        _ opponent: AnalysisSubject.LaneOpponent?, record: HistoryRecord?, champion: String,
        names: ReasonNames, rows: Rows
    ) -> Block {
        guard let opponent, let record else {
            return Block(
                kind: .opponent,
                title: String(localized: "vs tu rival de línea", table: "History"),
                empty: String(
                    localized: "Todavía no hay un rival lockeado en tu rol.", table: "History"),
                rows: [])
        }
        let isInferred: Bool
        if case .assigned = opponent.role { isInferred = false } else { isInferred = true }
        let rival = names.champion(opponent.champion)
        return Block(
            kind: .opponent, title: HistoryText.opponentTitle(rival, isInferred: isInferred),
            empty: record.games == 0
                ? HistoryText.neverAgainst(champion, opponent: rival) : nil,
            rows: rows.record(record), champion: opponent.champion)
    }
}

private struct Rows {
    let now: Date
    let locale: Locale

    /// Nothing without games.
    func record(_ record: HistoryRecord) -> [HistorySummary.Row] {
        guard record.games > 0 else { return [] }
        var rows = [wins(record)] + performance(record, comparesAverage: false)
        if let date = record.lastPlayed {
            rows.append(
                HistorySummary.Row(
                    label: String(localized: "Última partida", table: "History"),
                    value: HistoryText.lastPlayed(date, now: now, locale: locale)))
        }
        return rows
    }

    func mastery(_ points: Int) -> HistorySummary.Row {
        HistorySummary.Row(
            label: String(localized: "Maestría", table: "History"),
            value: HistoryText.mastery(points, locale: locale))
    }

    /// Only the champion in the role compares against the snapshot: its average is per
    /// (champion, role).
    func role(champion name: String, inRole: HistoryRecord, all: HistoryRecord)
        -> [HistorySummary.Row]
    {
        [winsOrNone(inRole, label: HistoryText.withChampion(name))]
            + performance(inRole, comparesAverage: true)
            + [
                winsOrNone(
                    all, label: String(localized: "Todos tus campeones", table: "History"))
            ]
    }

    private func wins(_ record: HistoryRecord) -> HistorySummary.Row {
        HistorySummary.Row(
            label: String(localized: "Victorias", table: "History"),
            value: HistoryText.wins(record, locale: locale))
    }

    private func winsOrNone(_ record: HistoryRecord, label: String) -> HistorySummary.Row {
        HistorySummary.Row(
            label: label,
            value: record.games > 0
                ? HistoryText.wins(record, locale: locale)
                : String(localized: "Sin partidas", table: "History"))
    }

    private func performance(_ record: HistoryRecord, comparesAverage: Bool)
        -> [HistorySummary.Row]
    {
        let compares = comparesAverage && record.hasAverage
        var rows: [HistorySummary.Row] = []
        if let kda = record.kda {
            rows.append(
                HistorySummary.Row(
                    label: String(localized: "KDA", table: "History"),
                    value: HistoryText.ratio(
                        kda, versusAverage: compares ? record.metrics.kdaVsAverage : nil,
                        games: record.games, locale: locale)))
        }
        if let cs = record.csPerMinute {
            rows.append(
                HistorySummary.Row(
                    label: String(localized: "CS/min", table: "History"),
                    value: HistoryText.ratio(
                        cs, versusAverage: compares ? record.metrics.csVsAverage : nil,
                        games: record.games, locale: locale)))
        }
        return rows
    }
}
