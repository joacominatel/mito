public struct DraftSlot: Hashable, Sendable {
    public let cellId: Int
    public let champion: ChampionID?
    public let hover: ChampionID?
    public let role: Role?
    /// 1.0 when assigned by the client; below 1 when inferred.
    public let roleConfidence: Double

    public init(
        cellId: Int,
        champion: ChampionID?,
        hover: ChampionID?,
        role: Role?,
        roleConfidence: Double
    ) {
        self.cellId = cellId
        self.champion = champion
        self.hover = hover
        self.role = role
        self.roleConfidence = roleConfidence
    }
}
