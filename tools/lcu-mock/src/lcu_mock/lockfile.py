import os
from pathlib import Path


def lockfile_text(pid: int, port: int, password: str) -> str:
    return f"LeagueClient:{pid}:{port}:{password}:https"


def write_lockfile(path: Path, port: int, password: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as file:
        file.write(lockfile_text(os.getpid(), port, password))
