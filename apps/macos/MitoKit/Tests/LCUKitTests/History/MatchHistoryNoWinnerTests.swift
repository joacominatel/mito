import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Testing

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/history/\(name).json"))
}

private func noWinnerPage() throws -> [MyMatch] {
    try LCUEndpoint.matchHistory(localPUUID: "fake-puuid-local").decode(fixture("no-winner-page"))
        .matches
}

private func game(_ id: Int) throws -> MyMatch? {
    try noWinnerPage().first { $0.game == GameID(rawValue: id) }
}

struct MatchHistoryNoWinnerTests {
    @Test func anAbortedGameWhereBothTeamsLostIsSkippedAndThePageStillDecodes() throws {
        let ids = try noWinnerPage().map(\.game.rawValue)
        #expect(!ids.contains(7_000_000_031))
        #expect(ids == [7_000_000_030, 7_000_000_032, 7_000_000_034, 7_000_000_036, 7_000_000_037])
    }

    @Test func aNormalWinAndANormalLossStillMap() throws {
        #expect(try #require(try game(7_000_000_030)).win)
        #expect(try #require(try game(7_000_000_032)).win == false)
    }

    @Test func twoWinningTeamsAreSkipped() throws {
        #expect(try game(7_000_000_033) == nil)
    }

    @Test func withoutTeamsThePlayersResultsDecide() throws {
        #expect(try #require(try game(7_000_000_034)).win)
        #expect(try game(7_000_000_035) == nil)
    }

    @Test func teamsWithoutAResultFallBackToThePlayersResults() throws {
        #expect(try #require(try game(7_000_000_037)).win == false)
    }

    @Test func withNoResultButTheLocalPlayersTheGameMapsAsBefore() throws {
        #expect(try #require(try game(7_000_000_036)).win == false)
    }

    @Test func theSingleGameEndpointRejectsAnAbortedGame() throws {
        let data = try fixture("no-winner-game")
        #expect(throws: LCUError.self) {
            try LCUEndpoint.matchHistoryGame(
                GameID(rawValue: 7_000_000_002), localPUUID: "fake-puuid-local"
            ).decode(data)
        }
    }
}
