/// `MITO_CONTEXT.md` §11.3; values not yet verified against a recording.
public struct ReadyCheck: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case inProgress
        case everyoneReady
        case strangerNotReady
        case partyNotReady
        case invalid
        case error
        case unknown(String)

        public init(_ rawValue: String) {
            switch rawValue {
            case "InProgress": self = .inProgress
            case "EveryoneReady": self = .everyoneReady
            case "StrangerNotReady": self = .strangerNotReady
            case "PartyNotReady": self = .partyNotReady
            case "Invalid": self = .invalid
            case "Error": self = .error
            default: self = .unknown(rawValue)
            }
        }
    }

    public enum PlayerResponse: Hashable, Sendable {
        case none
        case accepted
        case declined
        case unknown(String)

        public init(_ rawValue: String) {
            switch rawValue {
            case "None": self = .none
            case "Accepted": self = .accepted
            case "Declined": self = .declined
            default: self = .unknown(rawValue)
            }
        }
    }

    public let state: State
    public let playerResponse: PlayerResponse

    public init(state: State, playerResponse: PlayerResponse) {
        self.state = state
        self.playerResponse = playerResponse
    }

    /// `nil` when the event says the ready check is gone: a `Delete`, or null or empty data.
    public init?(_ event: LCUEvent) throws(LCUError) {
        guard event.eventType != .delete, !Self.isAbsent(event.data) else { return nil }
        self = try LCUEndpoint<ReadyCheck>.readyCheck.decode(event.data)
    }

    private static func isAbsent(_ data: some Collection<UInt8>) -> Bool {
        let trimmed = data.filter { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }
        return trimmed.isEmpty || trimmed.elementsEqual("null".utf8)
    }
}

extension ReadyCheck: Decodable {
    private enum CodingKeys: String, CodingKey {
        case state
        case playerResponse
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = State(try container.decode(String.self, forKey: .state))
        playerResponse = PlayerResponse(try container.decode(String.self, forKey: .playerResponse))
    }
}
