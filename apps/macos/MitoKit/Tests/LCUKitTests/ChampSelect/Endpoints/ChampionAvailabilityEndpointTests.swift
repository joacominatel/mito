import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Testing

private let endpoints: [(endpoint: LCUEndpoint<Set<ChampionID>>, path: String)] = [
    (.pickableChampionIDs, "/lol-champ-select/v1/pickable-champion-ids"),
    (.bannableChampionIDs, "/lol-champ-select/v1/bannable-champion-ids"),
]

private func idsBody() throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/champ-select/pickable-champion-ids.json"))
}

private func champions(_ ids: Int...) -> Set<ChampionID> {
    Set(ids.map(ChampionID.init(rawValue:)))
}

struct ChampionAvailabilityEndpointTests {
    @Test(arguments: endpoints)
    func isAGetOnItsPath(endpoint: LCUEndpoint<Set<ChampionID>>, path: String) {
        #expect(endpoint.method == .get)
        #expect(endpoint.path == path)
        #expect(endpoint.body == nil)
    }

    @Test(arguments: endpoints.map(\.endpoint))
    func dropsZeroAndNonIntegers(_ endpoint: LCUEndpoint<Set<ChampionID>>) throws {
        #expect(try endpoint.decode(idsBody()) == champions(266, 103, 157))
    }

    @Test(arguments: endpoints.map(\.endpoint))
    func anEmptyArrayIsAnEmptySet(_ endpoint: LCUEndpoint<Set<ChampionID>>) throws {
        #expect(try endpoint.decode(Data("[]".utf8)).isEmpty)
    }

    @Test(arguments: endpoints.map(\.endpoint))
    func aBodyThatIsNotAnArrayIsADecodingError(_ endpoint: LCUEndpoint<Set<ChampionID>>) {
        for json in ["", "null", "103", #"{"ids":[103]}"#] {
            #expect {
                try endpoint.decode(Data(json.utf8))
            } throws: { error in
                if case .decoding = error as? LCUError { true } else { false }
            }
        }
    }

    @Test(arguments: endpoints)
    func sendsThroughAConnection(endpoint: LCUEndpoint<Set<ChampionID>>, path: String)
        async throws
    {
        let connection = FakeLCUConnection(responses: [
            .init(method: .get, path: path, body: try idsBody())
        ])
        #expect(try await connection.send(endpoint) == champions(266, 103, 157))
        #expect(connection.requests.map(\.path) == [path])
    }
}
