import Foundation
import Testing

@testable import Mito

struct GeneralSettingTests {
    @Test func onlyLanguageAndDiamondPlusDataAreStillWithoutEffect() {
        #expect(
            GeneralSetting.allCases.filter { !$0.takesEffect } == [.language, .diamondPlusData])
    }

    @Test(arguments: GeneralSetting.allCases)
    func theFooterNamesExactlyTheSettingsWithoutEffect(setting: GeneralSetting) {
        let footer = String(localized: GeneralSetting.pendingFooter)
        let title = String(localized: setting.title)
        #expect(footer.contains("«\(title)»") == !setting.takesEffect, "\(title)")
    }
}
