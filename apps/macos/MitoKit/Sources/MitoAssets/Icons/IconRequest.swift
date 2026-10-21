public import Foundation

/// One icon: its client asset path, the game version it belongs to, and an optional Data Dragon
/// fallback. The initializer rejects anything the loader must never fetch.
public struct IconRequest: Hashable, Sendable {
    public static let assetPathPrefix = "/lol-game-data/assets/"
    public static let dataDragonHost = "ddragon.leagueoflegends.com"

    public let assetPath: String
    public let gameVersion: String
    public let dataDragonURL: URL?

    public init(assetPath: String, gameVersion: String, dataDragonURL: URL? = nil)
        throws(IconError)
    {
        guard Self.isSafeAssetPath(assetPath) else { throw .invalidAssetPath(assetPath) }
        guard Self.isSafeVersion(gameVersion) else { throw .invalidGameVersion(gameVersion) }
        if let dataDragonURL, !Self.isDataDragon(dataDragonURL) {
            throw .invalidDataDragonURL(dataDragonURL.absoluteString)
        }
        self.assetPath = assetPath
        self.gameVersion = gameVersion
        self.dataDragonURL = dataDragonURL
    }

    /// The path below the assets prefix, split into its segments.
    var relativeSegments: [Substring] {
        assetPath.dropFirst(Self.assetPathPrefix.count).split(separator: "/")
    }

    private static func isSafeAssetPath(_ path: String) -> Bool {
        guard path.hasPrefix(assetPathPrefix),
            !path.contains(where: { "?#\\".contains($0) }),
            let decoded = path.removingPercentEncoding
        else { return false }
        // Checked decoded too: the client would resolve "%2e%2e" to "..".
        return [path, decoded].allSatisfy { candidate in
            let segments = candidate.dropFirst(assetPathPrefix.count)
                .split(separator: "/", omittingEmptySubsequences: false)
            return !segments.isEmpty
                && segments.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
        }
    }

    private static func isSafeVersion(_ version: String) -> Bool {
        !version.isEmpty && version != "." && version != ".."
            && version.allSatisfy {
                $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0))
            }
    }

    private static func isDataDragon(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.lowercased() == dataDragonHost
            && url.port == nil && url.user() == nil && url.password() == nil
    }
}
