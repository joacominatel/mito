public import Foundation
import os

/// GETs files from Data Dragon and from no other host (`MITO_CONTEXT.md` §5, §16.1). The app
/// hands it to `IconLoader` as its `DataDragonTransport`; caching is the loader's job.
public struct DataDragonClient: Sendable {
    static let host = "ddragon.leagueoflegends.com"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SettingsStore.fallbackBundleIdentifier,
        category: "MitoStore")
    private static let timeout: TimeInterval = 15

    private let session: URLSession

    /// Tests inject a stub through `configuration.protocolClasses`.
    public init(configuration: URLSessionConfiguration = .ephemeral) {
        session = URLSession(configuration: configuration)
    }

    public func data(from url: URL) async throws(DataDragonError) -> Data {
        guard Self.allows(url) else {
            Self.logger.debug("Refused a non-Data Dragon URL")
            throw .refused(url)
        }
        Self.logger.debug("Data Dragon GET \(url.path(), privacy: .public)")

        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: RedirectGuard())
        } catch {
            throw .transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw .transport("the response is not HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw .http(status: http.statusCode)
        }
        return data
    }

    static func allows(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return false
        }
        return components.scheme == "https" && components.percentEncodedHost == host
            && components.port == nil && components.percentEncodedUser == nil
            && components.percentEncodedPassword == nil
    }
}

/// A redirect would otherwise carry the request off the allowlist after the check.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    // The async variant of this requirement crashes the Swift 6.4 compiler.
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(DataDragonClient.allows) == true ? request : nil)
    }
}
