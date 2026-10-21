public import MitoCore

// Only `id` is required: an entry without one is skipped, other fields fall back to empty.

extension LCUEndpoint where Response == GameDataChampions {
    public static var gameDataChampions: Self {
        Self(method: .get, path: "/lol-game-data/assets/v1/champion-summary.json")
    }
}

extension LCUEndpoint where Response == GameDataItems {
    public static var gameDataItems: Self {
        Self(method: .get, path: "/lol-game-data/assets/v1/items.json")
    }
}

extension LCUEndpoint where Response == GameDataPerkStyles {
    public static var gameDataPerkStyles: Self {
        Self(method: .get, path: "/lol-game-data/assets/v1/perkstyles.json")
    }
}

extension LCUEndpoint where Response == GameDataPerks {
    public static var gameDataPerks: Self {
        Self(method: .get, path: "/lol-game-data/assets/v1/perks.json")
    }
}

extension LCUEndpoint where Response == GameDataSummonerSpells {
    public static var gameDataSummonerSpells: Self {
        Self(method: .get, path: "/lol-game-data/assets/v1/summoner-spells.json")
    }
}

/// `champion-summary.json`, which includes the client's `-1` "None" placeholder.
public struct GameDataChampions: Decodable, Hashable, Sendable {
    public let champions: [Champion]

    public init(from decoder: any Decoder) throws {
        champions = try LossyArray<Entry>(from: decoder).elements.map(\.value)
    }

    private struct Entry: Decodable {
        let value: Champion

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: GameDataKey.self)
            value = Champion(
                id: ChampionID(rawValue: try container.decode(Int.self, forKey: .id)),
                alias: container.lenient(String.self, .alias) ?? "",
                name: container.lenient(String.self, .name) ?? "",
                iconPath: container.lenient(String.self, .squarePortraitPath) ?? "")
        }
    }
}

/// `items.json`; `itemClass` is always `nil`, since it comes from the snapshot.
public struct GameDataItems: Decodable, Hashable, Sendable {
    public let items: [Item]

    public init(from decoder: any Decoder) throws {
        items = try LossyArray<Entry>(from: decoder).elements.map(\.value)
    }

    private struct Entry: Decodable {
        let value: Item

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: GameDataKey.self)
            value = Item(
                id: ItemID(rawValue: try container.decode(Int.self, forKey: .id)),
                name: container.lenient(String.self, .name) ?? "",
                totalGold: container.lenient(Int.self, .priceTotal) ?? 0,
                iconPath: container.lenient(String.self, .iconPath) ?? "",
                itemClass: nil)
        }
    }
}

/// `perkstyles.json`, an object whose `styles` array is required.
public struct GameDataPerkStyles: Decodable, Hashable, Sendable {
    public let styles: [PerkStyle]

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: GameDataKey.self)
        styles = try container.decode(LossyArray<Entry>.self, forKey: .styles).elements.map(
            \.value)
    }

    private struct Entry: Decodable {
        let value: PerkStyle

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: GameDataKey.self)
            value = PerkStyle(
                id: PerkStyleID(rawValue: try container.decode(Int.self, forKey: .id)),
                name: container.lenient(String.self, .name) ?? "",
                iconPath: container.lenient(String.self, .iconPath) ?? "",
                slots: container.decodeLossyArray(SlotEntry.self, forKey: .slots).map(\.value))
        }
    }

    /// A row without a `type` is skipped: guessing its kind could misplace a keystone.
    private struct SlotEntry: Decodable {
        let value: PerkStyle.Slot

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: GameDataKey.self)
            value = PerkStyle.Slot(
                kind: PerkStyle.Slot.Kind(
                    lcuType: try container.decode(String.self, forKey: .type)),
                perks: container.decodeLossyArray(Int.self, forKey: .perks).map {
                    PerkID(rawValue: $0)
                })
        }
    }
}

/// `perks.json`, every rune and stat shard.
public struct GameDataPerks: Decodable, Hashable, Sendable {
    public let perks: [Perk]

    public init(from decoder: any Decoder) throws {
        perks = try LossyArray<Entry>(from: decoder).elements.map(\.value)
    }

    private struct Entry: Decodable {
        let value: Perk

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: GameDataKey.self)
            value = Perk(
                id: PerkID(rawValue: try container.decode(Int.self, forKey: .id)),
                name: container.lenient(String.self, .name) ?? "",
                iconPath: container.lenient(String.self, .iconPath) ?? "")
        }
    }
}

/// `summoner-spells.json`, including spells of every game mode.
public struct GameDataSummonerSpells: Decodable, Hashable, Sendable {
    public let spells: [SummonerSpell]

    public init(from decoder: any Decoder) throws {
        spells = try LossyArray<Entry>(from: decoder).elements.map(\.value)
    }

    private struct Entry: Decodable {
        let value: SummonerSpell

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: GameDataKey.self)
            value = SummonerSpell(
                id: SummonerSpellID(rawValue: try container.decode(Int.self, forKey: .id)),
                name: container.lenient(String.self, .name) ?? "",
                iconPath: container.lenient(String.self, .iconPath) ?? "",
                gameModes: Set(container.decodeLossyArray(String.self, forKey: .gameModes)))
        }
    }
}

extension PerkStyle.Slot.Kind {
    init(lcuType: String) {
        switch lcuType {
        case "kKeyStone": self = .keystone
        case "kMixedRegularSplashable": self = .regular
        case "kStatMod": self = .statMod
        default: self = .unknown(lcuType)
        }
    }
}

private enum GameDataKey: String, CodingKey {
    case id, alias, name, squarePortraitPath, priceTotal, iconPath, styles, slots, type, perks
    case gameModes
}

extension KeyedDecodingContainer {
    /// Missing, `null`, or the wrong type decodes as `nil`.
    fileprivate func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }
}
