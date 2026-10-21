public import Foundation

/// Fetches a Data Dragon file. Throws for a non-2xx response; the loader has already checked
/// that the URL is HTTPS on `ddragon.leagueoflegends.com`.
public protocol DataDragonTransport: Sendable {
    func data(from url: URL) async throws -> Data
}
