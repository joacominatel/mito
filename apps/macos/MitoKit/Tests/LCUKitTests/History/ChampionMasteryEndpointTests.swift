import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Testing

private func fixture() throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/history/mastery.json"))
}

private func mastery(_ champion: Int, points: Int, level: Int) -> ChampionMastery {
    ChampionMastery(champion: ChampionID(rawValue: champion), points: points, level: level)
}

struct ChampionMasteryEndpointTests {
    @Test func isABodylessGetOnTheLocalPlayersMastery() {
        #expect(LCUEndpoint.championMastery.method == .get)
        #expect(
            LCUEndpoint.championMastery.path
                == "/lol-champion-mastery/v1/local-player/champion-mastery")
        #expect(LCUEndpoint.championMastery.body == nil)
    }

    @Test func decodesPointsAndLevelPerChampionAndSkipsIncompleteEntries() throws {
        #expect(
            try LCUEndpoint.championMastery.decode(fixture()).masteries == [
                mastery(103, points: 245_310, level: 14),
                mastery(134, points: 61_234, level: 7),
                mastery(222, points: 0, level: 1),
            ])
    }

    @Test(arguments: ["{}", "null", #""mastery""#])
    func aBodyThatIsNotAListIsADecodingError(_ json: String) {
        #expect(throws: LCUError.self) {
            try LCUEndpoint.championMastery.decode(Data(json.utf8))
        }
    }

    @Test func sendsThroughAConnection() async throws {
        let connection = FakeLCUConnection(responses: [
            .init(
                method: .get, path: "/lol-champion-mastery/v1/local-player/champion-mastery",
                body: try fixture())
        ])
        let list = try await connection.send(.championMastery)
        #expect(list.masteries.count == 3)
    }
}
