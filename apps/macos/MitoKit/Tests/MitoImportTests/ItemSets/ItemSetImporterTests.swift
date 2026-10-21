import Foundation
import LCUKit
import MitoCore
import MitoImport
import MitoTestSupport
import Testing

private let summonerId = 42
private let setsPath = "/lol-item-sets/v1/item-sets/42/sets"
private let ahri = ChampionID(rawValue: 103)

private let recommended = ItemSet(blocks: [
    .init(
        title: "Inicio (54,8 % WR)",
        items: [.init(id: ItemID(rawValue: 1056)), .init(id: ItemID(rawValue: 2003), count: 2)]),
    .init(title: "Habilidades: Q > W > E", items: []),
])

private var expectedNewSet: NSDictionary {
    [
        "uid": "mito-103",
        "title": "Mito · Ahri MID vs Zed",
        "type": "custom",
        "map": "SR",
        "mode": "any",
        "associatedChampions": [103],
        "associatedMaps": [11],
        "sortrank": 0,
        "startedFrom": "blank",
        "preferredItemSlots": [],
        "blocks": [
            [
                "type": "Inicio (54,8 % WR)",
                "items": [["id": "1056", "count": 1], ["id": "2003", "count": 2]],
            ],
            ["type": "Habilidades: Q > W > E", "items": []],
        ],
    ]
}

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/item-sets/\(name).json"))
}

private func jsonObject(_ data: Data) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

private func connection(
    get body: Data, getStatus: Int = 200, putStatus: Int = 204
) -> FakeLCUConnection {
    FakeLCUConnection(responses: [
        .init(method: .get, path: setsPath, status: getStatus, body: body),
        .init(method: .put, path: setsPath, status: putStatus),
    ])
}

private func apply(
    on connection: FakeLCUConnection, settings: ImportSettings = ImportSettings()
) async -> ItemSetImportResult {
    await ItemSetImporter(connection: connection).apply(
        recommended, champion: ahri, map: .summonersRift, title: "Ahri MID vs Zed",
        summonerId: summonerId, settings: settings)
}

