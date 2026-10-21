import Foundation
import MitoCore
import MitoEngine
import Testing

@testable import Mito

private let ahri = ChampionID(rawValue: 103)
private let syndra = ChampionID(rawValue: 134)

/// `count` games of one champion and role, the first `wins` of them won.
private func games(
    from id: Int, _ count: Int, champion: Int, role: Role? = .middle, opponent: Int? = nil,
    wins: Int, minutes: Int = 30
) -> [MyMatch] {
    (0..<count).map {
        TestGame.make(
            id + $0, champion: champion, role: role, opponent: opponent, win: $0 < wins,
            minutes: minutes, hoursAgo: Double(id + $0))
    }
}

private func best(_ matches: [MyMatch], pool: [PoolEntry] = []) -> [RoleChampions] {
    ProfileInsights.bestChampions(
        matches: matches, pool: pool, overrides: [], masteryPoints: [:], stats: TestStats(),
        now: TestGame.now)
}

struct ProfileInsightsTests {
    @Test func eachRoleRanksItsChampionsByThePersonalScore() throws {
        // Ahri has more games; Syndra is in the pool, which is worth more than that comfort.
        let matches =
            games(from: 0, 6, champion: 103, wins: 3) + games(from: 10, 2, champion: 134, wins: 1)
            + games(from: 20, 3, champion: 86, role: .top, wins: 2)
            + games(from: 30, 4, champion: 222, role: nil, wins: 4)
        let pool = [PoolEntry(role: .middle, champion: syndra, priority: 0)]

        let sections = best(matches, pool: pool)

        #expect(sections.map(\.role) == [.top, .middle])
        let middle = try #require(sections.last)
        #expect(middle.rows.map(\.champion) == [syndra, ahri])
        let engine = PersonalScoring.score(
            champion: syndra, role: .middle, matches: matches, pool: pool, overrides: [],
            masteryPoints: [:], stats: TestStats(), now: TestGame.now)
        #expect(middle.rows.first?.score == engine)
        #expect(middle.rows.first?.games == 2)
        #expect(middle.rows.first?.winrate == 0.5)
    }

    @Test func eachRoleShowsAtMostItsTopChampions() {
        let matches = (0..<8).flatMap {
            games(from: $0 * 10, $0 + 1, champion: 100 + $0, wins: $0 + 1)
        }

        let rows = best(matches).first?.rows ?? []

        #expect(rows.count == ProfileInsights.championsPerRole)
        #expect(rows.first?.champion == ChampionID(rawValue: 107))
    }

    @Test func rowsUnderTenGamesAreLowSample() {
        let matches =
            games(from: 0, 9, champion: 103, wins: 5) + games(from: 20, 10, champion: 134, wins: 5)

        let rows = best(matches).first?.rows ?? []

        #expect(rows.first { $0.champion == ahri }?.isLowSample == true)
        #expect(rows.first { $0.champion == syndra }?.isLowSample == false)
    }

    @Test func matchupsNeedThreeGamesAndSplitAtFiftyPercent() {
        let matches =
            games(from: 0, 3, champion: 103, opponent: 238, wins: 3)  // 3–0: best
            + games(from: 10, 2, champion: 103, opponent: 84, wins: 2)  // 2 games: too few
            + games(from: 20, 4, champion: 103, opponent: 7, wins: 1)  // 1–3: worst
            + games(from: 30, 4, champion: 103, opponent: 4, wins: 2)  // 50 %: neither
            + games(from: 40, 3, champion: 103, role: .top, opponent: 238, wins: 0)  // other role
            + games(from: 50, 3, champion: 103, opponent: 61, wins: 3, minutes: 4)  // remakes

        let matchups = ProfileInsights.matchups(in: matches)

        #expect(matchups.best.map(\.id.opponent.rawValue) == [238])
        #expect(matchups.best.first?.id.role == .middle)
        #expect(matchups.best.first?.wins == 3)
        #expect(matchups.worst.map(\.id.opponent.rawValue) == [238, 7])
        #expect(matchups.worst.first?.id.role == .top)
        #expect(matchups.worst.allSatisfy { $0.isLowSample })
    }

