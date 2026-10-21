public import MitoCore

/// The queue and map of `GET /lol-gameflow/v1/session` (`MITO_CONTEXT.md` §11.1).
///
/// Rosters and player identity are never decoded (§5). Field paths follow the community LCU
/// schema and are not yet verified against a recording.
public struct GameflowSession: Hashable, Sendable {
    /// `gameData.queue.id`.
    public let queueID: QueueID?
    /// `gameData.queue.mapId`, e.g. `11` for Summoner's Rift.
    public let mapID: Int?

    public init(queueID: QueueID? = nil, mapID: Int? = nil) {
        self.queueID = queueID
        self.mapID = mapID
    }

    public var queueType: QueueType? { queueID.map(QueueType.init(queueID:)) }
}

extension GameflowSession: Decodable {
    private enum CodingKeys: String, CodingKey {
        case gameData
    }

    private struct GameData: Decodable {
        let queue: Queue?
    }

    private struct Queue: Decodable {
        let id: Int?
        let mapId: Int?
    }

    public init(from decoder: any Decoder) throws {
        let queue = try decoder.container(keyedBy: CodingKeys.self)
            .decodeIfPresent(GameData.self, forKey: .gameData)?.queue
        self.init(queueID: queue?.id.map(QueueID.init(rawValue:)), mapID: queue?.mapId)
    }
}
