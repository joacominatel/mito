import Foundation
import LCUKit
import MitoCore
import Testing

struct MySelectionEndpointTests {
    @Test func patchesMySelectionWithBothSpellsInSlotOrder() throws {
        let endpoint = try LCUEndpoint.updateMySelection(
            spells: SpellPair(
                first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)))

        #expect(endpoint.method == .patch)
        #expect(endpoint.path == "/lol-champ-select/v1/session/my-selection")
        let body = try #require(endpoint.body)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Int]
        #expect(json == ["spell1Id": 4, "spell2Id": 14])
    }
}
