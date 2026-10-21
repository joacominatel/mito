import Foundation
import LCUKit

/// The connection `AutoAccepter` listens to: the live ready-check events plus the ones the
/// model reads over REST on connecting, since the event stream only reports changes.
nonisolated struct ReadyCheckFeed: LCUConnection {
    /// The raw body of `GET` ready-check, forwarded unchanged as an event's `data`.
    static let current = LCUEndpoint<Data>(
        method: LCUEndpoint.readyCheck.method, path: LCUEndpoint.readyCheck.path
    ) { $0 }

    let base: any LCUConnection
    /// Single subscriber: the accepter.
    let fetched: AsyncStream<LCUEvent>

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        try await base.send(endpoint)
    }

    func states() -> AsyncStream<ConnectionState> { base.states() }

    /// Finishes when the live stream does.
    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> {
        let live = base.events(topics)
        let fetched = topics.contains(.readyCheck) ? fetched : nil
        return AsyncStream { continuation in
            let forwarding = Task {
                await withDiscardingTaskGroup { group in
                    if let fetched {
                        group.addTask {
                            for await event in fetched { continuation.yield(event) }
                        }
                    }
                    for await event in live { continuation.yield(event) }
                    group.cancelAll()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in forwarding.cancel() }
        }
    }

    static func event(_ body: Data) -> LCUEvent {
        LCUEvent(uri: LCUEndpoint.readyCheck.path, eventType: .update, data: body)
    }

    static let ended = LCUEvent(
        uri: LCUEndpoint.readyCheck.path, eventType: .delete, data: Data("null".utf8))
}
