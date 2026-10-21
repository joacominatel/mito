import MitoCore

/// The system notifications of §22.5. Posting lands with each owning feature.
enum MitoNotification: Hashable {
    case matchAccepted
    case pickTurn(recommended: ChampionID?)
    case loadoutImported(champion: ChampionID, opponent: ChampionID?)
}
