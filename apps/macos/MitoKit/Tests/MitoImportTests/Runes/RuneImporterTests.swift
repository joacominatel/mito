import Foundation
import LCUKit
import MitoCore
import MitoImport
import MitoTestSupport
import Testing

private let pagesPath = "/lol-perks/v1/pages"
private let inventoryPath = "/lol-perks/v1/inventory"
private let stylesPath = "/lol-perks/v1/styles"
private let title = "Ahri MID vs Zed"
private let mitoName = "Mito · Ahri MID vs Zed"

private let domination = PerkStyleID(rawValue: 8100)
private let precision = PerkStyleID(rawValue: 8000)
private let sorcery = PerkStyleID(rawValue: 8200)

/// Electrocute, Taste of Blood, Grisly Mementos, Ultimate Hunter; Manaflow Band, Transcendence;
/// adaptive, adaptive, health scaling.
private let validPerks = [8112, 8139, 8140, 8135, 8226, 8210, 5008, 5008, 5001]

private func runePage(
    _ perks: [Int] = validPerks, primary: PerkStyleID = domination, sub: PerkStyleID = sorcery
) -> RunePage {
    RunePage(primaryStyle: primary, subStyle: sub, perks: perks.map(PerkID.init))
}

private func replacing(_ perks: [Int], at index: Int, with perk: Int) -> [Int] {
    var perks = perks
    perks[index] = perk
    return perks
}

private func runesCase(_ name: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/runes/\(name).json"))
}

/// Every page in the fixtures accepts writes, so a test sees exactly where the importer wrote.
private func connection(
    pages: String = "pages-without-mito-page", pagesJSON: String? = nil,
    inventory: String = "inventory-with-room", inventoryJSON: String? = nil,
    stylesJSON: String? = nil, writeStatus: Int = 200
) throws -> FakeLCUConnection {
    let writes = [101, 201, 202, 203, 204].map {
        FakeLCUConnection.Response(method: .put, path: "\(pagesPath)/\($0)", status: writeStatus)
    }
    return FakeLCUConnection(
        responses: [
            .init(
                method: .get, path: stylesPath,
                body: try stylesJSON.map { Data($0.utf8) } ?? runesCase("styles")),
            .init(
                method: .get, path: pagesPath,
                body: try pagesJSON.map { Data($0.utf8) } ?? runesCase(pages)),
            .init(
                method: .get, path: inventoryPath,
                body: try inventoryJSON.map { Data($0.utf8) } ?? runesCase(inventory)),
            .init(method: .post, path: pagesPath, status: writeStatus),
        ] + writes)
}

private func apply(
    _ page: RunePage = runePage(), settings: ImportSettings = ImportSettings(),
    confirmedReplacement: Int? = nil, on connection: FakeLCUConnection
) async -> RuneImportResult {
    await RuneImporter(connection: connection).apply(
        page, title: title, settings: settings, confirmedReplacement: confirmedReplacement)
}

private func writeRoutes(_ connection: FakeLCUConnection) -> [String] {
    connection.writes.map { "\($0.method.rawValue) \($0.path)" }
}

