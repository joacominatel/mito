import Foundation
public import MitoCore

/// One hand-written matchup tip from a locale's tips file (`MITO_CONTEXT.md` §14.12).
public struct CuratedTipRecord: Hashable, Sendable {
    public let champion: ChampionID
    public let role: Role
    /// `nil` is a general tip for the champion in the role (`opp_id = 0`).
    public let opponent: ChampionID?
    /// The last patch the tip was checked against.
    public let reviewedPatch: Patch
    public let text: String

    public init(
        champion: ChampionID, role: Role, opponent: ChampionID?, reviewedPatch: Patch,
        text: String
    ) {
        self.champion = champion
        self.role = role
        self.opponent = opponent
        self.reviewedPatch = reviewedPatch
        self.text = text
    }
}

/// A locale's curated tips, read from its file or empty when there is none.
public struct CuratedTips: Equatable, Sendable {
    public static let empty = CuratedTips(records: [])

    static let supportedFormatVersions = 1...1
    static let sizeLimit = 2 * 1024 * 1024

    public let records: [CuratedTipRecord]

    public init(records: [CuratedTipRecord]) {
        self.records = records
    }

    /// The tips against `opponent` first, then the general ones; only the general ones without an
    /// opponent. File order within each group.
    public func tips(for champion: ChampionID, role: Role, against opponent: ChampionID?)
        -> [CuratedTipRecord]
    {
        let own = records.filter { $0.champion == champion && $0.role == role }
        let general = own.filter { $0.opponent == nil }
        guard let opponent else { return general }
        return own.filter { $0.opponent == opponent } + general
    }

    /// `nil` when the file is not the §14.12 shape or not a supported format for `locale`. A tip
    /// that does not decode, has an unknown role, or has no text is skipped.
    static func decode(_ data: Data, locale: String) -> CuratedTips? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let file = try? decoder.decode(File.self, from: data),
            supportedFormatVersions.contains(file.formatVersion), file.locale == locale
        else { return nil }
        return CuratedTips(records: file.tips.compactMap(\.record))
    }

    private struct File: Decodable {
        let formatVersion: Int
        let locale: String
        let tips: [LossyTip]
    }

    private struct LossyTip: Decodable {
        private struct Raw: Decodable {
            let championId: Int
            let role: String
            let oppId: Int
            let reviewedPatch: String
            let text: String
        }

        let record: CuratedTipRecord?

        init(from decoder: any Decoder) throws {
            guard let raw = try? Raw(from: decoder), raw.championId > 0, raw.oppId >= 0,
                let role = Role(rawValue: raw.role),
                SnapshotManifest.isPatch(raw.reviewedPatch),
                !raw.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                record = nil
                return
            }
            record = CuratedTipRecord(
                champion: ChampionID(rawValue: raw.championId), role: role,
                opponent: raw.oppId == 0 ? nil : ChampionID(rawValue: raw.oppId),
                reviewedPatch: Patch(rawValue: raw.reviewedPatch), text: raw.text)
        }
    }
}
