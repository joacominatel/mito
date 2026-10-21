import Foundation
import LCUKit
import Testing

@testable import Mito

@Suite(.timeLimit(.minutes(1)))
struct LCUWiringTests {
    private static func withDefaults(_ body: (UserDefaults) async throws -> Void) async throws {
        let suite = "MitoTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await body(defaults)
    }

    #if DEBUG
        @Test func debugReadsTheLockfileOverrideFromDefaults() async throws {
            try await Self.withDefaults { defaults in
                defaults.set("/tmp/lcu-mock/lockfile", forKey: AppModel.lockfileOverrideKey)
                #expect(AppModel.lockfileOverride(in: defaults) == "/tmp/lcu-mock/lockfile")
            }
        }
    #endif

    @Test func withoutTheKeyThereIsNoOverride() async throws {
        try await Self.withDefaults { defaults in
            #expect(AppModel.lockfileOverride(in: defaults) == nil)
        }
    }

    @Test func underXCTestTheLifecycleNeverRunsTheClient() async throws {
        let lockfile = FileManager.default.temporaryDirectory.appending(
            path: "lockfile-\(UUID().uuidString)")
        try "LeagueClient:1:61000:token:https".write(
            to: lockfile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: lockfile) }
        try await Self.withDefaults { defaults in
            #if DEBUG
                defaults.set(
                    lockfile.path(percentEncoded: false), forKey: AppModel.lockfileOverrideKey)
            #endif
            let client = AppModel.liveClient(defaults: defaults)

            // A running client never returns on its own, so returning proves it never started.
            await AppModel.lifecycle(running: client, underTest: true)()

            var states = client.states().makeAsyncIterator()
            #expect(await states.next() == .searching)
            await #expect(throws: LCUError.notConnected) {
                _ = try await client.send(.currentSummoner)
            }
        }
    }

    /// Release must not read `-MitoLCULockfilePath`; tests build Debug only, so this pins it in
    /// the source: every mention of the key sits in an `#if DEBUG` branch.
    @Test func onlyDebugCodeMentionsTheLockfileOverrideKey() throws {
        let appSources = URL(filePath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appending(path: "Mito")
        let files = try #require(
            FileManager.default.enumerator(at: appSources, includingPropertiesForKeys: nil))
        var mentions = 0
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            var branches: [(condition: String, debugOnly: Bool)] = []
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
            {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("#if ") {
                    let condition = String(code.dropFirst(4))
                    branches.append((condition, condition == "DEBUG"))
                } else if code.hasPrefix("#elseif"), !branches.isEmpty {
                    branches[branches.count - 1].debugOnly = false
                } else if code.hasPrefix("#else"), let last = branches.last {
                    branches[branches.count - 1].debugOnly = last.condition == "!DEBUG"
                } else if code.hasPrefix("#endif"), !branches.isEmpty {
                    branches.removeLast()
                } else if !code.hasPrefix("//"),
                    code.contains("MitoLCULockfilePath") || code.contains("lockfileOverrideKey")
                {
                    mentions += 1
                    if !branches.contains(where: \.debugOnly) {
                        offenders.append("\(url.lastPathComponent):\(index + 1)")
                    }
                }
            }
        }
        #expect(mentions > 0, "No mention found; is \(appSources.path()) the app's sources?")
        #expect(offenders.isEmpty, "Outside #if DEBUG: \(offenders)")
    }
}
