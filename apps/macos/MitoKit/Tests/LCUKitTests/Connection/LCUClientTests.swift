import Foundation
import Testing

@testable import LCUKit

@Suite(.timeLimit(.minutes(1)))
struct LCUClientTests {
    private static let first = LCUCredentials(port: 50_001, token: "first-token")
    private static let second = LCUCredentials(port: 50_002, token: "second-token")
    private static let summonerPath = "/lol-summoner/v1/current-summoner"

    private let clock = ManualSleep()

    private func client(
        discovery script: [LCUCredentials?],
        rest: FakeREST = FakeREST([first.port: [FakeREST.ok], second.port: [FakeREST.ok]]),
        sockets: FakeSockets = FakeSockets([FakeWAMPSocket()])
    ) -> LCUClient {
        let discovery = ScriptedDiscovery(script)
        return LCUClient(
            discover: { discovery.discover() },
            makeREST: { rest.sender(for: $0) },
            makeSocket: { credentials throws(LCUError) in try sockets.open(credentials) },
            sleep: { [clock] in try await clock.sleep(for: $0) }
        )
    }

    private func start(_ client: LCUClient) -> Task<Void, Never> {
        Task { await client.run() }
    }

    private func stop(_ running: Task<Void, Never>) async {
        running.cancel()
        await running.value
    }

    private func nextSleep() async -> Duration? {
        var requests = clock.requests.makeAsyncIterator()
        return await requests.next()
    }

