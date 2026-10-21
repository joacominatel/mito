import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Testing

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/assets/\(name).json"))
}

struct GameDataEndpointPathTests {
    @Test(arguments: [
        (
            "champion-summary", LCUEndpoint.gameDataChampions.path,
            LCUEndpoint.gameDataChampions.method, LCUEndpoint.gameDataChampions.body
        ),
        (
            "items", LCUEndpoint.gameDataItems.path, LCUEndpoint.gameDataItems.method,
            LCUEndpoint.gameDataItems.body
        ),
        (
            "perkstyles", LCUEndpoint.gameDataPerkStyles.path,
            LCUEndpoint.gameDataPerkStyles.method, LCUEndpoint.gameDataPerkStyles.body
        ),
        (
            "perks", LCUEndpoint.gameDataPerks.path, LCUEndpoint.gameDataPerks.method,
            LCUEndpoint.gameDataPerks.body
        ),
        (
            "summoner-spells", LCUEndpoint.gameDataSummonerSpells.path,
            LCUEndpoint.gameDataSummonerSpells.method, LCUEndpoint.gameDataSummonerSpells.body
        ),
    ])
    func eachFileIsABodylessGetUnderTheGameDataAssets(
        file: String, path: String, method: HTTPMethod, body: Data?
    ) {
        #expect(path == "/lol-game-data/assets/v1/\(file).json")
        #expect(method == .get)
        #expect(body == nil)
    }

    @Test func sendsThroughAConnection() async throws {
        let connection = FakeLCUConnection(responses: [
            .init(
                method: .get, path: "/lol-game-data/assets/v1/perks.json",
                body: try fixture("perks"))
        ])
        let perks = try await connection.send(.gameDataPerks)
        #expect(perks.perks.map(\.id.rawValue) == [8112, 8139, 5008])
    }
}

struct GameDataChampionsTests {
    @Test func decodesChampionSummaryIntoChampions() throws {
        let champions = try LCUEndpoint.gameDataChampions.decode(fixture("champion-summary"))
        #expect(
            champions.champions == [
                Champion(
                    id: ChampionID(rawValue: -1), alias: "None", name: "None",
                    iconPath: "/lol-game-data/assets/v1/champion-icons/-1.png"),
                Champion(
                    id: ChampionID(rawValue: 1), alias: "Annie", name: "Annie",
                    iconPath: "/lol-game-data/assets/v1/champion-icons/1.png"),
                Champion(
                    id: ChampionID(rawValue: 103), alias: "Ahri", name: "Ahri",
                    iconPath: "/lol-game-data/assets/v1/champion-icons/103.png"),
            ])
    }

    @Test func skipsEntriesWithoutANumericIDAndEmptiesBadFields() throws {
        let champions = try LCUEndpoint.gameDataChampions.decode(
            fixture("champion-summary-malformed"))
        #expect(
            champions.champions == [
                Champion(
                    id: ChampionID(rawValue: 103), alias: "Ahri", name: "Ahri",
                    iconPath: "/lol-game-data/assets/v1/champion-icons/103.png"),
                Champion(id: ChampionID(rawValue: 1), alias: "", name: "", iconPath: ""),
            ])
    }

    @Test func aBodyThatIsNotAnArrayIsADecodingError() {
        #expect {
            _ = try LCUEndpoint.gameDataChampions.decode(Data(#"{"champions":[]}"#.utf8))
        } throws: { error in
            if case .decoding = error as? LCUError { true } else { false }
        }
    }
}

struct GameDataItemsTests {
    @Test func decodesItemsWithoutAClass() throws {
        let items = try LCUEndpoint.gameDataItems.decode(fixture("items"))
        #expect(
            items.items == [
                Item(
                    id: ItemID(rawValue: 1001), name: "Boots", totalGold: 300,
                    iconPath:
                        "/lol-game-data/assets/ASSETS/Items/Icons2D/1001_Class_T1_BootsofSpeed.png",
                    itemClass: nil),
                Item(
                    id: ItemID(rawValue: 2003), name: "Health Potion", totalGold: 50,
                    iconPath:
                        "/lol-game-data/assets/ASSETS/Items/Icons2D/2003_Class_T1_HealthPotion.png",
                    itemClass: nil),
                Item(
                    id: ItemID(rawValue: 3157), name: "Zhonya's Hourglass", totalGold: 3250,
                    iconPath:
                        "/lol-game-data/assets/ASSETS/Items/Icons2D/3157_Mage_T3_ZhonyasHourglass.png",
                    itemClass: nil),
            ])
    }

    @Test func skipsMalformedItemsAndZeroesAMistypedPrice() throws {
        let items = try LCUEndpoint.gameDataItems.decode(fixture("items-malformed"))
        #expect(items.items.map(\.id.rawValue) == [3157, 1001])
        #expect(items.items.map(\.totalGold) == [3250, 0])
    }
}

