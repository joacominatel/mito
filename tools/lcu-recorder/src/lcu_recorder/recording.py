import json
import re
from dataclasses import dataclass, field
from importlib.metadata import version
from pathlib import Path
from typing import Any

from lcu_recorder.anonymize import Anonymizer
from lcu_recorder.discovery import Credentials

FORMAT = 0
SCENARIO_NAME = re.compile(r"[a-z0-9][a-z0-9-]*")


@dataclass(frozen=True)
class RestLine:
    method: str
    path: str
    status: int
    body: Any

    def as_json(self) -> dict[str, Any]:
        return {"method": self.method, "path": self.path, "status": self.status, "body": self.body}


@dataclass(frozen=True)
class EventLine:
    t_ms: int
    topic: str
    uri: str
    event_type: str
    data: Any

    def as_json(self) -> dict[str, Any]:
        return {
            "t_ms": self.t_ms,
            "topic": self.topic,
            "uri": self.uri,
            "eventType": self.event_type,
            "data": self.data,
        }


@dataclass
class Recording:
    """Raw traffic, held in memory only until `write_scenario` anonymizes it."""

    client_patch: str | None = None
    queue_id: int | None = None
    rest: list[RestLine] = field(default_factory=list)
    events: list[EventLine] = field(default_factory=list)


def scenario_dir(root: Path, name: str) -> Path:
    if not SCENARIO_NAME.fullmatch(name):
        raise ValueError("scenario names use lowercase letters, digits, and dashes")
    target = root / name
    if target.exists() and any(target.iterdir()):
        raise FileExistsError(f"{target} already has a recording; delete it to re-record")
    return target


def _line(value: dict[str, Any]) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n"


def render(recording: Recording, credentials: Credentials) -> dict[str, str]:
    """Anonymizes and serializes the three v0 files; raises LeakError if anything leaks."""
    anonymizer = Anonymizer(secrets=[credentials.token], port=credentials.port)
    payloads = [line.as_json() for line in (*recording.rest, *recording.events)]
    for payload in payloads:
        anonymizer.collect(payload)

    def clean(lines: list[RestLine] | list[EventLine]) -> str:
        out = []
        for line in lines:
            safe = anonymizer.apply(line.as_json())
            anonymizer.verify(safe)
            text = _line(safe)
            anonymizer.verify_text(text)
            out.append(text)
        return "".join(out)

    rest, events = clean(recording.rest), clean(recording.events)
    scenario = {
        "format": FORMAT,
        "clientPatch": recording.client_patch,
        "queueId": recording.queue_id,
        "recorderVersion": version("lcu-recorder"),
        "anonymized": True,
    }
    return {
        "scenario.json": json.dumps(scenario, indent=2) + "\n",
        "rest.jsonl": rest,
        "events.jsonl": events,
    }


def write_scenario(target: Path, recording: Recording, credentials: Credentials) -> None:
    files = render(recording, credentials)
    target.mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        (target / name).write_text(text, encoding="utf-8")
