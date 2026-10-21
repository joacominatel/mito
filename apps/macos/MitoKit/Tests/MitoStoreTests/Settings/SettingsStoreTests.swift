import Foundation
import MitoCore
import Testing

@testable import MitoStore

struct SettingsStoreTests {
    private static let bundleIdentifier = "com.joacominatel.mito.tests"

    @Test func aMissingFileLoadsTheDefaults() async throws {
        try await withTemporaryDirectory { base in
            let store = SettingsStore(bundleIdentifier: Self.bundleIdentifier, baseDirectory: base)
            #expect(await store.load() == MitoSettings())
        }
    }

    @Test func savedNonDefaultValuesLoadBack() async throws {
        try await withTemporaryDirectory { base in
            var settings = MitoSettings()
            settings.general.language = .english
            settings.general.leagueInstallPath = "/Applications/League of Legends.app"
            settings.game.autoAcceptDelaySeconds = 7
            settings.champSelect.metaComfortBalance = 0.8
            settings.importing.importSpells = false

            let store = SettingsStore(bundleIdentifier: Self.bundleIdentifier, baseDirectory: base)
            try await store.save(settings)

            let reopened = SettingsStore(
                bundleIdentifier: Self.bundleIdentifier, baseDirectory: base)
            #expect(await reopened.load() == settings)
        }
    }

    @Test func theFileIsPrettyPrintedWithSortedKeys() async throws {
        try await withTemporaryDirectory { base in
            let store = SettingsStore(bundleIdentifier: Self.bundleIdentifier, baseDirectory: base)
            try await store.save(MitoSettings())

            let text = try String(contentsOf: store.fileURL, encoding: .utf8)
            let topLevelKeys = text.split(separator: "\n")
                .filter { $0.hasPrefix("  \"") }
                .map { $0.drop { $0 == " " }.prefix { $0 != " " } }
            #expect(
                topLevelKeys == [#""champSelect""#, #""game""#, #""general""#, #""importing""#])
        }
    }

    @Test func unknownAndMissingKeysInTheFileAreTolerated() async throws {
        try await withTemporaryDirectory { base in
            let store = SettingsStore(bundleIdentifier: Self.bundleIdentifier, baseDirectory: base)
            try write(
                #"{"fromTheFuture": true, "game": {"autoAcceptDelaySeconds": 4, "newToggle": 1}}"#,
                to: store.fileURL)

            let settings = await store.load()
            #expect(settings.game.autoAcceptDelaySeconds == 4)
            #expect(settings.general == GeneralSettings())
            #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        }
    }

    @Test func aCorruptFileLoadsTheDefaultsAndIsMovedAsideIntact() async throws {
        try await withTemporaryDirectory { base in
            let store = SettingsStore(bundleIdentifier: Self.bundleIdentifier, baseDirectory: base)
            let garbage = #"{"general": {"launchAtLogin": tr"#
            try write(garbage, to: store.fileURL)

            #expect(await store.load() == MitoSettings())

            let directory = store.fileURL.deletingLastPathComponent()
            let movedAside = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            ).filter {
                $0.lastPathComponent.hasPrefix("settings.corrupt-") && $0.pathExtension == "json"
            }
            #expect(movedAside.count == 1)
            #expect(try movedAside.map { try String(contentsOf: $0, encoding: .utf8) } == [garbage])
            #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        }
    }

    @Test func anUnreadableFileLoadsTheDefaultsAndIsMovedAside() async throws {
        try await withTemporaryDirectory { base in
            let store = SettingsStore(bundleIdentifier: Self.bundleIdentifier, baseDirectory: base)
            try FileManager.default.createDirectory(
                at: store.fileURL, withIntermediateDirectories: true)

            #expect(await store.load() == MitoSettings())

            let names = try FileManager.default.contentsOfDirectory(
                atPath: store.fileURL.deletingLastPathComponent().path)
            #expect(names.count == 1)
            #expect(names.allSatisfy { $0.hasPrefix("settings.corrupt-") })
        }
    }

    @Test func savingCreatesTheMissingDirectory() async throws {
        try await withTemporaryDirectory { base in
            let nestedBase = base.appending(
                path: "Application Support", directoryHint: .isDirectory)
            let store = SettingsStore(
                bundleIdentifier: Self.bundleIdentifier, baseDirectory: nestedBase)
            try await store.save(MitoSettings())

            #expect(
                store.fileURL
                    == nestedBase.appending(path: "\(Self.bundleIdentifier)/settings.json"))
            #expect(FileManager.default.fileExists(atPath: store.fileURL.path))
        }
    }

    @Test func eachBundleIdentifierGetsItsOwnFile() async throws {
        try await withTemporaryDirectory { base in
            let release = SettingsStore(
                bundleIdentifier: "com.joacominatel.mito", baseDirectory: base)
            let debug = SettingsStore(
                bundleIdentifier: "com.joacominatel.mito.debug", baseDirectory: base)
            var debugSettings = MitoSettings()
            debugSettings.general.showDockIcon = true

            try await debug.save(debugSettings)

            #expect(release.fileURL != debug.fileURL)
            #expect(await release.load() == MitoSettings())
            #expect(await debug.load() == debugSettings)
        }
    }

    @Test func concurrentSavesLeaveAValidFileAndTheLastSaveWins() async throws {
        try await withTemporaryDirectory { base in
            let store = SettingsStore(bundleIdentifier: Self.bundleIdentifier, baseDirectory: base)
            let delays = 1...50

            try await withThrowingTaskGroup { group in
                for delay in delays {
                    group.addTask {
                        var settings = MitoSettings()
                        settings.game.autoAcceptDelaySeconds = delay
                        try await store.save(settings)
                    }
                }
                try await group.waitForAll()
            }
            let data = try Data(contentsOf: store.fileURL)
            let afterRace = try JSONDecoder().decode(MitoSettings.self, from: data)
            #expect(delays.contains(afterRace.game.autoAcceptDelaySeconds))

            var last = MitoSettings()
            last.game.autoAcceptDelaySeconds = 99
            try await store.save(last)
            #expect(await store.load() == last)
        }
    }

    @Test func aFailedSaveThrowsSettingsNotSaved() async throws {
        try await withTemporaryDirectory { base in
            let blocker = base.appending(path: "blocker", directoryHint: .notDirectory)
            try write("not a directory", to: blocker)
            let store = SettingsStore(
                bundleIdentifier: Self.bundleIdentifier, baseDirectory: blocker)

            await #expect(throws: StoreError.settingsNotSaved) {
                try await store.save(MitoSettings())
            }
        }
    }

    @Test func aMissingBundleIdentifierFallsBackToTheReleaseIdentifier() {
        let base = URL(filePath: "/base", directoryHint: .isDirectory)
        let store = SettingsStore(bundleIdentifier: nil, baseDirectory: base)
        #expect(store.fileURL == base.appending(path: "com.joacominatel.mito/settings.json"))
    }
}

private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

private func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "SettingsStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
}
