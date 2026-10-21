public import MitoCore

extension ChampSelectSession {
    /// One ban, pick, or reveal step of the draft.
    public struct Action: Hashable, Sendable {
        /// The ID that `PATCH /lol-champ-select/v1/session/actions/{id}` takes.
        public let id: Int?
        public let actorCellId: Int?
        /// The hovered or locked champion; `nil` while the action has none.
        public let championId: ChampionID?
        public let type: Kind?
        public let isInProgress: Bool?
        public let completed: Bool?
        public let isAllyAction: Bool?

        public init(
            id: Int? = nil,
            actorCellId: Int? = nil,
            championId: ChampionID? = nil,
            type: Kind? = nil,
            isInProgress: Bool? = nil,
            completed: Bool? = nil,
            isAllyAction: Bool? = nil
        ) {
            self.id = id
            self.actorCellId = actorCellId
            self.championId = championId
            self.type = type
            self.isInProgress = isInProgress
            self.completed = completed
            self.isAllyAction = isAllyAction
        }

        public enum Kind: Hashable, Sendable {
            case ban
            case pick
            case tenBansReveal
            case unknown(String)

            public init(_ rawValue: String) {
                switch rawValue {
                case "ban": self = .ban
                case "pick": self = .pick
                case "ten_bans_reveal": self = .tenBansReveal
                default: self = .unknown(rawValue)
                }
            }
        }
    }
}

extension ChampSelectSession.Action: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, actorCellId, championId, type, isInProgress, completed, isAllyAction
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decodeIfPresent(Int.self, forKey: .id),
            actorCellId: try container.decodeIfPresent(Int.self, forKey: .actorCellId),
            championId: try container.decodeID(ChampionID.self, forKey: .championId),
            type: try container.decodeIfPresent(String.self, forKey: .type).map(Kind.init),
            isInProgress: try container.decodeIfPresent(Bool.self, forKey: .isInProgress),
            completed: try container.decodeIfPresent(Bool.self, forKey: .completed),
            isAllyAction: try container.decodeIfPresent(Bool.self, forKey: .isAllyAction)
        )
    }
}
