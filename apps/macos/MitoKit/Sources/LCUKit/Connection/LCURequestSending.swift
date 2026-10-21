/// The REST seam of `LCUClient`: the live `LCURESTClient`, or a fake in tests.
protocol LCURequestSending: Sendable {
    func send<R: Decodable & Sendable>(_ endpoint: LCUEndpoint<R>) async throws(LCUError) -> R
}

extension LCURESTClient: LCURequestSending {}
