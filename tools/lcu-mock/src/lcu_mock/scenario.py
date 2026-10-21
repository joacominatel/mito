import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

FORMAT = 0


class ScenarioError(Exception):
    pass


@dataclass(frozen=True)
class Event:
    t_ms: int
    topic: str
    uri: str
    event_type: str
    data: Any


@dataclass
class Scenario:
    """REST state at replay start, plus the events that change it over time."""

    rest: dict[str, tuple[int, Any]] = field(default_factory=dict)
    events: list[Event] = field(default_factory=list)


def _lines(path: Path) -> list[tuple[int, dict[str, Any]]]:
    if not path.exists():
        return []
    out = []
    for number, text in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        if not text.strip():
            continue
        try:
            value = json.loads(text)
        except ValueError as error:
            raise ScenarioError(f"{path.name}:{number} is not JSON") from error
        if not isinstance(value, dict):
            raise ScenarioError(f"{path.name}:{number} is not an object")
        out.append((number, value))
    return out


def _require(value: dict[str, Any], key: str, kind: type, where: str) -> Any:
    found = value.get(key)
    if not isinstance(found, kind) or isinstance(found, bool):
        raise ScenarioError(f"{where} needs '{key}' as {kind.__name__}")
    return found


def load(directory: Path) -> Scenario:
    """Reads a format v0 directory (`fixtures/lcu/README.md`)."""
    meta_path = directory / "scenario.json"
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ScenarioError(f"{meta_path} is missing or not JSON") from error
    if not isinstance(meta, dict) or meta.get("format") != FORMAT:
        raise ScenarioError(f"{meta_path} is not format {FORMAT}")

    scenario = Scenario()
    for number, line in _lines(directory / "rest.jsonl"):
        where = f"rest.jsonl:{number}"
        path = _require(line, "path", str, where)
        status = _require(line, "status", int, where)
        # v0 rest lines carry no time, so only the first one per path is placed (at the start).
        if line.get("method", "GET") == "GET" and path not in scenario.rest:
            scenario.rest[path] = (status, line.get("body"))
    for number, line in _lines(directory / "events.jsonl"):
        where = f"events.jsonl:{number}"
        scenario.events.append(
            Event(
                t_ms=_require(line, "t_ms", int, where),
                topic=_require(line, "topic", str, where),
                uri=_require(line, "uri", str, where),
                event_type=_require(line, "eventType", str, where),
                data=line.get("data"),
            )
        )
    return scenario
