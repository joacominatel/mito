import Synchronization

@testable import LCUKit

/// Feeds text frames to the reader and publishes every frame the writer sends, in order.
final class FakeWAMPSocket: WAMPSocket {
    struct Closed: Error {}

    private struct State {
        var inbox: [String] = []
        var waiter: CheckedContinuation<String, any Error>?
        var closed = false
        var failsSends = false
    }

    private let state = Mutex(State())
    /// Every frame sent, in order; finishes when the socket closes.
    let sent: AsyncStream<String>
    private let sentContinuation: AsyncStream<String>.Continuation

    init() {
        (sent, sentContinuation) = AsyncStream.makeStream(of: String.self)
    }

    func feed(_ frame: String) {
        state.withLock { state in
            if let waiter = state.waiter {
                state.waiter = nil
                waiter.resume(returning: frame)
            } else {
                state.inbox.append(frame)
            }
        }
    }

    func failSends() {
        state.withLock { $0.failsSends = true }
    }

    func send(_ frame: String) async throws {
        try state.withLock { state in
            guard !state.closed, !state.failsSends else { throw Closed() }
        }
        sentContinuation.yield(frame)
    }

    func receive() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            state.withLock { state in
                if !state.inbox.isEmpty {
                    continuation.resume(returning: state.inbox.removeFirst())
                } else if state.closed {
                    continuation.resume(throwing: Closed())
                } else {
                    state.waiter = continuation
                }
            }
        }
    }

    func close() {
        state.withLock { state in
            state.closed = true
            state.waiter?.resume(throwing: Closed())
            state.waiter = nil
        }
        sentContinuation.finish()
    }
}
