import Foundation
import MitoCore
import MitoTestSupport
import Testing

@testable import MitoAssets

struct DataDragonFileTests {
    private static let patch = Patch(rawValue: "16.21")

    @Test func anImageLivesBelowTheResolvedVersion() throws {
        let file = try #require(DataDragonFile.image("champion/Ahri.png", patch: Self.patch))

        #expect(
            file.url(version: "16.21.2")?.absoluteString
                == "https://ddragon.leagueoflegends.com/cdn/16.21.2/img/champion/Ahri.png")
        #expect(file.url(version: nil) == nil)
    }

    @Test(arguments: [
        "", "../api/versions.json", "champion//Ahri.png", "champion/./Ahri.png",
        "champion/Ahri.png?x=1", "champion/Ahri.png#x", "champion\\Ahri.png",
        "champion/%2e%2e/Ahri.png",
    ])
    func aPathThatCouldLeaveImgIsRejected(_ path: String) {
        #expect(DataDragonFile.image(path, patch: Self.patch) == nil)
    }

    @Test(arguments: ["", "16", "16.21.1", "16.x", "../16.21"])
    func aPatchThatIsNotXYIsRejected(_ patch: String) {
        #expect(DataDragonFile.image("champion/Ahri.png", patch: Patch(rawValue: patch)) == nil)
    }

    /// Expected paths are the `icon` fields of Data Dragon 16.21.1 `runesReforged.json`.
    @Test func everyRecordedRuneAndTreeMapsToItsDataDragonIcon() throws {
        struct Perk: Decodable { let iconPath: String }
        struct Styles: Decodable { let styles: [Perk] }
        let perks = try JSONDecoder().decode(
            [Perk].self, from: Data(contentsOf: Fixtures.url("lcu/cases/assets/perks.json")))
        let styles = try JSONDecoder().decode(
            Styles.self, from: Data(contentsOf: Fixtures.url("lcu/cases/assets/perkstyles.json")))

        let urls = (perks + styles.styles).map {
            DataDragonFile.rune(clientIconPath: $0.iconPath)?.url(version: nil)?.absoluteString
        }

        let base = "https://ddragon.leagueoflegends.com/cdn/img/perk-images/"
        #expect(
            urls == [
                base + "Styles/Domination/Electrocute/Electrocute.png",
                base + "Styles/Domination/TasteOfBlood/GreenTerror_TasteOfBlood.png",
                base + "StatMods/StatModsAdaptiveForceIcon.png",
                base + "Styles/7200_Domination.png",
                base + "Styles/7202_Sorcery.png",
            ])
    }

    @Test(arguments: [
        "/lol-game-data/assets/DATA/Spells/Icons2D/SummonerIgnite.png",
        "/lol-game-data/assets/v1/champion-icons/103.png",
        "/lol-game-data/assets/v1/Perk-Images/Styles/7200_Domination.png",
        "/lol-game-data/assets/v1/perk-images/../champion-icons/103.png",
    ])
    func aClientPathOutsideTheRuneArtHasNoRuneFile(_ path: String) {
        #expect(DataDragonFile.rune(clientIconPath: path) == nil)
    }

    @Test func theNewestBuildOfThePatchWins() {
        let versions = ["16.22.1", "16.21.10", "16.21.2", "16.21.1", "16.2.1"]

        #expect(DataDragonFile.version(for: Self.patch, in: versions) == "16.21.10")
    }

    @Test func anUnlistedPatchOrAMalformedEntryResolvesToNothing() {
        let versions = ["16.20.1", "lolpatch_16.21", "16.21.1/../x", "16.21", "16.21.1a"]

        #expect(DataDragonFile.version(for: Self.patch, in: versions) == nil)
    }
}
