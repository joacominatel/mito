/// The `X.Y` key taken from `info.gameVersion` (`MITO_CONTEXT.md` §14.9), e.g. `16.21`.
public struct Patch: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}
