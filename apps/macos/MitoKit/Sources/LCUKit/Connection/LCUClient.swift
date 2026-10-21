import Foundation
import Synchronization
import os

/// The live connection to the League client (`MITO_CONTEXT.md` §10.2): it searches, verifies,
/// connects, and starts over whenever the client goes away. Streams from `events(_:)` and
/// `states()` belong to their subscriber and survive reconnections.
public actor LCUClient: LCUConnection {
    static let searchInterval = Duration.seconds(2)
    private static let maxSearchInterval = Duration.seconds(5)
    private static let searchBackoffStep = Duration.seconds(1)
    static let verifyRetryInterval = Duration.seconds(1)

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.joacominatel.mito", category: "LCUKit")

    private struct EventSubscriber: Sendable {
        let topics: Set<LCUTopic>
        let continuation: AsyncStream<LCUEvent>.Continuation
    }

    private struct Hub {
        var state = ConnectionState.searching
        var nextID = 0
        var stateSubscribers: [Int: AsyncStream<ConnectionState>.Continuation] = [:]
        var eventSubscribers: [Int: EventSubscriber] = [:]
        /// Feeds new subscribers to the live connection's bridge; `nil` while not connected.
        var intake: AsyncStream<EventSubscriber>.Continuation?
    }

    private let discover: @Sendable () async -> LCUCredentials?
    private let makeREST: @Sendable (LCUCredentials) -> any LCURequestSending
    private let makeSocket: @Sendable (LCUCredentials) throws(LCUError) -> any WAMPSocket
    private let sleep: @Sendable (Duration) async throws -> Void

    // Reached synchronously from `events(_:)` and `states()`, so it cannot be actor state.
    private let hub = Mutex(Hub())
    private var connected: (any LCURequestSending)?
    private var isRunning = false
    private var waitingRuns: [CheckedContinuation<Void, Never>] = []

    /// `installPath` defaults to `/Applications/League of Legends.app` (§10.1).
    public init(installPath: String? = nil) {
        self.init(discovery: LCUDiscovery(installPath: installPath))
    }

    /// Discovers only through this lockfile, never process arguments: for `tools/lcu-mock`
    /// (§10.2).
    public init(lockfilePath: String) {
        self.init(discovery: LCUDiscovery(lockfilePath: lockfilePath))
    }

    init(
        discovery: LCUDiscovery,
        makeREST: @escaping @Sendable (LCUCredentials) -> any LCURequestSending = {
            LCURESTClient(credentials: $0)
        },
        makeSocket: @escaping @Sendable (LCUCredentials) throws(LCUError) -> any WAMPSocket = {
            credentials throws(LCUError) in try URLSessionWAMPSocket(credentials: credentials)
        },
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.init(
            discover: { await discovery.discover() }, makeREST: makeREST, makeSocket: makeSocket,
            sleep: sleep)
    }

    init(
        discover: @escaping @Sendable () async -> LCUCredentials?,
        makeREST: @escaping @Sendable (LCUCredentials) -> any LCURequestSending,
        makeSocket: @escaping @Sendable (LCUCredentials) throws(LCUError) -> any WAMPSocket,
        sleep: @escaping @Sendable (Duration) async throws -> Void
    ) {
        self.discover = discover
        self.makeREST = makeREST
        self.makeSocket = makeSocket
        self.sleep = sleep
    }

    /// Drives the lifecycle until the calling task is cancelled, then disconnects. A call made
    /// while another is still running waits for it to end, then runs.
    public func run() async {
        while isRunning {
            await withCheckedContinuation { waitingRuns.append($0) }
        }
        isRunning = true
        var next = await search(immediately: true)
        while let found = next {
            next = await connect(found)
        }
        publish(.searching)
        isRunning = false
        if !waitingRuns.isEmpty { waitingRuns.removeFirst().resume() }
    }

    /// Throws `.notConnected` in any state but `.connected`; nothing is queued.
    public func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError)
        -> R
    {
        guard let connected else { throw .notConnected }
        return try await connected.send(endpoint)
    }

    public nonisolated func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: LCUEvent.self, bufferingPolicy: .unbounded)
        let subscriber = EventSubscriber(topics: topics, continuation: continuation)
        let id = hub.withLock { hub in
            let id = hub.nextID
            hub.nextID += 1
            hub.eventSubscribers[id] = subscriber
            hub.intake?.yield(subscriber)
            return id
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.hub.withLock { $0.eventSubscribers.removeValue(forKey: id) }
        }
        return stream
    }

    public nonisolated func states() -> AsyncStream<ConnectionState> {
        let (stream, continuation) = AsyncStream.makeStream(of: ConnectionState.self)
        let id = hub.withLock { hub in
            let id = hub.nextID
            hub.nextID += 1
            hub.stateSubscribers[id] = continuation
            continuation.yield(hub.state)
            return id
        }
        continuation.onTermination = { [weak self] _ in
            _ = self?.hub.withLock { $0.stateSubscribers.removeValue(forKey: id) }
        }
        return stream
    }

    /// `nil` once the task is cancelled.
    private func search(immediately: Bool) async -> LCUCredentials? {
        var interval = Self.searchInterval
        if immediately, let found = await discover() { return found }
        while await pause(interval) {
            interval = min(interval + Self.searchBackoffStep, Self.maxSearchInterval)
            if let found = await discover() { return found }
        }
        return nil
    }

    /// Runs one client from verification to loss; returns the next client to try, or `nil`
    /// once the task is cancelled.
    private func connect(_ found: LCUCredentials) async -> LCUCredentials? {
        publish(.connecting)
        var credentials = found
        var rest = makeREST(credentials)
        // 404 while the client is still loading, or refused while it starts: retry while the
        // same client is still there.
        while !(await verify(rest)) {
            guard await pause(Self.verifyRetryInterval) else { return nil }
            guard let again = await discover() else { return await lost() }
            if again != credentials {
                credentials = again
                rest = makeREST(again)
            }
        }

        let socket: any WAMPSocket
        do {
            socket = try makeSocket(credentials)
        } catch {
            return await lost()
        }
        connected = rest
        let port = credentials.port
        publish(.connected)
        Self.logger.info("Connected to the client on port \(port, privacy: .public)")
        await serve(LCUEventStream(socket: socket))
        return await lost()
    }

    private func verify(_ rest: any LCURequestSending) async -> Bool {
        do {
            _ = try await rest.send(.currentSummoner)
            return true
        } catch {
            let reason = Self.reason(error)
            Self.logger.notice("Client not ready yet: \(reason, privacy: .public)")
            return false
        }
    }

    /// The error's case and status only: bodies and transport messages stay out of the log.
    private static func reason(_ error: LCUError) -> String {
        switch error {
        case .notConnected: "not connected"
        case .http(let status, _): "HTTP \(status)"
        case .transport: "transport"
        case .decoding: "decoding"
        case .encoding: "encoding"
        }
    }

    private func lost() async -> LCUCredentials? {
        connected = nil
        publish(.searching)
        return await search(immediately: false)
    }

    /// Bridges every subscriber, present and future, to this connection's stream until the
    /// stream ends or the task is cancelled.
    private func serve(_ stream: LCUEventStream) async {
        let (intake, intakeContinuation) = AsyncStream.makeStream(
            of: EventSubscriber.self, bufferingPolicy: .unbounded)
        hub.withLock { hub in
            // In subscription order, so the socket sees the same frames on every connection.
            for (_, subscriber) in hub.eventSubscribers.sorted(by: { $0.key < $1.key }) {
                intakeContinuation.yield(subscriber)
            }
            hub.intake = intakeContinuation
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await stream.run() }
            group.addTask {
                await withDiscardingTaskGroup { forwarders in
                    for await subscriber in intake {
                        let events = stream.events(subscriber.topics)
                        forwarders.addTask {
                            await Self.forward(events, to: subscriber.continuation)
                        }
                    }
                }
            }
            // Only `run()` ends on its own; the bridge waits on the intake.
            await group.next()
            hub.withLock { $0.intake = nil }
            intakeContinuation.finish()
            group.cancelAll()
        }
    }

    private static func forward(
        _ events: AsyncStream<LCUEvent>, to subscriber: AsyncStream<LCUEvent>.Continuation
    ) async {
        // DEBT: a cancelled subscriber keeps its inner subscription until its next event or the loss.
        for await event in events {
            if case .terminated = subscriber.yield(event) { return }
        }
    }

    /// `false` once the task is cancelled.
    private func pause(_ duration: Duration) async -> Bool {
        do {
            try await sleep(duration)
            return true
        } catch {
            return false
        }
    }

    private func publish(_ state: ConnectionState) {
        let changed = hub.withLock { hub in
            guard hub.state != state else { return false }
            hub.state = state
            for subscriber in hub.stateSubscribers.values { subscriber.yield(state) }
            return true
        }
        if changed {
            Self.logger.info("Connection state: \(String(describing: state), privacy: .public)")
        }
    }
}
