public import MitoCore

/// No identity fields on purpose: champ select is anonymous (`MITO_CONTEXT.md` §5, §12.1).
public struct ChampSelectSession: Hashable, Sendable {
    public let localPlayerCellId: Int?
    public let myTeam: [Member]
    public let theirTeam: [Member]
    /// Draft steps in order; the actions of one inner array run at the same time.
    public let actions: [[Action]]
    public let bans: Bans
    public let timer: Timer?

    public init(
        localPlayerCellId: Int? = nil,
        myTeam: [Member] = [],
        theirTeam: [Member] = [],
        actions: [[Action]] = [],
        bans: Bans = Bans(),
        timer: Timer? = nil
    ) {
        self.localPlayerCellId = localPlayerCellId
        self.myTeam = myTeam
        self.theirTeam = theirTeam
        self.actions = actions
        self.bans = bans
        self.timer = timer
    }

    /// The session carried by a `LCUTopic.champSelectSession` event.
    public init(_ event: LCUEvent) throws(LCUError) {
        self = try LCUEndpoint<ChampSelectSession>.champSelectSession.decode(event.data)
    }
}

extension ChampSelectSession: Decodable {
    private enum CodingKeys: String, CodingKey {
        case localPlayerCellId, myTeam, theirTeam, actions, bans, timer
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            localPlayerCellId: try container.decodeIfPresent(Int.self, forKey: .localPlayerCellId),
            myTeam: container.decodeLossyArray(Member.self, forKey: .myTeam),
            theirTeam: container.decodeLossyArray(Member.self, forKey: .theirTeam),
            actions: container.decodeLossyArray(LossyArray<Action>.self, forKey: .actions)
                .map(\.elements),
            bans: try container.decodeIfPresent(Bans.self, forKey: .bans) ?? Bans(),
            timer: try container.decodeIfPresent(Timer.self, forKey: .timer)
        )
    }
}

extension ChampSelectSession {
    public struct Member: Hashable, Sendable {
        public let cellId: Int?
        public let championId: ChampionID?
        /// The hover, before the pick is locked.
        public let championPickIntent: ChampionID?
        public let assignedPosition: AssignedPosition
        public let spell1Id: SummonerSpellID?
        public let spell2Id: SummonerSpellID?
        /// The map side, `1` or `2`.
        public let team: Int?

        public init(
            cellId: Int? = nil,
            championId: ChampionID? = nil,
            championPickIntent: ChampionID? = nil,
            assignedPosition: AssignedPosition = .unassigned,
            spell1Id: SummonerSpellID? = nil,
            spell2Id: SummonerSpellID? = nil,
            team: Int? = nil
        ) {
            self.cellId = cellId
            self.championId = championId
            self.championPickIntent = championPickIntent
            self.assignedPosition = assignedPosition
            self.spell1Id = spell1Id
            self.spell2Id = spell2Id
            self.team = team
        }
    }

    public enum AssignedPosition: Hashable, Sendable {
        /// `""` or missing: blind pick, ARAM, or an enemy cell.
        case unassigned
        case role(Role)
        case unknown(String)

        public init(_ rawValue: String) {
            if rawValue.isEmpty {
                self = .unassigned
            } else if let role = Role(lcuPosition: rawValue) {
                self = .role(role)
            } else {
                self = .unknown(rawValue)
            }
        }

        public var role: Role? {
            if case .role(let role) = self { role } else { nil }
        }
    }

    public struct Bans: Hashable, Sendable {
        public let myTeamBans: [ChampionID]
        public let theirTeamBans: [ChampionID]

        public init(myTeamBans: [ChampionID] = [], theirTeamBans: [ChampionID] = []) {
            self.myTeamBans = myTeamBans
            self.theirTeamBans = theirTeamBans
        }
    }

    public struct Timer: Hashable, Sendable {
        public let phase: Phase?
        /// Milliseconds.
        public let adjustedTimeLeftInPhase: Int?

        public init(phase: Phase? = nil, adjustedTimeLeftInPhase: Int? = nil) {
            self.phase = phase
            self.adjustedTimeLeftInPhase = adjustedTimeLeftInPhase
        }

        public enum Phase: Hashable, Sendable {
            case planning
            case banPick
            case finalization
            case unknown(String)

            public init(_ rawValue: String) {
                switch rawValue {
                case "PLANNING": self = .planning
                case "BAN_PICK": self = .banPick
                case "FINALIZATION": self = .finalization
                default: self = .unknown(rawValue)
                }
            }
        }
    }
}

extension ChampSelectSession.Member: Decodable {
    private enum CodingKeys: String, CodingKey {
        case cellId, championId, championPickIntent, assignedPosition, spell1Id, spell2Id, team
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            cellId: try container.decodeIfPresent(Int.self, forKey: .cellId),
            championId: try container.decodeID(ChampionID.self, forKey: .championId),
            championPickIntent: try container.decodeID(
                ChampionID.self, forKey: .championPickIntent),
            assignedPosition: try container.decodeIfPresent(String.self, forKey: .assignedPosition)
                .map(ChampSelectSession.AssignedPosition.init) ?? .unassigned,
            spell1Id: try container.decodeID(SummonerSpellID.self, forKey: .spell1Id),
            spell2Id: try container.decodeID(SummonerSpellID.self, forKey: .spell2Id),
            team: try container.decodeIfPresent(Int.self, forKey: .team)
        )
    }
}

extension ChampSelectSession.Bans: Decodable {
    private enum CodingKeys: String, CodingKey {
        case myTeamBans, theirTeamBans
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            myTeamBans: container.decodeBans(forKey: .myTeamBans),
            theirTeamBans: container.decodeBans(forKey: .theirTeamBans)
        )
    }
}

extension ChampSelectSession.Timer: Decodable {
    private enum CodingKeys: String, CodingKey {
        case phase, adjustedTimeLeftInPhase
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            phase: try container.decodeIfPresent(String.self, forKey: .phase).map(Phase.init),
            // The client may send fractional milliseconds; a bad timer must not sink the session.
            adjustedTimeLeftInPhase: (try? container.decodeIfPresent(
                Double.self, forKey: .adjustedTimeLeftInPhase))?.map { Int($0.rounded()) }
        )
    }
}

extension KeyedDecodingContainer {
    // 0 and -1 are "no champion" here too.
    fileprivate func decodeBans(forKey key: Key) -> [ChampionID] {
        decodeLossyArray(Int.self, forKey: key).filter { $0 > 0 }.map(ChampionID.init)
    }
}
