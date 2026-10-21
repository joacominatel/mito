import json
from dataclasses import dataclass
from typing import Any

SUBSCRIBE = 5
UNSUBSCRIBE = 6
EVENT = 8

# Mirrors LCUTopic in apps/macos/MitoKit/Sources/LCUKit/Contracts/LCUTopic.swift.
TOPICS = (
    "OnJsonApiEvent_lol-gameflow_v1_gameflow-phase",
    "OnJsonApiEvent_lol-matchmaking_v1_ready-check",
    "OnJsonApiEvent_lol-champ-select_v1_session",
    "OnJsonApiEvent_lol-lobby_v2_lobby",
    "OnJsonApiEvent_lol-summoner_v1_current-summoner",
)


@dataclass(frozen=True)
class Event:
    topic: str
    uri: str
    event_type: str
    data: Any


def subscribe_frame(topic: str) -> str:
    return json.dumps([SUBSCRIBE, topic])


def unsubscribe_frame(topic: str) -> str:
    return json.dumps([UNSUBSCRIBE, topic])


def parse_event(message: str | bytes) -> Event | None:
    """Same acceptance rule as LCUKit's WAMPCodec; everything else is ignorable."""
    try:
        frame = json.loads(message)
    except ValueError:
        return None
    if not isinstance(frame, list) or len(frame) < 3:
        return None
    opcode, topic, payload = frame[0], frame[1], frame[2]
    if type(opcode) is not int or opcode != EVENT or topic not in TOPICS:
        return None
    if not isinstance(payload, dict):
        return None
    uri, event_type = payload.get("uri"), payload.get("eventType")
    if not isinstance(uri, str) or not isinstance(event_type, str):
        return None
    return Event(topic=topic, uri=uri, event_type=event_type, data=payload.get("data"))
