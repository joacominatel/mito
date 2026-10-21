import Foundation
import os

/// One discovery attempt (`MITO_CONTEXT.md` §10.1): process arguments first, then the lockfile.
/// Polling and backoff belong to the connection lifecycle (§10.2).
struct LCUDiscovery: Sendable {
    static let defaultInstallPath = "/Applications/League of Legends.app"

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.joacominatel.mito", category: "LCUKit")

    private let searchesProcesses: Bool
    private let lockfileURLs: @Sendable () async -> [URL]
    private let commandLines: @Sendable () async -> [String]
    private let readFile: @Sendable (URL) async -> String?

    init(
        installPath: String? = nil,
        commandLines: @escaping @Sendable () async -> [String] = runningCommandLines,
        readFile: @escaping @Sendable (URL) async -> String? = contents(of:)
    ) {
        self.init(
            installPath: { installPath }, commandLines: commandLines, readFile: readFile)
    }

    /// Reads `installPath()` on every attempt, so a changed setting applies to the next one. Its
    /// lockfile goes first; the default install's lockfile backs it up when it is missing or
    /// unreadable.
    init(
        installPath: @escaping @Sendable () async -> String?,
        commandLines: @escaping @Sendable () async -> [String] = runningCommandLines,
        readFile: @escaping @Sendable (URL) async -> String? = contents(of:)
    ) {
        self.searchesProcesses = true
        self.lockfileURLs = {
            let paths = [await installPath(), Self.defaultInstallPath].compactMap(\.self)
            var urls: [URL] = []
            for path in paths {
                let url = URL(filePath: path).appending(path: "Contents/LoL/lockfile")
                if !urls.contains(url) { urls.append(url) }
            }
            return urls
        }
        self.commandLines = commandLines
        self.readFile = readFile
    }

    /// Reads only `lockfilePath` and never lists processes, so a running client cannot win
    /// over `tools/lcu-mock` (§10.2).
    init(
        lockfilePath: String,
        commandLines: @escaping @Sendable () async -> [String] = runningCommandLines,
        readFile: @escaping @Sendable (URL) async -> String? = contents(of:)
    ) {
        let url = URL(filePath: lockfilePath)
        self.searchesProcesses = false
        self.lockfileURLs = { [url] }
        self.commandLines = commandLines
        self.readFile = readFile
    }

    /// `nil` when no client is running.
    func discover() async -> LCUCredentials? {
        if searchesProcesses, let found = await fromProcessArguments() { return found }
        for url in await lockfileURLs() {
            if let found = await fromLockfile(at: url) { return found }
        }
        return nil
    }

    private func fromLockfile(at url: URL) async -> LCUCredentials? {
        guard let contents = await readFile(url) else { return nil }
        guard let found = Lockfile.credentials(fromContents: contents) else {
            Self.logger.notice("Lockfile present but unreadable as credentials")
            return nil
        }
        let port = found.port
        Self.logger.info("Client found in lockfile, port \(port, privacy: .public)")
        return found
    }

    private func fromProcessArguments() async -> LCUCredentials? {
        for line in await commandLines() {
            if let found = ProcessArguments.credentials(fromCommandLine: line) {
                let port = found.port
                Self.logger.info(
                    "Client found in process arguments, port \(port, privacy: .public)")
                return found
            }
        }
        return nil
    }

    static func port(_ text: String) -> Int? {
        guard let port = Int(text), (1...65_535).contains(port) else { return nil }
        return port
    }

    /// Reads arguments only, through `ps`: no memory access, no hooks (§5).
    @concurrent static func runningCommandLines() async -> [String] {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/ps")
        process.arguments = ["-A", "-ww", "-o", "args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            // Drain before waiting, or a full pipe deadlocks ps.
            let output = try pipe.fileHandleForReading.readToEnd() ?? Data()
            process.waitUntilExit()
            return String(decoding: output, as: UTF8.self).split(separator: "\n").map(String.init)
        } catch {
            logger.error(
                "Listing processes failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    @concurrent static func contents(of url: URL) async -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }
}
