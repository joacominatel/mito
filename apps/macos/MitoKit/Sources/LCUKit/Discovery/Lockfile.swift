import Foundation

/// `LeagueClient:<pid>:<port>:<password>:<protocol>` (`MITO_CONTEXT.md` §10.1 B).
enum Lockfile {
    static func credentials(fromContents contents: String) -> LCUCredentials? {
        let fields = contents.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
        // Fewer than five fields means the client is still writing it, so the password may be cut.
        guard fields.count >= 5, let port = LCUDiscovery.port(String(fields[2])), !fields[3].isEmpty
        else { return nil }
        return LCUCredentials(port: port, token: String(fields[3]))
    }
}
