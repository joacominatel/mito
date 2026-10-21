import Foundation
import MitoCore

/// The §19.2 metrics of one (champion, role). Every value is finite: a ratio without data on
/// either side is 1, the neutral "like the average" (`MITO_CONTEXT.md` §19.3).
public struct PersonalMetrics: Hashable, Sendable {
    /// `my_games(c, r)`.
    public let games: Int
    public let wins: Int
    /// `wr_s(c, r)`: the snapshot's `wr_smoothed(champ, role)`, the prior of `smoothedWinrate`.
    public let globalWinrate: Double
    /// `my_wr_smoothed(c, r)`.
    public let smoothedWinrate: Double
    /// `recency(c, r)`: each game is worth `exp(−days / 30)`.
    public let recency: Double
    /// `mastery_norm(c)`, in [0, 1].
    public let masteryNorm: Double
    /// `kda_vs_avg(c, r)`.
    public let kdaVsAverage: Double
    /// `cs_vs_avg(c, r)`.
    public let csVsAverage: Double

    public init(
        games: Int, wins: Int, globalWinrate: Double, smoothedWinrate: Double, recency: Double,
        masteryNorm: Double, kdaVsAverage: Double, csVsAverage: Double
    ) {
        self.games = games
        self.wins = wins
        self.globalWinrate = globalWinrate
        self.smoothedWinrate = smoothedWinrate
        self.recency = recency
        self.masteryNorm = masteryNorm
        self.kdaVsAverage = kdaVsAverage
        self.csVsAverage = csVsAverage
    }
}

extension PersonalMetrics {
    /// `m` of `my_wr_smoothed`, in games.
    static let personalPriorStrength = 15.0
    /// The `30` of `exp(−days / 30)`.
    static let recencyDecayDays = 30.0
    /// `p0` for (champ, role) when no snapshot is open (§18.1).
    static let fallbackGlobalWinrate = 0.5

    /// `matches` must already be this (champion, role)'s games.
    init(
        matches: [MyMatch], masteryPoints: Int, maxMasteryPoints: Int,
        snapshot: ChampionRoleStats?, priors: SmoothingPriors?, now: Date
    ) {
        let wins = matches.count { $0.win }
        let globalWinrate =
            priors?.championRoleWinrate(wins: snapshot?.wins ?? 0, games: snapshot?.games ?? 0)
            ?? Self.fallbackGlobalWinrate
        let kills = matches.reduce(0) { $0 + $1.kills }
        let deaths = matches.reduce(0) { $0 + $1.deaths }
        let assists = matches.reduce(0) { $0 + $1.assists }
        let cs = matches.reduce(0) { $0 + $1.cs }
        let minutes = Double(matches.reduce(0) { $0 + $1.durationSeconds }) / 60

        self.init(
            games: matches.count,
            wins: wins,
            globalWinrate: globalWinrate,
            smoothedWinrate: Smoothing.winrate(
                wins: wins, games: matches.count, strength: Self.personalPriorStrength,
                baseline: globalWinrate),
            recency: Self.recency(of: matches.map(\.playedAt), now: now),
            masteryNorm: Self.masteryNorm(points: masteryPoints, maxPoints: maxMasteryPoints),
            kdaVsAverage: Self.ratio(
                Self.kda(kills: kills, deaths: deaths, assists: assists, games: matches.count),
                to: snapshot.flatMap {
                    Self.kda(
                        kills: $0.kills, deaths: $0.deaths, assists: $0.assists, games: $0.games)
                }),
            csVsAverage: Self.ratio(
                Self.perMinute(Double(cs), minutes: minutes),
                to: snapshot.flatMap { Self.perMinute(Double($0.cs), minutes: Double($0.minutes)) })
        )
    }

    /// A game in the future (clock skew) counts as played now, so none is worth more than 1.
    static func recency(of playedAt: [Date], now: Date) -> Double {
        playedAt.reduce(0) { sum, date in
            let days = max(0, now.timeIntervalSince(date)) / 86_400
            return sum + exp(-days / recencyDecayDays)
        }
    }

    /// 0 when no champion has points, so a fresh account divides by nothing.
    static func masteryNorm(points: Int, maxPoints: Int) -> Double {
        guard maxPoints > 0 else { return 0 }
        return min(1, log1p(Double(max(0, points))) / log1p(Double(maxPoints)))
    }

    /// `(kills + assists) / max(1, deaths)`; `nil` without games.
    static func kda(kills: Int, deaths: Int, assists: Int, games: Int) -> Double? {
        guard games > 0 else { return nil }
        return Double(kills + assists) / Double(max(1, deaths))
    }

    static func perMinute(_ value: Double, minutes: Double) -> Double? {
        minutes > 0 ? value / minutes : nil
    }

    /// 1 when either side is missing or the average is 0.
    static func ratio(_ mine: Double?, to average: Double?) -> Double {
        guard let mine, let average, average > 0 else { return 1 }
        return mine / average
    }
}
