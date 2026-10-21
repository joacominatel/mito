import argparse
import asyncio
import math
import secrets
import signal
import sys
from pathlib import Path

from lcu_mock.lockfile import write_lockfile
from lcu_mock.scenario import ScenarioError, load
from lcu_mock.server import HOST, MockLCU, serve
from lcu_mock.tls import self_signed_context

DEFAULT_LOCKFILE = Path(".run/lockfile")


def parse_speed(text: str) -> float:
    try:
        speed = float(text.removesuffix("x"))
    except ValueError:
        raise argparse.ArgumentTypeError(f"invalid speed {text!r}; use e.g. 4x") from None
    if not (math.isfinite(speed) and speed > 0):
        raise argparse.ArgumentTypeError("speed must be positive")
    return speed


def parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="lcu-mock")
    parser.add_argument("--scenario", type=Path, required=True, help="format v0 directory")
    parser.add_argument("--speed", type=parse_speed, default=1.0, help="replay speed, e.g. 4x")
    parser.add_argument(
        "--skip-lead-in",
        action="store_true",
        help="send the first event on subscribe instead of after its t_ms",
    )
    parser.add_argument("--lockfile", type=Path, default=DEFAULT_LOCKFILE)
    parser.add_argument("--port", type=int, default=0, help="default: any free port")
    return parser.parse_args(argv)


async def run(args: argparse.Namespace, stop: asyncio.Event) -> None:
    """Serves until `stop` is set; the lockfile exists only while serving, like the client's."""
    mock = MockLCU(
        load(args.scenario),
        password=secrets.token_urlsafe(16),
        speed=args.speed,
        skip_lead_in=args.skip_lead_in,
    )
    async with serve(mock, self_signed_context(), port=args.port) as port:
        write_lockfile(args.lockfile, port, mock.password)
        try:
            print(
                f"Serving {args.scenario} on https://{HOST}:{port} at {args.speed:g}x; "
                f"lockfile {args.lockfile.resolve()}",
                file=sys.stderr,
                flush=True,
            )
            await stop.wait()
        finally:
            args.lockfile.unlink(missing_ok=True)


async def _main(args: argparse.Namespace) -> None:
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for signum in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(signum, stop.set)
    await run(args, stop)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        asyncio.run(_main(args))
    except ScenarioError as error:
        print(f"Bad scenario: {error}", file=sys.stderr)
        return 1
    except OSError as error:
        print(f"Could not serve: {error.strerror or error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