struct GameDataPerkStylesTests {
    @Test func decodesStylesWithTheirRowsInClientOrder() throws {
        let styles = try LCUEndpoint.gameDataPerkStyles.decode(fixture("perkstyles")).styles
        #expect(styles.map(\.id.rawValue) == [8100, 8200])
        let domination = try #require(styles.first)
        #expect(domination.name == "Domination")
        #expect(
            domination.iconPath == "/lol-game-data/assets/v1/perk-images/Styles/7200_Domination.png"
        )
        #expect(
            domination.slots.map(\.kind) == [
                .keystone, .regular, .regular, .regular, .statMod, .statMod, .statMod,
            ])
        #expect(domination.slots.first?.perks.map(\.rawValue) == [8112, 8128, 9923])
    }

    @Test func anUnknownRowTypeIsKeptAsUnknown() throws {
        let styles = try LCUEndpoint.gameDataPerkStyles.decode(fixture("perkstyles-malformed"))
        let kinds = try #require(styles.styles.first).slots.map(\.kind)
        #expect(kinds.contains(.unknown("kFutureRow")))
    }

    @Test func skipsRowsWithoutATypeAndPerksThatAreNotNumbers() throws {
        let styles = try LCUEndpoint.gameDataPerkStyles.decode(fixture("perkstyles-malformed"))
        let slots = try #require(styles.styles.first).slots
        #expect(
            slots == [
                PerkStyle.Slot(
                    kind: .keystone, perks: [PerkID(rawValue: 8112), PerkID(rawValue: 9923)]),
                PerkStyle.Slot(kind: .unknown("kFutureRow"), perks: [PerkID(rawValue: 9999)]),
                PerkStyle.Slot(kind: .statMod, perks: []),
            ])
    }

    @Test func skipsStylesWithoutANumericIDAndKeepsOnesWithoutRows() throws {
        let styles = try LCUEndpoint.gameDataPerkStyles.decode(fixture("perkstyles-malformed"))
        #expect(styles.styles.map(\.id.rawValue) == [8100, 8300])
        #expect(styles.styles.last?.slots == [])
    }

    @Test func aBodyWithoutStylesIsADecodingError() {
        #expect {
            _ = try LCUEndpoint.gameDataPerkStyles.decode(Data(#"{"schemaVersion":2}"#.utf8))
        } throws: { error in
            if case .decoding = error as? LCUError { true } else { false }
        }
    }
}

struct GameDataPerksTests {
    @Test func decodesPerksIncludingShards() throws {
        let perks = try LCUEndpoint.gameDataPerks.decode(fixture("perks")).perks
        #expect(
            perks == [
                Perk(
                    id: PerkID(rawValue: 8112), name: "Electrocute",
                    iconPath:
                        "/lol-game-data/assets/v1/perk-images/Styles/Domination/Electrocute/Electrocute.png"
                ),
                Perk(
                    id: PerkID(rawValue: 8139), name: "Taste of Blood",
                    iconPath:
                        "/lol-game-data/assets/v1/perk-images/Styles/Domination/TasteOfBlood/GreenTerror_TasteOfBlood.png"
                ),
                Perk(
                    id: PerkID(rawValue: 5008), name: "Adaptive Force",
                    iconPath:
                        "/lol-game-data/assets/v1/perk-images/StatMods/StatModsAdaptiveForceIcon.png"
                ),
            ])
    }

    @Test func skipsAPerkWithAFractionalID() throws {
        let perks = try LCUEndpoint.gameDataPerks.decode(fixture("perks-malformed")).perks
        #expect(perks.map(\.id.rawValue) == [8112, 5008])
        #expect(perks.last == Perk(id: PerkID(rawValue: 5008), name: "", iconPath: ""))
    }
}

struct GameDataSummonerSpellsTests {
    @Test func decodesSpellsWithTheirGameModes() throws {
        let spells = try LCUEndpoint.gameDataSummonerSpells.decode(fixture("summoner-spells"))
            .spells
        #expect(spells.map(\.id.rawValue) == [4, 11, 14])
        #expect(
            spells.first
                == SummonerSpell(
                    id: SummonerSpellID(rawValue: 4), name: "Flash",
                    iconPath: "/lol-game-data/assets/DATA/Spells/Icons2D/Summoner_flash.png",
                    gameModes: ["ARAM", "CLASSIC", "URF"]))
        #expect(spells[1].gameModes == ["CLASSIC", "URF"])
    }

    @Test func skipsMalformedSpellsAndNonStringGameModes() throws {
        let spells = try LCUEndpoint.gameDataSummonerSpells.decode(
            fixture("summoner-spells-malformed")
        ).spells
        #expect(spells.map(\.id.rawValue) == [4, 14])
        #expect(spells.first?.gameModes == ["CLASSIC", "ARAM"])
        #expect(spells.last?.gameModes == [])
    }
}
