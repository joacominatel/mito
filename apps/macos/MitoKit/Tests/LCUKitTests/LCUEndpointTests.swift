import Foundation
import LCUKit
import Testing

struct LCUEndpointTests {
    private struct Summoner: Codable, Equatable {
        let gameName: String
    }

    @Test func decodesTheJSONResponse() throws {
        let endpoint = LCUEndpoint<Summoner>(
            method: .get, path: "/lol-summoner/v1/current-summoner")
        let summoner = try endpoint.decode(Data(#"{"gameName": "Mito", "extra": 1}"#.utf8))
        #expect(summoner == Summoner(gameName: "Mito"))
    }

    @Test func aMalformedResponseIsADecodingError() {
        let endpoint = LCUEndpoint<Summoner>(
            method: .get, path: "/lol-summoner/v1/current-summoner")
        #expect {
            try endpoint.decode(Data("[]".utf8))
        } throws: { error in
            if case .decoding = error as? LCUError { true } else { false }
        }
    }

    @Test func noContentAcceptsAnEmptyBody() throws {
        let endpoint = LCUEndpoint<LCUNoContent>(
            method: .post, path: "/lol-matchmaking/v1/ready-check/accept")
        #expect(try endpoint.decode(Data()) == LCUNoContent())
    }

    @Test func jsonBodyIsEncoded() throws {
        let endpoint = try LCUEndpoint<LCUNoContent>(
            method: .patch, path: "/lol-champ-select/v1/session/my-selection",
            json: ["spell1Id": 4])
        #expect(endpoint.body == Data(#"{"spell1Id":4}"#.utf8))
    }
}
