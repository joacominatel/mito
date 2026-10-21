import Foundation
import MitoCore
import MitoStore
import Testing

@testable import Mito

struct UpdaterConfigurationTests {
    private static let key = Data(repeating: 7, count: 32).base64EncodedString()
    private static let feed = "https://updates.example.com/appcast.xml"

    @Test func aReleaseWithAnHTTPSFeedAndAnEd25519KeyIsComplete() {
        #expect(UpdaterConfiguration.isComplete(info: info(), isDebugBuild: false))
    }

    @Test func debugIsNeverCompleteEvenWithARealFeedAndKey() {
        #expect(!UpdaterConfiguration.isComplete(info: info(), isDebugBuild: true))
    }

    @Test func theShippedReleasePlaceholderIsNotComplete() {
        let placeholder = info(feed: "https://updates.mito.invalid/appcast.xml", key: "")
        #expect(!UpdaterConfiguration.isComplete(info: placeholder, isDebugBuild: false))
    }

    @Test(arguments: [
        "https://updates.mito.invalid/appcast.xml",
        "https://UPDATES.MITO.INVALID/appcast.xml",
        "https://invalid/appcast.xml",
    ])
    func aFeedOnAnInvalidHostIsNotComplete(feed: String) {
        #expect(!UpdaterConfiguration.isComplete(info: info(feed: feed), isDebugBuild: false))
    }

    @Test(arguments: ["", "http://updates.example.com/appcast.xml", "not a url", "file:///tmp/a"])
    func aMissingOrNonHTTPSFeedIsNotComplete(feed: String) {
        #expect(!UpdaterConfiguration.isComplete(info: info(feed: feed), isDebugBuild: false))
    }

    @Test(arguments: ["", "   ", "REPLACE_ME", Data(repeating: 1, count: 16).base64EncodedString()])
    func anEmptyOrMalformedKeyIsNotComplete(key: String) {
        #expect(!UpdaterConfiguration.isComplete(info: info(key: key), isDebugBuild: false))
    }

    @Test func missingKeysAreNotComplete() {
        #expect(!UpdaterConfiguration.isComplete(info: nil, isDebugBuild: false))
        #expect(!UpdaterConfiguration.isComplete(info: [:], isDebugBuild: false))
        #expect(
            !UpdaterConfiguration.isComplete(info: ["SUFeedURL": Self.feed], isDebugBuild: false))
    }

    @Test func thisTestBuildIsDebugSoItsOwnPlistIsNeverComplete() {
        #expect(UpdaterConfiguration.isDebugBuild)
        #expect(!UpdaterConfiguration.isComplete(info: Bundle.main.infoDictionary))
    }

    private func info(feed: String = Self.feed, key: String = Self.key) -> [String: Any] {
        ["SUFeedURL": feed, "SUPublicEDKey": key]
    }
}

struct UpdaterModelTests {
    @Test func underXCTestTheUpdaterIsNeverCreated() {
        var created = 0
        let model = UpdaterModel.live(
            settings: SettingsModel(), underTest: true, info: [:],
            makeUpdater: {
                created += 1
                return FakeUpdater()
            })
        model.start()

        #expect(created == 0)
        #expect(!model.isConfigured)
        #expect(!model.canCheckForUpdates)
    }

    @Test func anUnconfiguredBuildNeverCreatesTheUpdater() {
        var created = 0
        let model = UpdaterModel.live(
            settings: SettingsModel(), underTest: false,
            info: ["SUFeedURL": "https://updates.mito.invalid/appcast.xml", "SUPublicEDKey": ""],
            makeUpdater: {
                created += 1
                return FakeUpdater()
            })

        #expect(created == 0)
        #expect(!model.isConfigured)
    }

    @Test func checkingIsDisabledUntilSparkleStartsAndSaysItCan() {
        let updater = FakeUpdater()
        let model = UpdaterModel(updater: updater, settings: SettingsModel())
        #expect(!model.canCheckForUpdates)

        model.start()
        #expect(updater.startCount == 1)
        #expect(!model.canCheckForUpdates)

        updater.canCheckChanged?(true)
        #expect(model.canCheckForUpdates)
    }

    @Test func checkingIsDisabledWhileACheckIsInProgress() {
        let updater = FakeUpdater()
        let model = UpdaterModel(updater: updater, settings: SettingsModel())
        model.start()
        updater.canCheckChanged?(true)

        model.checkForUpdates()
        updater.canCheckChanged?(false)
        model.checkForUpdates()

        #expect(!model.canCheckForUpdates)
        #expect(updater.checks == 1)
    }

    @Test func checkingWithoutAnUpdaterDoesNothing() {
        let model = UpdaterModel(settings: SettingsModel())
        model.start()
        model.checkForUpdates()

        #expect(!model.isConfigured)
        #expect(!model.canCheckForUpdates)
    }

    @Test func startsAtMostOnce() {
        let updater = FakeUpdater()
        let model = UpdaterModel(updater: updater, settings: SettingsModel())

        model.start()
        model.start()

        #expect(updater.startCount == 1)
    }

    @Test func startHandsSparkleTheSavedChoiceOnlyWhenItDiffers() {
        let updater = FakeUpdater()
        let settings = SettingsModel()
        settings.value.general.automaticallyCheckForUpdates = false
        UpdaterModel(updater: updater, settings: settings).start()
        #expect(updater.automaticWrites == [false])

        let unchanged = FakeUpdater()
        UpdaterModel(updater: unchanged, settings: SettingsModel()).start()
        #expect(unchanged.automaticWrites.isEmpty)
    }

