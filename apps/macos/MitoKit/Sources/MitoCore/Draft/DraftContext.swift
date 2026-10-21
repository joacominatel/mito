public struct DraftContext: Hashable, Sendable {
    public let queue: QueueType
    public let patch: Patch
    /// `nil` in blind pick and ARAM.
    public let myRole: Role?
    public let myCellId: Int
    /// Includes the local player.
    public let allies: [DraftSlot]
    public let enemies: [DraftSlot]
    public let bans: Set<ChampionID>
    public let pickable: Set<ChampionID>
    public let phase: DraftPhase
    public let isMyTurnToPick: Bool
    public let isMyTurnToBan: Bool

    public init(
        queue: QueueType,
        patch: Patch,
        myRole: Role?,
        myCellId: Int,
        allies: [DraftSlot],
        enemies: [DraftSlot],
        bans: Set<ChampionID>,
        pickable: Set<ChampionID>,
        phase: DraftPhase,
        isMyTurnToPick: Bool,
        isMyTurnToBan: Bool
    ) {
        self.queue = queue
        self.patch = patch
        self.myRole = myRole
        self.myCellId = myCellId
        self.allies = allies
        self.enemies = enemies
        self.bans = bans
        self.pickable = pickable
        self.phase = phase
        self.isMyTurnToPick = isMyTurnToPick
        self.isMyTurnToBan = isMyTurnToBan
    }
}
