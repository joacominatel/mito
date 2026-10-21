import Foundation
import MitoCore
import MitoTestSupport
import Testing

@testable import MitoEngine

/// The Mi historial tab's aggregation of your own games (§20.2).
struct HistoryReadTests {
    private let ahri = ChampionID(rawValue: 103)
    private let syndra = ChampionID(rawValue: 134)
    private let zed = ChampionID(rawValue: 238)
    private let yasuo = ChampionID(rawValue: 157)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let day = 86_400.0

    /// avg KDA (5000 + 5000) / 5000 = 2; avg CS/min 70000 / 10000 = 7.
    private let ahriMiddle = ChampionRoleStats(
        games: 1_000, wins: 520, timelineGames: 0, kills: 5_000, deaths: 5_000, assists: 5_000,
        cs: 70_000, minutes: 10_000)

    private func game(
        _ champion: ChampionID? = nil, role: Role? = .middle, queue: Int = 420,
        win: Bool = true, daysAgo: Double = 0, kills: Int = 2, deaths: Int = 1, assists: Int = 1,
        cs: Int = 210, durationSeconds: Int = 1_800, opponent: ChampionID? = nil
    ) -> MyMatch {
        MyMatch(
            game: GameID(rawValue: 1), queue: QueueID(rawValue: queue),
            patch: Patch(rawValue: "16.21"), playedAt: now.addingTimeInterval(-daysAgo * day),
            champion: champion ?? ahri, role: role, win: win, kills: kills, deaths: deaths,
            assists: assists, cs: cs, durationSeconds: durationSeconds, opponent: opponent,
            spells: SpellPair(
                first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
            perks: [], items: [], participants: [])
    }

    private func read(
        _ matches: [MyMatch], role: Role? = .middle, opponent: ChampionID? = nil,
        queue: QueueType = .rankedSolo, mastery: [ChampionID: Int] = [:],
        stats: InMemoryStatsProvider = InMemoryStatsProvider()
    ) -> HistoryRead {
        PersonalHistory.read(
            champion: ahri, role: role, opponent: opponent, queue: queue, matches: matches,
            masteryPoints: mastery, stats: stats, now: now)
    }

    // MARK: By champion

    @Test func theChampionCountsEveryRoleOnTheRift() {
        let history = read([
            game(), game(role: .top, win: false), game(role: nil), game(syndra),
        ])

        #expect(history.champion.games == 2)
        #expect(history.champion.wins == 1)
    }

    @Test func kdaAndCsPerMinuteAreAggregates() {
        let history = read([
            game(kills: 4, deaths: 2, assists: 6, cs: 200, durationSeconds: 1_200),
            game(kills: 0, deaths: 0, assists: 2, cs: 160, durationSeconds: 1_200),
        ])

        #expect(history.champion.kda == 6)
        #expect(history.champion.csPerMinute == 9)
    }

    @Test func lastPlayedIsTheMostRecentGame() {
        let history = read([game(daysAgo: 9), game(daysAgo: 2), game(daysAgo: 5)])

        #expect(history.champion.lastPlayed == now.addingTimeInterval(-2 * day))
    }

    @Test func remakesCountForNothing() {
        let history = read([game(durationSeconds: 299), game(durationSeconds: 300)])

        #expect(history.champion.games == 1)
    }

    @Test func masteryIsShownOnlyWithPoints() {
        #expect(read([], mastery: [ahri: 45_000, syndra: 90_000]).masteryPoints == 45_000)
        #expect(read([], mastery: [ahri: 0]).masteryPoints == nil)
        #expect(read([], mastery: [syndra: 10]).masteryPoints == nil)
    }

    @Test func withoutGamesEverythingIsEmptyNotZero() {
        let history = read([game(syndra)])

        #expect(history.champion.games == 0)
        #expect(history.champion.kda == nil)
        #expect(history.champion.csPerMinute == nil)
        #expect(history.champion.lastPlayed == nil)
    }

    // MARK: By rival

    @Test func theRivalCountsYourGamesWithTheChampionAgainstIt() {
        let history = read(
            [
                game(opponent: zed), game(win: false, opponent: zed), game(opponent: yasuo),
                game(syndra, opponent: zed), game(role: .top, opponent: zed),
            ],
            opponent: zed)

        #expect(history.versusOpponent?.games == 3)
        #expect(history.versusOpponent?.wins == 2)
    }

    @Test func noRivalMeansNoRivalRecord() {
        #expect(read([game(opponent: zed)]).versusOpponent == nil)
    }

    @Test func aRivalNeverFacedHasZeroGames() {
        #expect(read([game(opponent: yasuo)], opponent: zed).versusOpponent?.games == 0)
    }

    // MARK: By role

    @Test func theRoleCountsTheChampionThereAndEveryChampionThere() {
        let history = read([
            game(), game(win: false), game(role: .top), game(syndra), game(syndra, win: false),
            game(syndra, role: .bottom),
        ])

        #expect(history.championInRole?.games == 2)
        #expect(history.championInRole?.wins == 1)
        #expect(history.role?.games == 4)
        #expect(history.role?.wins == 2)
    }

    @Test func withASnapshotRowTheRoleComparesAgainstTheAverage() {
        let stats = InMemoryStatsProvider(
            meta: .example(), championRoleStatsByRole: [.middle: [ahri: ahriMiddle]])

        let history = read(
            [game(kills: 3, deaths: 1, assists: 1, cs: 240, durationSeconds: 1_800)],
            stats: stats)

        let inRole = history.championInRole
        #expect(inRole?.hasAverage == true)
        #expect(inRole?.metrics.kdaVsAverage == 2)
        #expect(inRole?.metrics.csVsAverage == 8.0 / 7.0)
        #expect(history.champion.hasAverage == false)
        #expect(history.role?.hasAverage == false)
    }

    @Test func withoutASnapshotNothingComparesAgainstAnAverage() {
        let stats = InMemoryStatsProvider(
            meta: nil, championRoleStatsByRole: [.middle: [ahri: ahriMiddle]])

        let history = read([game()], stats: stats)

        #expect(history.championInRole?.hasAverage == false)
        #expect(history.championInRole?.metrics.kdaVsAverage == 1)
    }

    // MARK: ARAM

    @Test func aramCountsOnlyAramGamesAndHasNoRivalOrRole() {
        let history = read(
            [
                game(role: nil, queue: 450), game(role: nil, queue: 450, win: false), game(),
                game(role: nil, queue: 1700),
            ],
            role: nil, opponent: zed, queue: .aram)

        #expect(history.champion.games == 2)
        #expect(history.champion.wins == 1)
        #expect(history.versusOpponent == nil)
        #expect(history.championInRole == nil)
        #expect(history.role == nil)
    }
}
