import Foundation
import Testing

/// LCUKit talks only to the League client on `127.0.0.1` (charter security dimension,
/// `MITO_CONTEXT.md` §5 and §10.3). ArchitectureTests does not link LCUKit, so this is a source
/// scan; the runtime loopback check lives in `LCUKitTests/Client`. MitoStore gets a host fence.
struct NetworkSentinelTests {
    private static let loopback = "127.0.0.1"
    /// The one file allowed to accept a server trust.
    private static let trustDecision = "MitoKit/Sources/LCUKit/Client/LCUTrust.swift"

    @Test func lcuKitURLsNameOnlyLoopback() throws {
        let urlLiteral = #/\b(?:https?|wss?)://([^/:"\s]*)/#
        let tree = try SourceTree()
        var hosts: [String] = []

        for file in try tree.swiftFiles(in: tree.target("LCUKit")) {
            for (index, line) in file.lines.enumerated() {
                for match in line.matches(of: urlLiteral) {
                    let host = String(match.1)
                    hosts.append(host)
                    if host != Self.loopback {
                        Issue.record(
                            """
                            \(file.path):\(index + 1) builds a URL for "\(host)"; LCUKit talks \
                            only to \(Self.loopback). Write the host as a literal.
                            """)
                    }
                }
            }
        }
        #expect(!hosts.isEmpty, "no URL literal found in LCUKit; the scan proved nothing")
    }

    /// Data Dragon (P4-08) and the snapshot bucket. The bucket host is injected at init, so this
    /// pins the literals a reviewer must approve; add the real R2 host here when it exists.
    private static let mitoStoreHosts: Set<String> = [
        "ddragon.leagueoflegends.com", "snapshots.mito.invalid",
    ]

    @Test func mitoStoreURLsNameOnlyDataDragonAndTheSnapshotHost() throws {
        let urlLiteral = #/\b(?:https?|wss?)://([^/:"\s]*)/#
        let tree = try SourceTree()
        var hosts: [String] = []

        for file in try tree.swiftFiles(in: tree.target("MitoStore")) {
            for (index, line) in file.lines.enumerated() {
                for match in line.matches(of: urlLiteral) {
                    let host = String(match.1)
                    hosts.append(host)
                    if !Self.mitoStoreHosts.contains(host) {
                        Issue.record(
                            """
                            \(file.path):\(index + 1) builds a URL for "\(host)"; MitoStore talks \
                            only to \(Self.mitoStoreHosts.sorted()) (MITO_CONTEXT.md §5, §14.12).
                            """)
                    }
                }
            }
        }
        #expect(!hosts.isEmpty, "no URL literal found in MitoStore; the scan proved nothing")
    }

    @Test func mitoStoreNeverUsesTheSharedSession() throws {
        let tree = try SourceTree()
        for file in try tree.swiftFiles(in: tree.target("MitoStore")) {
            for (index, line) in file.lines.enumerated()
            where line.contains(#/\bURLSession\.shared\b/#) {
                Issue.record(
                    """
                    \(file.path):\(index + 1) uses URLSession.shared; MitoStore sessions take an \
                    injected configuration so tests and the sentinel can see every request.
                    """)
            }
        }
    }

    @Test func lcuKitHasNoNetworkingEscapeHatch() throws {
        let hatches: [(pattern: Regex<Substring>, why: String)] = [
            (#/\bURLSession\.shared\b/#, "skips the loopback-only trust delegate"),
            (#/\bSecTrustSetExceptions\b/#, "overrides certificate validation"),
            (#/\bkCFStreamSSLValidatesCertificateChain\b/#, "disables certificate validation"),
            (#/\bNSAllowsArbitraryLoads\b/#, "disables App Transport Security"),
            (#/\bgetStreamsToHost\b|\bCFStreamCreatePairWithSocket/#, "opens a raw socket"),
        ]
        let acceptTrust = #/\.useCredential\b|URLCredential\(\s*trust:/#
        let tree = try SourceTree()

        for file in try tree.swiftFiles(in: tree.target("LCUKit")) {
            for (index, line) in file.lines.enumerated() {
                for hatch in hatches where line.contains(hatch.pattern) {
                    Issue.record("\(file.path):\(index + 1) \(hatch.why) — LCUKit must not.")
                }
                if line.contains(acceptTrust), !file.path.hasSuffix(Self.trustDecision) {
                    Issue.record(
                        """
                        \(file.path):\(index + 1) accepts a server trust; only \
                        \(Self.trustDecision) decides that, and only for \(Self.loopback).
                        """)
                }
            }
        }
    }
}
