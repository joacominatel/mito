import Foundation
import LCUKit

/// The connection `AutoAccepter` listens to: `GameflowModel`'s ready-check stream, the live
/// events plus the read it makes on connecting, since the event stream only reports changes.
nonisolated struct ReadyCheckFeed: LCUConnection {
    /// The raw body of `GET` ready-check, forwarded unchanged as an event's `data`.
    static let current = LCUEndpoint<Data>(
        method: LCUEndpoint.readyCheck.method, path: LCUEndpoint.readyCheck.path
    ) { $0 }

    let base: any LCUConnection
    /// Single subscriber: the accepter.
    let readyChecks: AsyncStream<LCUEvent>

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        try await base.send(endpoint)
    }

    func states() -> AsyncStream<ConnectionState> { base.states() }

    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> {
        topics == [.readyCheck] ? readyChecks : base.events(topics)
    }

    static func event(_ body: Data) -> LCUEvent {
        LCUEvent(uri: LCUEndpoint.readyCheck.path, eventType: .update, data: body)
    }

    static let ended = LCUEvent(
        uri: LCUEndpoint.readyCheck.path, eventType: .delete, data: Data("null".utf8))
}
