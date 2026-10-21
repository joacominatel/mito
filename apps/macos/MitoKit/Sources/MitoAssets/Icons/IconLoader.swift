public import Foundation
public import LCUKit
import MitoCore
import os

/// Cancelling one caller never cancels the fetch it shares with others; it just waits it out.
public actor IconLoader {
    public static let fallbackBundleIdentifier = "com.joacominatel.mito"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier, category: "MitoAssets")

    private struct Flight {
        let task: Task<Result<Data, IconError>, Never>
        var callers: Int
    }

    public nonisolated let directory: URL
    private let connection: any LCUConnection
    private let dataDragon: (any DataDragonTransport)?
    private var flights: [URL: Flight] = [:]
    private var versions: Task<[String]?, Never>?

    public init(
        connection: any LCUConnection,
        dataDragon: (any DataDragonTransport)? = nil,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        baseDirectory: URL = .cachesDirectory
    ) {
        self.connection = connection
        self.dataDragon = dataDragon
        directory =
            baseDirectory
            .appending(
                path: bundleIdentifier ?? Self.fallbackBundleIdentifier, directoryHint: .isDirectory
            )
            .appending(path: "icons", directoryHint: .isDirectory)
    }

    public func icon(for request: IconRequest) async throws(IconError) -> Data {
        let file = cacheFile(for: request)
        let task: Task<Result<Data, IconError>, Never>
        if var flight = flights[file] {
            flight.callers += 1
            flights[file] = flight
            task = flight.task
        } else {
            task = Task { [connection, dataDragon] in
                await Self.resolve(
                    request, file: file, connection: connection, dataDragon: dataDragon,
                    version: { await self.dataDragonVersion(for: $0) })
            }
            flights[file] = Flight(task: task, callers: 1)
        }

        let result = await task.value
        if flights[file]?.task == task { flights[file] = nil }
        return try result.get()
    }

    nonisolated func cacheFile(for request: IconRequest) -> URL {
        request.relativeSegments.reduce(
            directory.appending(path: request.gameVersion, directoryHint: .isDirectory)
        ) { $0.appending(path: String($1), directoryHint: .notDirectory) }
    }

    /// `versions.json` is asked for only when a versioned fallback is needed, then kept for the
    /// loader's life; a failed list is asked for again next time, and meanwhile `<patch>.1` stands in.
    func dataDragonVersion(for patch: Patch) async -> String {
        let task: Task<[String]?, Never>
        if let versions {
            task = versions
        } else if let dataDragon {
            task = Task { await Self.fetchVersions(transport: dataDragon) }
            versions = task
        } else {
            return "\(patch.rawValue).1"
        }
        let list = await task.value
        if list == nil, versions == task { versions = nil }
        return list.flatMap { DataDragonFile.version(for: patch, in: $0) } ?? "\(patch.rawValue).1"
    }

    /// Lets tests release a gated fetch only once every caller has joined it.
    func callers(awaiting request: IconRequest) -> Int {
        flights[cacheFile(for: request)]?.callers ?? 0
    }

    @concurrent
    private static func resolve(
        _ request: IconRequest,
        file: URL,
        connection: any LCUConnection,
        dataDragon: (any DataDragonTransport)?,
        version: @Sendable (Patch) async -> String
    ) async -> Result<Data, IconError> {
        if let cached = try? Data(contentsOf: file), isImage(cached) { return .success(cached) }

        let data: Data
        if let fromClient = await fetchFromClient(request.assetPath, connection: connection) {
            data = fromClient
        } else if let fallback = request.dataDragonFile, let dataDragon,
            let url = await url(for: fallback, version: version),
            let fromDataDragon = await fetchFromDataDragon(url, transport: dataDragon)
        {
            data = fromDataDragon
        } else {
            return .failure(.unavailable(assetPath: request.assetPath))
        }

        store(data, at: file)
        return .success(data)
    }

    private static func fetchFromClient(_ path: String, connection: any LCUConnection) async
        -> Data?
    {
        let endpoint = LCUEndpoint<Data>(method: .get, path: path) { $0 }
        do {
            let data = try await connection.send(endpoint)
            if isImage(data) { return data }
            logger.debug("Client icon is not an image: \(path, privacy: .public)")
        } catch {
            logger.debug("Client icon failed: \(path, privacy: .public)")
        }
        return nil
    }

    private static func fetchFromDataDragon(_ url: URL, transport: any DataDragonTransport) async
        -> Data?
    {
        do {
            let data = try await transport.data(from: url)
            if isImage(data) { return data }
            logger.debug("Data Dragon icon is not an image: \(url.path(), privacy: .public)")
        } catch {
            logger.debug("Data Dragon icon failed: \(url.path(), privacy: .public)")
        }
        return nil
    }

    private static func url(
        for file: DataDragonFile, version: @Sendable (Patch) async -> String
    ) async -> URL? {
        guard let patch = file.patch else { return file.url(version: nil) }
        return file.url(version: await version(patch))
    }

    private static func fetchVersions(transport: any DataDragonTransport) async -> [String]? {
        do {
            guard let url = DataDragonFile.versionsURL else { return nil }
            return try JSONDecoder().decode([String].self, from: await transport.data(from: url))
        } catch {
            logger.debug("Data Dragon versions failed")
            return nil
        }
    }

    /// A failed write only costs a refetch next time.
    private static func store(_ data: Data, at file: URL) {
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            logger.debug("Icon not cached: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// Without decoding, a file whose bytes are not PNG, JPEG or WebP is the only corruption we can see.
    private static func isImage(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        return bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            || bytes.starts(with: [0xFF, 0xD8, 0xFF])
            || (bytes.count == 12 && bytes.starts(with: Array("RIFF".utf8))
                && bytes[8...].elementsEqual("WEBP".utf8))
    }
}
