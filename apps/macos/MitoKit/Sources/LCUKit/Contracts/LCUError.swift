public import Foundation

public enum LCUError: Error, Equatable, Sendable {
    case notConnected
    /// A non-2xx response; the body is the client's JSON error payload, if any.
    case http(status: Int, body: Data)
    case transport(String)
    case decoding(String)
    case encoding(String)
}
