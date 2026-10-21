import Foundation
import MitoAssets
import MitoCore
import MitoEngine

/// The "Mi perfil" numbers (§19.3, §19.4), from the user's own games only. The thresholds are
/// written in §19.4.
enum ProfileInsights {
    static let championsPerRole = 5
    /// Below this many games a row, matchup, or short-game split is marked "muestra baja".
    static let reliableGames = 10
    static let minimumMatchupGames = 3
    static let matchupsShown = 3
    static let shortGameSeconds = 25 * 60
    static let minimumShortGames = 5
    /// The short-game winrate must differ from the rest by this much to be worth a line.
    static let minimumShortGameGap = 0.10
    static let minimumLossStreak = 3
    /// Remakes end before this; they say nothing about how the user plays.
    static let remakeSeconds = 5 * 60

    /// Per role, the champions the user played there, best `PersonalScoring` total first.
    static func bestChampions(
        matches: [MyMatch], pool: [PoolEntry], overrides: [ChampionOverride],
        masteryPoints: [ChampionID: Int], stats: some StatsProvider, now: Date
    ) -> [RoleChampions] {
        Role.allCases.compactMap { role in
            let champions = Set(matches.filter { $0.role == role }.map(\.champion))
            guard !champions.isEmpty else { return nil }
            let rows = champions.map {
                ChampionScoreRow(
                    score: PersonalScoring.score(
                        champion: $0, role: role, matches: matches, pool: pool,
                        overrides: overrides, masteryPoints: masteryPoints, stats: stats,
                        now: now))
            }
            .sorted(by: ChampionScoreRow.ranking)
            return RoleChampions(role: role, rows: Array(rows.prefix(championsPerRole)))
        }
    }

    /// By (champion, role, opponent), from `minimumMatchupGames` up. Best are above 50 %,
    /// worst below, so one matchup never sits in both lists.
    static func matchups(in matches: [MyMatch]) -> Matchups {
        let records = Dictionary(grouping: matches.filter { !isRemake($0) }) {
            match -> MatchupRecord.Key? in
            guard let role = match.role, let opponent = match.opponent else { return nil }
            return MatchupRecord.Key(champion: match.champion, role: role, opponent: opponent)
        }
        .compactMap { key, games -> MatchupRecord? in
            guard let key, games.count >= minimumMatchupGames else { return nil }
            return MatchupRecord(id: key, games: games.count, wins: games.count { $0.win })
        }
        let best = records.filter { $0.winrate > 0.5 }.sorted {
            $0.winrate != $1.winrate ? $0.winrate > $1.winrate : MatchupRecord.tieBreak($0, $1)
        }
        let worst = records.filter { $0.winrate < 0.5 }.sorted {
            $0.winrate != $1.winrate ? $0.winrate < $1.winrate : MatchupRecord.tieBreak($0, $1)
        }
        return Matchups(
            best: Array(best.prefix(matchupsShown)), worst: Array(worst.prefix(matchupsShown)))
    }

    /// The champion whose games under 25 minutes differ most from its longer ones, when both
    /// sides have `minimumShortGames` and the gap reaches `minimumShortGameGap`.
    static func shortGames(in matches: [MyMatch]) -> ShortGameInsight? {
        Dictionary(grouping: matches.filter { $0.role != nil && !isRemake($0) }, by: \.champion)
            .compactMap { champion, games -> ShortGameInsight? in
                let short = games.filter { $0.durationSeconds < shortGameSeconds }
                let longer = games.filter { $0.durationSeconds >= shortGameSeconds }
                guard short.count >= minimumShortGames, longer.count >= minimumShortGames
                else { return nil }
                let insight = ShortGameInsight(
                    champion: champion, shortGames: short.count, shortWins: short.count { $0.win },
                    longerGames: longer.count, longerWins: longer.count { $0.win })
                return abs(insight.gap) >= minimumShortGameGap ? insight : nil
            }
            .sorted {
                if abs($0.gap) != abs($1.gap) { return abs($0.gap) > abs($1.gap) }
                return $0.champion.rawValue < $1.champion.rawValue
            }
            .first
    }

    /// The losses in a row up to the newest game, any queue, when it reaches
    /// `minimumLossStreak`.
    static func lossStreak(in matches: [MyMatch]) -> Int? {
        let newestFirst = matches.filter { !isRemake($0) }.sorted { $0.playedAt > $1.playedAt }
        let streak = newestFirst.prefix { !$0.win }.count
        return streak >= minimumLossStreak ? streak : nil
    }

    private static func isRemake(_ match: MyMatch) -> Bool {
        match.durationSeconds < remakeSeconds
    }
}

struct RoleChampions: Hashable {
    let role: Role
    let rows: [ChampionScoreRow]
}

/// One (champion, role) of "Mi perfil", every number from `PersonalScore`.
struct ChampionScoreRow: Identifiable, Hashable {
    let score: PersonalScore

    var id: ChampionID { score.champion }
    var champion: ChampionID { score.champion }
    var games: Int { score.metrics.games }
    /// The raw winrate; the score itself uses the smoothed one.
    var winrate: Double { games > 0 ? Double(score.metrics.wins) / Double(games) : 0 }
    var isLowSample: Bool { games < ProfileInsights.reliableGames }

    fileprivate static func ranking(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.score.total != rhs.score.total { return lhs.score.total > rhs.score.total }
        if lhs.games != rhs.games { return lhs.games > rhs.games }
        return lhs.champion.rawValue < rhs.champion.rawValue
    }
}

struct Matchups: Hashable {
    let best: [MatchupRecord]
    let worst: [MatchupRecord]

    var isEmpty: Bool { best.isEmpty && worst.isEmpty }
}

struct MatchupRecord: Identifiable, Hashable {
    struct Key: Hashable {
        let champion: ChampionID
        let role: Role
        let opponent: ChampionID
    }

    let id: Key
    let games: Int
    let wins: Int

    var winrate: Double { Double(wins) / Double(games) }
    var isLowSample: Bool { games < ProfileInsights.reliableGames }

    /// More games first, then a fixed order so equal records never swap.
    fileprivate static func tieBreak(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.games != rhs.games { return lhs.games > rhs.games }
        let left = (lhs.id.champion.rawValue, lhs.id.opponent.rawValue, lhs.id.role.rawValue)
        let right = (rhs.id.champion.rawValue, rhs.id.opponent.rawValue, rhs.id.role.rawValue)
        return left < right
    }
}

struct ShortGameInsight: Hashable {
    let champion: ChampionID
    let shortGames: Int
    let shortWins: Int
    let longerGames: Int
    let longerWins: Int

    var shortWinrate: Double { Double(shortWins) / Double(shortGames) }
    var longerWinrate: Double { Double(longerWins) / Double(longerGames) }
    var gap: Double { shortWinrate - longerWinrate }
    var isLowSample: Bool {
        min(shortGames, longerGames) < ProfileInsights.reliableGames
    }
}

/// Client-locale names; "Campeón 103" until they load (§22.2).
struct ChampionNames {
    let gameData: GameData?

    func callAsFunction(_ id: ChampionID) -> String {
        if let name = gameData?.champion(id)?.name, !name.isEmpty { return name }
        return String(localized: "Campeón \(id.rawValue)", table: "Profile")
    }
}
