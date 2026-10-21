import MitoCore
import Testing

struct PersonalModeTests {
    @Test(arguments: [
        ("adaptive", ChampionOverride.RuneMode.adaptive), ("general", .general), ("fixed", .fixed),
    ])
    func mapsTheRuneModes(raw: String, mode: ChampionOverride.RuneMode) {
        #expect(ChampionOverride.RuneMode(rawValue: raw) == mode)
        #expect(mode.rawValue == raw)
    }

    @Test(arguments: [("recommended", ChampionOverride.SpellMode.recommended), ("fixed", .fixed)])
    func mapsTheSpellModes(raw: String, mode: ChampionOverride.SpellMode) {
        #expect(ChampionOverride.SpellMode(rawValue: raw) == mode)
        #expect(mode.rawValue == raw)
    }

    @Test(arguments: [
        ("recommended", ChampionOverride.ItemMode.recommended), ("fixed_set", .fixedSet),
        ("skip", .skip),
    ])
    func mapsTheItemModes(raw: String, mode: ChampionOverride.ItemMode) {
        #expect(ChampionOverride.ItemMode(rawValue: raw) == mode)
        #expect(mode.rawValue == raw)
    }

    @Test(arguments: [
        ("runes", ImportLogEntry.Part.runes), ("spells", .spells), ("items", .items),
    ])
    func mapsTheImportLogParts(raw: String, part: ImportLogEntry.Part) {
        #expect(ImportLogEntry.Part(rawValue: raw) == part)
        #expect(part.rawValue == raw)
    }

    @Test(arguments: [
        ("applied", ImportLogEntry.Outcome.applied), ("skipped", .skipped), ("failed", .failed),
    ])
    func mapsTheImportLogOutcomes(raw: String, outcome: ImportLogEntry.Outcome) {
        #expect(ImportLogEntry.Outcome(rawValue: raw) == outcome)
        #expect(outcome.rawValue == raw)
    }

    @Test func keepsUnknownValuesVerbatim() {
        #expect(ChampionOverride.RuneMode(rawValue: "per_matchup") == .unknown("per_matchup"))
        #expect(ChampionOverride.RuneMode.unknown("per_matchup").rawValue == "per_matchup")
        #expect(ChampionOverride.SpellMode(rawValue: "smart") == .unknown("smart"))
        #expect(ChampionOverride.SpellMode.unknown("smart").rawValue == "smart")
        #expect(ChampionOverride.ItemMode(rawValue: "starter_only") == .unknown("starter_only"))
        #expect(ChampionOverride.ItemMode.unknown("starter_only").rawValue == "starter_only")
        #expect(ImportLogEntry.Part(rawValue: "skills") == .unknown("skills"))
        #expect(ImportLogEntry.Part.unknown("skills").rawValue == "skills")
        #expect(ImportLogEntry.Outcome(rawValue: "partial") == .unknown("partial"))
        #expect(ImportLogEntry.Outcome.unknown("partial").rawValue == "partial")
    }
}
