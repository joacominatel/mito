/// Sets stay raw JSON objects so a `PUT` returns every member the client sent, modeled or not.
public struct LCUItemSets: Codable, Hashable, Sendable {
    public typealias Object = [String: Value]

    public enum Value: Codable, Hashable, Sendable {
        case null
        case bool(Bool)
        case integer(Int64)
        // `accountId` and `timestamp` are uint64.
        case unsigned(UInt64)
        case double(Double)
        case string(String)
        case array([Value])
        case object(Object)

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int64.self) {
                self = .integer(value)
            } else if let value = try? container.decode(UInt64.self) {
                self = .unsigned(value)
            } else if let value = try? container.decode(Double.self) {
                self = .double(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([Value].self) {
                self = .array(value)
            } else {
                self = .object(try container.decode(Object.self))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case .bool(let value): try container.encode(value)
            case .integer(let value): try container.encode(value)
            case .unsigned(let value): try container.encode(value)
            case .double(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            }
        }
    }

    public var itemSets: [Object]
    /// Every top-level member other than `itemSets` (`accountId`, `timestamp`, …), as received.
    public var otherMembers: Object

    public init(itemSets: [Object], otherMembers: Object = [:]) {
        self.itemSets = itemSets
        self.otherMembers = otherMembers
    }

    public init(from decoder: any Decoder) throws {
        var members = try Object(from: decoder)
        switch members.removeValue(forKey: Self.itemSetsKey) {
        case nil, .null?:
            itemSets = []
        case .array(let values)?:
            // A set that is not an object could not be sent back, so the whole list is refused.
            itemSets = try values.map { value in
                guard case .object(let set) = value else {
                    throw DecodingError.dataCorrupted(
                        .init(codingPath: [], debugDescription: "An item set is not an object"))
                }
                return set
            }
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "itemSets is not an array"))
        }
        otherMembers = members
    }

    public func encode(to encoder: any Encoder) throws {
        var members = otherMembers
        members[Self.itemSetsKey] = .array(itemSets.map(Value.object))
        try members.encode(to: encoder)
    }

    private static let itemSetsKey = "itemSets"
}

extension LCUEndpoint where Response == LCUItemSets {
    public static func itemSets(summonerId: Int) -> Self {
        Self(method: .get, path: itemSetsPath(summonerId))
    }
}

extension LCUEndpoint where Response == LCUNoContent {
    /// Replaces the whole list: any set left out of `sets` is deleted from the account.
    public static func replaceItemSets(_ sets: LCUItemSets, summonerId: Int) throws(LCUError)
        -> Self
    {
        try Self(method: .put, path: itemSetsPath(summonerId), json: sets)
    }
}

private func itemSetsPath(_ summonerId: Int) -> String {
    "/lol-item-sets/v1/item-sets/\(summonerId)/sets"
}
