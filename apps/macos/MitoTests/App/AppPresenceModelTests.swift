import AppKit
import MitoCore
import Testing

@testable import Mito

struct AppPresenceModelTests {
    private final class PolicyRecorder {
        var applied: [NSApplication.ActivationPolicy] = []
    }

    private func model(_ settings: SettingsModel = SettingsModel())
        -> (AppPresenceModel, PolicyRecorder)
    {
        let recorder = PolicyRecorder()
        let model = AppPresenceModel(settings: settings) { recorder.applied.append($0) }
        return (model, recorder)
    }

    @Test func byDefaultItIsAMenuBarOnlyApp() {
        let (presence, recorder) = model()
        presence.applyPolicy()

        #expect(presence.showsMenuBarIcon)
        #expect(!presence.showsDockIcon)
        #expect(recorder.applied == [.accessory])
    }

    @Test func withTheDockIconOffTheAppIsRegularOnlyWhileAWindowIsOpen() {
        let (presence, recorder) = model()
        presence.applyPolicy()

        presence.windowOpened(.main)
        presence.windowOpened(.settings)
        presence.windowClosed(.main)
        #expect(presence.policy == .regular)
        presence.windowClosed(.settings)

        #expect(recorder.applied == [.accessory, .regular, .accessory])
    }

    @Test func withTheDockIconOnTheAppIsAlwaysRegular() {
        let settings = SettingsModel()
        let (presence, recorder) = model(settings)
        presence.applyPolicy()

        presence.showsDockIcon = true
        presence.windowOpened(.main)
        presence.windowClosed(.main)

        #expect(settings.value.general.showDockIcon)
        #expect(recorder.applied == [.accessory, .regular])
    }

    @Test func turningTheDockIconOffWithAWindowOpenWaitsForItToClose() {
        let settings = SettingsModel()
        settings.value.general.showDockIcon = true
        let (presence, recorder) = model(settings)
        presence.windowOpened(.settings)

        presence.showsDockIcon = false
        #expect(recorder.applied == [.regular])
        presence.windowClosed(.settings)

        #expect(recorder.applied == [.regular, .accessory])
    }

    @Test func hidingTheMenuBarIconForcesTheDockIconOn() {
        let settings = SettingsModel()
        let (presence, recorder) = model(settings)
        presence.applyPolicy()

        presence.showsMenuBarIcon = false

        #expect(!settings.value.general.showMenuBarIcon)
        #expect(settings.value.general.showDockIcon)
        #expect(presence.showsDockIcon)
        #expect(!presence.canHideDockIcon)
        #expect(recorder.applied == [.accessory, .regular])
    }

    @Test func theDockIconCannotBeTurnedOffWhileTheMenuBarIconIsOff() {
        let settings = SettingsModel()
        let (presence, _) = model(settings)
        presence.showsMenuBarIcon = false

        presence.showsDockIcon = false

        #expect(settings.value.general.showDockIcon)
        #expect(presence.showsDockIcon)
    }

    @Test func aSavedFileWithBothIconsOffStillShowsTheDockIcon() {
        let settings = SettingsModel()
        settings.value.general.showMenuBarIcon = false
        settings.value.general.showDockIcon = false
        let (presence, recorder) = model(settings)

        presence.applyPolicy()

        #expect(presence.showsDockIcon)
        #expect(recorder.applied == [.regular])
    }

    @Test func theMenuBarIconComesBackWithTheDockIconStillOn() {
        let settings = SettingsModel()
        let (presence, _) = model(settings)
        presence.showsMenuBarIcon = false

        presence.showsMenuBarIcon = true

        #expect(presence.showsDockIcon)
        #expect(presence.canHideDockIcon)
    }

    @Test func theMenuBarExtraFollowsTheSettingOnceTheWindowCanBeOpened() {
        let settings = SettingsModel()
        settings.value.general.showMenuBarIcon = false
        let (presence, _) = model(settings)
        #expect(presence.isMenuBarExtraInserted)

        var opened = 0
        presence.setMainWindowOpener { opened += 1 }
        #expect(!presence.isMenuBarExtraInserted)

        presence.isMenuBarExtraInserted = true
        #expect(settings.value.general.showMenuBarIcon)
        #expect(presence.isMenuBarExtraInserted)

        presence.openMainWindow()
        #expect(opened == 1)
    }

    @Test func removingTheMenuBarExtraFromOutsideKeepsTheAppInTheDock() {
        let settings = SettingsModel()
        let (presence, _) = model(settings)
        presence.setMainWindowOpener {}

        presence.isMenuBarExtraInserted = false

        #expect(!settings.value.general.showMenuBarIcon)
        #expect(presence.showsDockIcon)
    }

    @Test func theFirstOpenerIsKept() {
        let (presence, _) = model()
        var first = 0
        var second = 0
        presence.setMainWindowOpener { first += 1 }
        presence.setMainWindowOpener { second += 1 }

        presence.openMainWindow()

        #expect(first == 1)
        #expect(second == 0)
    }

    @Test func appStartAppliesThePersistedDockChoice() async {
        var persisted = MitoSettings()
        persisted.general.showDockIcon = true
        let recorder = PolicyRecorder()
        let app = AppModel(
            connection: ScriptedLCUConnection(script: []),
            settings: SettingsModel(persistence: FixedPersistence(settings: persisted)),
            setActivationPolicy: { recorder.applied.append($0) })

        await app.start()

        #expect(recorder.applied == [.regular])
    }
}
