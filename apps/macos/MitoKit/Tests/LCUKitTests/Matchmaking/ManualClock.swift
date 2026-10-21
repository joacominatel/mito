import Synchronization

/// Time moves only on `advance(by:)`; every sleep is recorded.
final class ManualClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var nextID = 0
        var sleepers: [Int: Sleeper] = [:]
        var cancelled: Set<Int> = []
        var requested: [Duration] = []
        var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }

    /// Every duration asked of `sleep`, in order.
    var requestedSleeps: [Duration] { state.withLock { $0.requested } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let (resume, waiters) = state.withLock {
                    state -> (Result<Void, any Error>?, [CheckedContinuation<Void, Never>]) in
                    state.requested.append(state.now.duration(to: deadline))
                    let ready = state.waiters.filter { $0.count <= state.requested.count }
                    state.waiters.removeAll { $0.count <= state.requested.count }
                    if state.cancelled.contains(id) {
                        return (.failure(CancellationError()), ready.map(\.continuation))
                    }
                    if deadline <= state.now { return (.success(()), ready.map(\.continuation)) }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return (nil, ready.map(\.continuation))
                }
                for waiter in waiters { waiter.resume() }
                if let resume { continuation.resume(with: resume) }
            }
        } onCancel: {
            let sleeper = state.withLock { state in
                state.cancelled.insert(id)
                return state.sleepers.removeValue(forKey: id)
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.sleepers.filter { $0.value.deadline <= now }
            for id in due.keys { state.sleepers[id] = nil }
            return due.values.map(\.continuation)
        }
        for continuation in due { continuation.resume() }
    }

    /// Returns once at least `count` sleeps have been requested.
    func sleeps(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state in
                guard state.requested.count < count else { return true }
                state.waiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}
