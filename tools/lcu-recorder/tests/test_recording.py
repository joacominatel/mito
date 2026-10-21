import json
from pathlib import Path

import pytest

from lcu_recorder.anonymize import LeakError
from lcu_recorder.discovery import Credentials
from lcu_recorder.recording import (
    EventLine,
    Recording,
    RestLine,
    render,
    scenario_dir,
    write_scenario,
)

CREDS = Credentials(port=54321, token="s3cr3tT0ken")
PHASE_TOPIC = "OnJsonApiEvent_lol-gameflow_v1_gameflow-phase"


def sample() -> Recording:
    return Recording(
        client_patch="25.20",
        queue_id=420,
        rest=[
            RestLine("GET", "/lol-gameflow/v1/gameflow-phase", 200, "ChampSelect"),
            RestLine("GET", "/lol-matchmaking/v1/ready-check", 404, None),
            RestLine(
                "GET",
                "/lol-summoner/v1/current-summoner",
                200,
                {"puuid": "6f1c2b3a-1111-4222-8333-944455556666", "gameName": "RealPlayer"},
            ),
        ],
        events=[
            EventLine(1532, PHASE_TOPIC, "/lol-gameflow/v1/gameflow-phase", "Update", "ChampSelect")
        ],
    )


def test_writes_the_three_v0_files_with_exact_shapes(tmp_path: Path):
    target = tmp_path / "ready-check"
    write_scenario(target, sample(), CREDS)

    assert sorted(p.name for p in target.iterdir()) == [
        "events.jsonl",
        "rest.jsonl",
        "scenario.json",
    ]
    scenario = json.loads((target / "scenario.json").read_text())
    assert list(scenario) == ["format", "clientPatch", "queueId", "recorderVersion", "anonymized"]
    assert scenario == {
        "format": 0,
        "clientPatch": "25.20",
        "queueId": 420,
        "recorderVersion": "0.1.0",
        "anonymized": True,
    }

    rest = (target / "rest.jsonl").read_text().splitlines()
    assert rest[0] == (
        '{"method":"GET","path":"/lol-gameflow/v1/gameflow-phase",'
        '"status":200,"body":"ChampSelect"}'
    )
    assert json.loads(rest[1]) == {
        "method": "GET",
        "path": "/lol-matchmaking/v1/ready-check",
        "status": 404,
        "body": None,
    }
    assert list(json.loads(rest[2])) == ["method", "path", "status", "body"]

    events = (target / "events.jsonl").read_text().splitlines()
    assert events == [
        '{"t_ms":1532,"topic":"OnJsonApiEvent_lol-gameflow_v1_gameflow-phase",'
        '"uri":"/lol-gameflow/v1/gameflow-phase","eventType":"Update","data":"ChampSelect"}'
    ]


def test_written_files_hold_no_identifier_token_or_port(tmp_path: Path):
    target = tmp_path / "s"
    write_scenario(target, sample(), CREDS)
    text = "".join(p.read_text() for p in target.iterdir())
    for secret in ["RealPlayer", "6f1c2b3a-1111", "s3cr3tT0ken", "54321"]:
        assert secret not in text


def test_an_empty_recording_still_writes_valid_files(tmp_path: Path):
    write_scenario(tmp_path / "empty", Recording(), CREDS)
    assert (tmp_path / "empty" / "rest.jsonl").read_text() == ""
    assert json.loads((tmp_path / "empty" / "scenario.json").read_text())["queueId"] is None


def test_a_leak_writes_nothing(tmp_path: Path, monkeypatch):
    def leak(self, value):
        raise LeakError("forced")

    monkeypatch.setattr("lcu_recorder.anonymize.Anonymizer.verify", leak)
    target = tmp_path / "leaky"
    with pytest.raises(LeakError):
        write_scenario(target, sample(), CREDS)
    assert not target.exists()


def test_render_runs_the_anonymizer_before_serializing():
    files = render(sample(), CREDS)
    assert "RealPlayer" not in files["rest.jsonl"]


def test_scenario_names_are_plain_directory_names(tmp_path: Path):
    assert scenario_dir(tmp_path, "champ-select") == tmp_path / "champ-select"
    for bad in ["../escape", "Upper", "a/b", "", "-x"]:
        with pytest.raises(ValueError):
            scenario_dir(tmp_path, bad)


def test_refuses_to_overwrite_an_existing_recording(tmp_path: Path):
    (tmp_path / "ready-check").mkdir()
    (tmp_path / "ready-check" / "rest.jsonl").write_text("")
    with pytest.raises(FileExistsError):
        scenario_dir(tmp_path, "ready-check")