    private static func next(
        _ count: Int, of states: inout AsyncStream<ConnectionState>.Iterator
    ) async -> [ConnectionState] {
        var received: [ConnectionState] = []
        for _ in 0..<count {
            guard let state = await states.next(isolation: #isolation) else { break }
            received.append(state)
        }
        return received
    }

    private static func event(_ phase: String) -> (frame: String, event: LCUEvent) {
        let topic = LCUTopic.gameflowPhase.rawValue
        let frame = #"[8,"\#(topic)",{"uri":"/x","eventType":"Update","data":"\#(phase)"}]"#
        return (frame, LCUEvent(uri: "/x", eventType: .update, data: Data(#""\#(phase)""#.utf8)))
    }

    @Test func movesFromSearchingThroughConnectingToConnected() async {
        let sockets = FakeSockets([FakeWAMPSocket()])
        let client = client(discovery: [nil, Self.first], sockets: sockets)
        var states = client.states().makeAsyncIterator()
        #expect(await states.next() == .searching)

        let running = start(client)
        #expect(await nextSleep() == LCUClient.searchInterval)
        clock.advance()

        #expect(await Self.next(2, of: &states) == [.connecting, .connected])
        #expect(sockets.ports == [Self.first.port])
        await stop(running)
    }

    @Test func retriesCurrentSummonerUntilTheClientStopsAnswering404() async {
        let rest = FakeREST([Self.first.port: [FakeREST.notFound, FakeREST.notFound, FakeREST.ok]])
        let client = client(discovery: [Self.first], rest: rest)
        var states = client.states().makeAsyncIterator()
        let running = start(client)

        #expect(await nextSleep() == LCUClient.verifyRetryInterval)
        clock.advance()
        #expect(await nextSleep() == LCUClient.verifyRetryInterval)
        clock.advance()

        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])
        #expect(
            rest.requests
                == Array(repeating: .init(port: Self.first.port, path: Self.summonerPath), count: 3)
        )
        await stop(running)
    }

    @Test func returnsToSearchingWhenTheClientDisappearsDuringVerification() async {
        let sockets = FakeSockets([FakeWAMPSocket()])
        let client = client(
            discovery: [Self.first, nil], rest: FakeREST([Self.first.port: [FakeREST.notFound]]),
            sockets: sockets)
        var states = client.states().makeAsyncIterator()
        let running = start(client)

        #expect(await nextSleep() == LCUClient.verifyRetryInterval)
        clock.advance()

        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .searching])
        #expect(await nextSleep() == LCUClient.searchInterval)
        #expect(sockets.ports.isEmpty)
        await stop(running)
    }

    @Test func returnsToSearchingWhenTheSocketEnds() async {
        let socket = FakeWAMPSocket()
        let client = client(discovery: [Self.first, nil], sockets: FakeSockets([socket]))
        var states = client.states().makeAsyncIterator()
        let running = start(client)
        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])

        socket.close()

        #expect(await states.next() == .searching)
        #expect(await nextSleep() == LCUClient.searchInterval)
        await stop(running)
    }

    @Test func reconnectsToARestartedClientOnItsNewPort() async throws {
        let rest = FakeREST([Self.first.port: [FakeREST.ok], Self.second.port: [FakeREST.ok]])
        let firstSocket = FakeWAMPSocket()
        let sockets = FakeSockets([firstSocket, FakeWAMPSocket()])
        let client = client(discovery: [Self.first, Self.second], rest: rest, sockets: sockets)
        var states = client.states().makeAsyncIterator()
        let running = start(client)
        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])

        firstSocket.close()
        #expect(await states.next() == .searching)
        #expect(await nextSleep() == LCUClient.searchInterval)
        clock.advance()

        #expect(await Self.next(2, of: &states) == [.connecting, .connected])
        #expect(sockets.ports == [Self.first.port, Self.second.port])
        _ = try await client.send(.currentSummoner)
        #expect(rest.requests.last == .init(port: Self.second.port, path: Self.summonerPath))
        await stop(running)
    }

    @Test func keepsDeliveringEventsToASubscriberAcrossAReconnect() async {
        let firstSocket = FakeWAMPSocket()
        let secondSocket = FakeWAMPSocket()
        let client = client(
            discovery: [Self.first, Self.second],
            sockets: FakeSockets([firstSocket, secondSocket]))
        var events = client.events([.gameflowPhase]).makeAsyncIterator()
        var states = client.states().makeAsyncIterator()
        let running = start(client)
        let (lobbyFrame, lobby) = Self.event("Lobby")
        let (champSelectFrame, champSelect) = Self.event("ChampSelect")

        var firstSent = firstSocket.sent.makeAsyncIterator()
        #expect(await firstSent.next() == WAMPCodec.subscribe(.gameflowPhase))
        firstSocket.feed(lobbyFrame)
        #expect(await events.next() == lobby)

        firstSocket.close()
        #expect(
            await Self.next(4, of: &states) == [.searching, .connecting, .connected, .searching])
        #expect(await nextSleep() == LCUClient.searchInterval)
        clock.advance()

        var secondSent = secondSocket.sent.makeAsyncIterator()
        #expect(await secondSent.next() == WAMPCodec.subscribe(.gameflowPhase))
        secondSocket.feed(champSelectFrame)
        #expect(await events.next() == champSelect)
        await stop(running)
    }

    @Test func bridgesASubscriberThatArrivesWhileConnected() async {
        let socket = FakeWAMPSocket()
        let client = client(discovery: [Self.first], sockets: FakeSockets([socket]))
        var states = client.states().makeAsyncIterator()
        let running = start(client)
        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])
        let (frame, event) = Self.event("InProgress")

        var events = client.events([.gameflowPhase]).makeAsyncIterator()
        var sent = socket.sent.makeAsyncIterator()
        #expect(await sent.next() == WAMPCodec.subscribe(.gameflowPhase))
        socket.feed(frame)

        #expect(await events.next() == event)
        await stop(running)
    }

    @Test func replaysTheCurrentStateToANewSubscriber() async {
        let client = client(discovery: [Self.first])
        var states = client.states().makeAsyncIterator()
        let running = start(client)
        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])

        var late = client.states().makeAsyncIterator()

        #expect(await late.next() == .connected)
        await stop(running)
    }

    @Test func sendThrowsNotConnectedBeforeTheLifecycleRuns() async {
        let rest = FakeREST([:])
        let client = client(discovery: [Self.first], rest: rest)

        await #expect(throws: LCUError.notConnected) {
            try await client.send(.currentSummoner)
        }
        #expect(rest.requests.isEmpty)
    }

    @Test func sendThrowsNotConnectedWhileTheClientIsStillLoading() async {
        let rest = FakeREST([Self.first.port: [FakeREST.notFound]])
        let client = client(discovery: [Self.first], rest: rest)
        let running = start(client)
        #expect(await nextSleep() == LCUClient.verifyRetryInterval)

        await #expect(throws: LCUError.notConnected) {
            try await client.send(.currentSummoner)
        }
        #expect(rest.requests.count == 1)
        await stop(running)
    }

    @Test func cancellingRunDisconnectsAndClosesTheSocket() async {
        let socket = FakeWAMPSocket()
        let client = client(discovery: [Self.first], sockets: FakeSockets([socket]))
        var states = client.states().makeAsyncIterator()
        let running = start(client)
        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])

        await stop(running)

        #expect(await states.next() == .searching)
        var sent = socket.sent.makeAsyncIterator()
        #expect(await sent.next() == nil)
        await #expect(throws: LCUError.notConnected) {
            try await client.send(.currentSummoner)
        }
    }

    @Test func backsOffFromTwoToFiveSecondsWhileNoClientRuns() async {
        let client = client(discovery: [nil])
        let running = start(client)

        var intervals: [Duration] = []
        for _ in 0..<5 {
            guard let interval = await nextSleep() else { break }
            intervals.append(interval)
            clock.advance()
        }

        #expect(intervals == [.seconds(2), .seconds(3), .seconds(4), .seconds(5), .seconds(5)])
        await stop(running)
    }

    @Test func returnsToSearchingWhenTheSocketCannotOpen() async {
        let client = client(discovery: [Self.first], sockets: FakeSockets([]))
        var states = client.states().makeAsyncIterator()
        let running = start(client)

        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .searching])
        #expect(await nextSleep() == LCUClient.searchInterval)
        await stop(running)
    }

    @Test func aRunStartedWhileTheCancelledOneUnwindsStillConnects() async {
        let sockets = FakeSockets([FakeWAMPSocket(), FakeWAMPSocket()])
        let client = client(discovery: [Self.first], sockets: sockets)
        var states = client.states().makeAsyncIterator()
        let cancelled = start(client)
        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])

        cancelled.cancel()
        let restarted = start(client)
        await cancelled.value

        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])
        #expect(sockets.ports == [Self.first.port, Self.first.port])
        await stop(restarted)
    }

    @Test func aSecondRunWaitsForTheFirstAndThenTakesOver() async {
        let sockets = FakeSockets([FakeWAMPSocket(), FakeWAMPSocket(), FakeWAMPSocket()])
        let client = client(discovery: [Self.first], sockets: sockets)
        var states = client.states().makeAsyncIterator()
        let firstRun = start(client)
        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])
        let secondRun = start(client)

        await stop(firstRun)

        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])
        #expect(sockets.ports == [Self.first.port, Self.first.port])
        await stop(secondRun)
    }

    @Test func aCancelledSubscriberIsNotSubscribedOnTheNextConnection() async {
        let firstSocket = FakeWAMPSocket()
        let secondSocket = FakeWAMPSocket()
        let client = client(
            discovery: [Self.first, Self.second],
            sockets: FakeSockets([firstSocket, secondSocket]))
        let phases = client.events([.gameflowPhase])
        let consumer = Task { for await _ in phases {} }
        let lobbies = client.events([.lobby])
        var states = client.states().makeAsyncIterator()
        let running = start(client)

        var firstSent = firstSocket.sent.makeAsyncIterator()
        #expect(await firstSent.next() == WAMPCodec.subscribe(.gameflowPhase))
        #expect(await firstSent.next() == WAMPCodec.subscribe(.lobby))
        consumer.cancel()
        await consumer.value
        firstSocket.close()
        #expect(
            await Self.next(4, of: &states) == [.searching, .connecting, .connected, .searching])
        #expect(await nextSleep() == LCUClient.searchInterval)
        clock.advance()

        // Bridging follows subscription order, so a leftover phase subscribe would come first.
        var secondSent = secondSocket.sent.makeAsyncIterator()
        #expect(await secondSent.next() == WAMPCodec.subscribe(.lobby))
        await stop(running)
        withExtendedLifetime(lobbies) {}
    }

    @Test func deliversEachEventOnceAfterAReconnect() async {
        let firstSocket = FakeWAMPSocket()
        let secondSocket = FakeWAMPSocket()
        let client = client(
            discovery: [Self.first, Self.second],
            sockets: FakeSockets([firstSocket, secondSocket]))
        var states = client.states().makeAsyncIterator()
        let running = start(client)
        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])
        var events = client.events([.gameflowPhase]).makeAsyncIterator()
        var firstSent = firstSocket.sent.makeAsyncIterator()
        #expect(await firstSent.next() == WAMPCodec.subscribe(.gameflowPhase))

        firstSocket.close()
        #expect(await states.next() == .searching)
        #expect(await nextSleep() == LCUClient.searchInterval)
        clock.advance()
        var secondSent = secondSocket.sent.makeAsyncIterator()
        #expect(await secondSent.next() == WAMPCodec.subscribe(.gameflowPhase))
        let (lobbyFrame, lobby) = Self.event("Lobby")
        let (matchmakingFrame, matchmaking) = Self.event("Matchmaking")
        secondSocket.feed(lobbyFrame)
        secondSocket.feed(matchmakingFrame)

        #expect(await events.next() == lobby)
        #expect(await events.next() == matchmaking)
        await stop(running)
    }

    @Test func losingAClientResetsTheBackoffToTwoSeconds() async {
        let socket = FakeWAMPSocket()
        let client = client(
            discovery: [nil, nil, nil, Self.first, nil], sockets: FakeSockets([socket]))
        var states = client.states().makeAsyncIterator()
        let running = start(client)
        var grown: [Duration] = []
        for _ in 0..<3 {
            guard let interval = await nextSleep() else { break }
            grown.append(interval)
            clock.advance()
        }
        #expect(grown == [.seconds(2), .seconds(3), .seconds(4)])
        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])

        socket.close()

        #expect(await states.next() == .searching)
        #expect(await nextSleep() == .seconds(2))
        clock.advance()
        #expect(await nextSleep() == .seconds(3))
        await stop(running)
    }

    @Test func neverRepublishesTheStateItIsAlreadyIn() async {
        let client = client(discovery: [nil, Self.first])
        var states = client.states().makeAsyncIterator()
        #expect(await states.next() == .searching)
        let searching = start(client)
        #expect(await nextSleep() == LCUClient.searchInterval)

        // Cancelled while searching, the run ends in `.searching` again: no new state.
        await stop(searching)
        let running = start(client)

        #expect(await Self.next(2, of: &states) == [.connecting, .connected])
        await stop(running)
    }

    @Test func verifiesTheNewCredentialsWhenTheyChangeDuringVerification() async {
        let rest = FakeREST([Self.first.port: [FakeREST.notFound], Self.second.port: [FakeREST.ok]])
        let sockets = FakeSockets([FakeWAMPSocket()])
        let client = client(discovery: [Self.first, Self.second], rest: rest, sockets: sockets)
        var states = client.states().makeAsyncIterator()
        let running = start(client)

        #expect(await nextSleep() == LCUClient.verifyRetryInterval)
        clock.advance()

        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])
        #expect(
            rest.requests == [
                .init(port: Self.first.port, path: Self.summonerPath),
                .init(port: Self.second.port, path: Self.summonerPath),
            ])
        #expect(sockets.ports == [Self.second.port])
        await stop(running)
    }
}
