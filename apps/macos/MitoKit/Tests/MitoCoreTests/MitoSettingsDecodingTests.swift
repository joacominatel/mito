import Foundation
import MitoCore
import Testing

struct MitoSettingsDecodingTests {
    @Test func emptyJSONDecodesToTheDefaults() throws {
        #expect(try decode("{}") == MitoSettings())
    }

    @Test func defaultsMatchTheDocumentedTable() {
        let settings = MitoSettings()
        #expect(!settings.general.launchAtLogin)
        #expect(settings.general.showWindowOnChampSelect)
        #expect(settings.general.diamondPlusData == .auto)
        #expect(settings.game.autoAccept == .always)
        #expect(settings.game.autoAcceptDelaySeconds == 2)
        #expect(settings.champSelect.candidates == .owned)
        #expect(settings.champSelect.metaComfortBalance == 0.5)
        #expect(settings.importing.runeMode == .adaptive)
        #expect(settings.importing.flashPosition == .auto)
        #expect(!settings.importing.importOnHover)
    }

    @Test func updatesAreCheckedAutomaticallyAndBetasAreOptIn() {
        let general = MitoSettings().general
        #expect(general.automaticallyCheckForUpdates)
        #expect(!general.receiveBetaUpdates)
    }

    @Test func settingsSavedBeforeTheUpdateKeysExistedKeepTheirValuesAndGetUpdateDefaults() throws {
        let settings = try decode(#"{"general": {"launchAtLogin": true, "showDockIcon": true}}"#)
        #expect(settings.general.launchAtLogin)
        #expect(settings.general.showDockIcon)
        #expect(settings.general.automaticallyCheckForUpdates)
        #expect(!settings.general.receiveBetaUpdates)
    }

    @Test func aMistypedUpdateKeyFallsBackWithoutResettingTheOther() throws {
        let settings = try decode(
            #"{"general": {"automaticallyCheckForUpdates": "yes", "receiveBetaUpdates": true}}"#)
        #expect(settings.general.automaticallyCheckForUpdates)
        #expect(settings.general.receiveBetaUpdates)
    }

    @Test func autoPickAndAutoBanAreOffByDefault() {
        let settings = MitoSettings()
        #expect(settings.champSelect.autoPick == .off)
        #expect(settings.champSelect.autoBan == .off)
        #expect(!settings.champSelect.autoHover)
    }

    @Test func missingFieldsTakeTheirDefaultsAndPresentOnesAreKept() throws {
        let settings = try decode(#"{"game": {"autoAcceptDelaySeconds": 5}}"#)
        #expect(settings.game.autoAcceptDelaySeconds == 5)
        #expect(settings.game.autoAccept == .always)
        #expect(settings.general == GeneralSettings())
    }

    @Test func unknownFieldsAreIgnored() throws {
        let settings = try decode(
            #"{"fromTheFuture": 1, "general": {"launchAtLogin": true, "newToggle": false}}"#)
        #expect(settings.general.launchAtLogin)
    }

    @Test func anUnknownEnumValueFallsBackForThatFieldOnly() throws {
        let settings = try decode(
            #"{"importing": {"runeMode": "telepathic", "importSpells": false}}"#)
        #expect(settings.importing.runeMode == .adaptive)
        #expect(!settings.importing.importSpells)
    }

    @Test func aMistypedSectionFallsBackToItsDefaults() throws {
        let settings = try decode(#"{"champSelect": 7, "game": {"notifyMatchFound": false}}"#)
        #expect(settings.champSelect == ChampSelectSettings())
        #expect(!settings.game.notifyMatchFound)
    }

    @Test func roundTripsEveryNonDefaultValue() throws {
        var settings = MitoSettings()
        settings.general.leagueInstallPath = "/Applications/League of Legends.app"
        settings.general.language = .english
        settings.general.automaticallyCheckForUpdates = false
        settings.general.receiveBetaUpdates = true
        settings.game.autoAccept = .selectedQueues
        settings.game.autoAcceptQueues = [QueueID(rawValue: 420)]
        settings.champSelect.autoPick = .listByRole
        settings.champSelect.autoPickList = [.middle: [ChampionID(rawValue: 103)]]
        settings.importing.runePageTarget = .reservedPage
        settings.importing.reservedRunePageID = 42

        let decoded = try JSONDecoder().decode(
            MitoSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }

    private func decode(_ json: String) throws -> MitoSettings {
        try JSONDecoder().decode(MitoSettings.self, from: Data(json.utf8))
    }
}
