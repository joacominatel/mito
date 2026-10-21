import asyncio
import json
from collections.abc import AsyncIterator, Callable
from contextlib import asynccontextmanager
from dataclasses import dataclass
from pathlib import Path

import aiohttp

from lcu_mock.scenario import Event, Scenario, load
from lcu_mock.server import MockLCU, serve
from lcu_mock.tls import self_signed_context

SCENARIOS = Path(__file__).parent / "scenarios"
PASSWORD = "test-password"
TLS = self_signed_context()


def scenario(name: str) -> Scenario:
    return load(SCENARIOS / name)


def event(t_ms: int, uri: str, data: object, event_type: str = "Update") -> Event:
    return Event(t_ms, "OnJsonApiEvent" + uri.replace("/", "_"), uri, event_type, data)


class RecordingSleep:
    """Records each replay delay and returns at once."""

    def __init__(self) -> None:
        self.delays: list[float] = []

    async def __call__(self, delay: float) -> None:
        self.delays.append(delay)


class GatedSleep:
    """Holds the replay before each event until the test releases it."""

    def __init__(self) -> None:
        self._gate: asyncio.Queue[None] = asyncio.Queue()

    async def __call__(self, delay: float) -> None:
        await self._gate.get()

    def release(self) -> None:
        self._gate.put_nowait(None)


@dataclass
class Running:
    port: int
    http: aiohttp.ClientSession

    @property
    def url(self) -> str:
        return f"https://127.0.0.1:{self.port}"

    async def wamp(self) -> aiohttp.ClientWebSocketResponse:
        return await self.http.ws_connect(f"wss://127.0.0.1:{self.port}/", protocols=("wamp",))


@asynccontextmanager
async def running(mock: MockLCU, password: str = PASSWORD) -> AsyncIterator[Running]:
    async with (
        serve(mock, TLS) as port,
        aiohttp.ClientSession(
            base_url=f"https://127.0.0.1:{port}",
            headers={"Authorization": aiohttp.encode_basic_auth("riot", password)},
            connector=aiohttp.TCPConnector(ssl=False),
        ) as http,
    ):
        yield Running(port, http)


async def until(condition: Callable[[], bool], timeout: float = 2.0) -> None:
    async with asyncio.timeout(timeout):
        while not condition():
            await asyncio.sleep(0.005)


async def next_event(socket: aiohttp.ClientWebSocketResponse, timeout: float = 2.0) -> list:
    return json.loads(await socket.receive_str(timeout=timeout))
