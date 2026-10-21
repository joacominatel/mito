import Foundation

/// The token stays inside LCUKit and is redacted from every textual and reflected form.
public struct LCUCredentials: Sendable, Equatable {
    public let port: Int
    let token: String

    public init(port: Int, token: String) {
        self.port = port
        self.token = token
    }

    var authHeader: String {
        "Basic " + Data("riot:\(token)".utf8).base64EncodedString()
    }
}

extension LCUCredentials: CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public var description: String { "LCUCredentials(port: \(port), token: <redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["port": port, "token": "<redacted>"], displayStyle: .struct)
    }
}
