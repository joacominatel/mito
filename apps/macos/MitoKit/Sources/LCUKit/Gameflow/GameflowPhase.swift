/// The client's `gameflow-phase` (`MITO_CONTEXT.md` §11.1).
public enum GameflowPhase: Hashable, Sendable {
    case none
    case lobby
    case matchmaking
    case readyCheck
    case champSelect
    case gameStart
    case inProgress
    case waitingForStats
    case preEndOfGame
    case endOfGame
    case reconnect
    case checkedIntoTournament
    case unknown(String)

    public init(_ rawValue: String) {
        switch rawValue {
        case "None": self = .none
        case "Lobby": self = .lobby
        case "Matchmaking": self = .matchmaking
        case "ReadyCheck": self = .readyCheck
        case "ChampSelect": self = .champSelect
        case "GameStart": self = .gameStart
        case "InProgress": self = .inProgress
        case "WaitingForStats": self = .waitingForStats
        case "PreEndOfGame": self = .preEndOfGame
        case "EndOfGame": self = .endOfGame
        case "Reconnect": self = .reconnect
        case "CheckedIntoTournament": self = .checkedIntoTournament
        default: self = .unknown(rawValue)
        }
    }

    /// The phase carried by a `LCUTopic.gameflowPhase` event, whose `data` is the bare string.
    public init(_ event: LCUEvent) throws(LCUError) {
        self = try LCUEndpoint<GameflowPhase>.gameflowPhase.decode(event.data)
    }
}

extension GameflowPhase: Decodable {
    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }
}
