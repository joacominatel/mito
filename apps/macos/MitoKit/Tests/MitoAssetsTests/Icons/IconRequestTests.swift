import Foundation
import MitoAssets
import Testing

struct IconRequestTests {
    @Test func aClientAssetPathWithADataDragonURLIsAccepted() throws {
        let url = URL(
            string: "https://ddragon.leagueoflegends.com/cdn/16.21.1/img/champion/Ahri.png")
        let request = try IconRequest(
            assetPath: "/lol-game-data/assets/v1/champion-icons/103.png", gameVersion: "16.21.1",
            dataDragonURL: url)
        #expect(request.dataDragonURL == url)
    }

    @Test(arguments: [
        "/lol-summoner/v1/current-summoner",
        "lol-game-data/assets/v1/champion-icons/103.png",
        "/lol-game-data/assets/",
        "/lol-game-data/assets/../../lol-summoner/v1/current-summoner",
        "/lol-game-data/assets/v1/%2e%2e/%2e%2e/lol-summoner/v1/current-summoner",
        "/lol-game-data/assets/v1//champion-icons/103.png",
        "/lol-game-data/assets/v1/champion-icons/103.png?x=1",
    ])
    func aPathOutsideTheClientAssetsIsRejected(_ path: String) {
        #expect(throws: IconError.invalidAssetPath(path)) {
            try IconRequest(assetPath: path, gameVersion: "16.21.1")
        }
    }

    @Test(arguments: [
        "http://ddragon.leagueoflegends.com/cdn/16.21.1/img/champion/Ahri.png",
        "https://raw.communitydragon.org/latest/champion/103/square.png",
        "https://ddragon.leagueoflegends.com.example.com/cdn/img/champion/Ahri.png",
        "https://ddragon.leagueoflegends.com:8443/cdn/16.21.1/img/champion/Ahri.png",
        "https://user@ddragon.leagueoflegends.com/cdn/16.21.1/img/champion/Ahri.png",
    ])
    func aDataDragonURLOnAnotherHostOrSchemeIsRejected(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(throws: IconError.invalidDataDragonURL(url.absoluteString)) {
            try IconRequest(
                assetPath: "/lol-game-data/assets/v1/champion-icons/103.png",
                gameVersion: "16.21.1", dataDragonURL: url)
        }
    }

    @Test(arguments: ["", ".", "..", "16/21", "16.21 1"])
    func aGameVersionThatIsNotADirectoryNameIsRejected(_ version: String) {
        #expect(throws: IconError.invalidGameVersion(version)) {
            try IconRequest(
                assetPath: "/lol-game-data/assets/v1/champion-icons/103.png", gameVersion: version)
        }
    }
}
