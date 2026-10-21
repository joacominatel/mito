public import MitoCore

public enum AutoAcceptDecision: Hashable, Sendable {
    case accept(after: Duration)
    case skip(AutoAcceptSkipReason)
}

public enum AutoAcceptSkipReason: Hashable, Sendable {
    /// `GameSettings.AutoAccept.off`.
    case disabled
    case queueNotSelected(QueueID)
    /// `selectedQueues` with no known queue: never guess.
    case unknownQueue
    case notInProgress(ReadyCheck.State)
    /// The player already answered, from the client or by an earlier accept.
    case alreadyAnswered(ReadyCheck.PlayerResponse)
    /// The ready check disappeared.
    case readyCheckEnded
}

/// Whether to answer a ready check and when (`MITO_CONTEXT.md` §11.3). Pure.
public enum AutoAcceptPolicy {
    public static let delayRange: ClosedRange<Int> = 0...8

    public static func decide(
        settings: GameSettings, queue: QueueID?, readyCheck: ReadyCheck
    ) -> AutoAcceptDecision {
        guard readyCheck.state == .inProgress else {
            return .skip(.notInProgress(readyCheck.state))
        }
        guard readyCheck.playerResponse == .none else {
            return .skip(.alreadyAnswered(readyCheck.playerResponse))
        }
        switch settings.autoAccept {
        case .off:
            return .skip(.disabled)
        case .always:
            break
        case .selectedQueues:
            guard let queue else { return .skip(.unknownQueue) }
            guard settings.autoAcceptQueues.contains(queue) else {
                return .skip(.queueNotSelected(queue))
            }
        }
        return .accept(after: delay(settings))
    }

    public static func delay(_ settings: GameSettings) -> Duration {
        let seconds = min(
            max(settings.autoAcceptDelaySeconds, delayRange.lowerBound), delayRange.upperBound)
        return .seconds(seconds)
    }
}
