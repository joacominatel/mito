/// What Mito shows and acts on (`MITO_CONTEXT.md` §11.2).
public enum MitoState: Hashable, Sendable {
    case searching
    case connecting
    case idle
    case lobby
    case matchmaking
    case readyCheck
    case champSelect
    case inGame
}

/// Folds connection changes and gameflow phases into a `MitoState`. Pure: no I/O, no timers.
public struct MitoStateMachine: Hashable, Sendable {
    public private(set) var connection: ConnectionState = .searching
    /// The latest phase of the current connection; `nil` until one arrives.
    public private(set) var phase: GameflowPhase?

    public init() {}

    public var state: MitoState {
        switch connection {
        case .searching: .searching
        case .connecting: .connecting
        case .connected: phase.map(Self.state(for:)) ?? .idle
        }
    }

    /// Losing the connection forgets the phase, so a reconnect never shows a stale one.
    public mutating func apply(_ connection: ConnectionState) {
        self.connection = connection
        if connection != .connected { phase = nil }
    }

    /// Ignored unless connected: a phase only means something for a live client.
    public mutating func apply(_ phase: GameflowPhase) {
        guard connection == .connected else { return }
        self.phase = phase
    }

    private static func state(for phase: GameflowPhase) -> MitoState {
        switch phase {
        case .lobby, .checkedIntoTournament: .lobby
        case .matchmaking: .matchmaking
        case .readyCheck: .readyCheck
        case .champSelect: .champSelect
        case .gameStart, .inProgress, .reconnect: .inGame
        case .none, .waitingForStats, .preEndOfGame, .endOfGame, .unknown: .idle
        }
    }
}
