import Foundation
import MitoCore

extension SnapshotMeta {
    /// The `meta` keys Phase 6 reads; the others (`regions`, `blend_k`, `profile_rules`, …) are
    /// not checked until something uses them.
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
                }))
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
