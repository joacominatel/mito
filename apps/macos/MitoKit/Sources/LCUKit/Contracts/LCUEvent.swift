public import Foundation

public struct LCUEvent: Equatable, Sendable {
    public enum EventType: Hashable, Sendable {
        case create
        case update
        case delete
        case unknown(String)

        public init(_ rawValue: String) {
            switch rawValue {
            case "Create": self = .create
            case "Update": self = .update
            case "Delete": self = .delete
            default: self = .unknown(rawValue)
            }
        }
    }

    public let uri: String
    public let eventType: EventType
    /// The raw JSON of the event's `data` member.
    public let data: Data

    public init(uri: String, eventType: EventType, data: Data) {
        self.uri = uri
        self.eventType = eventType
        self.data = data
    }
}
