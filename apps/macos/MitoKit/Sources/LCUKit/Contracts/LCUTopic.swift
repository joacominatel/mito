/// The v1 WAMP subscriptions (`MITO_CONTEXT.md` §10.5); never the firehose.
public enum LCUTopic: String, CaseIterable, Hashable, Sendable {
    case gameflowPhase = "OnJsonApiEvent_lol-gameflow_v1_gameflow-phase"
    case readyCheck = "OnJsonApiEvent_lol-matchmaking_v1_ready-check"
    case champSelectSession = "OnJsonApiEvent_lol-champ-select_v1_session"
    case lobby = "OnJsonApiEvent_lol-lobby_v2_lobby"
    case currentSummoner = "OnJsonApiEvent_lol-summoner_v1_current-summoner"
}
