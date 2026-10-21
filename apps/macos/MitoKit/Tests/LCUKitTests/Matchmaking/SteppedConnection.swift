import Foundation
import LCUKit
import Synchronization

/// Parks every caller of `pass()` until `open()`; `arrivals` yields once per caller.
final class Gate: Sendable {
    private struct State {
        var isOpen = false
        var waiters: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    private let arrivals: AsyncStream<Void>
    private let arrivalsContinuation: AsyncStream<Void>.Continuation

    init() {
        (arrivals, arrivalsContinuation) = AsyncStream.makeStream(of: Void.self)
    }

    func pass() async {
        await withCheckedContinuation { continuation in
            let isOpen = state.withLock { state in
                if !state.isOpen { state.waiters.append(continuation) }
                return state.isOpen
            }
            arrivalsContinuation.yield()
            if isOpen { continuation.resume() }
        }
    }

    /// Returns once the next caller has reached the gate.
    func arrival() async {
        var iterator = arrivals.makeAsyncIterator()
        _ = await iterator.next()
    }

    func open() {
        let waiters = state.withLock { state in
            state.isOpen = true
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume() }
    }
}

/// A connection the test steps by hand: events arrive when `emit` is called, and a request
/// whose route has a gate waits at it. Routes are `"<METHOD> <path>"`; an unscripted one is a 404.
final class SteppedConnection: LCUConnection {
    private struct State {
        var requests: [String] = []
    }

    private let replies: [String: Result<Data, LCUError>]
    private let gates: [String: Gate]
    private let state = Mutex(State())
    private let stream: AsyncStream<LCUEvent>
    private let continuation: AsyncStream<LCUEvent>.Continuation

    init(replies: [String: Result<Data, LCUError>], gates: [String: Gate] = [:]) {
        self.replies = replies
        self.gates = gates
        (stream, continuation) = AsyncStream.makeStream(
            of: LCUEvent.self, bufferingPolicy: .unbounded)
    }

    var requests: [String] { state.withLock { $0.requests } }

    func emit(_ event: LCUEvent) {
        continuation.yield(event)
    }

    func finishEvents() {
        continuation.finish()
    }

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        let route = "\(endpoint.method.rawValue) \(endpoint.path)"
        state.withLock { $0.requests.append(route) }
        await gates[route]?.pass()
        guard let reply = replies[route] else { throw .http(status: 404, body: Data()) }
        return try endpoint.decode(reply.get())
    }

    /// The one scripted stream; the accepter subscribes once.
    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> { stream }

    func states() -> AsyncStream<ConnectionState> {
        AsyncStream { $0.yield(.connected) }
    }
}
