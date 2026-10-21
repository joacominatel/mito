/// Raw values are the `duration_curves.bucket` encoding (§17): game length in minutes, each
/// bucket `[lowerMinutes, upperMinutes)`.
public enum DurationBucket: String, CaseIterable, Hashable, Sendable {
    case under20 = "<20"
    case from20To25 = "20-25"
    case from25To30 = "25-30"
    case from30To35 = "30-35"
    case from35To40 = "35-40"
    case over40 = "40+"

    public var lowerMinutes: Int {
        switch self {
        case .under20: 0
        case .from20To25: 20
        case .from25To30: 25
        case .from30To35: 30
        case .from35To40: 35
        case .over40: 40
        }
    }

    /// Exclusive; `nil` for `40+`.
    public var upperMinutes: Int? {
        switch self {
        case .under20: 20
        case .from20To25: 25
        case .from25To30: 30
        case .from30To35: 35
        case .from35To40: 40
        case .over40: nil
        }
    }
}
