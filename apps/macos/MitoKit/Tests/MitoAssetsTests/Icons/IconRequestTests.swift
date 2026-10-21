import Foundation
import MitoAssets
import MitoCore
import Testing

struct IconRequestTests {
    @Test func aClientAssetPathWithADataDragonFileIsAccepted() throws {
        let file = DataDragonFile.image("champion/Ahri.png", patch: Patch(rawValue: "16.21"))
        let request = try IconRequest(
            assetPath: "/lol-game-data/assets/v1/champion-icons/103.png", gameVersion: "16.21.1",
            dataDragonFile: file)
        #expect(request.dataDragonFile == file)
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

    @Test(arguments: ["", ".", "..", "16/21", "16.21 1"])
    func aGameVersionThatIsNotADirectoryNameIsRejected(_ version: String) {
        #expect(throws: IconError.invalidGameVersion(version)) {
            try IconRequest(
                assetPath: "/lol-game-data/assets/v1/champion-icons/103.png", gameVersion: version)
        }
    }
}
