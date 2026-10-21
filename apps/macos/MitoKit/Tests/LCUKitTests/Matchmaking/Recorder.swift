import Synchronization

final class Recorder<Element: Sendable>: Sendable {
    private struct State {
        var values: [Element] = []
        var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state = Mutex(State())

    var values: [Element] { state.withLock { $0.values } }

    func append(_ value: Element) {
        let ready = state.withLock { state in
            state.values.append(value)
            let ready = state.waiters.filter { $0.count <= state.values.count }
            state.waiters.removeAll { $0.count <= state.values.count }
            return ready.map(\.continuation)
        }
        for waiter in ready { waiter.resume() }
    }

    /// Returns once at least `count` values have arrived.
    func wait(for count: Int) async {
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state in
                guard state.values.count < count else { return true }
                state.waiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }
}
