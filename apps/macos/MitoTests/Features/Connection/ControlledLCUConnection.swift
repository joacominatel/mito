import Foundation
import LCUKit

/// A connection the test drives by hand: it pushes states and account-change events, and
/// answers each current-summoner request when it chooses to.
nonisolated final class ControlledLCUConnection: LCUConnection {
    struct SummonerRequest: Sendable {
        let respond: @Sendable (Result<CurrentSummoner, LCUError>) -> Void
    }

    let requests: AsyncStream<SummonerRequest>
    private let requestSink: AsyncStream<SummonerRequest>.Continuation
    private let stateStream: AsyncStream<ConnectionState>
    private let stateSink: AsyncStream<ConnectionState>.Continuation
    private let eventStream: AsyncStream<LCUEvent>
    private let eventSink: AsyncStream<LCUEvent>.Continuation

    init() {
        (requests, requestSink) = AsyncStream.makeStream()
        (stateStream, stateSink) = AsyncStream.makeStream()
        (eventStream, eventSink) = AsyncStream.makeStream()
    }

    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R {
        guard endpoint.path == LCUEndpoint.currentSummoner.path else { throw .notConnected }
        let result = await withCheckedContinuation { continuation in
            requestSink.yield(SummonerRequest { continuation.resume(returning: $0) })
        }
        guard let response = try result.get() as? R else { throw .decoding("not \(R.self)") }
        return response
    }

    /// Single subscriber: the model under test.
    func events(_ topics: Set<LCUTopic>) -> AsyncStream<LCUEvent> { eventStream }

    /// Single subscriber: the model under test.
    func states() -> AsyncStream<ConnectionState> { stateStream }

    func enter(_ state: ConnectionState) {
        stateSink.yield(state)
    }

    func changeAccount() {
        eventSink.yield(
            LCUEvent(
                uri: "/lol-summoner/v1/current-summoner", eventType: .update, data: Data("{}".utf8))
        )
    }

    func finish() {
        stateSink.finish()
        eventSink.finish()
        requestSink.finish()
    }
}
