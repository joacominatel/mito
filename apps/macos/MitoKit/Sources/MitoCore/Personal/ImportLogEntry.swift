public import Foundation

/// An `import_log` row: one part of one import.
public struct ImportLogEntry: Hashable, Sendable {
    /// Raw values are the `what` encoding.
    public enum Part: RawRepresentable, Hashable, Sendable {
        case runes
        case spells
        case items
        case unknown(String)

        public init(rawValue: String) {
            switch rawValue {
            case "runes": self = .runes
            case "spells": self = .spells
            case "items": self = .items
            default: self = .unknown(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .runes: "runes"
            case .spells: "spells"
            case .items: "items"
            case .unknown(let value): value
            }
        }
    }

    /// Raw values are the `result` encoding.
    public enum Outcome: RawRepresentable, Hashable, Sendable {
        case applied
        case skipped
        case failed
        case unknown(String)

        public init(rawValue: String) {
            switch rawValue {
            case "applied": self = .applied
            case "skipped": self = .skipped
            case "failed": self = .failed
            default: self = .unknown(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .applied: "applied"
            case .skipped: "skipped"
            case .failed: "failed"
            case .unknown(let value): value
            }
        }
    }

    public let timestamp: Date
    /// `nil` when the champ select session had no game ID yet.
    public let game: GameID?
    public let champion: ChampionID
    public let part: Part
    public let outcome: Outcome
    /// Why it was skipped or failed.
    public let detail: String?

    public init(
        timestamp: Date, game: GameID?, champion: ChampionID, part: Part, outcome: Outcome,
        detail: String? = nil
    ) {
        self.timestamp = timestamp
        self.game = game
        self.champion = champion
        self.part = part
        self.outcome = outcome
        self.detail = detail
    }
}
