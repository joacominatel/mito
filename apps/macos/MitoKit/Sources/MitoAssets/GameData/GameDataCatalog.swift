public import LCUKit

/// The client's static data, fetched once and kept in memory until `reload()` (a reconnect or a
/// new patch). Concurrent callers share one fetch; a failed fetch is not kept.
public actor GameDataCatalog {
    private let connection: any LCUConnection
    private var current: Task<Result<GameData, LCUError>, Never>?

    public init(connection: any LCUConnection) {
        self.connection = connection
    }

    /// The loaded data, fetching it only if nothing is loaded or loading.
    public func load() async throws(LCUError) -> GameData {
        try await settle(current ?? fetch())
    }

    /// Fetches again; a load already in flight is superseded, and callers waiting on it keep
    /// its result.
    public func reload() async throws(LCUError) -> GameData {
        try await settle(fetch())
    }

    private func fetch() -> Task<Result<GameData, LCUError>, Never> {
        let task = Task { [connection] in await Self.fetchAll(from: connection) }
        current = task
        return task
    }

    private func settle(_ task: Task<Result<GameData, LCUError>, Never>) async throws(LCUError)
        -> GameData
    {
        let result = await task.value
        if case .failure = result, current == task { current = nil }
        return try result.get()
    }

    @concurrent
    private static func fetchAll(from connection: any LCUConnection) async -> Result<
        GameData, LCUError
    > {
        async let champions = send(.gameDataChampions, connection)
        async let items = send(.gameDataItems, connection)
        async let perkStyles = send(.gameDataPerkStyles, connection)
        async let perks = send(.gameDataPerks, connection)
        async let spells = send(.gameDataSummonerSpells, connection)
        let results = await (champions, items, perkStyles, perks, spells)
        do throws(LCUError) {
            return .success(
                GameData(
                    champions: try results.0.get().champions,
                    items: try results.1.get().items,
                    perkStyles: try results.2.get().styles,
                    perks: try results.3.get().perks,
                    spells: try results.4.get().spells))
        } catch {
            return .failure(error)
        }
    }

    private static func send<R>(_ endpoint: LCUEndpoint<R>, _ connection: any LCUConnection)
        async -> Result<R, LCUError>
    {
        do {
            return .success(try await connection.send(endpoint))
        } catch {
            return .failure(error)
        }
    }
}
