import Foundation

/// `<root>/<locale>.json`, the verified file exactly as downloaded, so its own sha256 is the cache
/// key and no record is needed.
struct TipsCache {
    let root: URL

    private var fileManager: FileManager { .default }

    /// The locale becomes a file name, so nothing but a language tag gets through.
    func fileURL(locale: String) -> URL? {
        guard locale.wholeMatch(of: #/[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*/#) != nil else {
            return nil
        }
        return root.appending(path: "\(locale).json", directoryHint: .notDirectory)
    }

    func data(locale: String) -> Data? {
        fileURL(locale: locale).flatMap { try? Data(contentsOf: $0) }
    }

    /// Atomic, so a failure keeps the previous file.
    func install(_ data: Data, locale: String) throws(SnapshotDownloadError) {
        guard let file = fileURL(locale: locale) else { throw .installFailed }
        do {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            throw .installFailed
        }
    }

    func remove(locale: String) {
        guard let file = fileURL(locale: locale) else { return }
        try? fileManager.removeItem(at: file)
    }
}
