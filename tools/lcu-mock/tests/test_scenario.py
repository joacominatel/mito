import json
import re

import pytest
from support import SCENARIOS

from lcu_mock.scenario import ScenarioError, load

FAKE_UUID = re.compile(r"00000000-0000-4000-8000-\d{12}")
ANY_UUID = re.compile(
    r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
)


def _write(directory, meta, rest="", events=""):
    directory.mkdir()
    (directory / "scenario.json").write_text(json.dumps(meta))
    (directory / "rest.jsonl").write_text(rest)
    (directory / "events.jsonl").write_text(events)
    return directory


def test_first_rest_line_per_path_is_the_initial_state(tmp_path):
    rest = "\n".join(
        json.dumps({"method": "GET", "path": "/p", "status": s, "body": b})
        for s, b in ((200, "first"), (200, "second"))
    )
    loaded = load(_write(tmp_path / "s", {"format": 0}, rest))
    assert loaded.rest == {"/p": (200, "first")}


def test_events_keep_file_order_and_fields(tmp_path):
    line = {"t_ms": 5, "topic": "T", "uri": "/u", "eventType": "Create", "data": {"a": 1}}
    loaded = load(_write(tmp_path / "s", {"format": 0}, events=json.dumps(line) + "\n"))
    [found] = loaded.events
    assert (found.t_ms, found.topic, found.uri, found.event_type, found.data) == (
        5,
        "T",
        "/u",
        "Create",
        {"a": 1},
    )


@pytest.mark.parametrize(
    ("meta", "events"),
    [
        ({"format": 1}, ""),
        ({"format": 0}, "not json\n"),
        ({"format": 0}, json.dumps({"t_ms": "5", "topic": "T", "uri": "/u", "eventType": "X"})),
    ],
)
def test_rejects_other_formats_and_malformed_lines(tmp_path, meta, events):
    with pytest.raises(ScenarioError):
        load(_write(tmp_path / "s", meta, events=events))


@pytest.mark.parametrize("name", ["ready-check", "champ-select"])
def test_synthetic_scenarios_load_and_carry_only_fake_identifiers(name):
    directory = SCENARIOS / name
    loaded = load(directory)
    assert loaded.rest and loaded.events
    assert json.loads((directory / "scenario.json").read_text())["anonymized"] is True
    text = "".join(path.read_text() for path in directory.iterdir())
    assert all(FAKE_UUID.fullmatch(uuid) for uuid in ANY_UUID.findall(text))
