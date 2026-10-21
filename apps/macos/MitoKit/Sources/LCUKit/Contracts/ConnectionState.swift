/// `MITO_CONTEXT.md` §11.2.
public enum ConnectionState: Hashable, Sendable {
    case searching
    case connecting
    case connected
}
