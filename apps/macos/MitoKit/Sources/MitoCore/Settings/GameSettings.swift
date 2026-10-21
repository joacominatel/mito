/// `MITO_CONTEXT.md` §21.2.
public struct GameSettings: Codable, Hashable, Sendable {
    public enum AutoAccept: String, Codable, Hashable, Sendable {
        case off
        case always
        /// Only the queues in `autoAcceptQueues`.
        case selectedQueues
    }

    public var autoAccept: AutoAccept
    public var autoAcceptQueues: Set<QueueID>
    /// 0–8 seconds.
    public var autoAcceptDelaySeconds: Int
    public var notifyMatchFound: Bool

    public init(
        autoAccept: AutoAccept = .always,
        autoAcceptQueues: Set<QueueID> = [],
        autoAcceptDelaySeconds: Int = 2,
        notifyMatchFound: Bool = true
    ) {
        self.autoAccept = autoAccept
        self.autoAcceptQueues = autoAcceptQueues
        self.autoAcceptDelaySeconds = autoAcceptDelaySeconds
        self.notifyMatchFound = notifyMatchFound
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        autoAccept = container.decode(.autoAccept, default: defaults.autoAccept)
        autoAcceptQueues = container.decode(.autoAcceptQueues, default: defaults.autoAcceptQueues)
        autoAcceptDelaySeconds = container.decode(
            .autoAcceptDelaySeconds, default: defaults.autoAcceptDelaySeconds)
        notifyMatchFound = container.decode(.notifyMatchFound, default: defaults.notifyMatchFound)
    }
}
