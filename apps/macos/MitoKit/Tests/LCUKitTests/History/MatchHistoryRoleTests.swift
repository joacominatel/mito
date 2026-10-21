import Foundation
import LCUKit
import MitoCore
import Testing

private func localRole(lane: String, role: String, mapID: String = "11") throws -> Role? {
    let json = """
        {"gameId": 1, "queueId": 420, "mapId": \(mapID), "gameVersion": "16.21.1.1",
         "gameCreation": 0, "gameDuration": 1,
         "participants": [{"participantId": 1, "teamId": 100, "championId": 103,
           "spell1Id": 4, "spell2Id": 14, "timeline": {"lane": "\(lane)", "role": "\(role)"},
           "stats": {"win": true, "kills": 0, "deaths": 0, "assists": 0,
             "totalMinionsKilled": 0, "neutralMinionsKilled": 0}}],
         "participantIdentities": [{"participantId": 1, "player": {}}]}
        """
    return try LCUEndpoint.matchHistoryGame(GameID(rawValue: 1), localPUUID: nil)
        .decode(Data(json.utf8)).match.role
}

struct MatchHistoryRoleTests {
    @Test(arguments: [
        ("TOP", "SOLO", Role.top), ("JUNGLE", "NONE", .jungle), ("MIDDLE", "SOLO", .middle),
        ("MID", "SOLO", .middle), ("BOTTOM", "DUO_CARRY", .bottom), ("BOT", "CARRY", .bottom),
        ("BOTTOM", "DUO_SUPPORT", .utility), ("BOT", "SUPPORT", .utility),
    ])
    func mapsTheLaneAndRoleOnSummonersRift(lane: String, role: String, expected: Role) throws {
        #expect(try localRole(lane: lane, role: role) == expected)
    }

    @Test(arguments: [("NONE", "NONE"), ("BOTTOM", "DUO"), ("BOTTOM", "SOLO"), ("RIVER", "SOLO")])
    func anUnassignedOrUnknownLaneIsNoRole(lane: String, role: String) throws {
        #expect(try localRole(lane: lane, role: role) == nil)
    }

    @Test func aMissingMapStillReadsLanes() throws {
        #expect(try localRole(lane: "TOP", role: "SOLO", mapID: "null") == .top)
    }

    @Test(arguments: ["12", "30"])
    func lanesOffSummonersRiftAreNoRole(mapID: String) throws {
        #expect(try localRole(lane: "TOP", role: "SOLO", mapID: mapID) == nil)
    }
}
