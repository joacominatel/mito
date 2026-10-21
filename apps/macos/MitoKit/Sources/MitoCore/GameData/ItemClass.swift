/// Raw values are the snapshot's `item_classes.class` encoding (`MITO_CONTEXT.md` §17).
public enum ItemClass: RawRepresentable, Hashable, Sendable {
    case starter
    case consumable
    case component
    case bootsT1
    case bootsT2
    case legendary
    case supportUpgrade
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "starter": self = .starter
        case "consumable": self = .consumable
        case "component": self = .component
        case "boots_t1": self = .bootsT1
        case "boots_t2": self = .bootsT2
        case "legendary": self = .legendary
        case "support_upgrade": self = .supportUpgrade
        default: self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .starter: "starter"
        case .consumable: "consumable"
        case .component: "component"
        case .bootsT1: "boots_t1"
        case .bootsT2: "boots_t2"
        case .legendary: "legendary"
        case .supportUpgrade: "support_upgrade"
        case .unknown(let value): value
        }
    }
}
