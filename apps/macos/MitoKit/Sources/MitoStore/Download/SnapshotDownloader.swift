public import Foundation
public import MitoCore
import os

/// An actor so hashing and xz decoding stay off the main actor and installs never interleave.
public actor SnapshotDownloader {
    /// The R2 bucket does not exist yet; `.invalid` never resolves.
    public static let placeholderBaseURL = "https://snapshots.mito.invalid/"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? SettingsStore.fallbackBundleIdentifier,
        category: "MitoStore")
    private static let manifestSizeLimit = 1024 * 1024
    private static let timeout: TimeInterval = 30

    public nonisolated let manifestURL: URL
    /// `<caches>/<bundle id>/snapshots`, so Debug and Release never share a file.
    public nonisolated let cacheDirectory: URL

    private let supportedSchemaVersions: ClosedRange<Int>
    private let decompressedSizeLimit: Int
    private let session: URLSession
    private let cache: SnapshotCache

    /// Tests inject a stub through `configuration.protocolClasses`.
    public init(
        baseURL: String = SnapshotDownloader.placeholderBaseURL,
        supportedSchemaVersions: ClosedRange<Int> = 1...1,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        cachesDirectory: URL = .cachesDirectory,
        configuration: URLSessionConfiguration = .ephemeral
    ) throws(SnapshotDownloadError) {
        try self.init(
            baseURL: baseURL, supportedSchemaVersions: supportedSchemaVersions,
            bundleIdentifier: bundleIdentifier, cachesDirectory: cachesDirectory,
            configuration: configuration,
            decompressedSizeLimit: SnapshotArchive.decompressedSizeLimit)
    }

    init(
        baseURL: String,
        supportedSchemaVersions: ClosedRange<Int>,
        bundleIdentifier: String?,
        cachesDirectory: URL,
        configuration: URLSessionConfiguration,
        decompressedSizeLimit: Int
    ) throws(SnapshotDownloadError) {
        guard let base = URL(string: baseURL), Self.isHTTPS(base) else { throw .insecureURL }
        manifestURL = base.appending(path: "manifest.json", directoryHint: .notDirectory)
        cacheDirectory =
            cachesDirectory
            .appending(
                path: bundleIdentifier ?? SettingsStore.fallbackBundleIdentifier,
                directoryHint: .isDirectory
            )
            .appending(path: "snapshots", directoryHint: .isDirectory)
        self.supportedSchemaVersions = supportedSchemaVersions
        self.decompressedSizeLimit = decompressedSizeLimit
        session = URLSession(configuration: configuration)
        cache = SnapshotCache(root: cacheDirectory)
    }

    /// Reads only the disk; `nil` means the degraded mode of `MITO_CONTEXT.md` §20.3.
    public func installedSnapshot(queue: QueueID, bracket: Bracket) -> InstalledSnapshot? {
        cache.installed(queue: queue, bracket: bracket, schemaVersions: supportedSchemaVersions)?
            .snapshot
    }

    /// On any error the previously installed file stays where it was.
    public func installCurrent(queue: QueueID, bracket: Bracket)
        async throws(SnapshotDownloadError) -> InstalledSnapshot
    {
        let manifestData: Data
        do {
            manifestData = try await fetch(manifestURL, limit: Self.manifestSizeLimit)
        } catch .tooLarge {
            throw .manifestInvalid
        } catch {
            throw .manifestUnreachable(error.description)
        }
        let manifest = try SnapshotManifest.decode(manifestData)
        guard
            let entry = manifest.entry(
                queue: queue, bracket: bracket, supportedSchemaVersions: supportedSchemaVersions)
        else { throw .noMatchingSnapshot }

        if let hit = cache.installed(
            queue: queue, bracket: bracket,
            schemaVersions: entry.schemaVersion...entry.schemaVersion),
            hit.snapshot.patch.rawValue == entry.patch, hit.sha256 == entry.sha256.lowercased(),
            Self.fileSize(hit.snapshot.fileURL) == entry.rawBytes
        {
            Self.logger.debug("Snapshot \(entry.patch, privacy: .public) already current")
            return hit.snapshot
        }

        guard Self.isHTTPS(entry.url) else { throw .insecureURL }
        guard entry.bytes <= SnapshotArchive.compressedSizeLimit,
            entry.rawBytes <= decompressedSizeLimit
        else { throw .sizeLimitExceeded }

        let compressed: Data
        do {
            compressed = try await fetch(entry.url, limit: entry.bytes)
        } catch .tooLarge(let received) {
            throw .sizeMismatch(expected: entry.bytes, actual: received)
        } catch {
            throw .downloadFailed(error.description)
        }
        try SnapshotArchive.verify(compressed, bytes: entry.bytes, sha256: entry.sha256)
        let sqlite = try SnapshotArchive.decompress(compressed, limit: decompressedSizeLimit)
        guard sqlite.count == entry.rawBytes else {
            throw .decompressedSizeMismatch(expected: entry.rawBytes, actual: sqlite.count)
        }

        let installed = try cache.install(sqlite, entry: entry, queue: queue, bracket: bracket)
        cache.removeAll(queue: queue, bracket: bracket, except: installed.fileURL)
        Self.logger.notice(
            "Installed snapshot \(entry.patch, privacy: .public) for queue \(queue.rawValue, privacy: .public)"
        )
        return installed
    }

    private enum FetchFailure: Error, CustomStringConvertible {
        case transport(String)
        case http(status: Int)
        /// How many bytes had arrived when the limit was passed.
        case tooLarge(Int)

        var description: String {
            switch self {
            case .transport(let reason): reason
            case .http(let status): "HTTP \(status)"
            case .tooLarge(let received): "more than expected (\(received) bytes)"
            }
        }
    }

    /// Stops reading one byte past `limit`, so an oversized body is cut off instead of buffered.
    private func fetch(_ url: URL, limit: Int) async throws(FetchFailure) -> Data {
        var request = URLRequest(
            url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = "GET"
        do {
            let (bytes, response) = try await session.bytes(for: request, delegate: HTTPSOnly())
            guard let http = response as? HTTPURLResponse else {
                throw FetchFailure.transport("the response is not HTTP")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw FetchFailure.http(status: http.statusCode)
            }
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > limit { throw FetchFailure.tooLarge(body.count) }
            }
            return body
        } catch let failure as FetchFailure {
            throw failure
        } catch {
            throw .transport(error.localizedDescription)
        }
    }

    private static func isHTTPS(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host(percentEncoded: true)?.isEmpty == false
    }

    private static func fileSize(_ url: URL) -> Int? {
        try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
    }
}

/// A redirect would otherwise be followed to plain HTTP after the scheme check.
private final class HTTPSOnly: NSObject, URLSessionTaskDelegate, Sendable {
    // The async variant of this requirement crashes the Swift 6.4 compiler.
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }
}
