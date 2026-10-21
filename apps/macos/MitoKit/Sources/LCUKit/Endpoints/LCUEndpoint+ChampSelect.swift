import Foundation
public import MitoCore

extension LCUEndpoint where Response == ChampSelectSession {
    /// 404 outside champ select.
    public static var champSelectSession: Self {
        Self(method: .get, path: "/lol-champ-select/v1/session")
    }
}

extension LCUEndpoint where Response == LCUNoContent {
    /// Sets the local player's summoner spells, in slot order.
    public static func updateMySelection(spells: SpellPair) throws(LCUError) -> Self {
        try Self(
            method: .patch, path: "/lol-champ-select/v1/session/my-selection",
            json: MySelectionBody(
                spell1Id: spells.first.rawValue, spell2Id: spells.second.rawValue))
    }
}

private struct MySelectionBody: Encodable {
    let spell1Id: Int
    let spell2Id: Int
}

extension LCUEndpoint where Response == Set<ChampionID> {
    /// Drops `0` and every element that is not an integer.
    public static var pickableChampionIDs: Self {
        Self(method: .get, path: "/lol-champ-select/v1/pickable-champion-ids", decode: championIDs)
    }

    /// Drops `0` and every element that is not an integer.
    public static var bannableChampionIDs: Self {
        Self(method: .get, path: "/lol-champ-select/v1/bannable-champion-ids", decode: championIDs)
    }
}

@Sendable private func championIDs(_ data: Data) throws -> Set<ChampionID> {
    let ids = try JSONDecoder().decode(LossyArray<Int>.self, from: data).elements
    return Set(ids.filter { $0 != 0 }.map(ChampionID.init(rawValue:)))
}