/// The body of the single `PUT` sent.
private func sentList(_ connection: FakeLCUConnection) throws -> NSDictionary {
    try #require(connection.writes.count == 1)
    let put = connection.writes[0]
    #expect(put.method == .put)
    #expect(put.path == setsPath)
    return try jsonObject(try #require(put.body))
}

private func sentSets(_ connection: FakeLCUConnection) throws -> [NSDictionary] {
    try #require(try sentList(connection)["itemSets"] as? [NSDictionary])
}

struct ItemSetImporterTests {
    @Test func theUsersSetsAndTopLevelMembersAreSentBackExactly() async throws {
        let recorded = try fixture("user-sets-with-unknown-fields")
        let lcu = connection(get: recorded)
        let result = await apply(on: lcu)

        #expect(result == .applied)
        let original = try jsonObject(recorded)
        let sent = try sentList(lcu).mutableCopy() as? NSMutableDictionary
        let sentSets = try #require(sent?["itemSets"] as? [NSDictionary])
        #expect(Array(sentSets.dropLast()) == original["itemSets"] as? [NSDictionary])
        sent?["itemSets"] = original["itemSets"]
        #expect(sent == original)
    }

    @Test func theNewSetIsAppendedWithTheMitoPayload() async throws {
        let lcu = connection(get: try fixture("user-sets-with-unknown-fields"))
        _ = await apply(on: lcu)

        #expect(try sentSets(lcu).last == expectedNewSet)
    }

    @Test func anEmptyListGetsOnlyTheNewSet() async throws {
        let lcu = connection(get: try fixture("empty"))
        let result = await apply(on: lcu)

        #expect(result == .applied)
        #expect(try sentSets(lcu) == [expectedNewSet])
    }

    @Test func cleaningOldSetsRemovesEveryMitoSetAndKeepsLookalikes() async throws {
        let lcu = connection(get: try fixture("old-mito-sets"))
        _ = await apply(on: lcu, settings: ImportSettings(cleanOldItemSets: true))

        // "My Mito notes" only contains the word, "Mito · copied by hand" has a non-Mito uid
        // and "mito-notes" has a non-Mito title: all three are the user's.
        #expect(
            try sentSets(lcu).map { $0["uid"] as? String } == [
                "0f9c2a4e-0000-4000-8000-000000000003",
                "0f9c2a4e-0000-4000-8000-000000000004",
                "0f9c2a4e-0000-4000-8000-000000000005",
                "mito-notes",
                "mito-103",
            ])
    }

    @Test func withoutCleaningOnlyThisChampionsMitoSetIsReplaced() async throws {
        let lcu = connection(get: try fixture("old-mito-sets"))
        _ = await apply(on: lcu, settings: ImportSettings(cleanOldItemSets: false))

        #expect(
            try sentSets(lcu).map { $0["uid"] as? String } == [
                "0f9c2a4e-0000-4000-8000-000000000003",
                "0f9c2a4e-0000-4000-8000-000000000004",
                "mito-238",
                "0f9c2a4e-0000-4000-8000-000000000005",
                "mito-notes",
                "mito-103",
            ])
    }

    @Test(arguments: [true, false])
    func setsThatAreNotMitosSurviveUnchanged(_ clean: Bool) async throws {
        let recorded = try fixture("old-mito-sets")
        let lcu = connection(get: recorded)
        _ = await apply(on: lcu, settings: ImportSettings(cleanOldItemSets: clean))

        let mitoUIDs: Set = ["mito-103-middle", "mito-238"]
        let userSets = try #require(try jsonObject(recorded)["itemSets"] as? [NSDictionary])
            .filter { !mitoUIDs.contains($0["uid"] as? String ?? "") }
        #expect(try sentSets(lcu).filter(userSets.contains) == userSets)
    }

    @Test func nothingIsSentWhenItemSetImportIsOff() async throws {
        let lcu = connection(get: try fixture("old-mito-sets"))
        let result = await apply(on: lcu, settings: ImportSettings(importItemSets: false))

        #expect(result == .disabled)
        #expect(lcu.requests.isEmpty)
    }

    @Test func aFailedReadIsReportedAndNothingIsWritten() async throws {
        let lcu = connection(get: Data(), getStatus: 500)
        let result = await apply(on: lcu)

        #expect(result == .failed(.http(status: 500, body: Data())))
        #expect(lcu.writes.isEmpty)
    }

    @Test func anUnreadableListIsReportedAndNothingIsWritten() async throws {
        let lcu = connection(get: Data(#"{"itemSets": [{"uid": "a"}, 3]}"#.utf8))
        let result = await apply(on: lcu)

        guard case .failed(.decoding) = result else {
            Issue.record("Expected a decoding failure, got \(result)")
            return
        }
        #expect(lcu.writes.isEmpty)
    }

    @Test func aRejectedPutIsReportedAsFailed() async throws {
        let lcu = connection(get: try fixture("empty"), putStatus: 400)
        let result = await apply(on: lcu)

        #expect(result == .failed(.http(status: 400, body: Data())))
        #expect(lcu.writes.count == 1)
    }
}

struct ItemSetImporterMitoSetLookupTests {
    private func list(_ json: String) throws -> LCUItemSets {
        try LCUEndpoint.itemSets(summonerId: summonerId).decode(Data(json.utf8))
    }

    @Test func readsBackTheBlocksOfTheSetTheImporterSent() async throws {
        let lcu = connection(get: try fixture("old-mito-sets"))
        _ = await apply(on: lcu)
        let sent = try LCUEndpoint.itemSets(summonerId: summonerId)
            .decode(try #require(lcu.writes.first?.body))

        #expect(ItemSetImporter.mitoItemSet(in: sent, champion: ahri) == recommended)
    }

    @Test func readsTheSetOfTheRequestedChampionOnly() throws {
        let sets = try LCUEndpoint.itemSets(summonerId: summonerId)
            .decode(try fixture("old-mito-sets"))

        #expect(
            ItemSetImporter.mitoItemSet(in: sets, champion: ChampionID(rawValue: 238))
                == ItemSet(blocks: []))
        #expect(ItemSetImporter.mitoItemSet(in: sets, champion: ChampionID(rawValue: 1)) == nil)
    }

    @Test(arguments: ["old-mito-sets", "user-sets-with-unknown-fields", "empty"])
    func onlyLookalikesOrNoSetsReadAsNoMitoSet(_ name: String) throws {
        // In old-mito-sets, Ahri's sets are the user's or an older uid ("mito-103-middle").
        let sets = try LCUEndpoint.itemSets(summonerId: summonerId).decode(try fixture(name))

        #expect(ItemSetImporter.mitoItemSet(in: sets, champion: ahri) == nil)
    }

    @Test func aMitoUIDUnderTheUsersTitleIsNotMitos() throws {
        let sets = try list(#"{"itemSets": [{"uid": "mito-103", "title": "Ahri", "blocks": []}]}"#)

        #expect(ItemSetImporter.mitoItemSet(in: sets, champion: ahri) == nil)
    }

    @Test func blocksAndItemsTheClientChangedBeyondReadingAreLeftOut() throws {
        let sets = try list(
            #"""
            {"itemSets": [{"uid": "mito-103", "title": "Mito · Ahri MID", "blocks": [
              {"type": "Inicio", "items": [{"id": "1056"}, {"id": 2003, "count": 2},
                {"id": "3020", "count": "2"}, {"id": "abc", "count": 1}]},
              {"items": [{"id": "1001", "count": 1}]},
              {"type": "Vacío"}
            ]}]}
            """#)

        #expect(
            ItemSetImporter.mitoItemSet(in: sets, champion: ahri)
                == ItemSet(blocks: [
                    .init(title: "Inicio", items: [.init(id: ItemID(rawValue: 1056))]),
                    .init(title: "Vacío", items: []),
                ]))
    }
}
