import re
import subprocess
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_LOCKFILE = Path("/Applications/League of Legends.app/Contents/LoL/lockfile")

_PORT = re.compile(r"""--app-port=["']?(\d+)""")
_TOKEN = re.compile(r"""--remote-auth-token=["']?([\w-]+)""")


@dataclass(frozen=True)
class Credentials:
    port: int
    token: str = field(repr=False)


def _valid_port(value: str) -> int | None:
    port = int(value)
    return port if 0 < port < 65536 else None


def parse_process_list(output: str) -> Credentials | None:
    """Finds the LeagueClientUx line in `ps -A -o args` output."""
    for line in output.splitlines():
        if "LeagueClientUx" not in line:
            continue
        port, token = _PORT.search(line), _TOKEN.search(line)
        if port and token and (valid := _valid_port(port.group(1))):
            return Credentials(port=valid, token=token.group(1))
    return None


def parse_lockfile(text: str) -> Credentials | None:
    """`LeagueClient:<pid>:<port>:<password>:<protocol>`; anything else is None."""
    parts = text.strip().split(":")
    if len(parts) != 5 or not parts[2].isdigit() or not parts[3]:
        return None
    port = _valid_port(parts[2])
    return Credentials(port=port, token=parts[3]) if port else None


def discover(lockfile: Path = DEFAULT_LOCKFILE) -> Credentials | None:
    try:
        ps = subprocess.run(
            ["/bin/ps", "-A", "-o", "args"], capture_output=True, text=True, check=False
        )
        found = parse_process_list(ps.stdout)
    except OSError:
        found = None
    if found:
        return found
    try:
        return parse_lockfile(lockfile.read_text(encoding="utf-8"))
    except OSError:
        return None
