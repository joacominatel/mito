/// The signed-in account, from `GET /lol-summoner/v1/current-summoner`.
///
/// Field names follow `MITO_CONTEXT.md` §10.6 and are not yet verified against a recording.
public struct CurrentSummoner: Decodable, Hashable, Sendable {
    public let puuid: String?
    public let summonerId: Int?
    public let gameName: String?
    public let tagLine: String?
    public let summonerLevel: Int?

    public init(
        puuid: String? = nil,
        summonerId: Int? = nil,
        gameName: String? = nil,
        tagLine: String? = nil,
        summonerLevel: Int? = nil
    ) {
        self.puuid = puuid
        self.summonerId = summonerId
        self.gameName = gameName
        self.tagLine = tagLine
        self.summonerLevel = summonerLevel
    }

    /// `gameName#tagLine`, or `nil` when either part is missing or empty.
    public var riotID: String? {
        guard let gameName, !gameName.isEmpty, let tagLine, !tagLine.isEmpty else { return nil }
        return "\(gameName)#\(tagLine)"
    }
}

// Identity is personal data: a stray interpolation must not leak it into a log.
extension CurrentSummoner: CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    public var description: String {
        "CurrentSummoner(summonerLevel: \(summonerLevel.map(String.init) ?? "nil"), identity: <redacted>)"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(
            self,
            children: ["summonerLevel": summonerLevel as Any, "identity": "<redacted>"],
            displayStyle: .struct)
    }
}
