import Foundation
import GRDB
import MitoTestSupport

/// A temporary copy of the committed fixture, edited with SQL; the fixture itself is never
/// opened for writing.
enum SnapshotCopy {
    static let fixture = Fixtures.url("snapshot/emerald_plus.sqlite")

    static func with(_ edit: String? = nil, _ body: (URL) throws -> Void) throws {
        try withDirectory { directory in
            let copy = directory.appending(path: "emerald_plus.sqlite")
            try FileManager.default.copyItem(at: fixture, to: copy)
            if let edit {
                let queue = try DatabaseQueue(path: copy.path(percentEncoded: false))
                try queue.write { try $0.execute(sql: edit) }
                try queue.close()
            }
            try body(copy)
        }
    }

    static func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "SnapshotReaderTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }
}