    @Test func matchupsKeepTheThreeBestAndThreeWorst() {
        // Ahri goes 5–0, 4–1, 3–2, 2–3; Syndra 0–5, 1–4, 2–3, 3–2.
        let ahriGames = (0..<4).flatMap {
            games(from: $0 * 10, 5, champion: 103, opponent: 200 + $0, wins: 5 - $0)
        }
        let syndraGames = (0..<4).flatMap {
            games(from: 100 + $0 * 10, 5, champion: 134, opponent: 300 + $0, wins: $0)
        }

        let matchups = ProfileInsights.matchups(in: ahriGames + syndraGames)

        // Equal records keep a fixed order: Ahri (103) before Syndra (134).
        #expect(matchups.best.map(\.id.opponent.rawValue) == [200, 201, 202])
        #expect(matchups.worst.map(\.id.opponent.rawValue) == [300, 301, 203])
    }

    @Test func shortGamesAreComparedWithTheLongerOnes() throws {
        let matches =
            games(from: 0, 5, champion: 134, wins: 4, minutes: 22)
            + games(from: 10, 5, champion: 134, wins: 1, minutes: 31)
            + games(from: 20, 3, champion: 134, wins: 0, minutes: 3)  // remakes don't count

        let insight = try #require(ProfileInsights.shortGames(in: matches))

        #expect(insight.champion == syndra)
        #expect(insight.shortWinrate == 0.8)
        #expect(insight.longerWinrate == 0.2)
        #expect(insight.isLowSample)
    }

    @Test(arguments: [(4, 5, 4, 1), (5, 4, 4, 1), (5, 5, 3, 3)])
    func shortGamesNeedFiveOnEachSideAndATenPointGap(
        short: Int, longer: Int, shortWins: Int, longerWins: Int
    ) {
        let matches =
            games(from: 0, short, champion: 134, wins: shortWins, minutes: 24)
            + games(from: 10, longer, champion: 134, wins: longerWins, minutes: 25)

        #expect(ProfileInsights.shortGames(in: matches) == nil)
    }

    @Test func shortGamesPickTheChampionWithTheWidestGap() {
        let matches =
            games(from: 0, 5, champion: 134, wins: 4, minutes: 20)
            + games(from: 10, 5, champion: 134, wins: 2, minutes: 30)
            + games(from: 20, 5, champion: 103, wins: 1, minutes: 20)
            + games(from: 30, 5, champion: 103, wins: 5, minutes: 30)

        #expect(ProfileInsights.shortGames(in: matches)?.champion == ahri)
    }

    @Test func aLossStreakCountsBackFromTheNewestGame() {
        let matches = [
            TestGame.make(1, champion: 103, win: false, hoursAgo: 1),
            TestGame.make(2, champion: 103, win: false, minutes: 3, hoursAgo: 2),  // a remake
            TestGame.make(3, champion: 222, role: nil, win: false, hoursAgo: 3),
            TestGame.make(4, champion: 103, win: false, hoursAgo: 4),
            TestGame.make(5, champion: 134, win: false, hoursAgo: 5),
            TestGame.make(6, champion: 103, win: true, hoursAgo: 6),
            TestGame.make(7, champion: 103, win: false, hoursAgo: 7),
        ]

        #expect(ProfileInsights.lossStreak(in: matches.shuffled()) == 4)
    }

    @Test func twoLossesAreNoStreak() {
        let matches = [
            TestGame.make(1, champion: 103, win: false, hoursAgo: 1),
            TestGame.make(2, champion: 103, win: false, hoursAgo: 2),
            TestGame.make(3, champion: 103, win: true, hoursAgo: 3),
        ]

        #expect(ProfileInsights.lossStreak(in: matches) == nil)
    }

    @Test func anEmptyHistoryHasNothingToShow() {
        #expect(best([]).isEmpty)
        #expect(ProfileInsights.matchups(in: []).isEmpty)
        #expect(ProfileInsights.shortGames(in: []) == nil)
        #expect(ProfileInsights.lossStreak(in: []) == nil)
    }
}
