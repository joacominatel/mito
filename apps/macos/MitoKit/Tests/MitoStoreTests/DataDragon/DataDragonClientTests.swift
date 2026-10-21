import Foundation
import Testing

@testable import MitoStore

/// Mirrors `MitoAssets.DataDragonTransport`, which this target cannot import: if this stops
/// compiling, the app's one-line conformance stops compiling too.
private protocol DataDragonTransportShape: Sendable {
    func data(from url: URL) async throws -> Data
}

extension DataDragonClient: DataDragonTransportShape {}

@Suite(.serialized)
struct DataDragonClientTests {
    private static let iconURL = URL(
        string: "https://ddragon.leagueoflegends.com/cdn/14.23.1/img/champion/Ahri.png")

    private func client(replying reply: StubURLProtocol.Reply) -> DataDragonClient {
        StubURLProtocol.reset(replying: reply)
        return DataDragonClient(configuration: StubURLProtocol.configuration())
    }

    private func failure(_ client: DataDragonClient, _ url: URL) async -> DataDragonError? {
        do {
            _ = try await client.data(from: url)
            return nil
        } catch {
            return error
        }
    }

    @Test func aSuccessfulResponseReturnsTheBodyBytes() async throws {
        let body = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])
        let client = client(replying: .response(status: 200, body: body))

        #expect(try await client.data(from: #require(Self.iconURL)) == body)
    }

    @Test func requestsTheExactURLWithAGet() async throws {
        let url = try #require(Self.iconURL)
        _ = try await client(replying: .response(status: 200, body: Data())).data(from: url)

        let received = StubURLProtocol.received
        try #require(received.count == 1)
        #expect(received[0].url == url)
        #expect(received[0].httpMethod == "GET")
    }

    @Test func anUpperCaseHostIsTheSameHost() async throws {
        let url = try #require(
            URL(string: "https://DDragon.LeagueOfLegends.com/cdn/16.21.1/img/x.png"))
        let bytes = Data([1, 2, 3])
        #expect(
            try await client(replying: .response(status: 200, body: bytes)).data(from: url) == bytes
        )
    }

    @Test(arguments: [404, 500])
    func aNon2xxStatusThrowsWithTheStatus(_ status: Int) async throws {
        let client = client(replying: .response(status: status, body: Data("nope".utf8)))

        #expect(await failure(client, try #require(Self.iconURL)) == .http(status: status))
    }

    @Test func aTransportFailureThrows() async throws {
        let client = client(replying: .failure(.notConnectedToInternet))

        guard case .transport = await failure(client, try #require(Self.iconURL)) else {
            Issue.record("expected a transport error")
            return
        }
    }

    @Test(arguments: [
        "http://ddragon.leagueoflegends.com/cdn/14.23.1/img/champion/Ahri.png",
        "https://raw.communitydragon.org/latest/game/assets/ahri.png",
        "https://ddragon.leagueoflegends.com.evil.example/cdn/a.png",
        "https://evil-ddragon.leagueoflegends.com/cdn/a.png",
        "https://ddragon.leagueoflegends.com:443/cdn/a.png",
        "https://user@ddragon.leagueoflegends.com/cdn/a.png",
        "https://user:pass@ddragon.leagueoflegends.com/cdn/a.png",
        "https://ddragon.leagueoflegends.com@evil.example/cdn/a.png",
    ])
    func aURLOffTheAllowlistIsRefusedWithoutARequest(_ string: String) async throws {
        let url = try #require(URL(string: string))
        let client = client(replying: .response(status: 200, body: Data()))

        #expect(await failure(client, url) == .refused(url))
        #expect(StubURLProtocol.received.isEmpty)
    }

    @Test func aRedirectOffTheAllowlistIsNotFollowed() async throws {
        let elsewhere = try #require(URL(string: "https://evil.example/a.png"))
        let client = client(replying: .redirect(to: elsewhere))

        #expect(await failure(client, try #require(Self.iconURL)) == .http(status: 302))
        #expect(StubURLProtocol.received.map(\.url) == [Self.iconURL])
    }
}
