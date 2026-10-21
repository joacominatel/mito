import Foundation
import MitoCore
import MitoStore
import SwiftUI
import Testing

@testable import Mito

struct SettingsWiringTests {
    @Test func loadsThePersistedSettingsAtStart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(bundleIdentifier: "tests", baseDirectory: directory)
        var persisted = MitoSettings()
        persisted.game.autoAccept = .off
        try await store.save(persisted)
        let app = makeApp(persistence: store)
        #expect(app.settings == MitoSettings())

        await app.start()

        #expect(app.settings == persisted)
    }

    @Test func loadingDoesNotWriteTheSettingsBack() async {
        let persistence = RecordingPersistence()
        let app = makeApp(persistence: persistence)

        await app.start()

        #expect(app.settingsModel.pendingSave == nil)
        #expect(await persistence.saves.isEmpty)
    }

    @Test func savesAChangeAfterTheDebounce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SettingsStore(bundleIdentifier: "tests", baseDirectory: directory)
        let app = makeApp(persistence: store)
        await app.start()

        app.settings.game.autoAcceptDelaySeconds = 5
        await app.settingsModel.pendingSave?.value

        #expect(await store.load().game.autoAcceptDelaySeconds == 5)
    }

    @Test func rapidChangesSaveOnceWithTheLastValue() async {
        let persistence = RecordingPersistence()
        let app = makeApp(persistence: persistence)
        await app.start()

        for balance in [0.1, 0.2, 0.3, 0.4] {
            app.settings.champSelect.metaComfortBalance = balance
        }
        await app.settingsModel.pendingSave?.value

        #expect(await persistence.saves.map(\.champSelect.metaComfortBalance) == [0.4])
    }

    @Test func aBindingWriteIsSaved() async {
        let persistence = RecordingPersistence()
        let app = makeApp(persistence: persistence)
        await app.start()

        Bindable(app).settings.importing.importRunes.wrappedValue = false
        await app.settingsModel.pendingSave?.value

        #expect(await persistence.saves.map(\.importing.importRunes) == [false])
    }

    @Test func featureModelsReadTheCurrentSettings() {
        let app = makeApp(persistence: nil)

        app.settings.game.autoAccept = .selectedQueues
        app.settings.champSelect.autoHover = true
        app.settings.importing.flashPosition = .f

        #expect(app.gameflow.settings().autoAccept == .selectedQueues)
        #expect(app.champSelect.settings().autoHover)
        #expect(app.importing.settings().flashPosition == .f)
    }

    @Test func aFailedSaveKeepsTheInMemoryValue() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // A file where the settings folder should be makes every save fail.
        try Data().write(to: directory.appending(path: "blocked"))
        let store = SettingsStore(bundleIdentifier: "blocked", baseDirectory: directory)
        let app = makeApp(persistence: store)
        await app.start()

        app.settings.general.showDockIcon = true
        await app.settingsModel.pendingSave?.value

        #expect(app.settings.general.showDockIcon)
        await #expect(throws: StoreError.settingsNotSaved) { try await store.save(app.settings) }
    }

    private func makeApp(persistence: (any SettingsPersistence)?) -> AppModel {
        AppModel(
            connection: ScriptedLCUConnection(script: []),
            settings: SettingsModel(persistence: persistence, saveDelay: .milliseconds(10)))
    }
}

private actor RecordingPersistence: SettingsPersistence {
    private(set) var saves: [MitoSettings] = []

    func load() -> MitoSettings { MitoSettings() }

    func save(_ settings: MitoSettings) {
        saves.append(settings)
    }
}

private func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "MitoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