private func body(_ request: FakeLCUConnection.Request?) throws -> NSDictionary {
    let data = try #require(request?.body)
    return try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

private func expectedBody(_ perks: [Int] = validPerks) -> NSDictionary {
    [
        "name": mitoName, "primaryStyleId": 8100, "subStyleId": 8200,
        "selectedPerkIds": perks, "current": true,
    ]
}

private func page(
    _ id: Int, _ name: String, current: Bool = false, editable: Bool = true,
    deletable: Bool = true
) -> String {
    #"{"id": \#(id), "name": "\#(name)", "current": \#(current), "isEditable": \#(editable), "isDeletable": \#(deletable)}"#
}

struct RuneImporterStrategyTests {
    @Test func editsTheExistingMitoPageWithAPutAndMakesItCurrent() async throws {
        let lcu = try connection(pages: "pages-with-mito-page")
        let result = await apply(on: lcu)

        #expect(result == .updated(pageID: 202))
        #expect(writeRoutes(lcu) == ["PUT /lol-perks/v1/pages/202"])
        #expect(try body(lcu.writes.first) == expectedBody())
    }

    @Test func editsTheMitoPageEvenWhenThereIsNoRoom() async throws {
        let lcu = try connection(pages: "pages-with-mito-page", inventory: "inventory-full")
        let result = await apply(on: lcu)

        #expect(result == .updated(pageID: 202))
        #expect(writeRoutes(lcu) == ["PUT /lol-perks/v1/pages/202"])
    }

    @Test func prefersTheCurrentMitoPageWhenThereAreSeveral() async throws {
        let pages = [page(203, "Mito · old"), page(204, "Mito · newer", current: true)]
        let lcu = try connection(pagesJSON: "[\(pages.joined(separator: ","))]")
        _ = await apply(on: lcu)

        #expect(writeRoutes(lcu) == ["PUT /lol-perks/v1/pages/204"])
    }

    @Test func aLockedPageNamedLikeMitosIsNotEdited() async throws {
        let pages = [page(201, "Mine", current: true), page(101, "Mito · x", editable: false)]
        let lcu = try connection(pagesJSON: "[\(pages.joined(separator: ","))]")
        let result = await apply(on: lcu)

        #expect(result == .created)
        #expect(writeRoutes(lcu) == ["POST /lol-perks/v1/pages"])
    }

    @Test func createsTheMitoPageWithAPostWhenThereIsRoom() async throws {
        let lcu = try connection()
        let result = await apply(on: lcu)

        #expect(result == .created)
        #expect(writeRoutes(lcu) == ["POST /lol-perks/v1/pages"])
        #expect(try body(lcu.writes.first) == expectedBody())
        #expect(lcu.requests.contains { $0.path == inventoryPath })
    }

    @Test func asksForConfirmationInsteadOfOverwritingTheUsersCurrentPage() async throws {
        let lcu = try connection(inventory: "inventory-full")
        let result = await apply(on: lcu)

        #expect(result == .needsConfirmation(pageID: 201, pageName: "My page"))
        #expect(lcu.writes.isEmpty)
    }

    @Test func replacesTheCurrentPageOnceTheUserConfirmedIt() async throws {
        let lcu = try connection(inventory: "inventory-full")
        let result = await apply(confirmedReplacement: 201, on: lcu)

        #expect(result == .replacedCurrentPage(pageID: 201))
        #expect(writeRoutes(lcu) == ["PUT /lol-perks/v1/pages/201"])
        #expect(try body(lcu.writes.first) == expectedBody())
    }

    @Test func aConfirmationForAPageThatIsNoLongerCurrentAsksAgain() async throws {
        let lcu = try connection(inventory: "inventory-full")
        let result = await apply(confirmedReplacement: 203, on: lcu)

        #expect(result == .needsConfirmation(pageID: 201, pageName: "My page"))
        #expect(lcu.writes.isEmpty)
    }

    @Test func anInventoryWithoutACountIsTreatedAsFull() async throws {
        let lcu = try connection(inventoryJSON: "{}")
        let result = await apply(on: lcu)

        #expect(result == .needsConfirmation(pageID: 201, pageName: "My page"))
        #expect(lcu.writes.isEmpty)
    }

    @Test func pagesWithoutADeletableFlagTakeACustomSlot() async throws {
        let pages = [
            #"{"id": 201, "name": "Mine", "current": true, "isEditable": true}"#,
            #"{"id": 203, "name": "Also mine", "isEditable": true}"#,
        ]
        let lcu = try connection(
            pagesJSON: "[\(pages.joined(separator: ","))]", inventoryJSON: #"{"ownedPageCount": 2}"#
        )
        let result = await apply(on: lcu)

        #expect(result == .needsConfirmation(pageID: 201, pageName: "Mine"))
        #expect(lcu.writes.isEmpty)
    }

    @Test func aMitoPageWithoutAnEditableFlagIsNotEdited() async throws {
        let pages = [page(201, "Mine", current: true), #"{"id": 204, "name": "Mito · old"}"#]
        let lcu = try connection(pagesJSON: "[\(pages.joined(separator: ","))]")
        let result = await apply(on: lcu)

        #expect(result == .created)
        #expect(writeRoutes(lcu) == ["POST /lol-perks/v1/pages"])
    }

    @Test func noPageIsAvailableWhenFullAndTheCurrentPageIsLocked() async throws {
        let pages = [
            page(101, "Domination: The Hunter", current: true, editable: false, deletable: false),
            page(201, "Mine"), page(203, "Also mine"),
        ]
        let lcu = try connection(
            pagesJSON: "[\(pages.joined(separator: ","))]", inventory: "inventory-full")
        let result = await apply(confirmedReplacement: 101, on: lcu)

        #expect(result == .noEditablePage)
        #expect(lcu.writes.isEmpty)
    }
}

struct RuneImporterTargetTests {
    @Test func theReservedPageIsOverwrittenWithoutConfirmation() async throws {
        let lcu = try connection(inventory: "inventory-full")
        let result = await apply(
            settings: ImportSettings(runePageTarget: .reservedPage, reservedRunePageID: 203),
            on: lcu)

        #expect(result == .updated(pageID: 203))
        #expect(writeRoutes(lcu) == ["PUT /lol-perks/v1/pages/203"])
        #expect(try body(lcu.writes.first) == expectedBody())
        #expect(!lcu.requests.contains { $0.path == inventoryPath })
    }

    @Test func theReservedPageWinsOverAnExistingMitoPage() async throws {
        let lcu = try connection(pages: "pages-with-mito-page")
        _ = await apply(
            settings: ImportSettings(runePageTarget: .reservedPage, reservedRunePageID: 201),
            on: lcu)

        #expect(writeRoutes(lcu) == ["PUT /lol-perks/v1/pages/201"])
    }

    /// Unset, gone from the client, or one of the client's locked pages.
    @Test(arguments: [nil, 999, 101])
    func nothingIsSentWhenTheReservedPageCannotBeWritten(_ reserved: Int?) async throws {
        let lcu = try connection()
        let result = await apply(
            settings: ImportSettings(runePageTarget: .reservedPage, reservedRunePageID: reserved),
            on: lcu)

        #expect(result == .noEditablePage)
        #expect(lcu.writes.isEmpty)
    }

    @Test func theCurrentPageTargetOverwritesTheCurrentPageWithoutConfirmation() async throws {
        let lcu = try connection(pages: "pages-with-mito-page", inventory: "inventory-full")
        let result = await apply(settings: ImportSettings(runePageTarget: .currentPage), on: lcu)

        #expect(result == .replacedCurrentPage(pageID: 201))
        #expect(writeRoutes(lcu) == ["PUT /lol-perks/v1/pages/201"])
        #expect(try body(lcu.writes.first) == expectedBody())
    }

    @Test func theCurrentPageTargetSendsNothingWhenTheCurrentPageIsLocked() async throws {
        let pages = [
            page(101, "Domination: The Hunter", current: true, editable: false, deletable: false),
            page(201, "Mine"),
        ]
        let lcu = try connection(pagesJSON: "[\(pages.joined(separator: ","))]")
        let result = await apply(settings: ImportSettings(runePageTarget: .currentPage), on: lcu)

        #expect(result == .noEditablePage)
        #expect(lcu.writes.isEmpty)
    }
}

struct RuneImporterValidationTests {
    private func expectInvalid(
        _ page: RunePage, _ error: RunePageValidationError, stylesJSON: String? = nil
    ) async throws {
        let lcu = try connection(stylesJSON: stylesJSON)
        let result = await apply(page, on: lcu)

        #expect(result == .invalid(error))
        #expect(lcu.writes.isEmpty)
        #expect(!lcu.requests.contains { $0.path == pagesPath })
    }

    @Test(arguments: [8, 10])
    func aPageWithoutNinePerksIsNotSent(_ count: Int) async throws {
        let perks = Array((validPerks + [5001]).prefix(count))
        try await expectInvalid(runePage(perks), .wrongPerkCount(count))
    }

    @Test func theSameStyleTwiceIsNotSent() async throws {
        try await expectInvalid(runePage(sub: domination), .sameStyleTwice)
    }

    @Test func anUnknownPrimaryStyleIsNotSent() async throws {
        let unknown = PerkStyleID(rawValue: 9999)
        try await expectInvalid(runePage(primary: unknown), .unknownStyle(unknown))
    }

    @Test func anUnknownSecondaryStyleIsNotSent() async throws {
        let resolve = PerkStyleID(rawValue: 8400)  // Not in the trimmed styles sample.
        try await expectInvalid(runePage(sub: resolve), .unknownStyle(resolve))
    }

    @Test func aKeystoneFromAnotherStyleIsNotSent() async throws {
        let conqueror = 8010
        try await expectInvalid(
            runePage(replacing(validPerks, at: 0, with: conqueror)),
            .perkOutOfPlace(index: 0, perk: PerkID(rawValue: conqueror)))
    }

    @Test func primaryPerksInTheWrongRowOrderAreNotSent() async throws {
        let swapped = [8112, 8140, 8139, 8135, 8226, 8210, 5008, 5008, 5001]
        try await expectInvalid(
            runePage(swapped), .perkOutOfPlace(index: 1, perk: PerkID(rawValue: 8140)))
    }

    @Test func aSecondaryKeystoneIsNotSent() async throws {
        let arcaneComet = 8229
        try await expectInvalid(
            runePage(replacing(validPerks, at: 4, with: arcaneComet)),
            .perkOutOfPlace(index: 4, perk: PerkID(rawValue: arcaneComet)))
    }

    @Test func aSecondaryPerkFromAnotherStyleIsNotSent() async throws {
        let triumph = 9111
        try await expectInvalid(
            runePage(replacing(validPerks, at: 5, with: triumph)),
            .perkOutOfPlace(index: 5, perk: PerkID(rawValue: triumph)))
    }

    @Test func twoSecondaryPerksFromTheSameRowAreNotSent() async throws {
        let nimbusCloak = 8275  // Artifact row, with Manaflow Band.
        try await expectInvalid(
            runePage(replacing(validPerks, at: 5, with: nimbusCloak)), .secondaryPerksShareARow)
    }

    @Test(arguments: [(6, 5011), (7, 5013), (8, 5005)])
    func aShardFromTheWrongRowIsNotSent(_ index: Int, _ shard: Int) async throws {
        try await expectInvalid(
            runePage(replacing(validPerks, at: index, with: shard)),
            .perkOutOfPlace(index: index, perk: PerkID(rawValue: shard)))
    }

    /// 5008 sits in the offense and flex rows, 5001 in the flex and defense rows (§16.2).
    @Test(arguments: [[5008, 5008, 5001], [5005, 5001, 5001], [5007, 5010, 5011]])
    func aShardSharedByTwoRowsIsValidInEither(_ shards: [Int]) async throws {
        let perks = Array(validPerks.prefix(6)) + shards
        let lcu = try connection()
        let result = await apply(runePage(perks), on: lcu)

        #expect(result == .created)
        #expect(try body(lcu.writes.first) == expectedBody(perks))
    }

    @Test func secondaryPerksAreAcceptedInEitherOrder() async throws {
        let perks = [8112, 8139, 8140, 8135, 8210, 8226, 5008, 5008, 5001]
        let lcu = try connection()

        #expect(await apply(runePage(perks), on: lcu) == .created)
    }

    @Test func rowsAreFoundBySlotKindNotPosition() async throws {
        let styles = """
            [{"id": 8100, "slots": [
              {"type": "kStatMod", "perks": [5008, 5005, 5007]},
              {"type": "kSomethingNew", "perks": [8112]},
              {"type": "kMixedRegularSplashable", "perks": [8126, 8139, 8143]},
              {"type": "kStatMod", "perks": [5008, 5010, 5001]},
              {"type": "kKeyStone", "perks": [8112, 8128, 9923]},
              {"type": "kMixedRegularSplashable", "perks": [8137, 8140, 8141]},
              {"type": "kStatMod", "perks": [5011, 5013, 5001]},
              {"type": "kMixedRegularSplashable", "perks": [8135, 8105, 8106]}
            ]},
            {"id": 8200, "slots": [
              {"type": "kMixedRegularSplashable", "perks": [8226]},
              {"type": "kMixedRegularSplashable", "perks": [8210]}
            ]}]
            """
        let lcu = try connection(stylesJSON: styles)

        #expect(await apply(on: lcu) == .created)
    }

    @Test func aStyleMissingAShardRowIsNotSent() async throws {
        let styles = """
            [{"id": 8100, "slots": [
              {"type": "kKeyStone", "perks": [8112]},
              {"type": "kMixedRegularSplashable", "perks": [8139]},
              {"type": "kMixedRegularSplashable", "perks": [8140]},
              {"type": "kMixedRegularSplashable", "perks": [8135]},
              {"type": "kStatMod", "perks": [5008]},
              {"type": "kStatMod", "perks": [5008]}
            ]},
            {"id": 8200, "slots": [
              {"type": "kMixedRegularSplashable", "perks": [8226]},
              {"type": "kMixedRegularSplashable", "perks": [8210]}
            ]}]
            """
        try await expectInvalid(runePage(), .unexpectedStyleLayout(domination), stylesJSON: styles)
    }

    @Test func aSecondaryStyleWithFewerThanTwoRegularRowsIsNotSent() async throws {
        let styles = """
            [{"id": 8100, "slots": [
              {"type": "kKeyStone", "perks": [8112]},
              {"type": "kMixedRegularSplashable", "perks": [8139]},
              {"type": "kMixedRegularSplashable", "perks": [8140]},
              {"type": "kMixedRegularSplashable", "perks": [8135]},
              {"type": "kStatMod", "perks": [5008]},
              {"type": "kStatMod", "perks": [5008]},
              {"type": "kStatMod", "perks": [5001]}
            ]},
            {"id": 8200, "slots": [
              {"type": "kKeyStone", "perks": [8226]},
              {"type": "kMixedRegularSplashable", "perks": [8226, 8210]}
            ]}]
            """
        try await expectInvalid(runePage(), .unexpectedStyleLayout(sorcery), stylesJSON: styles)
    }

    @Test func aValidPageFromTheSampleIsSent() async throws {
        let precisionPage = runePage(
            [8010, 9111, 9104, 8014, 8139, 8135, 5005, 5008, 5001], primary: precision,
            sub: domination)
        let lcu = try connection()

        #expect(await apply(precisionPage, on: lcu) == .created)
    }
}

struct RuneImporterOutcomeTests {
    @Test func nothingIsReadOrSentWhenRuneImportIsOff() async throws {
        let lcu = try connection()
        let result = await apply(settings: ImportSettings(importRunes: false), on: lcu)

        #expect(result == .disabled)
        #expect(lcu.requests.isEmpty)
    }

    @Test func aFailedStylesFetchIsReportedAndNothingIsSent() async {
        let lcu = FakeLCUConnection()
        let result = await apply(on: lcu)

        #expect(result == .failed(.http(status: 404, body: Data())))
        #expect(lcu.writes.isEmpty)
    }

    @Test func aFailedPagesFetchIsReportedAndNothingIsSent() async throws {
        let lcu = FakeLCUConnection(responses: [
            .init(method: .get, path: stylesPath, body: try runesCase("styles")),
            .init(method: .get, path: pagesPath, status: 500),
        ])
        let result = await apply(on: lcu)

        #expect(result == .failed(.http(status: 500, body: Data())))
        #expect(lcu.writes.isEmpty)
    }

    @Test func aRejectedPostIsReportedAndNotRetried() async throws {
        let lcu = try connection(writeStatus: 500)
        let result = await apply(on: lcu)

        #expect(result == .failed(.http(status: 500, body: Data())))
        #expect(writeRoutes(lcu) == ["POST /lol-perks/v1/pages"])
    }

    @Test func aRejectedPutIsReportedAndNotRetried() async throws {
        let lcu = try connection(pages: "pages-with-mito-page", writeStatus: 400)
        let result = await apply(on: lcu)

        #expect(result == .failed(.http(status: 400, body: Data())))
        #expect(writeRoutes(lcu) == ["PUT /lol-perks/v1/pages/202"])
    }
}

struct RuneImporterMitoPageLookupTests {
    private let luxTitle = "Lux SUPPORT vs Nami"

    @Test func findsThePageNamedForTheTitleWithItsRunes() throws {
        let pages = try LCUEndpoint.perkPages.decode(runesCase("pages-with-mito-page"))
        let found = try #require(RuneImporter.mitoPage(in: pages, title: luxTitle))

        #expect(found.id == 202)
        #expect(
            found.runePage
                == runePage(
                    [8214, 8226, 8210, 8237, 8139, 8135, 5008, 5008, 5001], primary: sorcery,
                    sub: domination))
    }

    @Test(arguments: ["pages-with-mito-page", "pages-without-mito-page"])
    func aTitleWithNoPageOfItsOwnFindsNothing(_ fixture: String) throws {
        let pages = try LCUEndpoint.perkPages.decode(runesCase(fixture))

        #expect(RuneImporter.mitoPage(in: pages, title: title) == nil)
    }

    @Test(arguments: [
        "Mito · Lux SUPPORT vs Nami (copy)", "Mito ·Lux SUPPORT vs Nami",
        "Mito Lux SUPPORT vs Nami", "My Mito · Lux SUPPORT vs Nami",
    ])
    func aLookalikeNameIsNotMitosPage(_ name: String) {
        let pages = [PerkPage(id: 203, name: name, current: true, isEditable: true)]

        #expect(RuneImporter.mitoPage(in: pages, title: luxTitle) == nil)
    }

    @Test(arguments: [false, nil])
    func aPageWithMitosNameThatIsNotEditableIsNotMitos(_ editable: Bool?) {
        let pages = [PerkPage(id: 101, name: "Mito · \(luxTitle)", isEditable: editable)]

        #expect(RuneImporter.mitoPage(in: pages, title: luxTitle) == nil)
    }

    @Test func prefersTheCurrentPageWhenSeveralCarryTheName() {
        let pages = [203, 204].map {
            PerkPage(id: $0, name: "Mito · \(luxTitle)", current: $0 == 204, isEditable: true)
        }

        #expect(RuneImporter.mitoPage(in: pages, title: luxTitle)?.id == 204)
    }
}
