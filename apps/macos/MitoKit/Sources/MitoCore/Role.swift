/// Raw values are the canonical snapshot encoding (`MITO_CONTEXT.md` §17).
public enum Role: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case top = "TOP"
    case jungle = "JUNGLE"
    case middle = "MIDDLE"
    case bottom = "BOTTOM"
    case utility = "UTILITY"

    /// The champ select `assignedPosition` (`"middle"`); `""` in blind pick and unknown values
    /// yield `nil`.
    public init?(lcuPosition: String) {
        self.init(rawValue: lcuPosition.uppercased())
    }
}
