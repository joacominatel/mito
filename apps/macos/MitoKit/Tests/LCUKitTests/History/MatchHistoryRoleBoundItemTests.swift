import Foundation
import LCUKit
import MitoCore
import MitoTestSupport
import Testing

private func game(_ page: String, _ id: Int) throws -> MyMatch? {
    let data = try Data(contentsOf: Fixtures.url("lcu/cases/history/\(page).json"))
    return try LCUEndpoint.matchHistory(localPUUID: "fake-puuid-local").decode(data).matches
        .first { $0.game == GameID(rawValue: id) }
}

/// Items 3031 and 3363 in slots 0 and 6, plus `roleBoundItem` as raw JSON (absent when `nil`).
private func items(roleBoundItem: String?) throws -> [Int] {
    let roleSlot = roleBoundItem.map { #", "roleBoundItem": \#($0)"# } ?? ""
    let json = """
        {"gameId": 1, "queueId": 420, "mapId": 11, "gameVersion": "16.21.1.1",
         "gameCreation": 0, "gameDuration": 1,
         "participants": [{"participantId": 1, "teamId": 100, "championId": 222,
           "spell1Id": 4, "spell2Id": 7, "timeline": {"lane": "BOTTOM", "role": "DUO_CARRY"},
           "stats": {"win": true, "kills": 0, "deaths": 0, "assists": 0,
             "totalMinionsKilled": 0, "neutralMinionsKilled": 0,
             "item0": 3031, "item1": 0, "item6": 3363\(roleSlot)}}],
         "participantIdentities": [{"participantId": 1, "player": {}}]}
        """
    return try LCUEndpoint.matchHistoryGame(GameID(rawValue: 1), localPUUID: nil)
        .decode(Data(json.utf8)).match.items.map(\.rawValue)
}

struct MatchHistoryRoleBoundItemTests {
    @Test func bootsOnlyInTheRoleSlotOfABottomGameAreInTheItems() throws {
        let match = try #require(try game("role-bound-page", 7_000_000_020))
        #expect(match.role == .bottom)
        #expect(match.items.contains(ItemID(rawValue: 3009)))
    }

    @Test func theRoleSlotComesAfterItemZeroToSixInSlotOrder() throws {
        let match = try #require(try game("role-bound-page", 7_000_000_020))
        #expect(
            match.items == [1120, 6699, 3095, 3036, 3363, 3009].map(ItemID.init(rawValue:)))
    }

    @Test func aQuestRewardInTheRoleSlotIsDroppedAndTheBootsInANormalSlotStay() throws {
        let match = try #require(try game("ranked-page", 7_000_000_001))
        #expect(match.role == .middle)
        #expect(
            match.items == [6655, 3020, 4645, 3157, 3089, 3363].map(ItemID.init(rawValue:)))
    }

    @Test(arguments: Array(1200...1209) + Array(1220...1222))
    func everyKnownRoleQuestIDIsDropped(_ quest: Int) throws {
        #expect(try items(roleBoundItem: "\(quest)") == [3031, 3363])
    }

    @Test func aControlWardInTheRoleSlotOfASupportGameIsKept() throws {
        let match = try #require(try game("role-bound-page", 7_000_000_021))
        #expect(match.role == .utility)
        #expect(match.items == [3876, 3158, 3364, 2055].map(ItemID.init(rawValue:)))
    }

    @Test(arguments: [2055, 2422, 1001])
    func aPurchasableItemInTheRoleSlotIsKept(_ item: Int) throws {
        #expect(try items(roleBoundItem: "\(item)") == [3031, 3363, item])
    }

    @Test func aGameWithoutTheRoleSlotKeepsItsItems() throws {
        let match = try #require(try game("ranked-page", 7_000_000_003))
        #expect(match.items == [6655, 3020, 3363].map(ItemID.init(rawValue:)))
    }

    @Test(arguments: [nil, "null", #""boots""#])
    func aMissingOrUnreadableRoleSlotAddsNothing(_ roleBoundItem: String?) throws {
        #expect(try items(roleBoundItem: roleBoundItem) == [3031, 3363])
    }

    @Test func anEmptyRoleSlotIsDropped() throws {
        #expect(try items(roleBoundItem: "0") == [3031, 3363])
    }
}
