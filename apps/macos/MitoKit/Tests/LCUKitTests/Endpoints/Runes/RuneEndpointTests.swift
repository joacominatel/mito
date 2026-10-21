import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Testing

private func runesCase(_ name: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/runes/\(name).json"))
}

private func ids(_ raw: [Int]) -> [PerkID] { raw.map(PerkID.init) }

private let page = RunePage(
    primaryStyle: PerkStyleID(rawValue: 8100), subStyle: PerkStyleID(rawValue: 8200),
    perks: ids([8112, 8139, 8140, 8135, 8226, 8210, 5008, 5008, 5001]))

private func json(_ body: Data?) throws -> NSDictionary {
    let body = try #require(body)
    return try #require(try JSONSerialization.jsonObject(with: body) as? NSDictionary)
}

private func expectedBody() -> NSDictionary {
    [
        "name": "Mito · Ahri MID vs Zed",
        "primaryStyleId": 8100,
        "subStyleId": 8200,
        "selectedPerkIds": [8112, 8139, 8140, 8135, 8226, 8210, 5008, 5008, 5001],
        "current": true,
    ]
}

struct PerkStylesDecodingTests {
    @Test func decodesEachStyleWithItsSlotKindsAndPerksInOrder() throws {
        let styles = try LCUEndpoint.perkStyles.decode(runesCase("styles")).styles
        let domination = try #require(styles.first { $0.id == PerkStyleID(rawValue: 8100) })

        #expect(styles.map(\.id.rawValue) == [8100, 8000, 8200])
        #expect(domination.name == "Domination")
        #expect(
            domination.iconPath == "/lol-game-data/assets/v1/perk-images/Styles/7200_Domination.png"
        )
        #expect(
            domination.slots == [
                .init(kind: .keystone, perks: ids([8112, 8128, 9923])),
                .init(kind: .regular, perks: ids([8126, 8139, 8143])),
                .init(kind: .regular, perks: ids([8137, 8140, 8141])),
                .init(kind: .regular, perks: ids([8135, 8105, 8106])),
                .init(kind: .statMod, perks: ids([5008, 5005, 5007])),
                .init(kind: .statMod, perks: ids([5008, 5010, 5001])),
                .init(kind: .statMod, perks: ids([5011, 5013, 5001])),
            ])
    }

    @Test func anUnrecognizedSlotTypeIsKeptAsUnknownAndAMissingOneIsSkipped() throws {
        let body =
            #"[{"id": 1, "slots": [{"type": "kSomethingNew", "perks": [7]}, {"perks": [8]}]}]"#
        let styles = try LCUEndpoint.perkStyles.decode(Data(body.utf8)).styles

        #expect(
            styles.first?.slots == [
                .init(kind: .unknown("kSomethingNew"), perks: ids([7]))
            ])
    }

    @Test func aStyleWithoutAnIDIsSkippedAndMissingFieldsDefault() throws {
        let body = #"[{"name": "No id"}, {"id": 8300}]"#
        let styles = try LCUEndpoint.perkStyles.decode(Data(body.utf8)).styles

        #expect(
            styles == [
                PerkStyle(id: PerkStyleID(rawValue: 8300), name: "", iconPath: "", slots: [])
            ])
    }

    @Test func isAGetOnTheStylesPath() {
        #expect(LCUEndpoint.perkStyles.method == .get)
        #expect(LCUEndpoint.perkStyles.path == "/lol-perks/v1/styles")
    }
}

struct PerkPagesDecodingTests {
    @Test func decodesTheFieldsTheImporterReads() throws {
        let pages = try LCUEndpoint.perkPages.decode(runesCase("pages-with-mito-page"))

        #expect(
            pages == [
                PerkPage(
                    id: 101, name: "Domination: The Hunter", current: false, isEditable: false,
                    isDeletable: false),
                PerkPage(
                    id: 201, name: "My page", current: true, isEditable: true, isDeletable: true),
                PerkPage(
                    id: 202, name: "Mito · Lux SUPPORT vs Nami", current: false, isEditable: true,
                    isDeletable: true),
            ])
    }

    @Test func aPageWithoutAnIDIsSkippedAndMissingFieldsAreNil() throws {
        let pages = try LCUEndpoint.perkPages.decode(Data(#"[{"name": "x"}, {"id": 5}]"#.utf8))

        #expect(pages == [PerkPage(id: 5)])
    }

    @Test func isAGetOnThePagesPath() {
        #expect(LCUEndpoint.perkPages.method == .get)
        #expect(LCUEndpoint.perkPages.path == "/lol-perks/v1/pages")
    }
}

struct PerkInventoryDecodingTests {
    @Test func decodesTheOwnedPageCountIgnoringOtherFields() throws {
        let inventory = try LCUEndpoint.perkInventory.decode(runesCase("inventory-with-room"))

        #expect(inventory == PerkInventory(ownedPageCount: 3))
    }

    @Test func aMissingCountDecodesAsNil() throws {
        #expect(try LCUEndpoint.perkInventory.decode(Data("{}".utf8)) == PerkInventory())
    }

    @Test func isAGetOnTheInventoryPath() {
        #expect(LCUEndpoint.perkInventory.method == .get)
        #expect(LCUEndpoint.perkInventory.path == "/lol-perks/v1/inventory")
    }
}

struct PerkPageWriteEndpointTests {
    @Test func createPostsThePageAsCurrent() throws {
        let endpoint = try LCUEndpoint.createPerkPage(page, name: "Mito · Ahri MID vs Zed")

        #expect(endpoint.method == .post)
        #expect(endpoint.path == "/lol-perks/v1/pages")
        #expect(try json(endpoint.body) == expectedBody())
    }

    @Test func updatePutsThePageAsCurrentUnderItsID() throws {
        let endpoint = try LCUEndpoint.updatePerkPage(
            id: 202, page, name: "Mito · Ahri MID vs Zed")

        #expect(endpoint.method == .put)
        #expect(endpoint.path == "/lol-perks/v1/pages/202")
        #expect(try json(endpoint.body) == expectedBody())
    }

    @Test(arguments: ["", #"{"id": 202}"#])
    func writesIgnoreTheResponseBody(_ body: String) throws {
        let endpoint = try LCUEndpoint.updatePerkPage(id: 202, page, name: "Mito · x")

        #expect(try endpoint.decode(Data(body.utf8)) == LCUNoContent())
    }
}
