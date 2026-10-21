public import Foundation
public import MitoCore

/// One slice of your own games, as the Mi historial tab shows it (§20.2).
public struct HistoryRecord: Hashable, Sendable {
    public let metrics: PersonalMetrics
    /// `(Σkills + Σassists) / max(1, Σdeaths)`; `nil` without games.
    public let kda: Double?
    /// `Σcs / Σminutes`; `nil` without games.
    public let csPerMinute: Double?
    public let lastPlayed: Date?
    /// The snapshot has this (champion, role)'s row, so `metrics.kdaVsAverage` and
    /// `metrics.csVsAverage` compare against it; otherwise they are the neutral 1.
    public let hasAverage: Bool

    public var games: Int { metrics.games }
    public var wins: Int { metrics.wins }
}

/// Your games with a champion, against a lane opponent, and in a role (§20.2).
public struct HistoryRead: Hashable, Sendable {
    /// Any role on the Rift; in ARAM, your ARAM games.
    public let champion: HistoryRecord
    /// `nil` when the champion has no points.
    public let masteryPoints: Int?
    /// With the champion, against this opponent in your own past games; `nil` without one.
    public let versusOpponent: HistoryRecord?
    /// With the champion in the role, compared with the snapshot when it has the row; `nil`
    /// without a role.
    public let championInRole: HistoryRecord?
    /// Every champion in the role; `nil` without a role.
    public let role: HistoryRecord?
}

public enum PersonalHistory {
    /// Remakes count for nothing, as in the profile's insights (§19.4).
    public static let remakeSeconds = 5 * 60

    /// `role` is `nil` in ARAM, where only ARAM games count; elsewhere only games with a role
    /// (the Rift's) do.
    public static func read(
        champion: ChampionID,
        role: Role?,
        opponent: ChampionID?,
        queue: QueueType,
        matches: [MyMatch],
        masteryPoints: [ChampionID: Int],
        stats: some StatsProvider,
        now: Date
    ) -> HistoryRead {
        let played = matches.filter { $0.durationSeconds >= remakeSeconds }
        let isARAM = queue == .aram
        let pool =
            isARAM
            ? played.filter { QueueType(queueID: $0.queue) == .aram }
            : played.filter { $0.role != nil }
        let withChampion = pool.filter { $0.champion == champion }
        let maxPoints = masteryPoints.values.max() ?? 0
        let points = masteryPoints[champion] ?? 0

        func record(_ matches: [MyMatch], average: ChampionRoleStats? = nil) -> HistoryRecord {
            let metrics = PersonalMetrics(
                matches: matches, masteryPoints: points, maxMasteryPoints: maxPoints,
                snapshot: average, priors: stats.meta?.priors, now: now)
            let kills = matches.reduce(0) { $0 + $1.kills }
            let deaths = matches.reduce(0) { $0 + $1.deaths }
            let assists = matches.reduce(0) { $0 + $1.assists }
            let minutes = Double(matches.reduce(0) { $0 + $1.durationSeconds }) / 60
            return HistoryRecord(
                metrics: metrics,
                kda: PersonalMetrics.kda(
                    kills: kills, deaths: deaths, assists: assists, games: matches.count),
                csPerMinute: PersonalMetrics.perMinute(
                    Double(matches.reduce(0) { $0 + $1.cs }), minutes: minutes),
                lastPlayed: matches.map(\.playedAt).max(),
                hasAverage: average != nil)
        }

        let roleRecords = role.map { role in
            let average = stats.meta == nil ? nil : stats.championRoleStats(in: role)[champion]
            return (
                champion: record(withChampion.filter { $0.role == role }, average: average),
                all: record(pool.filter { $0.role == role })
            )
        }

        return HistoryRead(
            champion: record(withChampion),
            masteryPoints: points > 0 ? points : nil,
            versusOpponent: isARAM
                ? nil
                : opponent.map { rival in record(withChampion.filter { $0.opponent == rival }) },
            championInRole: roleRecords?.champion,
            role: roleRecords?.all)
    }
}
