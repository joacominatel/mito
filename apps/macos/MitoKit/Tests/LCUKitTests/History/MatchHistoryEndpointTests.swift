import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Testing

private let localPUUID = "fake-puuid-local"

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/history/\(name).json"))
}

private func page(_ name: String, localPUUID: String? = localPUUID) throws -> [MyMatch] {
    try LCUEndpoint.matchHistory(localPUUID: localPUUID).decode(fixture(name)).matches
}

private func rankedGame(_ id: Int, localPUUID: String? = localPUUID) throws -> MyMatch? {
    try page("ranked-page", localPUUID: localPUUID).first { $0.game == GameID(rawValue: id) }
}

private func participant(_ champion: Int, enemy: Bool, _ role: Role?) -> MyMatchParticipant {
    MyMatchParticipant(champion: ChampionID(rawValue: champion), isEnemy: enemy, role: role)
}

struct MatchHistoryEndpointTests {
    @Test func isABodylessGetOnTheFirstTwentyGamesByDefault() {
        let endpoint = LCUEndpoint.matchHistory(localPUUID: nil)
        #expect(endpoint.method == .get)
        #expect(
            endpoint.path
                == "/lol-match-history/v1/products/lol/current-summoner/matches?begIndex=0&endIndex=20"
        )
        #expect(endpoint.body == nil)
    }

    @Test func pagesThroughTheIndexesInThePath() {
        let endpoint = LCUEndpoint.matchHistory(begIndex: 20, endIndex: 40, localPUUID: nil)
        #expect(
            endpoint.path
                == "/lol-match-history/v1/products/lol/current-summoner/matches?begIndex=20&endIndex=40"
        )
    }

    @Test func mapsTheGameHeader() throws {
        let match = try #require(try rankedGame(7_000_000_001))
        #expect(match.queue == QueueID(rawValue: 420))
        #expect(match.playedAt == Date(timeIntervalSince1970: 1_792_094_400))
        #expect(match.durationSeconds == 1845)
    }

    @Test func takesThePatchFromTheFirstTwoComponentsOfTheGameVersion() throws {
        #expect(try rankedGame(7_000_000_001)?.patch == Patch(rawValue: "16.21"))
        #expect(try rankedGame(7_000_000_002)?.patch == Patch(rawValue: "16.20"))
    }

    @Test func mapsTheLocalPlayersChampionRoleAndResult() throws {
        let match = try #require(try rankedGame(7_000_000_001))
        #expect(match.champion == ChampionID(rawValue: 103))
        #expect(match.role == .middle)
        #expect(match.win)
    }

    @Test func mapsKillsDeathsAssistsAndCountsJungleMonstersAsCS() throws {
        let match = try #require(try rankedGame(7_000_000_001))
        #expect([match.kills, match.deaths, match.assists] == [8, 3, 11] as [Int])
        #expect(match.cs == 201 + 12)
    }

    @Test func keepsTheSpellsInSlotOrder() throws {
        let flashOnF = try #require(try rankedGame(7_000_000_002))
        #expect(
            flashOnF.spells
                == SpellPair(
                    first: SummonerSpellID(rawValue: 14), second: SummonerSpellID(rawValue: 4)))
    }

    @Test func keepsTheSixRunesInOrder() throws {
        let match = try #require(try rankedGame(7_000_000_001))
        #expect(match.perks == [8112, 8126, 8140, 8135, 8226, 8210].map(PerkID.init(rawValue:)))
    }

    @Test func keepsTheFinalItemsInSlotOrderAndDropsEmptySlots() throws {
        let match = try #require(try rankedGame(7_000_000_001))
        #expect(
            match.items == [6655, 3020, 4645, 3157, 3089, 3363].map(ItemID.init(rawValue:)))
    }

    @Test func mapsTheOtherNineAsChampionSideAndRole() throws {
        let match = try #require(try rankedGame(7_000_000_001))
        #expect(
            match.participants == [
                participant(516, enemy: false, .top), participant(64, enemy: false, .jungle),
                participant(222, enemy: false, .bottom), participant(412, enemy: false, .utility),
                participant(122, enemy: true, .top), participant(254, enemy: true, .jungle),
                participant(134, enemy: true, .middle), participant(145, enemy: true, .bottom),
                participant(117, enemy: true, .utility),
            ])
    }

    @Test func aLaneTheClientDoesNotAssignIsANilRole() throws {
        let match = try #require(try rankedGame(7_000_000_003))
        #expect(match.participants.first { $0.champion == ChampionID(rawValue: 64) }?.role == nil)
    }

    @Test func theOpponentIsTheEnemyInTheSameRole() throws {
        #expect(try rankedGame(7_000_000_001)?.opponent == ChampionID(rawValue: 134))
        #expect(try rankedGame(7_000_000_002)?.opponent == ChampionID(rawValue: 61))
    }

    @Test func twoEnemiesInTheSameRoleLeaveNoOpponent() throws {
        let match = try #require(try rankedGame(7_000_000_003))
        #expect(match.role == .middle)
        #expect(match.opponent == nil)
    }

    @Test func theOnlyIdentityIsTheLocalPlayerWithoutAPUUID() throws {
        let match = try #require(try rankedGame(7_000_000_001, localPUUID: nil))
        #expect(match.champion == ChampionID(rawValue: 103))
    }

    @Test func amongEveryIdentityTheLocalPlayerIsTheMatchingPUUID() throws {
        let match = try #require(try rankedGame(7_000_000_002))
        #expect(match.champion == ChampionID(rawValue: 134))
        #expect(!match.win)
        #expect(match.participants.filter(\.isEnemy).count == 5)
    }

    @Test func aGameWithManyIdentitiesAndNoPUUIDIsSkipped() throws {
        #expect(
            try page("ranked-page", localPUUID: nil).map(\.game.rawValue) == [
                7_000_000_001, 7_000_000_003,
            ])
    }

    @Test func keepsTheClientsOrder() throws {
        #expect(
            try page("ranked-page").map(\.game.rawValue) == [
                7_000_000_001, 7_000_000_002, 7_000_000_003,
            ])
    }

    @Test func noPlayerIdentityReachesTheMappedGames() throws {
        let mapped = String(describing: try page("ranked-page"))
        for marker in ["fake-puuid", "FakePlayer", "FakeSummoner", "FAKE", "LA2"] {
            #expect(!mapped.contains(marker), "\(marker)")
        }
    }

    @Test func anARAMGameHasNoRolesAndNoOpponent() throws {
        let match = try #require(try page("aram-page").first)
        #expect(match.queue == QueueID(rawValue: 450))
        #expect(match.role == nil)
        #expect(match.opponent == nil)
        #expect(match.participants.count == 9)
        #expect(match.participants.allSatisfy { $0.role == nil })
    }

    @Test func malformedGamesAreSkippedAndTheRestOfThePageDecodes() throws {
        #expect(try page("malformed-page").map(\.game.rawValue) == [7_000_000_001])
    }

    @Test(arguments: ["{}", #"{"games":{}}"#, #"{"games":{"games":{}}}"#, "[]", "null"])
    func aBodyWithoutAGameListIsADecodingError(_ json: String) {
        #expect(throws: LCUError.self) {
            try LCUEndpoint.matchHistory(localPUUID: nil).decode(Data(json.utf8))
        }
    }

    @Test func anEmptyGameListIsAnEmptyPage() throws {
        let page = try LCUEndpoint.matchHistory(localPUUID: nil).decode(
            Data(#"{"games":{"games":[]}}"#.utf8))
        #expect(page.matches.isEmpty)
    }

    @Test func sendsThroughAConnection() async throws {
        let path =
            "/lol-match-history/v1/products/lol/current-summoner/matches?begIndex=0&endIndex=3"
        let connection = FakeLCUConnection(responses: [
            .init(method: .get, path: path, body: try fixture("ranked-page"))
        ])
        let page = try await connection.send(
            .matchHistory(begIndex: 0, endIndex: 3, localPUUID: localPUUID))
        #expect(page.matches.count == 3)
        #expect(connection.requests.map(\.path) == [path])
    }
}

struct MatchHistoryGameEndpointTests {
    @Test func isABodylessGetOnTheGamePath() {
        let endpoint = LCUEndpoint.matchHistoryGame(
            GameID(rawValue: 7_000_000_002), localPUUID: nil)
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/lol-match-history/v1/games/7000000002")
        #expect(endpoint.body == nil)
    }

    @Test func findsTheLocalPlayerByPUUID() throws {
        let game = try LCUEndpoint.matchHistoryGame(
            GameID(rawValue: 7_000_000_002), localPUUID: localPUUID
        ).decode(fixture("game"))
        #expect(game.match.champion == ChampionID(rawValue: 134))
        #expect(game.match.opponent == ChampionID(rawValue: 61))
        #expect(game.match.participants.count == 9)
    }

    @Test func aGameWithoutAnIdentifiableLocalPlayerIsADecodingError() throws {
        let data = try fixture("game")
        #expect(throws: LCUError.self) {
            try LCUEndpoint.matchHistoryGame(GameID(rawValue: 7_000_000_002), localPUUID: nil)
                .decode(data)
        }
        #expect(throws: LCUError.self) {
            try LCUEndpoint.matchHistoryGame(
                GameID(rawValue: 7_000_000_002), localPUUID: "fake-puuid-stranger"
            ).decode(data)
        }
    }

    @Test func sendsThroughAConnection() async throws {
        let connection = FakeLCUConnection(responses: [
            .init(
                method: .get, path: "/lol-match-history/v1/games/7000000002",
                body: try fixture("game"))
        ])
        let game = try await connection.send(
            .matchHistoryGame(GameID(rawValue: 7_000_000_002), localPUUID: localPUUID))
        #expect(game.match.game == GameID(rawValue: 7_000_000_002))
    }
}
