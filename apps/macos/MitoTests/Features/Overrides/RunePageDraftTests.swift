import MitoCore
import Testing

@testable import Mito

private typealias Fixture = OverridesFixture

struct RunePageDraftTests {
    @Test func theDraftIsAPageOnlyWhenEveryChoiceIsMade() {
        var draft = Fixture.validDraft()
        #expect(draft.page == Fixture.validPage)

        draft.keystone = nil
        #expect(draft.page == nil)
    }

    @Test func aThirdSecondaryPickDropsTheOldest() {
        var draft = Fixture.validDraft()

        draft.setSecondaryPerk(PerkID(rawValue: 25), inRow: 1)

        #expect(draft.secondaryPerk(inRow: 0) == nil)
        #expect(draft.page?.perks[4...5] == Fixture.ids(27, 25)[...])
    }

    @Test func aPickInTheSameRowReplacesIt() {
        var draft = Fixture.validDraft()

        draft.setSecondaryPerk(PerkID(rawValue: 24), inRow: 0)

        #expect(draft.secondaryPerk(inRow: 0) == PerkID(rawValue: 24))
        #expect(draft.secondaryPerk(inRow: 2) == PerkID(rawValue: 27))
    }

    @Test func changingThePrimaryClearsItsPerksAndKeepsShardsThatStillFit() {
        let shiftedShards: [PerkStyle.Slot] = [
            .init(kind: .statMod, perks: Fixture.ids(91, 92)),
            .init(kind: .statMod, perks: Fixture.ids(91, 92)),
            .init(kind: .statMod, perks: Fixture.ids(94, 93)),
        ]
        let other = PerkStyleID(rawValue: 3)
        let styles = Fixture.styles + [Fixture.style(other, base: 30, shards: shiftedShards)]
        var draft = Fixture.validDraft()

        draft.setPrimaryStyle(other, styles: styles)

        #expect(draft.keystone == nil)
        #expect(draft.primaryPerks == [nil, nil, nil])
        #expect(draft.shards == [PerkID(rawValue: 91), nil, PerkID(rawValue: 94)])
        #expect(draft.subStyle == Fixture.domination)
    }

    @Test func thePrimaryAndSubStyleAreNeverTheSame() {
        var draft = Fixture.validDraft()

        draft.setSubStyle(Fixture.precision)
        #expect(draft.subStyle == nil)

        draft.setSubStyle(Fixture.domination)
        draft.setPrimaryStyle(Fixture.domination, styles: Fixture.styles)
        #expect(draft.primaryStyle == Fixture.domination)
        #expect(draft.subStyle == nil)
        #expect(draft.secondaryPerk(inRow: 0) == nil)
    }

    @Test func aStoredPageReopensRowByRow() {
        #expect(RunePageDraft(Fixture.validPage, styles: Fixture.styles) == Fixture.validDraft())
    }

    @Test func perksThatNoLongerFitTheClientsTreesAreLeftEmpty() {
        let stale = RunePage(
            primaryStyle: Fixture.precision, subStyle: Fixture.domination,
            perks: Fixture.ids(99, 13, 15, 17, 23, 88, 91, 93, 94))

        let draft = RunePageDraft(stale, styles: Fixture.styles)

        #expect(draft.keystone == nil)
        #expect(draft.secondaryPerk(inRow: 0) == PerkID(rawValue: 23))
        #expect(draft.page == nil)
    }
}
