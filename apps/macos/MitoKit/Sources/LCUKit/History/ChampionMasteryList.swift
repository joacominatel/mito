public import MitoCore

/// `GET /lol-champion-mastery/v1/local-player/champion-mastery`. An entry without a non-zero
/// `championId`, `championPoints`, or `championLevel` is skipped; the PUUID is never read.
public struct ChampionMasteryList: Decodable, Hashable, Sendable {
    public let masteries: [ChampionMastery]

    public init(from decoder: any Decoder) throws {
        masteries = try LossyArray<Entry>(from: decoder).elements.map(\.value)
    }

    private struct Entry: Decodable {
        let value: ChampionMastery

        private enum CodingKeys: String, CodingKey {
            case championId, championPoints, championLevel
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let champion = try container.decodeID(ChampionID.self, forKey: .championId)
            else {
                throw DecodingError.dataCorruptedError(
                    forKey: .championId, in: container, debugDescription: "No champion")
            }
            value = ChampionMastery(
                champion: champion,
                points: try container.decode(Int.self, forKey: .championPoints),
                level: try container.decode(Int.self, forKey: .championLevel))
        }
    }
}
