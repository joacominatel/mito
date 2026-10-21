public enum QueueType: Hashable, Sendable {
    case normalDraft
    case normalBlind
    case rankedSolo
    case rankedFlex
    case aram
    case other(QueueID)

    public init(queueID: QueueID) {
        switch queueID.rawValue {
        case 400: self = .normalDraft
        case 430: self = .normalBlind
        case 420: self = .rankedSolo
        case 440: self = .rankedFlex
        case 450: self = .aram
        default: self = .other(queueID)
        }
    }

    public var queueID: QueueID {
        switch self {
        case .normalDraft: QueueID(rawValue: 400)
        case .normalBlind: QueueID(rawValue: 430)
        case .rankedSolo: QueueID(rawValue: 420)
        case .rankedFlex: QueueID(rawValue: 440)
        case .aram: QueueID(rawValue: 450)
        case .other(let id): id
        }
    }
}
