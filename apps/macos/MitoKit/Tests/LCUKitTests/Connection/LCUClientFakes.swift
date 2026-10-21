import Foundation
import Synchronization

@testable import LCUKit

/// Each sleep is published on `requests` and suspends until `advance()`, so a test steps the
/// lifecycle without waiting real time.
final class ManualSleep: Sendable {
    private typealias Waiter = CheckedContinuation<Void, any Error>

    private struct State {
        var nextID = 0
        var waiter: (id: Int, continuation: Waiter)?
        /// Sleeps cancelled before they registered; only that call fails, not later ones.
        var cancelled: Set<Int> = []
    }

    private let state = Mutex(State())
    let requests: AsyncStream<Duration>
    private let requestsContinuation: AsyncStream<Duration>.Continuation

    init() {
        (requests, requestsContinuation) = AsyncStream.makeStream(of: Duration.self)
    }

    func sleep(for duration: Duration) async throws {
        let id = state.withLock { state in
            defer { state.nextID += 1 }
            return state.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (waiter: Waiter) in
                register(waiter, id: id, for: duration)
            }
        } onCancel: {
            cancel(id)
        }
    }

    private func register(_ waiter: Waiter, id: Int, for duration: Duration) {
        let accepted = state.withLock { state -> Bool in
            guard state.cancelled.remove(id) == nil else { return false }
            state.waiter = (id, waiter)
            requestsContinuation.yield(duration)
            return true
        }
        if !accepted { waiter.resume(throwing: CancellationError()) }
    }

    private func cancel(_ id: Int) {
        let waiter = state.withLock { state -> Waiter? in
            guard let waiter = state.waiter, waiter.id == id else {
                state.cancelled.insert(id)
                return nil
            }
            state.waiter = nil
            return waiter.continuation
        }
        waiter?.resume(throwing: CancellationError())
    }

    func advance() {
        let waiter = state.withLock { state -> Waiter? in
            defer { state.waiter = nil }
            return state.waiter?.continuation
        }
        waiter?.resume()
    }
}

/// Answers each discovery with the next scripted result; the last one keeps answering.
final class ScriptedDiscovery: Sendable {
    private let script: Mutex<[LCUCredentials?]>

    init(_ script: [LCUCredentials?]) {
        self.script = Mutex(script)
    }

    func discover() -> LCUCredentials? {
        script.withLock { script in
            guard let first = script.first else { return nil }
            if script.count > 1 { script.removeFirst() }
            return first
        }
    }
}

/// Serves scripted replies per port, in order (the last one keeps answering; none is a 404),
/// and records every request.
final class FakeREST: Sendable {
    struct Request: Equatable, Sendable {
        let port: Int
        let path: String
    }

    private struct State {
        var replies: [Int: [Result<Data, LCUError>]]
        var requests: [Request] = []
    }

    static let ok = Result<Data, LCUError>.success(Data("{}".utf8))
    static let notFound = Result<Data, LCUError>.failure(.http(status: 404, body: Data()))

    private let state: Mutex<State>

    init(_ replies: [Int: [Result<Data, LCUError>]]) {
        state = Mutex(State(replies: replies))
    }

    var requests: [Request] { state.withLock { $0.requests } }

    func sender(for credentials: LCUCredentials) -> any LCURequestSending {
        Sender(port: credentials.port, owner: self)
    }

    fileprivate func reply(port: Int, path: String) -> Result<Data, LCUError> {
        state.withLock { state in
            state.requests.append(Request(port: port, path: path))
            guard let queue = state.replies[port], let first = queue.first else {
                return Self.notFound
            }
            if queue.count > 1 { state.replies[port] = Array(queue.dropFirst()) }
            return first
        }
    }

    private struct Sender: LCURequestSending {
        let port: Int
        let owner: FakeREST

        func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError)
            -> R
        {
            try endpoint.decode(owner.reply(port: port, path: endpoint.path).get())
        }
    }
}

/// Hands out the given sockets in order, recording the port each one was opened for; once
/// they run out, opening fails.
final class FakeSockets: Sendable {
    private let sockets: [FakeWAMPSocket]
    private let opened = Mutex<[Int]>([])

    init(_ sockets: [FakeWAMPSocket]) {
        self.sockets = sockets
    }

    var ports: [Int] { opened.withLock { $0 } }

    func open(_ credentials: LCUCredentials) throws(LCUError) -> any WAMPSocket {
        let port = credentials.port
        let index = opened.withLock { opened -> Int? in
            guard opened.count < sockets.count else { return nil }
            opened.append(port)
            return opened.count - 1
        }
        guard let index else { throw .transport("no socket left") }
        return sockets[index]
    }
}
