import Foundation
import Synchronization

/// Fans the events of one WAMP socket out to any number of subscribers
/// (`MITO_CONTEXT.md` §10.5). The socket is subscribed to the union of the topics in use.
/// `run()` drives the socket; when it ends, every stream finishes and the type is spent.
final class LCUEventStream: Sendable {
    private struct Subscriber {
        let topics: Set<LCUTopic>
        let continuation: AsyncStream<LCUEvent>.Continuation
    }

    private struct State {
        var started = false
        var closed = false
        var nextID = 0
        var subscribers: [Int: Subscriber] = [:]
        var refCounts: [LCUTopic: Int] = [:]
    }

    private let socket: any WAMPSocket
    private let state = Mutex(State())
    // FIFO, so a subscribe and a later unsubscribe of the same topic reach the socket in order.
    private let outbound: AsyncStream<String>
    private let outboundContinuation: AsyncStream<String>.Continuation

    init(socket: any WAMPSocket) {
        self.socket = socket
        (outbound, outboundContinuation) = AsyncStream.makeStream(of: String.self)
    }

    convenience init(
        credentials: LCUCredentials, configuration: URLSessionConfiguration = .ephemeral
    ) throws(LCUError) {
        self.init(
            socket: try URLSessionWAMPSocket(
                credentials: credentials, configuration: configuration))
    }

    /// Unbounded buffering: yielding never blocks the reader and never drops a phase change;
    /// five specific topics are low volume.
    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: LCUEvent.self, bufferingPolicy: .unbounded)
        let id = state.withLock { state -> Int? in
            guard !state.closed else { return nil }
            let id = state.nextID
            state.nextID += 1
            state.subscribers[id] = Subscriber(topics: topics, continuation: continuation)
            for topic in LCUTopic.allCases where topics.contains(topic) {
                state.refCounts[topic, default: 0] += 1
                if state.refCounts[topic] == 1 {
                    outboundContinuation.yield(WAMPCodec.subscribe(topic))
                }
            }
            return id
        }
        guard let id else {
            continuation.finish()
            return stream
        }
        continuation.onTermination = { [weak self] _ in self?.release(id) }
        return stream
    }

    /// Returns when the socket closes or fails, or when the calling task is cancelled.
    /// Only the first call does anything.
    func run() async {
        let first = state.withLock { state in
            defer { state.started = true }
            return !state.started
        }
        guard first else { return }

        await withDiscardingTaskGroup { group in
            group.addTask { await self.write() }
            await withTaskCancellationHandler {
                await read()
            } onCancel: {
                socket.close()
            }
            shutdown()
        }
    }

    private func read() async {
        while let frame = try? await socket.receive() {
            guard case .event(let topic, let event) = WAMPCodec.decode(frame) else { continue }
            let targets = state.withLock { state in
                state.subscribers.values.filter { $0.topics.contains(topic) }.map(\.continuation)
            }
            for target in targets { target.yield(event) }
        }
    }

    private func write() async {
        for await frame in outbound {
            do {
                try await socket.send(frame)
            } catch {
                // The reader then fails too, which shuts everything down.
                socket.close()
                return
            }
        }
    }

    private func release(_ id: Int) {
        state.withLock { state in
            guard !state.closed, let subscriber = state.subscribers.removeValue(forKey: id)
            else { return }
            for topic in LCUTopic.allCases where subscriber.topics.contains(topic) {
                state.refCounts[topic, default: 1] -= 1
                if state.refCounts[topic] == 0 {
                    state.refCounts[topic] = nil
                    outboundContinuation.yield(WAMPCodec.unsubscribe(topic))
                }
            }
        }
    }

    private func shutdown() {
        let open = state.withLock { state in
            state.closed = true
            defer {
                state.subscribers = [:]
                state.refCounts = [:]
            }
            return state.subscribers.values.map(\.continuation)
        }
        socket.close()
        outboundContinuation.finish()
        // Outside the lock: finishing runs `onTermination`, which takes it again.
        for continuation in open { continuation.finish() }
    }
}
