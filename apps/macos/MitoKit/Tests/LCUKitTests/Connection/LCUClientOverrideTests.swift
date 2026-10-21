import Foundation
import Synchronization
import Testing

@testable import LCUKit

@Suite(.timeLimit(.minutes(1)))
struct LCUClientOverrideTests {
    private static let lockfilePath = "/tmp/lcu-mock/lockfile"
    private static let mock = LCUCredentials(port: 61_000, token: "mock-token")
    private static let realClient =
        "/Applications/League of Legends.app/Contents/LoL/LeagueClient.app/Contents/LeagueClientUx.app/Contents/MacOS/LeagueClientUx --app-port=54321 --remote-auth-token=real-token"

    private let clock = ManualSleep()
    private let rest = FakeREST([mock.port: [FakeREST.ok]])
    private let sockets = FakeSockets([FakeWAMPSocket()])

    /// Each read answers with the next scripted lockfile contents; the last one keeps answering.
    private func client(lockfile script: [String?]) -> LCUClient {
        let reads = Mutex(script)
        let discovery = LCUDiscovery(
            lockfilePath: Self.lockfilePath,
            commandLines: { [Self.realClient] },
            readFile: { url in
                guard url.path(percentEncoded: false) == Self.lockfilePath else { return nil }
                return reads.withLock { reads in
                    guard let first = reads.first else { return nil }
                    if reads.count > 1 { reads.removeFirst() }
                    return first
                }
            })
        return LCUClient(
            discovery: discovery,
            makeREST: { [rest] in rest.sender(for: $0) },
            makeSocket: { [sockets] credentials throws(LCUError) in try sockets.open(credentials) },
            sleep: { [clock] in try await clock.sleep(for: $0) })
    }

    private static func lockfile(_ credentials: LCUCredentials) -> String {
        "LeagueClient:999:\(credentials.port):\(credentials.token):https"
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

    @Test func connectsToTheOverrideLockfileAndNotToARunningClient() async {
        let client = client(lockfile: [Self.lockfile(Self.mock)])
        var states = client.states().makeAsyncIterator()
        let running = Task { await client.run() }

        #expect(await Self.next(3, of: &states) == [.searching, .connecting, .connected])
        #expect(sockets.ports == [Self.mock.port])
        #expect(rest.requests.map(\.port) == [Self.mock.port])
        running.cancel()
        await running.value
    }

    @Test func keepsSearchingUntilTheOverrideLockfileAppears() async {
        let client = client(lockfile: [nil, Self.lockfile(Self.mock)])
        var states = client.states().makeAsyncIterator()
        let running = Task { await client.run() }
        var sleeps = clock.requests.makeAsyncIterator()

        #expect(await states.next() == .searching)
        #expect(await sleeps.next() == LCUClient.searchInterval)
        clock.advance()

        #expect(await Self.next(2, of: &states) == [.connecting, .connected])
        #expect(sockets.ports == [Self.mock.port])
        running.cancel()
        await running.value
    }
}
