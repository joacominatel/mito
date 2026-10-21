import Foundation
import MitoAssets
import Synchronization
import Testing

let pngIcon = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01])
let otherPNGIcon = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x02])
let testBundleIdentifier = "com.joacominatel.mito.tests"

/// Serves one canned answer for every URL, optionally holding each call until `release()`.
final class FakeDataDragon: DataDragonTransport {
    enum Failure: Error { case scripted }

    private struct Gate {
        var open: Bool
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let answer: Result<Data, Failure>
    private let gate: Mutex<Gate>
    private let recorded = Mutex<[URL]>([])

    init(answer: Result<Data, Failure> = .success(pngIcon), gated: Bool = false) {
        self.answer = answer
        gate = Mutex(Gate(open: !gated))
    }

    var urls: [URL] { recorded.withLock { $0 } }

    func release() {
        let waiting = gate.withLock { gate in
            gate.open = true
            defer { gate.waiting = [] }
            return gate.waiting
        }
        for continuation in waiting { continuation.resume() }
    }

    func data(from url: URL) async throws -> Data {
        recorded.withLock { $0.append(url) }
        await withCheckedContinuation { continuation in
            let isOpen = gate.withLock { gate in
                if !gate.open { gate.waiting.append(continuation) }
                return gate.open
            }
            if isOpen { continuation.resume() }
        }
        return try answer.get()
    }
}

func withTemporaryDirectory(_ body: (URL) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "IconLoaderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(directory)
}

/// Fails the test instead of hanging when `condition` never holds.
func waitUntil(_ condition: () async -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(5)
    while await !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("condition never held")
            return
        }
        await Task.yield()
    }
}
