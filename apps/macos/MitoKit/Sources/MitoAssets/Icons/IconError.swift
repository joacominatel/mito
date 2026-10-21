public enum IconError: Error, Equatable, Sendable {
    /// Not a `/lol-game-data/assets/` path, or one that could escape it.
    case invalidAssetPath(String)
    /// Empty, or not safe as a cache directory name.
    case invalidGameVersion(String)
    /// Not `https://ddragon.leagueoflegends.com`.
    case invalidDataDragonURL(String)
    /// Neither the client nor Data Dragon produced the icon.
    case unavailable(assetPath: String)
}
