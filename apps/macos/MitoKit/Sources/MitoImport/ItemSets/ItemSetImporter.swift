public import LCUKit
public import MitoCore

public enum ItemSetImportResult: Equatable, Sendable {
    case applied
    /// `ImportSettings.importItemSets` is off.
    case disabled
    case failed(LCUError)
}

/// The map an item set is shown on: the client's `associatedMaps` ID and `map` code.
public struct ItemSetMap: Hashable, Sendable {
    public let id: Int
    public let code: String

    public init(id: Int, code: String) {
        self.id = id
        self.code = code
    }

    public static let summonersRift = Self(id: 11, code: "SR")
}

/// Writes Mito's item set for a champion and keeps every set of the user's (`MITO_CONTEXT.md` §13.4).
public struct ItemSetImporter: Sendable {
    static let titlePrefix = "Mito ·"
    static let uidPrefix = "mito-"

    private let connection: any LCUConnection

    public init(connection: any LCUConnection) {
        self.connection = connection
    }

    /// `title` is shown after `Mito · `; `summonerId` comes from `CurrentSummoner`.
    public func apply(
        _ itemSet: ItemSet, champion: ChampionID, map: ItemSetMap, title: String,
        summonerId: Int, settings: ImportSettings
    ) async -> ItemSetImportResult {
        guard settings.importItemSets else { return .disabled }
        // A failed read must stop here: a PUT built from a partial list deletes the user's sets.
        var list: LCUItemSets
        do {
            list = try await connection.send(.itemSets(summonerId: summonerId))
        } catch {
            return .failed(error)
        }
        list.itemSets.removeAll { set in
            Self.isMito(set) && (settings.cleanOldItemSets || Self.isFor(champion, set))
        }
        list.itemSets.append(
            Self.payload(itemSet, champion: champion, map: map, title: title))
        do {
            _ = try await connection.send(.replaceItemSets(list, summonerId: summonerId))
            return .applied
        } catch {
            return .failed(error)
        }
    }

    static func isMito(_ set: LCUItemSets.Object) -> Bool {
        guard case .string(let title)? = set["title"], case .string(let uid)? = set["uid"] else {
            return false
        }
        return title.hasPrefix(titlePrefix) && uid.hasPrefix(uidPrefix)
    }

    private static func isFor(_ champion: ChampionID, _ set: LCUItemSets.Object) -> Bool {
        guard case .array(let champions)? = set["associatedChampions"] else { return false }
        return champions.contains(.integer(Int64(champion.rawValue)))
    }

    private static func payload(
        _ itemSet: ItemSet, champion: ChampionID, map: ItemSetMap, title: String
    ) -> LCUItemSets.Object {
        let blocks = itemSet.blocks.map { block -> LCUItemSets.Value in
            .object([
                "type": .string(block.title),
                "items": .array(
                    block.items.map { item in
                        .object([
                            "id": .string(String(item.id.rawValue)),
                            "count": .integer(Int64(item.count)),
                        ])
                    }),
            ])
        }
        return [
            "uid": .string("\(uidPrefix)\(champion.rawValue)"),
            "title": .string("\(titlePrefix) \(title)"),
            "type": .string("custom"),
            "map": .string(map.code),
            "mode": .string("any"),
            "associatedChampions": .array([.integer(Int64(champion.rawValue))]),
            "associatedMaps": .array([.integer(Int64(map.id))]),
            "sortrank": .integer(0),
            "startedFrom": .string("blank"),
            "preferredItemSlots": .array([]),
            "blocks": .array(blocks),
        ]
    }
}
