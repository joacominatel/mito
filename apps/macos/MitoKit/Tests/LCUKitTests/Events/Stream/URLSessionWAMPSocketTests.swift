import Foundation
import Testing

@testable import LCUKit

@Suite(.timeLimit(.minutes(1)))
struct URLSessionWAMPSocketTests {
    private let credentials = LCUCredentials(port: 54_321, token: "AbCdEf123-secret")

    // Port 1 on loopback refuses the connection; nothing leaves the machine.
    @Test func aRefusedConnectionFinishesEveryStream() async throws {
        let hub = try LCUEventStream(credentials: LCUCredentials(port: 1, token: "unused"))
        let stream = hub.events([.gameflowPhase])

        await hub.run()

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }

    @Test func connectsToLoopbackOnTheCredentialsPortOverWSS() throws {
        let request = try URLSessionWAMPSocket.request(credentials)

        #expect(request.url?.absoluteString == "wss://127.0.0.1:54321/")
    }

    @Test func authenticatesAsRiotWithTheToken() throws {
        let request = try URLSessionWAMPSocket.request(credentials)

        let expected = "Basic " + Data("riot:AbCdEf123-secret".utf8).base64EncodedString()
        #expect(request.value(forHTTPHeaderField: "Authorization") == expected)
    }

    @Test func negotiatesTheWAMPSubprotocol() throws {
        let request = try URLSessionWAMPSocket.request(credentials)

        #expect(request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "wamp")
    }
}
