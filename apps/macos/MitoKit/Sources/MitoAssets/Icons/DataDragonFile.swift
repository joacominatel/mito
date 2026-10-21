import Foundation
public import MitoCore

/// An image on Data Dragon, below `cdn/<version>/img/` or, for rune art, below the unversioned
/// `cdn/img/`. The loader resolves the version, so a request names only the client's patch.
public struct DataDragonFile: Hashable, Sendable {
    static let versionsURL = URL(string: "https://\(IconRequest.dataDragonHost)/api/versions.json")

    private static let clientPrefix = "/lol-game-data/assets/v1/"

    let path: String
    /// `nil` for a file that is the same in every version.
    let patch: Patch?

    private init?(path: String, patch: Patch?) {
        guard Self.isSafe(path), patch.map({ Self.isPatch($0.rawValue) }) ?? true else {
            return nil
        }
        self.path = path
        self.patch = patch
    }

    /// `image("champion/Ahri.png", patch: 16.21)` is `cdn/<16.21 build>/img/champion/Ahri.png`.
    public static func image(_ path: String, patch: Patch) -> DataDragonFile? {
        DataDragonFile(path: path, patch: patch)
    }

    /// Data Dragon serves rune and rune-tree art at the client's own path below `perk-images/`,
    /// unversioned (checked against every rune in `runesReforged.json` 16.21.1).
    public static func rune(clientIconPath: String) -> DataDragonFile? {
        guard clientIconPath.hasPrefix(clientPrefix + "perk-images/") else { return nil }
        return DataDragonFile(
            path: String(clientIconPath.dropFirst(clientPrefix.count)), patch: nil)
    }

    /// A versioned file needs `version`; an unversioned one ignores it.
    func url(version: String?) -> URL? {
        let base = "https://\(IconRequest.dataDragonHost)/cdn/"
        switch (patch, version) {
        case (nil, _): return URL(string: base + "img/" + path)
        case (_, let version?): return URL(string: base + version + "/img/" + path)
        case (_, nil): return nil
        }
    }

    /// The newest build of `patch` in `versions.json` (`16.21.2` over `16.21.1`).
    static func version(for patch: Patch, in versions: [String]) -> String? {
        versions
            .compactMap { version -> (build: Int, version: String)? in
                guard
                    let match = version.wholeMatch(of: #/([0-9]{1,3}\.[0-9]{1,3})\.([0-9]{1,4})/#),
                    match.1 == patch.rawValue, let build = Int(match.2)
                else { return nil }
                return (build, version)
            }
            .max { $0.build < $1.build }?
            .version
    }

    private static func isPatch(_ value: String) -> Bool {
        value.wholeMatch(of: #/[0-9]{1,3}\.[0-9]{1,3}/#) != nil
    }

    private static func isSafe(_ path: String) -> Bool {
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        return !path.contains(where: { "?#\\%".contains($0) })
            && segments.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
