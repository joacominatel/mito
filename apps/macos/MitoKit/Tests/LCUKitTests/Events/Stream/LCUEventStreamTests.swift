import Foundation
import Testing

@testable import LCUKit

@Suite(.timeLimit(.minutes(1)))
struct LCUEventStreamTests {
    private let socket = FakeWAMPSocket()
    private let hub: LCUEventStream

    init() {
        hub = LCUEventStream(socket: socket)
    }

    private func start() -> Task<Void, Never> {
        Task { [hub] in await hub.run() }
    }

    private func consume(_ topics: Set<LCUTopic>) -> Task<[LCUEvent], Never> {
        let stream = hub.events(topics)
        return Task {
            var received: [LCUEvent] = []
            for await event in stream { received.append(event) }
            return received
        }
    }

    private func stop(_ running: Task<Void, Never>) async {
        socket.close()
        await running.value
    }

    private static func event(_ topic: LCUTopic, _ phase: String) -> (String, LCUEvent) {
        let payload = #"{"uri":"/x","eventType":"Update","data":"\#(phase)"}"#
        let frame = #"[8,"\#(topic.rawValue)",\#(payload)]"#
        return (frame, LCUEvent(uri: "/x", eventType: .update, data: Data(#""\#(phase)""#.utf8)))
    }

    @Test func subscribesATopicWhenItsFirstSubscriberAppears() async {
        var sent = socket.sent.makeAsyncIterator()
        let running = start()
        let consumer = consume([.gameflowPhase])

        #expect(await sent.next() == #"[5,"OnJsonApiEvent_lol-gameflow_v1_gameflow-phase"]"#)
        await stop(running)
        _ = await consumer.value
    }

    @Test func subscribesASharedTopicOnceAndUnsubscribesItWithItsLastSubscriber() async {
        var sent = socket.sent.makeAsyncIterator()
        let running = start()
        let first = consume([.gameflowPhase])
        let second = consume([.gameflowPhase, .lobby])
        #expect(await sent.next() == WAMPCodec.subscribe(.gameflowPhase))
        #expect(await sent.next() == WAMPCodec.subscribe(.lobby))

        first.cancel()
        _ = await first.value
        second.cancel()
        _ = await second.value

        #expect(await sent.next() == WAMPCodec.unsubscribe(.gameflowPhase))
        #expect(await sent.next() == WAMPCodec.unsubscribe(.lobby))
        await stop(running)
        #expect(await sent.next() == nil)
    }

    @Test func droppingAStreamReleasesItsTopics() async {
        var sent = socket.sent.makeAsyncIterator()
        let running = start()
        do { _ = hub.events([.readyCheck]) }

        #expect(await sent.next() == WAMPCodec.subscribe(.readyCheck))
        #expect(await sent.next() == WAMPCodec.unsubscribe(.readyCheck))
        await stop(running)
    }

    @Test func resubscribesATopicThatWasReleased() async {
        var sent = socket.sent.makeAsyncIterator()
        let running = start()
        let first = consume([.lobby])
        #expect(await sent.next() == WAMPCodec.subscribe(.lobby))
        first.cancel()
        _ = await first.value
        let second = consume([.lobby])

        #expect(await sent.next() == WAMPCodec.unsubscribe(.lobby))
        #expect(await sent.next() == WAMPCodec.subscribe(.lobby))
        await stop(running)
        _ = await second.value
    }

    @Test func deliversToEachSubscriberOnlyItsOwnTopics() async {
        let running = start()
        let phases = consume([.gameflowPhase])
        let lobbies = consume([.lobby])
        let both = consume([.gameflowPhase, .lobby])
        let (phaseFrame, phase) = Self.event(.gameflowPhase, "Lobby")
        let (lobbyFrame, lobby) = Self.event(.lobby, "Matchmaking")

        socket.feed(phaseFrame)
        socket.feed(lobbyFrame)
        await stop(running)

        #expect(await phases.value == [phase])
        #expect(await lobbies.value == [lobby])
        #expect(await both.value == [phase, lobby])
    }

    @Test func skipsIgnoredFrames() async {
        let running = start()
        let consumer = consume([.gameflowPhase])
        let (frame, event) = Self.event(.gameflowPhase, "ChampSelect")

        socket.feed(#"[0,"session",1,"server"]"#)
        socket.feed("not json")
        socket.feed(#"[8,"OnJsonApiEvent",{"uri":"/x","eventType":"Update","data":1}]"#)
        socket.feed(frame)
        await stop(running)

        #expect(await consumer.value == [event])
    }

    @Test func finishesEveryStreamWhenTheSocketCloses() async {
        let running = start()
        let first = consume([.champSelectSession])
        let second = consume([.currentSummoner])

        await stop(running)

        #expect(await first.value.isEmpty)
        #expect(await second.value.isEmpty)
    }

    @Test func finishesEveryStreamWhenASendFails() async {
        socket.failSends()
        let running = start()
        let consumer = consume([.gameflowPhase])

        await running.value

        #expect(await consumer.value.isEmpty)
    }

    @Test func finishesEveryStreamWhenRunIsCancelled() async {
        let running = start()
        let consumer = consume([.gameflowPhase])

        running.cancel()
        await running.value

        #expect(await consumer.value.isEmpty)
    }

    @Test func deliversNothingToASubscriberAfterItIsCancelled() async {
        let running = start()
        let cancelled = consume([.gameflowPhase])
        let remaining = consume([.gameflowPhase])
        let (frame, event) = Self.event(.gameflowPhase, "InProgress")

        cancelled.cancel()
        #expect(await cancelled.value.isEmpty)
        socket.feed(frame)
        await stop(running)

        #expect(await remaining.value == [event])
    }

    @Test func returnsAFinishedStreamOnceTheSocketHasClosed() async {
        await stop(start())

        var late = hub.events([.gameflowPhase]).makeAsyncIterator()

        #expect(await late.next() == nil)
    }
}
