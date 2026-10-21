public import Foundation

public enum DataDragonError: Error, Equatable, Sendable {
    /// Not `https://ddragon.leagueoflegends.com` exactly; nothing was sent.
    case refused(URL)
    case http(status: Int)
    case transport(String)
}
