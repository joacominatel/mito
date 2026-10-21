import Foundation
import MitoCore
import MitoStore
import Testing

/// The snapshot contract fixture, `fixtures/snapshot/emerald_plus.sqlite` (patch 16.21).
enum SnapshotFixture {
    static let file = URL(filePath: #filePath)
        .deletingLastPathComponent()  // App/
        .deletingLastPathComponent()  // MitoTests/
        .deletingLastPathComponent()  // macos/
        .deletingLastPathComponent()  // apps/
        .deletingLastPathComponent()  // repository root
        .appending(path: "fixtures/snapshot/emerald_plus.sqlite", directoryHint: .notDirectory)

    static func reader() throws -> SnapshotReader {
        try SnapshotReader(fileURL: file)
    }
}

/// Stands in for an opened file: only its `meta.patch` tells snapshots apart.
nonisolated struct PatchOnlyStats: StatsProvider {
    let patch: String

    var meta: SnapshotMeta? {
        SnapshotMeta(
            patch: Patch(rawValue: patch), queue: QueueID(rawValue: 420), bracket: .emeraldPlus,
            matches: 1, blendPatches: [Patch(rawValue: patch)], thresholds: [:],
            priors: SmoothingPriors(
                championRoleStrength: 100, championRoleBaseline: 0.5, relationStrength: 200,
                loadoutStrength: 500),
            tierCutoffs: [:])
    }

    func roleGames(for champion: ChampionID) -> [Role: Int] { [:] }
}
