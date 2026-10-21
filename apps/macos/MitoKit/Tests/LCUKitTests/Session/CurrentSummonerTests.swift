import Foundation
import LCUKit
import MitoTestSupport
import Testing

struct CurrentSummonerTests {
    private func decodeCase(_ name: String) throws -> CurrentSummoner {
        let data = try Data(contentsOf: Fixtures.url("lcu/cases/session/\(name).json"))
        return try LCUEndpoint.currentSummoner.decode(data)
    }

    @Test func decodesAFullPayload() throws {
        let summoner = try decodeCase("full")
        #expect(
            summoner
                == CurrentSummoner(
                    puuid: "00000000-0000-0000-0000-000000000000", summonerId: 1,
                    gameName: "Tester", tagLine: "TEST", summonerLevel: 30))
    }

    @Test func missingFieldsDecodeAsNil() throws {
        #expect(try decodeCase("missing-fields") == CurrentSummoner(gameName: "Tester"))
    }

    @Test func extraFieldsAreIgnored() throws {
        #expect(try decodeCase("extra-fields") == decodeCase("full"))
    }

    @Test func anEmptyTagLineDecodesAsEmpty() throws {
        #expect(try decodeCase("empty-tag-line").tagLine == "")
    }

    @Test func riotIDJoinsGameNameAndTagLine() {
        #expect(CurrentSummoner(gameName: "Tester", tagLine: "TEST").riotID == "Tester#TEST")
    }

    @Test(arguments: [
        CurrentSummoner(gameName: "Tester", tagLine: ""),
        CurrentSummoner(gameName: "", tagLine: "TEST"),
        CurrentSummoner(gameName: "Tester"),
        CurrentSummoner(tagLine: "TEST"),
        CurrentSummoner(),
    ])
    func riotIDIsNilWithoutBothParts(_ summoner: CurrentSummoner) {
        #expect(summoner.riotID == nil)
    }

    @Test func textualFormsDoNotExposeIdentity() throws {
        let summoner = try decodeCase("full")
        let forms = [
            String(describing: summoner), String(reflecting: summoner),
            String(describing: Mirror(reflecting: summoner).children.map(\.value)),
        ]
        for form in forms {
            #expect(!form.contains("00000000-0000-0000-0000-000000000000"))
            #expect(!form.contains("Tester"))
            #expect(!form.contains("TEST"))
        }
    }
}

struct CurrentSummonerEndpointTests {
    @Test func isAGetOnTheCurrentSummonerPath() {
        let endpoint = LCUEndpoint.currentSummoner
        #expect(endpoint.method == .get)
        #expect(endpoint.path == "/lol-summoner/v1/current-summoner")
        #expect(endpoint.body == nil)
    }

    @Test func sendsThroughAConnection() async throws {
        let connection = FakeLCUConnection(responses: [
            .init(
                method: .get, path: "/lol-summoner/v1/current-summoner",
                body: try Data(contentsOf: Fixtures.url("lcu/cases/session/full.json")))
        ])
        let summoner = try await connection.send(.currentSummoner)
        #expect(summoner.riotID == "Tester#TEST")
    }
}
