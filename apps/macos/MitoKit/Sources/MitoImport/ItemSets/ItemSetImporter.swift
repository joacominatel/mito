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

    /// The blocks of `champion`'s Mito set (`mito-<championId>`, `MITO_CONTEXT.md` §13.4), as
    /// the client has them now; a block without a `type` or an item it cannot read is left out.
    public static func mitoItemSet(in list: LCUItemSets, champion: ChampionID) -> ItemSet? {
        guard
            let set = list.itemSets.first(where: {
                isMito($0) && $0["uid"] == .string(uid(for: champion))
            })
        else { return nil }
        guard case .array(let blocks)? = set["blocks"] else { return ItemSet(blocks: []) }
        return ItemSet(blocks: blocks.compactMap(block))
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

    private static func uid(for champion: ChampionID) -> String {
        "\(uidPrefix)\(champion.rawValue)"
    }

    private static func block(_ value: LCUItemSets.Value) -> ItemSet.Block? {
        guard case .object(let block) = value, case .string(let title)? = block["type"] else {
            return nil
        }
        guard case .array(let items)? = block["items"] else {
            return ItemSet.Block(title: title, items: [])
        }
        return ItemSet.Block(title: title, items: items.compactMap(item))
    }

    private static func item(_ value: LCUItemSets.Value) -> ItemSet.Block.Item? {
        guard case .object(let item) = value, case .string(let rawID)? = item["id"],
            let id = Int(rawID)
        else { return nil }
        switch item["count"] {
        case nil: return ItemSet.Block.Item(id: ItemID(rawValue: id))
        case .integer(let count)?:
            return ItemSet.Block.Item(id: ItemID(rawValue: id), count: Int(count))
        default: return nil
        }
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
            "uid": .string(uid(for: champion)),
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
