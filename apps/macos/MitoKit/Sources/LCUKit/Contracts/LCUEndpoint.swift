public import Foundation

/// Endpoints are declared per group in `Endpoints/LCUEndpoint+<Group>.swift`, never as raw
/// paths at the call site.
public struct LCUEndpoint<Response: Decodable & Sendable>: Sendable {
    public let method: HTTPMethod
    public let path: String
    public let body: Data?
    private let decoder: @Sendable (Data) throws -> Response

    public init(method: HTTPMethod, path: String, body: Data? = nil) {
        self.init(method: method, path: path, body: body) {
            try JSONDecoder().decode(Response.self, from: $0)
        }
    }

    public init<Body: Encodable>(method: HTTPMethod, path: String, json: Body) throws(LCUError) {
        self.init(method: method, path: path, body: try encodeJSON(json))
    }

    public init(
        method: HTTPMethod,
        path: String,
        body: Data? = nil,
        decode: @escaping @Sendable (Data) throws -> Response
    ) {
        self.method = method
        self.path = path
        self.body = body
        self.decoder = decode
    }

    public func decode(_ data: Data) throws(LCUError) -> Response {
        do {
            return try decoder(data)
        } catch {
            throw .decoding(String(describing: error))
        }
    }
}

/// The response of an endpoint that answers with an empty body (e.g. 204).
public struct LCUNoContent: Decodable, Hashable, Sendable {
    public init() {}
}

extension LCUEndpoint where Response == LCUNoContent {
    public init(method: HTTPMethod, path: String, body: Data? = nil) {
        self.init(method: method, path: path, body: body) { _ in LCUNoContent() }
    }

    public init<Body: Encodable>(method: HTTPMethod, path: String, json: Body) throws(LCUError) {
        self.init(method: method, path: path, body: try encodeJSON(json))
    }
}

private func encodeJSON<Body: Encodable>(_ body: Body) throws(LCUError) -> Data {
    do {
        return try JSONEncoder().encode(body)
    } catch {
        throw .encoding(String(describing: error))
    }
}
