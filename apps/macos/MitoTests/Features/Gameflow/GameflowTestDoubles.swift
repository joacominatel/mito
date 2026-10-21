import Foundation
import LCUKit
import Observation
import Synchronization

@testable import Mito

/// A connection the test drives by hand: it pushes states and gameflow and ready-check events,
/// answers each path with the latest canned body, and can hold a path's requests until released.
/// A path with no answer gets a 404, like the real client.
nonisolated final class GameflowTestConnection: LCUConnection {
    private struct Waiter {
        let request: String
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var answers: [String: Result<Data, LCUError>] = [:]
        var held: Set<String> = []
        var holding: [String: [CheckedContinuation<Void, Never>]] = [:]
        var requests: [String] = []
        var waiters: [Waiter] = []
    }

    private let state = Mutex(State())
    private let stateStream: AsyncStream<ConnectionState>
    private let stateSink: AsyncStream<ConnectionState>.Continuation
    private let phaseStream: AsyncStream<LCUEvent>
    private let phaseSink: AsyncStream<LCUEvent>.Continuation
    private let readyCheckStream: AsyncStream<LCUEvent>
    private let readyCheckSink: AsyncStream<LCUEvent>.Continuation

    init() {
        (stateStream, stateSink) = AsyncStream.makeStream()
        (phaseStream, phaseSink) = AsyncStream.makeStream()
        (readyCheckStream, readyCheckSink) = AsyncStream.makeStream()
    }

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        let request = Self.request(endpoint.method, endpoint.path)
        let ready = state.withLock { state in
            state.requests.append(request)
            let count = state.requests.count { $0 == request }
            let ready = state.waiters.filter { $0.request == request && $0.count <= count }
            state.waiters.removeAll { $0.request == request && $0.count <= count }
            return ready
        }
        for waiter in ready { waiter.continuation.resume() }
        await withCheckedContinuation { continuation in
            let parked = state.withLock { state in
                guard state.held.contains(endpoint.path) else { return false }
                state.holding[endpoint.path, default: []].append(continuation)
                return true
            }
            if !parked { continuation.resume() }
        }
        let answer = state.withLock { $0.answers[endpoint.path] }
        guard let answer else { throw .http(status: 404, body: Data()) }
        return try endpoint.decode(try answer.get())
    }

    /// Single subscriber per topic: the model follows phases, the accepter ready checks.
    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> {
        if topics == [.gameflowPhase] { return phaseStream }
        if topics == [.readyCheck] { return readyCheckStream }
        return AsyncStream { $0.finish() }
    }

    /// Single subscriber: the model under test.
    func states() -> AsyncStream<ConnectionState> { stateStream }

    func enter(_ connectionState: ConnectionState) {
        stateSink.yield(connectionState)
    }

    func answer(_ path: String, json: String) {
        state.withLock { $0.answers[path] = .success(Data(json.utf8)) }
    }

    func answer(_ path: String, error: LCUError) {
        state.withLock { $0.answers[path] = .failure(error) }
    }

    func hold(_ path: String) {
        state.withLock { _ = $0.held.insert(path) }
    }

    /// Lets every held request to `path` through; held requests made after this one are not.
    func release(_ path: String) {
        let held = state.withLock { state in
            state.held.remove(path)
            return state.holding.removeValue(forKey: path) ?? []
        }
        for continuation in held { continuation.resume() }
    }

    /// Returns once `path` has been requested with `method` at least `times` times.
    func requested(_ method: HTTPMethod, _ path: String, times: Int = 1) async {
        let request = Self.request(method, path)
        await withCheckedContinuation { continuation in
            let ready = state.withLock { state in
                guard state.requests.count(where: { $0 == request }) < times else { return true }
                state.waiters.append(
                    Waiter(request: request, count: times, continuation: continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    func count(_ method: HTTPMethod, _ path: String) -> Int {
        let request = Self.request(method, path)
        return state.withLock { $0.requests.count { $0 == request } }
    }

    func emitPhase(_ phase: String) {
        phaseSink.yield(
            LCUEvent(
                uri: LCUEndpoint.gameflowPhase.path, eventType: .update,
                data: Data("\"\(phase)\"".utf8)))
    }

    func emitReadyCheck(_ json: String) {
        readyCheckSink.yield(
            LCUEvent(uri: LCUEndpoint.readyCheck.path, eventType: .update, data: Data(json.utf8)))
    }

    func emitReadyCheckEnded() {
        readyCheckSink.yield(
            LCUEvent(uri: LCUEndpoint.readyCheck.path, eventType: .delete, data: Data("null".utf8)))
    }

    func finish() {
        stateSink.finish()
        phaseSink.finish()
        readyCheckSink.finish()
    }

    private static func request(_ method: HTTPMethod, _ path: String) -> String {
        "\(method.rawValue) \(path)"
    }
}

/// Every sleep returns at once; the durations asked for are recorded.
nonisolated final class ImmediateClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private let requested = Mutex<[Duration]>([])

    var now: Instant { Instant(offset: .zero) }
    var minimumResolution: Duration { .zero }
    var sleeps: [Duration] { requested.withLock { $0 } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        requested.withLock { $0.append(now.duration(to: deadline)) }
        try Task.checkCancellation()
    }
}

@Observable
final class RecordingPoster: NotificationPosting {
    struct Post: Equatable {
        let notification: MitoNotification
        let title: String
    }

    private(set) var posts: [Post] = []

    func post(_ notification: MitoNotification, title: LocalizedStringResource) async {
        posts.append(Post(notification: notification, title: String(localized: title)))
    }
}

/// Suspends until `condition` holds, re-checking on every change to what it reads.
func waitUntil(_ condition: () -> Bool) async {
    while !condition() {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = condition()
            } onChange: {
                continuation.resume()
            }
        }
    }
}
