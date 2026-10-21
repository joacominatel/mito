import Foundation
import MitoCore

/// The About tab's content (§5 item 7, §25). Nothing here changes while the app runs except
/// the snapshot, which the view reads from `SnapshotModel`.
enum About {
    struct Notice: Identifiable {
        let name: String
        let license: String
        let url: URL?
        /// The license text as the dependency ships it; MIT requires it in every copy.
        let text: String

        var id: String { name }
    }

    /// Legal text: verbatim English from §5, never translated, so it is a constant rather than a
    /// catalog key a translation could replace.
    static let riotDisclaimer =
        "Mito isn't endorsed by Riot Games and doesn't reflect the views or opinions of Riot "
        + "Games or anyone officially involved in producing or managing Riot Games properties. "
        + "Riot Games, and all associated properties are trademarks or registered trademarks of "
        + "Riot Games, Inc."

    static let repository = URL(string: "https://github.com/joacominatel/mito")

    /// What the app binary links; build-time tooling is not distributed.
    static let notices = [
        Notice(
            name: "GRDB.swift", license: "MIT",
            url: URL(string: "https://github.com/groue/GRDB.swift"),
            text: """
                Copyright (C) 2015-2025 Gwendal Roué

                Permission is hereby granted, free of charge, to any person obtaining a copy of \
                this software and associated documentation files (the "Software"), to deal in \
                the Software without restriction, including without limitation the rights to \
                use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of \
                the Software, and to permit persons to whom the Software is furnished to do so, \
                subject to the following conditions:

                The above copyright notice and this permission notice shall be included in all \
                copies or substantial portions of the Software.

                THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR \
                IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS \
                FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR \
                COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN \
                AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION \
                WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
                """)
    ]

    /// Debug builds read "Mito Dev", which is what the Dock and menu bar call them too.
    static func name(info: [String: Any]?) -> String {
        info?["CFBundleDisplayName"] as? String ?? info?["CFBundleName"] as? String ?? "Mito"
    }

    static func version(info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return String(localized: "Versión \(version) (\(build))", table: "About")
    }

    static func snapshotLine(_ meta: SnapshotMeta?, locale: Locale = .autoupdatingCurrent)
        -> String
    {
        guard let meta else { return String(localized: "Sin estadísticas", table: "About") }
        let matches = meta.matches.formatted(.number.locale(locale))
        return String(
            localized: "Parche \(meta.patch.rawValue) · \(matches) partidas", table: "About")
    }
}
