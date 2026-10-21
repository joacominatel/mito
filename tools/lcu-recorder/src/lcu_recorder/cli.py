import argparse
import sys
import time
from collections.abc import Callable
from contextlib import suppress
from http.client import HTTPException
from pathlib import Path
from typing import Any

from websockets.exceptions import WebSocketException

from lcu_recorder import wamp
from lcu_recorder.anonymize import LeakError
from lcu_recorder.discovery import DEFAULT_LOCKFILE, discover
from lcu_recorder.lcu import LCUEvents, LCUHttp
from lcu_recorder.recording import EventLine, Recording, RestLine, scenario_dir, write_scenario

ONCE_PATHS = ("/lol-patch/v1/game-version", "/lol-summoner/v1/current-summoner")
SNAPSHOT_PATHS = (
    "/lol-gameflow/v1/gameflow-phase",
    "/lol-gameflow/v1/session",
    "/lol-lobby/v2/lobby",
    "/lol-matchmaking/v1/ready-check",
    "/lol-champ-select/v1/session",
    "/lol-champ-select/v1/pickable-champion-ids",
    "/lol-champ-select/v1/bannable-champion-ids",
)
SNAPSHOT_INTERVAL_S = 5.0


def _say(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def record(
    http: LCUHttp,
    events: LCUEvents,
    duration_s: float | None,
    clock: Callable[[], float] = time.monotonic,
) -> Recording:
    """Records until the duration ends, Ctrl-C, or the client goes away."""
    recording = Recording()
    last: dict[str, tuple[int, Any]] = {}
    start = clock()
    end = None if duration_s is None else start + duration_s

    def snapshot(paths: tuple[str, ...]) -> None:
        for path in paths:
            reply = http.get(path)
            if last.get(path) != (reply.status, reply.body):
                last[path] = (reply.status, reply.body)
                recording.rest.append(RestLine("GET", path, reply.status, reply.body))

    try:
        events.subscribe(wamp.TOPICS)
        snapshot(ONCE_PATHS + SNAPSHOT_PATHS)
        next_snapshot = start + SNAPSHOT_INTERVAL_S
        while end is None or clock() < end:
            wake = next_snapshot if end is None else min(next_snapshot, end)
            message = events.receive(timeout=max(0.0, wake - clock()))
            event = wamp.parse_event(message) if message is not None else None
            if event:
                t_ms = int((clock() - start) * 1000)
                recording.events.append(
                    EventLine(t_ms, event.topic, event.uri, event.event_type, event.data)
                )
            if clock() >= next_snapshot:
                snapshot(SNAPSHOT_PATHS)
                next_snapshot += SNAPSHOT_INTERVAL_S
    except KeyboardInterrupt:
        pass
    except (WebSocketException, OSError, HTTPException):
        _say("The client closed the connection; keeping what was recorded.")
    finally:
        with suppress(Exception):
            events.unsubscribe(wamp.TOPICS)
        with suppress(Exception):
            events.close()

    recording.client_patch = client_patch(recording)
    recording.queue_id = queue_id(recording)
    return recording


def client_patch(recording: Recording) -> str | None:
    for line in recording.rest:
        if line.path == ONCE_PATHS[0] and line.status == 200 and isinstance(line.body, str):
            return ".".join(line.body.split(".")[:2])
    return None


def queue_id(recording: Recording) -> int | None:
    """The first queue seen in a gameflow session, else in a lobby."""
    bodies = [(r.path, r.body) for r in recording.rest] + [
        (e.uri, e.data) for e in recording.events
    ]

    def dig(value: Any, *keys: str) -> Any:
        for key in keys:
            value = value.get(key) if isinstance(value, dict) else None
        return value

    for source, keys in (
        ("/lol-gameflow/v1/session", ("gameData", "queue", "id")),
        ("/lol-lobby/v2/lobby", ("gameConfig", "queueId")),
    ):
        for path, body in bodies:
            found = dig(body, *keys) if path == source else None
            if type(found) is int and found > 0:
                return found
    return None


def default_root() -> Path | None:
    for directory in (Path.cwd(), *Path.cwd().parents):
        if (directory / "fixtures" / "lcu").is_dir():
            return directory / "fixtures" / "lcu"
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="lcu-recorder")
    commands = parser.add_subparsers(dest="command", required=True)
    rec = commands.add_parser("record", help="record one scenario from the running client")
    rec.add_argument("scenario", help="directory name, e.g. ready-check")
    rec.add_argument("--duration", type=float, help="seconds to record (default: until Ctrl-C)")
    rec.add_argument("--out", type=Path, help="output root (default: the repo's fixtures/lcu)")
    rec.add_argument("--lockfile", type=Path, default=DEFAULT_LOCKFILE)
    args = parser.parse_args(argv)

    root = args.out or default_root()
    if root is None:
        _say("fixtures/lcu not found above the current directory; pass --out.")
        return 1
    try:
        target = scenario_dir(root, args.scenario)
    except (ValueError, FileExistsError) as error:
        _say(str(error))
        return 1

    credentials = discover(args.lockfile)
    if credentials is None:
        _say("No running League client found (process arguments or lockfile).")
        return 1

    try:
        events = LCUEvents.open(credentials)
    except (OSError, WebSocketException) as error:
        _say(f"Could not open the client's event socket: {type(error).__name__}")
        return 1

    _say(f"Recording '{args.scenario}'. Press Ctrl-C to stop.")
    recording = record(LCUHttp(credentials), events, args.duration)
    try:
        write_scenario(target, recording, credentials)
    except LeakError as error:
        _say(f"Nothing written: {error}.")
        return 2
    _say(f"Wrote {len(recording.rest)} REST and {len(recording.events)} event lines to {target}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
