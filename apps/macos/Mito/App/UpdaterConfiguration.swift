import Foundation

/// Whether Info.plist carries a real Sparkle feed and key (ADR 0009). Sparkle reads both itself.
nonisolated enum UpdaterConfiguration {
    #if DEBUG
        static let isDebugBuild = true
    #else
        static let isDebugBuild = false
    #endif

    /// `false` in Debug, with no feed or key, with a non-HTTPS feed, with a feed on an `.invalid`
    /// host, or with a key that is not a 32-byte Ed25519 public key in base64.
    static func isComplete(info: [String: Any]?, isDebugBuild: Bool = isDebugBuild) -> Bool {
        guard !isDebugBuild,
            let feed = info?["SUFeedURL"] as? String,
            let url = URL(string: feed), url.scheme?.lowercased() == "https",
            let host = url.host()?.lowercased(), !host.isEmpty,
            host != "invalid", !host.hasSuffix(".invalid"),
            let key = info?["SUPublicEDKey"] as? String
        else { return false }
        return Data(base64Encoded: key)?.count == 32
    }
}
