import Foundation
import Testing

/// The LCU token is never logged, and shipped code logs through `os.Logger`, never `print`
/// (charter security dimension, `.claude/rules/macos.md`).
struct SourceHygieneTests {
    @Test func noLoggingCallInterpolatesASecret() throws {
        let tree = try SourceTree()
        let logCall =
            #/(?:\b(?:print|debugPrint|dump|NSLog|os_log)|\.(?:trace|debug|info|notice|warning|error|critical|fault|log))\(/#
        let secret = #/\\\([^)]*(?i:token|password|passwd|secret|credential|authorization)/#

        for root in try tree.shippedRoots() {
            for file in try tree.swiftFiles(in: root) {
                for match in file.code.matches(of: logCall) {
                    let arguments = Self.balancedArguments(
                        in: file.code, from: match.range.upperBound)
                    if arguments.contains(secret) {
                        let line = file.code[..<match.range.lowerBound].count { $0 == "\n" } + 1
                        Issue.record(
                            """
                            \(file.path):\(line) logs a secret — the LCU token is never logged, \
                            not even with privacy: .private.
                            """)
                    }
                }
            }
        }
    }

    @Test func noPrintInShippedSources() throws {
        let tree = try SourceTree()
        let printCall = #/(?:^|[^\w.])(?:print|debugPrint)\(/#

        for root in try tree.shippedRoots() {
            for file in try tree.swiftFiles(in: root) {
                for (index, line) in file.lines.enumerated() where line.contains(printCall) {
                    Issue.record(
                        "\(file.path):\(index + 1) calls print — use the module's os.Logger category."
                    )
                }
            }
        }
    }

    /// The text up to the parenthesis closing the call, across lines.
    private static func balancedArguments(in code: String, from start: String.Index) -> Substring {
        var depth = 1
        var index = start
        while index < code.endIndex {
            switch code[index] {
            case "(": depth += 1
            case ")":
                depth -= 1
                if depth == 0 { return code[start..<index] }
            default: break
            }
            index = code.index(after: index)
        }
        return code[start...]
    }
}
