import Foundation
import LCUKit
import MitoTestSupport
import Testing

private let path = "/lol-item-sets/v1/item-sets/42/sets"

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: Fixtures.url("lcu/cases/item-sets/\(name).json"))
}

private func jsonObject(_ data: Data) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

struct ItemSetsEndpointTests {
    @Test func readsTheSummonersSets() {
        let endpoint = LCUEndpoint.itemSets(summonerId: 42)

        #expect(endpoint.method == .get)
        #expect(endpoint.path == path)
        #expect(endpoint.body == nil)
    }

    @Test func replacesTheSummonersSetsWithTheWholeList() throws {
        let sets = LCUItemSets(
            itemSets: [["uid": .string("a")]], otherMembers: ["accountId": .integer(1)])
        let endpoint = try LCUEndpoint.replaceItemSets(sets, summonerId: 42)

        #expect(endpoint.method == .put)
        #expect(endpoint.path == path)
        let body = try jsonObject(try #require(endpoint.body))
        #expect(body == ["accountId": 1, "itemSets": [["uid": "a"]]] as NSDictionary)
    }

    @Test(arguments: ["user-sets-with-unknown-fields", "old-mito-sets", "empty"])
    func aDecodedListEncodesBackToTheSameJSON(_ name: String) throws {
        let recorded = try fixture(name)
        let decoded = try LCUEndpoint.itemSets(summonerId: 42).decode(recorded)
        let body = try #require(try LCUEndpoint.replaceItemSets(decoded, summonerId: 42).body)

        #expect(try jsonObject(body) == jsonObject(recorded))
    }

    @Test func integersBeyondDoublePrecisionSurvive() throws {
        let decoded = try LCUEndpoint.itemSets(summonerId: 42)
            .decode(try fixture("user-sets-with-unknown-fields"))
        let body = try #require(try LCUEndpoint.replaceItemSets(decoded, summonerId: 42).body)

        #expect(decoded.itemSets.first?["largeIntegerField"] == .integer(9_007_199_254_740_993))
        #expect(String(decoding: body, as: UTF8.self).contains("9007199254740993"))
    }

    @Test func aMissingListDecodesAsEmpty() throws {
        let decoded = try LCUEndpoint.itemSets(summonerId: 42)
            .decode(Data(#"{"accountId": 1}"#.utf8))

        #expect(decoded.itemSets.isEmpty)
        #expect(decoded.otherMembers == ["accountId": .integer(1)])
    }

    @Test(arguments: [#"{"itemSets": [{"uid": "a"}, 3]}"#, #"{"itemSets": {"uid": "a"}}"#])
    func aListThatCannotBeSentBackIsRefused(_ json: String) {
        #expect(throws: LCUError.self) {
            try LCUEndpoint.itemSets(summonerId: 42).decode(Data(json.utf8))
        }
    }
}
