import LCUKit
import MitoCore
import Testing

struct RecordedSessionTests {
    @Test(arguments: Recording.scenarios)
    func theCurrentSummonerDecodesToTheAnonymizedAccount(_ scenario: String) throws {
        let recording = try Recording(scenario)
        let bodies = recording.bodies(at: LCUEndpoint.currentSummoner.path)
        #expect(bodies.count == 1)
        for body in bodies {
            let summoner = try LCUEndpoint.currentSummoner.decode(body)
            #expect(
                summoner
                    == CurrentSummoner(
                        puuid: "00000000-0000-4000-8000-000000000002", summonerId: 3,
                        gameName: "anon-1", tagLine: "anon-3", summonerLevel: 397))
            #expect(summoner.riotID == "anon-1#anon-3")
        }
    }

    @Test(arguments: Recording.scenarios)
    func theGameVersionDropsTheBuildMetadataAndYieldsTheRecordedPatch(_ scenario: String) throws {
        let recording = try Recording(scenario)
        let bodies = recording.bodies(at: LCUEndpoint.gameVersion.path)
        #expect(bodies.count == 1)
        for body in bodies {
            let version = try LCUEndpoint.gameVersion.decode(body)
            #expect(version.rawValue == "16.21.8298620")
            #expect(version.patch == Patch(rawValue: recording.clientPatch))
        }
    }
}
