import Foundation
import LCUKit
import MitoCore
import MitoImport
import Testing

@testable import Mito

struct HandWrittenBuildsTests {
    /// The trees in `fixtures/lcu/cases/runes/styles.json`: Precision, Domination, Sorcery.
    private static let fixtureStyles: Set<Int> = [8000, 8100, 8200]

    @Test func coversOneChampionPerRole() {
        #expect(Set(HandWrittenBuilds.all.keys.map(\.rawValue)) == [122, 64, 103, 222, 99])
    }

    /// Darius (122) is left out: his Resolve secondary is not in the styles fixture.
    @Test(arguments: [64, 103, 222, 99])
    func runePagePassesTheClientValidator(champion: Int) async throws {
        let page = try #require(
            HandWrittenBuilds.loadout(for: ChampionID(rawValue: champion)).runes)
        let connection = ImportTestConnection()
        connection.serve(LCUEndpoint.perkStyles.path, try ImportFixture.data("styles", in: "runes"))
        connection.serve(
            LCUEndpoint.perkPages.path,
            try ImportFixture.data("pages-without-mito-page", in: "runes"))
        connection.serve(
            LCUEndpoint.perkInventory.path,
            try ImportFixture.data("inventory-with-room", in: "runes"))

        let result = await RuneImporter(connection: connection)
            .apply(page, title: "Test", settings: ImportSettings())

        #expect(result == .created)
    }

    @Test func onlyResolveIsMissingFromTheStylesFixture() {
        let styles = HandWrittenBuilds.all.values.compactMap(\.loadout.runes)
            .flatMap { [$0.primaryStyle.rawValue, $0.subStyle.rawValue] }

        #expect(Set(styles).subtracting(Self.fixtureStyles) == [8400])
    }

    @Test func aChampionWithoutABuildGetsTheEmptyFallback() {
        let loadout = HandWrittenBuilds.loadout(for: ChampionID(rawValue: 1))

        #expect(loadout == HandWrittenBuilds.fallback)
        #expect(loadout.runes == nil && loadout.spells == nil && loadout.itemSet == nil)
    }

    @Test func repeatedItemsBecomeOneEntryWithACount() throws {
        let start = try #require(
            HandWrittenBuilds.loadout(for: ChampionID(rawValue: 103)).itemSet?.blocks.first)

        #expect(start.items.map(\.id.rawValue) == [1056, 2003])
        #expect(start.items.map(\.count) == [1, 2])
    }
}
