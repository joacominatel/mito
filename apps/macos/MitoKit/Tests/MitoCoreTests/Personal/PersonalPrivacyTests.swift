import Foundation
import MitoCore
import Testing

/// §5 and §25: personal records carry champions and roles, never who played them.
struct PersonalPrivacyTests {
    private static let identityMarkers = [
        "puuid", "summoner", "account", "name", "riotid", "tag", "player",
    ]

    private static func identityFields(of value: Any) -> [String] {
        Mirror(reflecting: value).children.compactMap(\.label).filter { label in
            identityMarkers.contains { label.lowercased().contains($0) }
        }
    }

    @Test func aParticipantHoldsOnlyChampionSideAndRole() {
        let participant = MyMatchParticipant(
            champion: ChampionID(rawValue: 238), isEnemy: true, role: .middle)
        #expect(
            Mirror(reflecting: participant).children.compactMap(\.label)
                == ["champion", "isEnemy", "role"])
    }

    @Test func personalRecordsHoldNoPlayerIdentity() {
        let match = MyMatch(
            game: GameID(rawValue: 1), queue: QueueID(rawValue: 420),
            patch: Patch(rawValue: "16.21"), playedAt: Date(timeIntervalSince1970: 0),
            champion: ChampionID(rawValue: 103), role: .middle, win: true, kills: 0, deaths: 0,
            assists: 0, cs: 0, durationSeconds: 0, opponent: nil,
            spells: SpellPair(
                first: SummonerSpellID(rawValue: 4), second: SummonerSpellID(rawValue: 14)),
            perks: [], items: [], participants: [])
        let entry = ImportLogEntry(
            timestamp: Date(timeIntervalSince1970: 0), game: nil,
            champion: ChampionID(rawValue: 103), part: .runes, outcome: .applied)
        let override = ChampionOverride(champion: ChampionID(rawValue: 103), role: .middle)
        let pool = PoolEntry(role: .middle, champion: ChampionID(rawValue: 103), priority: 0)

        for record in [match, entry, override, pool] as [Any] {
            #expect(Self.identityFields(of: record) == [], "\(type(of: record))")
        }
    }
}
