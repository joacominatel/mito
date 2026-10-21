import json
from pathlib import Path

from websockets.exceptions import ConnectionClosedError

from lcu_recorder import cli, wamp
from lcu_recorder.discovery import Credentials
from lcu_recorder.lcu import Response

PHASE_TOPIC = "OnJsonApiEvent_lol-gameflow_v1_gameflow-phase"


class Clock:
    def __init__(self):
        self.now = 100.0

    def __call__(self):
        return self.now


class FakeHttp:
    def __init__(self, bodies):
        self.bodies = bodies
        self.paths = []

    def get(self, path):
        self.paths.append(path)
        return Response(200, self.bodies.get(path)) if path in self.bodies else Response(404, None)


class FakeEvents:
    """Each script step advances the clock, then yields a message, None, or raises."""

    def __init__(self, clock, script):
        self.clock, self.script = clock, list(script)
        self.subscribed, self.unsubscribed, self.closed = [], [], False

    def subscribe(self, topics):
        self.subscribed = list(topics)

    def unsubscribe(self, topics):
        self.unsubscribed = list(topics)

    def close(self):
        self.closed = True

    def receive(self, timeout):
        advance, message = self.script.pop(0) if self.script else (timeout, None)
        self.clock.now += advance
        if isinstance(message, BaseException):
            raise message
        return message


def event(data):
    return json.dumps(
        [
            8,
            PHASE_TOPIC,
            {"uri": "/lol-gameflow/v1/gameflow-phase", "eventType": "Update", "data": data},
        ]
    )


def test_records_events_with_elapsed_ms_and_stops_at_the_duration():
    clock = Clock()
    http = FakeHttp(
        {"/lol-patch/v1/game-version": "15.20.712.4321", "/lol-gameflow/v1/gameflow-phase": "Lobby"}
    )
    events = FakeEvents(
        clock, [(1.5, event("ReadyCheck")), (0.25, '[0,"welcome"]'), (0.5, event("ChampSelect"))]
    )
    recording = cli.record(http, events, duration_s=12, clock=clock)

    assert [(e.t_ms, e.data) for e in recording.events] == [
        (1500, "ReadyCheck"),
        (2250, "ChampSelect"),
    ]
    assert events.subscribed == list(wamp.TOPICS) == events.unsubscribed
    assert events.closed
    assert recording.client_patch == "15.20"
    assert clock.now >= 112


def test_snapshots_every_interval_and_records_only_changes():
    clock = Clock()
    http = FakeHttp({"/lol-gameflow/v1/gameflow-phase": "Lobby"})
    events = FakeEvents(clock, [])
    recording = cli.record(http, events, duration_s=11, clock=clock)

    phase_gets = http.paths.count("/lol-gameflow/v1/gameflow-phase")
    phase_lines = [r for r in recording.rest if r.path == "/lol-gameflow/v1/gameflow-phase"]
    assert phase_gets == 3
    assert len(phase_lines) == 1
    assert http.paths[:2] == list(cli.ONCE_PATHS)
    assert http.paths.count("/lol-summoner/v1/current-summoner") == 1
    assert all(r.method == "GET" for r in recording.rest)


def test_ctrl_c_and_a_closed_client_end_the_recording_cleanly():
    for stop in (KeyboardInterrupt(), ConnectionClosedError(None, None)):
        clock = Clock()
        events = FakeEvents(clock, [(1, event("Lobby")), (1, stop)])
        recording = cli.record(FakeHttp({}), events, duration_s=None, clock=clock)
        assert [e.data for e in recording.events] == ["Lobby"]
        assert events.unsubscribed == list(wamp.TOPICS) and events.closed


def test_queue_id_comes_from_the_gameflow_session_then_the_lobby():
    clock = Clock()
    http = FakeHttp(
        {
            "/lol-lobby/v2/lobby": {"gameConfig": {"queueId": 400}},
            "/lol-gameflow/v1/session": {"gameData": {"queue": {"id": 420}}},
        }
    )
    assert cli.record(http, FakeEvents(clock, []), 1, clock=clock).queue_id == 420

    clock = Clock()
    http = FakeHttp(
        {
            "/lol-lobby/v2/lobby": {"gameConfig": {"queueId": 400}},
            "/lol-gameflow/v1/session": {"gameData": {"queue": {"id": -1}}},
        }
    )
    assert cli.record(http, FakeEvents(clock, []), 1, clock=clock).queue_id == 400


def test_main_refuses_to_run_without_a_client(tmp_path: Path, monkeypatch, capsys):
    monkeypatch.setattr(cli, "discover", lambda _lockfile: None)
    assert cli.main(["record", "ready-check", "--out", str(tmp_path)]) == 1
    assert "No running League client" in capsys.readouterr().err
    assert not (tmp_path / "ready-check").exists()


def test_main_rejects_a_bad_scenario_name(tmp_path: Path):
    assert cli.main(["record", "../x", "--out", str(tmp_path)]) == 1


def test_main_records_and_writes_an_anonymized_scenario(tmp_path: Path, monkeypatch):
    creds = Credentials(port=54321, token="s3cr3tT0ken")
    clock = Clock()
    summoner = {"puuid": "6f1c2b3a-1111-4222-8333-944455556666", "gameName": "RealPlayer"}
    http = FakeHttp({"/lol-summoner/v1/current-summoner": summoner})
    events = FakeEvents(clock, [(1, event("RealPlayer joined")), (1, KeyboardInterrupt())])
    monkeypatch.setattr(cli, "discover", lambda _lockfile: creds)
    monkeypatch.setattr(cli.LCUEvents, "open", classmethod(lambda _cls, _creds: events))
    monkeypatch.setattr(cli, "LCUHttp", lambda _creds: http)

    assert cli.main(["record", "ready-check", "--out", str(tmp_path)]) == 0

    target = tmp_path / "ready-check"
    text = "".join(p.read_text() for p in target.iterdir())
    for secret in ["RealPlayer", "6f1c2b3a", "s3cr3tT0ken", "54321"]:
        assert secret not in text
    assert json.loads((target / "scenario.json").read_text())["anonymized"] is True
