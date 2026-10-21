import Foundation
import MitoCore
import Testing

@testable import MitoStore

struct CuratedTipsTests {
    private static let ahri = ChampionID(rawValue: 103)
    private static let zed = ChampionID(rawValue: 238)
    private static let yasuo = ChampionID(rawValue: 157)

    // MARK: Contract fixture

    @Test func theContractFixtureDecodesEveryTip() throws {
        let tips = try #require(CuratedTips.decode(SnapshotFixture.tips, locale: "es-AR"))

        #expect(tips.records.count == 3)
        #expect(
            tips.records.first
                == CuratedTipRecord(
                    champion: Self.ahri, role: .middle, opponent: Self.zed,
                    reviewedPatch: Patch(rawValue: "16.21"),
                    text: "Synthetic tip: hold E until Zed commits his R."))
    }

    @Test func aGeneralTipHasNoOpponent() throws {
        let tips = try #require(CuratedTips.decode(SnapshotFixture.tips, locale: "es-AR"))

        #expect(tips.records[1].opponent == nil)
    }

    // MARK: Reader

    @Test func tipsAgainstTheOpponentComeBeforeTheGeneralOnes() throws {
        let tips = try #require(CuratedTips.decode(SnapshotFixture.tips, locale: "es-AR"))

        #expect(
            tips.tips(for: Self.ahri, role: .middle, against: Self.zed).map(\.text) == [
                "Synthetic tip: hold E until Zed commits his R.",
                "Synthetic tip: push the wave before roaming.",
            ])
    }

    @Test func withoutAnOpponentOnlyTheGeneralTipsAreReturned() throws {
        let tips = try #require(CuratedTips.decode(SnapshotFixture.tips, locale: "es-AR"))

        #expect(
            tips.tips(for: Self.ahri, role: .middle, against: nil).map(\.text) == [
                "Synthetic tip: push the wave before roaming."
            ])
    }

    @Test func anOpponentWithoutTipsFallsBackToTheGeneralOnes() throws {
        let tips = try #require(CuratedTips.decode(SnapshotFixture.tips, locale: "es-AR"))

        #expect(
            tips.tips(for: Self.ahri, role: .middle, against: Self.yasuo).map(\.text) == [
                "Synthetic tip: push the wave before roaming."
            ])
    }

    @Test func tipsForAnotherRoleOrChampionAreNotReturned() throws {
        let tips = try #require(CuratedTips.decode(SnapshotFixture.tips, locale: "es-AR"))

        #expect(tips.tips(for: Self.ahri, role: .top, against: Self.zed).isEmpty)
        #expect(tips.tips(for: Self.yasuo, role: .middle, against: Self.zed).isEmpty)
    }

    @Test func eachGroupKeepsTheFileOrder() {
        let records = [
            record(opponent: nil, text: "general 1"), record(opponent: 238, text: "zed 1"),
            record(opponent: nil, text: "general 2"), record(opponent: 238, text: "zed 2"),
        ]

        #expect(
            CuratedTips(records: records).tips(for: Self.ahri, role: .middle, against: Self.zed)
                .map(\.text) == ["zed 1", "zed 2", "general 1", "general 2"])
    }

    @Test func emptyTipsHaveNothingForAnyone() {
        #expect(CuratedTips.empty.tips(for: Self.ahri, role: .middle, against: Self.zed).isEmpty)
    }

    // MARK: Tolerant decoding

    @Test(arguments: [
        #"{"champion_id": 103, "role": "MID", "opp_id": 0, "reviewed_patch": "16.21", "text": "x"}"#,
        #"{"champion_id": 103, "role": "middle", "opp_id": 0, "reviewed_patch": "16.21", "text": "x"}"#,
        #"{"champion_id": 103, "role": "MIDDLE", "opp_id": 0, "reviewed_patch": "16.21"}"#,
        #"{"champion_id": 103, "role": "MIDDLE", "opp_id": 0, "reviewed_patch": "16.21", "text": "  "}"#,
        #"{"champion_id": "103", "role": "MIDDLE", "opp_id": 0, "reviewed_patch": "16.21", "text": "x"}"#,
        #"{"champion_id": 0, "role": "MIDDLE", "opp_id": 0, "reviewed_patch": "16.21", "text": "x"}"#,
        #"{"champion_id": 103, "role": "MIDDLE", "opp_id": -1, "reviewed_patch": "16.21", "text": "x"}"#,
        #"{"champion_id": 103, "role": "MIDDLE", "opp_id": 0, "reviewed_patch": "latest", "text": "x"}"#,
        #"{"champion_id": 103, "role": "MIDDLE", "reviewed_patch": "16.21", "text": "x"}"#,
        #""not a tip""#,
    ])
    func aMalformedTipIsSkippedAndTheRestKept(_ malformed: String) throws {
        let tips = try #require(
            CuratedTips.decode(file(tips: [malformed, Self.validTip]), locale: "es-AR"))

        #expect(tips.records.map(\.text) == ["valid"])
    }

    @Test func unknownFieldsAreIgnored() throws {
        let tip =
            #"{"champion_id": 103, "role": "MIDDLE", "opp_id": 0, "reviewed_patch": "16.21", "text": "valid", "author": "x"}"#
        let data = Data(
            #"{"format_version": 1, "locale": "es-AR", "generated_at": "x", "tips": [\#(tip)]}"#
                .utf8)

        #expect(CuratedTips.decode(data, locale: "es-AR")?.records.map(\.text) == ["valid"])
    }

    @Test func anUnsupportedFormatVersionIsNotRead() {
        #expect(
            CuratedTips.decode(file(formatVersion: 2, tips: [Self.validTip]), locale: "es-AR")
                == nil)
    }

    @Test func aFileForAnotherLocaleIsNotRead() {
        #expect(CuratedTips.decode(file(tips: [Self.validTip]), locale: "en-US") == nil)
    }

    @Test(arguments: [#"{"format_version": 1, "locale": "es-AR"}"#, "[]", "not json"])
    func aFileThatIsNotTheContractShapeIsNotRead(_ body: String) {
        #expect(CuratedTips.decode(Data(body.utf8), locale: "es-AR") == nil)
    }

    // MARK: Helpers

    private static let validTip =
        #"{"champion_id": 103, "role": "MIDDLE", "opp_id": 0, "reviewed_patch": "16.21", "text": "valid"}"#

    private func file(formatVersion: Int = 1, tips: [String]) -> Data {
        Data(
            #"{"format_version": \#(formatVersion), "locale": "es-AR", "tips": [\#(tips.joined(separator: ","))]}"#
                .utf8)
    }

    private func record(opponent: Int?, text: String) -> CuratedTipRecord {
        CuratedTipRecord(
            champion: Self.ahri, role: .middle, opponent: opponent.map(ChampionID.init(rawValue:)),
            reviewedPatch: Patch(rawValue: "16.21"), text: text)
    }
}
