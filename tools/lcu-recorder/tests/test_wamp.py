import json

from lcu_recorder.wamp import TOPICS, Event, parse_event, subscribe_frame, unsubscribe_frame

PHASE = "OnJsonApiEvent_lol-gameflow_v1_gameflow-phase"


def frame(*parts) -> str:
    return json.dumps(list(parts))


def test_decodes_an_event_frame_for_a_subscribed_topic():
    message = frame(
        8,
        PHASE,
        {
            "uri": "/lol-gameflow/v1/gameflow-phase",
            "eventType": "Update",
            "data": "ChampSelect",
            "extra": 1,
        },
    )
    assert parse_event(message) == Event(
        PHASE, "/lol-gameflow/v1/gameflow-phase", "Update", "ChampSelect"
    )


def test_missing_data_decodes_as_null_and_bytes_are_accepted():
    message = frame(8, PHASE, {"uri": "/x", "eventType": "Delete"}).encode()
    assert parse_event(message).data is None


def test_ignores_other_opcodes_topics_and_malformed_frames():
    payload = {"uri": "/x", "eventType": "Update", "data": 1}
    for message in [
        frame(0, "session", 1, "server"),
        frame(5, PHASE),
        frame(8, "OnJsonApiEvent", payload),
        frame(True, PHASE, payload),
        frame(8.0, PHASE, payload),
        frame(8, PHASE, {"uri": 1, "eventType": "Update"}),
        frame(8, PHASE, {"uri": "/x"}),
        frame(8, PHASE, "not an object"),
        frame(8, PHASE),
        json.dumps({"opcode": 8}),
        "[8, broken",
        "",
    ]:
        assert parse_event(message) is None, message


def test_frames_mito_sends():
    assert json.loads(subscribe_frame(PHASE)) == [5, PHASE]
    assert json.loads(unsubscribe_frame(PHASE)) == [6, PHASE]


def test_topics_are_the_five_v1_subscriptions_and_never_the_firehose():
    assert len(TOPICS) == 5
    assert "OnJsonApiEvent" not in TOPICS