    @Test func turningAutomaticChecksOffSavesItAndTellsSparkle() {
        let updater = FakeUpdater()
        let settings = SettingsModel()
        let model = UpdaterModel(updater: updater, settings: settings)
        model.start()

        model.automaticallyChecksForUpdates = false

        #expect(!settings.value.general.automaticallyCheckForUpdates)
        #expect(updater.automaticWrites == [false])
    }

    @Test func aToggleChangedBeforeStartIsOnlySaved() {
        let updater = FakeUpdater()
        let settings = SettingsModel()
        let model = UpdaterModel(updater: updater, settings: settings)

        model.automaticallyChecksForUpdates = false
        model.receivesBetaUpdates = true

        #expect(!settings.value.general.automaticallyCheckForUpdates)
        #expect(settings.value.general.receiveBetaUpdates)
        #expect(updater.automaticWrites.isEmpty)
        #expect(updater.resets == 0)
    }

    @Test func theBetaToggleDrivesTheChannelsSparkleAsksFor() {
        let updater = FakeUpdater()
        let settings = SettingsModel()
        let model = UpdaterModel(updater: updater, settings: settings)
        model.start()
        #expect(updater.allowedChannels?() == [])

        model.receivesBetaUpdates = true

        #expect(settings.value.general.receiveBetaUpdates)
        #expect(updater.allowedChannels?() == ["beta"])
        #expect(updater.resets == 1)
    }

    @Test func betasMapToSparklesBetaChannelAndTheDefaultChannelIsImplicit() {
        #expect(UpdaterModel.allowedChannels(receivingBetas: true) == ["beta"])
        #expect(UpdaterModel.allowedChannels(receivingBetas: false).isEmpty)
    }

    @Test func outsideAGameSparkleShowsScheduledUpdatesItself() throws {
        let updater = FakeUpdater()
        let model = UpdaterModel(updater: updater, settings: SettingsModel())
        model.start()
        let hooks = try #require(updater.hooks)

        #expect(hooks.showsScheduledUpdateNow())
    }

    @Test func aScheduledUpdateFoundDuringAGameWaitsForTheGameToEnd() throws {
        let updater = FakeUpdater()
        let model = UpdaterModel(updater: updater, settings: SettingsModel())
        model.start()
        let hooks = try #require(updater.hooks)

        model.isInGame = true
        #expect(!hooks.showsScheduledUpdateNow())
        hooks.scheduledUpdateDeferred()
        #expect(updater.checks == 0)

        model.isInGame = false

        #expect(updater.checks == 1)
        #expect(!model.hasDeferredUpdate)
        #expect(hooks.showsScheduledUpdateNow())
    }

    @Test func aGameEndingWithNothingHeldBackChecksNothing() {
        let updater = FakeUpdater()
        let model = UpdaterModel(updater: updater, settings: SettingsModel())
        model.start()

        model.isInGame = true
        model.isInGame = false

        #expect(updater.checks == 0)
    }

    @Test func anUpdateTheUserAlreadySawIsNotShownAgainAfterTheGame() throws {
        let updater = FakeUpdater()
        let model = UpdaterModel(updater: updater, settings: SettingsModel())
        model.start()
        let hooks = try #require(updater.hooks)
        model.isInGame = true
        hooks.scheduledUpdateDeferred()

        hooks.updateHandled()
        model.isInGame = false

        #expect(updater.checks == 0)
    }

    @Test func aUserInitiatedCheckDuringAGameRunsImmediately() {
        let updater = FakeUpdater()
        let model = UpdaterModel(updater: updater, settings: SettingsModel())
        model.start()
        updater.canCheckChanged?(true)
        model.isInGame = true

        model.checkForUpdates()

        #expect(updater.checks == 1)
    }

    @Test func appStartHandsSparkleThePersistedChoice() async {
        var persisted = MitoSettings()
        persisted.general.automaticallyCheckForUpdates = false
        let updater = FakeUpdater()
        let app = AppModel(
            connection: ScriptedLCUConnection(script: []),
            settings: SettingsModel(persistence: FixedPersistence(settings: persisted)),
            updates: { UpdaterModel(updater: updater, settings: $0) })

        await app.start()

        #expect(updater.startCount == 1)
        #expect(updater.automaticWrites == [false])
    }
}

final class FakeUpdater: SoftwareUpdater {
    private(set) var automaticWrites: [Bool] = []
    private(set) var startCount = 0
    private(set) var checks = 0
    private(set) var resets = 0
    private(set) var hooks: UpdaterHooks?
    var allowedChannels: (() -> Set<String>)? { hooks?.allowedChannels }
    var canCheckChanged: (@MainActor (Bool) -> Void)? { hooks?.canCheckChanged }

    var automaticallyChecksForUpdates = true {
        didSet { automaticWrites.append(automaticallyChecksForUpdates) }
    }

    func start(_ hooks: UpdaterHooks) {
        startCount += 1
        self.hooks = hooks
    }

    func checkForUpdates() { checks += 1 }

    func resetUpdateCycle() { resets += 1 }
}

struct FixedPersistence: SettingsPersistence {
    let settings: MitoSettings

    func load() async -> MitoSettings { settings }
    func save(_ settings: MitoSettings) async throws(StoreError) {}
}
