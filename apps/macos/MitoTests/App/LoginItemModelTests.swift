import MitoCore
import Testing

@testable import Mito

struct LoginItemModelTests {
    @Test func registeringTurnsItOnAndSavesTheMirror() {
        let service = FakeLoginItemService()
        let settings = SettingsModel()
        let model = LoginItemModel(service: service, settings: settings)

        model.launchesAtLogin = true

        #expect(service.calls == ["register"])
        #expect(model.launchesAtLogin)
        #expect(model.note == nil)
        #expect(settings.value.general.launchAtLogin)
    }

    @Test func unregisteringTurnsItOff() {
        let service = FakeLoginItemService(status: .enabled)
        let settings = SettingsModel()
        settings.value.general.launchAtLogin = true
        let model = LoginItemModel(service: service, settings: settings)

        model.launchesAtLogin = false

        #expect(service.calls == ["unregister"])
        #expect(!model.launchesAtLogin)
        #expect(!settings.value.general.launchAtLogin)
    }

    @Test func refreshReadsWhatTheUserChangedInSystemSettings() {
        let service = FakeLoginItemService(status: .enabled)
        let settings = SettingsModel()
        let model = LoginItemModel(service: service, settings: settings)
        model.refresh()
        #expect(model.launchesAtLogin)

        service.status = .notRegistered
        model.refresh()

        #expect(!model.launchesAtLogin)
        #expect(!settings.value.general.launchAtLogin)
        #expect(service.calls.isEmpty)
    }

    @Test func theSavedValueNeverOverridesTheSystem() {
        let settings = SettingsModel()
        settings.value.general.launchAtLogin = true
        let model = LoginItemModel(service: FakeLoginItemService(), settings: settings)

        model.refresh()

        #expect(!model.launchesAtLogin)
        #expect(!settings.value.general.launchAtLogin)
    }

    @Test func pendingApprovalCountsAsOnWithANote() {
        let service = FakeLoginItemService()
        service.statusAfterRegister = .requiresApproval
        let model = LoginItemModel(service: service, settings: SettingsModel())

        model.launchesAtLogin = true

        #expect(model.launchesAtLogin)
        #expect(model.note == .requiresApproval)
        model.openSystemSettings()
        #expect(service.calls == ["register", "openSystemSettings"])
    }

    @Test func aFailedRegistrationLeavesItOffWithANote() {
        let service = FakeLoginItemService()
        service.fails = true
        let settings = SettingsModel()
        let model = LoginItemModel(service: service, settings: settings)

        model.launchesAtLogin = true

        #expect(!model.launchesAtLogin)
        #expect(model.note == .failed)
        #expect(!settings.value.general.launchAtLogin)
    }

    @Test func settingTheStateItAlreadyHasCallsNothing() {
        let service = FakeLoginItemService(status: .enabled)
        let model = LoginItemModel(service: service, settings: SettingsModel())

        model.launchesAtLogin = true

        #expect(service.calls.isEmpty)
    }

    @Test(arguments: [(true, false), (false, true), (true, true)])
    func debugAndTestBuildsNeverTouchLoginItems(underTest: Bool, isDebugBuild: Bool) {
        var created = 0
        let settings = SettingsModel()
        let model = LoginItemModel.live(
            settings: settings, underTest: underTest, isDebugBuild: isDebugBuild,
            makeService: {
                created += 1
                return FakeLoginItemService()
            })

        model.refresh()
        model.launchesAtLogin = true

        #expect(created == 0)
        #expect(!model.isAvailable)
        #expect(!model.launchesAtLogin)
        #expect(model.note == .unavailable)
        #expect(!settings.value.general.launchAtLogin)
    }

    @Test func aReleaseBuildOutsideTestsUsesTheService() {
        let model = LoginItemModel.live(
            settings: SettingsModel(), underTest: false, isDebugBuild: false,
            makeService: { FakeLoginItemService() })
        #expect(model.isAvailable)
    }

    @Test func thisTestBuildGetsNoLoginItemByDefault() {
        #expect(!LoginItemModel.live(settings: SettingsModel(), underTest: false).isAvailable)
    }

    @Test func appStartReadsTheSystemState() async {
        let service = FakeLoginItemService(status: .enabled)
        let app = AppModel(
            connection: ScriptedLCUConnection(script: []),
            loginItem: { LoginItemModel(service: service, settings: $0) })

        await app.start()

        #expect(app.loginItem.launchesAtLogin)
        #expect(app.settings.general.launchAtLogin)
    }
}

final class FakeLoginItemService: LoginItemService {
    struct Failure: Error {}

    var status: LoginItemStatus
    var statusAfterRegister = LoginItemStatus.enabled
    var fails = false
    private(set) var calls: [String] = []

    init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    func register() throws {
        calls.append("register")
        if fails { throw Failure() }
        status = statusAfterRegister
    }

    func unregister() throws {
        calls.append("unregister")
        if fails { throw Failure() }
        status = .notRegistered
    }

    func openSystemSettings() { calls.append("openSystemSettings") }
}
