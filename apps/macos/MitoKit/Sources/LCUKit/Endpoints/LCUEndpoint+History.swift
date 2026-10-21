import Foundation
public import MitoCore

extension LCUEndpoint where Response == MatchHistoryPage {
    /// `localPUUID` is `CurrentSummoner.puuid`, compared in memory and never kept.
    public static func matchHistory(begIndex: Int = 0, endIndex: Int = 20, localPUUID: String?)
        -> Self
    {
        Self(
            method: .get,
            path: "/lol-match-history/v1/products/lol/current-summoner/matches"
                + "?begIndex=\(begIndex)&endIndex=\(endIndex)"
        ) {
            try historyDecoder(localPUUID: localPUUID).decode(MatchHistoryPage.self, from: $0)
        }
    }
}

extension LCUEndpoint where Response == MatchHistoryGame {
    /// Every participant of one game; the local player is found as in `matchHistory`.
    public static func matchHistoryGame(_ game: GameID, localPUUID: String?) -> Self {
        Self(method: .get, path: "/lol-match-history/v1/games/\(game.rawValue)") {
            try historyDecoder(localPUUID: localPUUID).decode(MatchHistoryGame.self, from: $0)
        }
    }
}

private func historyDecoder(localPUUID: String?) -> JSONDecoder {
    let decoder = JSONDecoder()
    if let key = CodingUserInfoKey.localPUUID {
        decoder.userInfo[key] = localPUUID
    }
    return decoder
}

extension LCUEndpoint where Response == ChampionMasteryList {
    /// Read live when needed, never stored (§17).
    public static var championMastery: Self {
        Self(method: .get, path: "/lol-champion-mastery/v1/local-player/champion-mastery")
    }
}
