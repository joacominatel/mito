import Foundation
import Testing

@testable import LCUKit

@Suite(.serialized)
struct LCURESTClientTests {
    private struct Phase: Decodable, Equatable {
        let phase: String
    }

    private static let token = "AbCdEf123-secret"
    private let credentials = LCUCredentials(port: 54_321, token: Self.token)

    private func client(replying reply: StubURLProtocol.Reply) -> LCURESTClient {
        StubURLProtocol.reset(replying: reply)
        return LCURESTClient(
            credentials: credentials, configuration: StubURLProtocol.configuration())
    }

    private func onlyRequest() throws -> StubURLProtocol.Received {
        let received = StubURLProtocol.received
        try #require(received.count == 1, "expected one request, got \(received.count)")
        return received[0]
    }

    private func failure<R>(_ client: LCURESTClient, _ endpoint: LCUEndpoint<R>) async -> LCUError?
    {
        do {
            _ = try await client.send(endpoint)
            return nil
        } catch {
            return error
        }
    }

    @Test func sendsToLoopbackOnTheCredentialsPortOverHTTPS() async throws {
        let client = client(replying: .response(status: 204, body: Data()))
        _ = try await client.send(
            LCUEndpoint<LCUNoContent>(method: .get, path: "/lol-gameflow/v1/gameflow-phase"))

        let url = try #require(try onlyRequest().request.url)
        #expect(url.absoluteString == "https://127.0.0.1:54321/lol-gameflow/v1/gameflow-phase")
    }

    @Test func keepsTheQueryStringOfThePath() async throws {
        let client = client(replying: .response(status: 204, body: Data()))
        _ = try await client.send(
            LCUEndpoint<LCUNoContent>(method: .get, path: "/lol-perks/v1/pages?mine=true"))

        let url = try #require(try onlyRequest().request.url)
        #expect(url.query() == "mine=true")
    }

    @Test(arguments: HTTPMethod.allCases)
    func sendsTheEndpointMethod(_ method: HTTPMethod) async throws {
        let client = client(replying: .response(status: 204, body: Data()))
        _ = try await client.send(LCUEndpoint<LCUNoContent>(method: method, path: "/x"))

        #expect(try onlyRequest().request.httpMethod == method.rawValue)
    }

    @Test func authenticatesWithBasicAuthAsRiot() async throws {
        let client = client(replying: .response(status: 204, body: Data()))
        _ = try await client.send(LCUEndpoint<LCUNoContent>(method: .get, path: "/x"))

        let expected = "Basic " + Data("riot:\(Self.token)".utf8).base64EncodedString()
        let request = try onlyRequest().request
        #expect(request.value(forHTTPHeaderField: "Authorization") == expected)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func sendsAJSONBodyAsJSON() async throws {
        let client = client(replying: .response(status: 204, body: Data()))
        _ = try await client.send(
            try LCUEndpoint<LCUNoContent>(
                method: .patch, path: "/lol-champ-select/v1/session/my-selection",
                json: ["spell1Id": 4]))

        let received = try onlyRequest()
        #expect(received.body == Data(#"{"spell1Id":4}"#.utf8))
        #expect(received.request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func aRequestWithoutABodySendsNoBodyOrContentType() async throws {
        let client = client(replying: .response(status: 204, body: Data()))
        _ = try await client.send(LCUEndpoint<LCUNoContent>(method: .post, path: "/x"))

        let received = try onlyRequest()
        #expect(received.body == nil)
        #expect(received.request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test func decodesASuccessfulResponse() async throws {
        let client = client(
            replying: .response(status: 200, body: Data(#"{"phase": "Lobby", "extra": 1}"#.utf8)))
        let phase = try await client.send(LCUEndpoint<Phase>(method: .get, path: "/x"))

        #expect(phase == Phase(phase: "Lobby"))
    }

    @Test func aNoContentEndpointAcceptsAnEmpty204() async throws {
        let client = client(replying: .response(status: 204, body: Data()))
        let result = try await client.send(
            LCUEndpoint<LCUNoContent>(
                method: .post, path: "/lol-matchmaking/v1/ready-check/accept"))

        #expect(result == LCUNoContent())
    }

    @Test func aNonSuccessStatusIsAnHTTPErrorCarryingTheBody() async {
        let body = Data(#"{"errorCode": "RPC_ERROR", "httpStatus": 404}"#.utf8)
        let client = client(replying: .response(status: 404, body: body))
        let error = await failure(client, LCUEndpoint<Phase>(method: .get, path: "/x"))

        #expect(error == .http(status: 404, body: body))
    }

    @Test func aMalformedBodyIsADecodingError() async {
        let client = client(replying: .response(status: 200, body: Data("[]".utf8)))
        let error = await failure(client, LCUEndpoint<Phase>(method: .get, path: "/x"))

        guard case .decoding = error else {
            Issue.record("expected a decoding error, got \(String(describing: error))")
            return
        }
    }

    @Test func aRefusedConnectionIsATransportError() async {
        let client = client(replying: .failure(.cannotConnectToHost))
        let error = await failure(client, LCUEndpoint<Phase>(method: .get, path: "/x"))

        guard case .transport = error else {
            Issue.record("expected a transport error, got \(String(describing: error))")
            return
        }
    }

    @Test(arguments: ["@example.com/x", "x", ""])
    func aPathThatDoesNotStartWithASlashIsRejectedUnsent(_ path: String) async {
        let client = client(replying: .response(status: 204, body: Data()))
        let error = await failure(client, LCUEndpoint<LCUNoContent>(method: .get, path: path))

        guard case .encoding = error else {
            Issue.record("expected an encoding error, got \(String(describing: error))")
            return
        }
        #expect(StubURLProtocol.received.isEmpty)
    }

    @Test(arguments: [
        StubURLProtocol.Reply.failure(.cannotConnectToHost),
        .failure(.serverCertificateUntrusted),
        .response(status: 500, body: Data()),
        .response(status: 200, body: Data("not json".utf8)),
    ])
    func errorsNeverCarryTheToken(_ reply: StubURLProtocol.Reply) async throws {
        let client = client(replying: reply)
        let error = try #require(
            await failure(client, LCUEndpoint<Phase>(method: .get, path: "/x")))

        let authHeader = Data("riot:\(Self.token)".utf8).base64EncodedString()
        for text in [String(describing: error), String(reflecting: error)] {
            #expect(!text.contains(Self.token))
            #expect(!text.contains(authHeader))
        }
    }
}
