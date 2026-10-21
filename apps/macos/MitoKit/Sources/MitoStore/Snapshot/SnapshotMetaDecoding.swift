import Foundation
import MitoCore

extension SnapshotMeta {
    /// The `meta` keys a file must carry. `profile_rules` is optional because Phase 6 files did
    /// not carry it meaningfully; the others (`regions`, `blend_k`, …) are not read.
    static let requiredKeys = [
        "schema_version", "patch", "queue", "bracket", "matches", "blend_patches", "thresholds",
        "priors", "tier_cutoffs",
    ]

    /// `values` is the raw `meta` table; `schema_version` has already been checked.
    init(values: [String: String]) throws(SnapshotReadError) {
        let missing = Self.requiredKeys.first { values[$0] == nil }
        if let missing { throw .missingMetaKey(missing) }

        guard let bracket = values["bracket"].flatMap(Bracket.init(rawValue:)) else {
            throw .invalidMetaValue("bracket")
        }
        let blendPatches = try Self.json([String].self, values, "blend_patches")
        let priors = try Self.json(Priors.self, values, "priors")
        let cutoffs = try Self.json([String: Double].self, values, "tier_cutoffs")
        let rules =
            values["profile_rules"] == nil
            ? nil : try Self.json(Rules.self, values, "profile_rules")

        var thresholds: [SampleKind: SampleThreshold] = [:]
        for (key, pair) in try Self.json([String: [Int]].self, values, "thresholds") {
            guard pair.count == 2 else { throw .invalidMetaValue("thresholds") }
            if let kind = SampleKind(rawValue: key) {
                thresholds[kind] = SampleThreshold(minimum: pair[0], reliable: pair[1])
            }
        }

        self.init(
            patch: Patch(rawValue: values["patch"] ?? ""),
            queue: QueueID(rawValue: try Self.integer(values, "queue")),
            bracket: bracket,
            matches: try Self.integer(values, "matches"),
            blendPatches: blendPatches.map(Patch.init(rawValue:)),
            thresholds: thresholds,
            priors: SmoothingPriors(
                championRoleStrength: priors.champRole.m,
                championRoleBaseline: priors.champRole.p0,
                relationStrength: priors.relation,
                loadoutStrength: priors.loadout),
            tierCutoffs: Dictionary(
                uniqueKeysWithValues: cutoffs.compactMap { key, value in
                    Tier(rawValue: key).map { ($0, value) }
                }),
            profileRules: rules?.profileRules)
    }

    static func integer(_ values: [String: String], _ key: String) throws(SnapshotReadError)
        -> Int
    {
        guard let value = values[key].flatMap({ Int($0) }) else { throw .invalidMetaValue(key) }
        return value
    }

    private static func json<Value: Decodable>(
        _ type: Value.Type, _ values: [String: String], _ key: String
    ) throws(SnapshotReadError) -> Value {
        do {
            return try JSONDecoder().decode(type, from: Data((values[key] ?? "").utf8))
        } catch {
            throw .invalidMetaValue(key)
        }
    }

    private struct Rules: Decodable {
        struct HeavyAD: Decodable {
            let share: Double
            enum CodingKeys: String, CodingKey { case share = "phys_share_weighted" }
        }

        struct HeavyAP: Decodable {
            let share: Double
            enum CodingKeys: String, CodingKey { case share = "magic_share_weighted" }
        }

        struct HeavyCC: Decodable {
            let mean: Double
            enum CodingKeys: String, CodingKey { case mean = "cc_score_mean" }
        }

        struct Mixed: Decodable {
            let not: [String]
        }

        let minChampions: Int
        let heavyAD: HeavyAD
        let heavyAP: HeavyAP
        let heavyCC: HeavyCC
        let mixed: Mixed

        enum CodingKeys: String, CodingKey {
            case minChampions = "min_champions"
            case heavyAD = "heavy_ad"
            case heavyAP = "heavy_ap"
            case heavyCC = "heavy_cc"
            case mixed
        }

        var profileRules: ProfileRules {
            ProfileRules(
                minimumChampions: minChampions,
                heavyADPhysicalShare: heavyAD.share,
                heavyAPMagicShare: heavyAP.share,
                heavyCCScore: heavyCC.mean,
                mixedExcludes: Set(mixed.not.map(EnemyProfile.init(rawValue:))))
        }
    }

    private struct Priors: Decodable {
        struct ChampionRole: Decodable {
            let m: Double
            let p0: Double
        }

        let champRole: ChampionRole
        let relation: Double
        let loadout: Double

        enum CodingKeys: String, CodingKey {
            case champRole = "champ_role"
            case relation
            case loadout
        }
    }
}
