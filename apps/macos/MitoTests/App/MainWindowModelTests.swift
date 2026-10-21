import LCUKit
import Testing

@testable import Mito

struct MainWindowModelTests {
    @Test func opensOnceWhenChampSelectStartsAndSelectsNow() {
        let model = MainWindowModel()
        model.destination = .profile
        #expect(!model.shouldOpen(isInChampSelect: false, phase: .readyCheck, enabled: true))
        #expect(!model.shouldOpen(isInChampSelect: false, phase: .champSelect, enabled: true))

        #expect(model.shouldOpen(isInChampSelect: true, phase: .champSelect, enabled: true))
        #expect(model.destination == .now)
        #expect(!model.shouldOpen(isInChampSelect: true, phase: .champSelect, enabled: true))
    }

    @Test func neverOpensWithTheSettingOff() {
        let model = MainWindowModel()
        model.destination = .profile

        #expect(!model.shouldOpen(isInChampSelect: true, phase: .champSelect, enabled: false))
        #expect(model.destination == .profile)
    }

    @Test func turningTheSettingOnMidwayDoesNotOpenIt() {
        let model = MainWindowModel()
        _ = model.shouldOpen(isInChampSelect: true, phase: .champSelect, enabled: false)

        #expect(!model.shouldOpen(isInChampSelect: true, phase: .champSelect, enabled: true))
    }

    @Test func aDraftThatDropsWithinTheSameChampSelectDoesNotReopen() {
        let model = MainWindowModel()
        #expect(model.shouldOpen(isInChampSelect: true, phase: .champSelect, enabled: true))

        #expect(!model.shouldOpen(isInChampSelect: false, phase: .champSelect, enabled: true))
        #expect(!model.shouldOpen(isInChampSelect: true, phase: .champSelect, enabled: true))
    }

    @Test(arguments: [MitoState.inGame, .lobby, .searching])
    func theNextChampSelectOpensItAgain(after phase: MitoState) {
        let model = MainWindowModel()
        #expect(model.shouldOpen(isInChampSelect: true, phase: .champSelect, enabled: true))

        #expect(!model.shouldOpen(isInChampSelect: false, phase: phase, enabled: true))

        #expect(model.shouldOpen(isInChampSelect: true, phase: .champSelect, enabled: true))
    }
}
