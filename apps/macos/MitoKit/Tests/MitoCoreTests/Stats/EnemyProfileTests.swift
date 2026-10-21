import MitoCore
import Testing

struct EnemyProfileTests {
    @Test(arguments: [
        ("heavy_ad", EnemyProfile.heavyAD), ("heavy_ap", .heavyAP), ("mixed", .mixed),
        ("heavy_cc", .heavyCC),
    ])
    func mapsTheSnapshotProfiles(raw: String, profile: EnemyProfile) {
        #expect(EnemyProfile(rawValue: raw) == profile)
        #expect(profile.rawValue == raw)
    }

    /// `'any'` is the `item_vs_profile` baseline, not a team profile.
    @Test func keepsAnUnknownProfileVerbatim() {
        let profile = EnemyProfile(rawValue: "any")
        #expect(profile == .unknown("any"))
        #expect(profile.rawValue == "any")
    }
}

struct ChampionFlagTests {
    @Test(arguments: [
        ("high_heal", ChampionFlag.highHeal), ("point_click_cc", .pointClickCC),
        ("auto_attacker", .autoAttacker), ("poke", .poke), ("engage", .engage),
    ])
    func mapsTheCuratedFlags(raw: String, flag: ChampionFlag) {
        #expect(ChampionFlag(rawValue: raw) == flag)
        #expect(flag.rawValue == raw)
    }

    @Test func keepsAnUnknownFlagVerbatim() {
        let flag = ChampionFlag(rawValue: "split_push")
        #expect(flag == .unknown("split_push"))
        #expect(flag.rawValue == "split_push")
    }
}
