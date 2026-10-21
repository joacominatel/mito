import Foundation
public import MitoCore

/// The client's build version, e.g. `16.21.8298620`. Only ASCII letters, digits, and `._-`, so
/// it is safe as a directory name and as `IconRequest.gameVersion`.
public struct GameVersion: Hashable, Sendable, Decodable {
    /// Without the build metadata: the client sends `16.21.8298620+branch.releases-16-21…`.
    public let rawValue: String
    /// The first two components, the numbering Data Dragon and the snapshot use.
    public let patch: Patch

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let version = try container.decode(String.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0 != "+" }
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2,
            components.prefix(2).allSatisfy({ !$0.isEmpty && $0.allSatisfy(Self.isDigit) }),
            version.allSatisfy({
                Self.isDigit($0) || ($0.isASCII && $0.isLetter) || "._-".contains($0)
            })
        else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Not a game version: \(version)")
        }
        rawValue = String(version)
        patch = Patch(rawValue: components.prefix(2).joined(separator: "."))
    }

    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}

extension LCUEndpoint where Response == GameVersion {
    /// The body is a bare JSON string.
    public static var gameVersion: Self {
        Self(method: .get, path: "/lol-patch/v1/game-version")
    }
}
