import Foundation
import MitoCore
import Testing

struct IDTests {
    @Test func championIDEncodesAsABareNumber() throws {
        let json = try JSONEncoder().encode(ChampionID(rawValue: 103))
        #expect(String(decoding: json, as: UTF8.self) == "103")
    }

    @Test func idsRoundTripThroughJSON() throws {
        #expect(try roundTrip(ChampionID(rawValue: 103)) == ChampionID(rawValue: 103))
        #expect(try roundTrip(ItemID(rawValue: 3157)) == ItemID(rawValue: 3157))
        #expect(try roundTrip(PerkID(rawValue: 8112)) == PerkID(rawValue: 8112))
        #expect(try roundTrip(PerkStyleID(rawValue: 8100)) == PerkStyleID(rawValue: 8100))
        #expect(try roundTrip(SummonerSpellID(rawValue: 4)) == SummonerSpellID(rawValue: 4))
        #expect(try roundTrip(QueueID(rawValue: 420)) == QueueID(rawValue: 420))
    }

    @Test func patchRoundTripsAsAString() throws {
        let json = try JSONEncoder().encode(Patch(rawValue: "16.21"))
        #expect(String(decoding: json, as: UTF8.self) == #""16.21""#)
        #expect(try roundTrip(Patch(rawValue: "16.21")) == Patch(rawValue: "16.21"))
    }

    @Test func bracketUsesTheSnapshotFileKey() throws {
        let json = try JSONEncoder().encode([Bracket.emeraldPlus, .diamondPlus])
        #expect(String(decoding: json, as: UTF8.self) == #"["emerald_plus","diamond_plus"]"#)
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }
}
