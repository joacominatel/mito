import Foundation
import LCUKit
import MitoAssets
import MitoCore
import MitoTestSupport
import Testing

struct GameDataCatalogTests {
    private static let files = [
        "champion-summary", "items", "perkstyles", "perks", "summoner-spells",
    ]

    private static func path(_ file: String) -> String {
        "/lol-game-data/assets/v1/\(file).json"
    }

    private static func response(_ file: String, case name: String? = nil) throws
        -> FakeLCUConnection.Response
    {
        .init(
            method: .get, path: path(file),
            body: try Data(contentsOf: Fixtures.url("lcu/cases/assets/\(name ?? file).json")))
    }

    /// Every file answers with its trimmed fixture; `extra` responses are served after those.
    private static func client(then extra: [FakeLCUConnection.Response] = []) throws
        -> FakeLCUConnection
    {
        FakeLCUConnection(responses: try files.map { try response($0) } + extra)
    }

    @Test func loadFetchesEachFileOnce() async throws {
        let connection = try Self.client()
        _ = try await GameDataCatalog(connection: connection).load()
        #expect(Set(connection.requests.map(\.path)) == Set(Self.files.map(Self.path)))
        #expect(connection.requests.count == 5)
        #expect(connection.writes.isEmpty)
    }

    @Test func loadBuildsTheLookupsFromTheClientFiles() async throws {
        let data = try await GameDataCatalog(connection: Self.client()).load()
        #expect(data.champion(ChampionID(rawValue: 103))?.alias == "Ahri")
        #expect(data.item(ItemID(rawValue: 3157))?.totalGold == 3250)
        #expect(data.perk(PerkID(rawValue: 8112))?.name == "Electrocute")
        #expect(data.perkStyle(PerkStyleID(rawValue: 8200))?.name == "Sorcery")
        #expect(data.spell(SummonerSpellID(rawValue: 4))?.name == "Flash")
        #expect(data.perkStyles.map(\.id.rawValue) == [8100, 8200])
    }

    @Test func aSecondLoadMakesNoRequest() async throws {
        let connection = try Self.client()
        let catalog = GameDataCatalog(connection: connection)
        let first = try await catalog.load()
        let second = try await catalog.load()
        #expect(first == second)
        #expect(connection.requests.count == 5)
    }

    @Test func concurrentLoadsShareOneFetch() async throws {
        let connection = try Self.client()
        let catalog = GameDataCatalog(connection: connection)
        async let first = catalog.load()
        async let second = catalog.load()
        #expect(try await first == second)
        #expect(connection.requests.count == 5)
    }

    @Test func reloadFetchesAgainAndReplacesTheData() async throws {
        let connection = try Self.client(then: [
            try Self.response("champion-summary", case: "champion-summary-malformed")
        ])
        let catalog = GameDataCatalog(connection: connection)
        #expect(try await catalog.load().champion(ChampionID(rawValue: -1)) != nil)

        let reloaded = try await catalog.reload()
        #expect(connection.requests.count == 10)
        #expect(reloaded.champion(ChampionID(rawValue: -1)) == nil)
        #expect(try await catalog.load() == reloaded)
        #expect(connection.requests.count == 10)
    }

    @Test func anLCUFailureIsThrownAsLCUError() async throws {
        let failing = FakeLCUConnection.Response(
            method: .get, path: Self.path("items"), status: 500, json: #"{"message":"boom"}"#)
        let responses = try Self.files.filter { $0 != "items" }.map { try Self.response($0) }
        let catalog = GameDataCatalog(
            connection: FakeLCUConnection(responses: responses + [failing]))
        await #expect(throws: LCUError.http(status: 500, body: Data(#"{"message":"boom"}"#.utf8))) {
            try await catalog.load()
        }
    }

    @Test func aMissingFileIsThrownAsANotFound() async throws {
        let responses = try Self.files.filter { $0 != "perks" }.map { try Self.response($0) }
        let catalog = GameDataCatalog(connection: FakeLCUConnection(responses: responses))
        await #expect(throws: LCUError.http(status: 404, body: Data())) {
            try await catalog.load()
        }
    }

    @Test func aFailedLoadIsRetriedOnTheNextLoad() async throws {
        let failing = FakeLCUConnection.Response(
            method: .get, path: Self.path("items"), status: 503)
        let responses = try Self.files.map { file in
            file == "items" ? failing : try Self.response(file)
        }
        let connection = FakeLCUConnection(responses: responses + [try Self.response("items")])
        let catalog = GameDataCatalog(connection: connection)
        await #expect(throws: LCUError.self) { try await catalog.load() }

        let data = try await catalog.load()
        #expect(data.item(ItemID(rawValue: 1001))?.name == "Boots")
        #expect(connection.requests.count == 10)
    }

}
