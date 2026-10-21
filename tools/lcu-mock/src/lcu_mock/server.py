import asyncio
import base64
import copy
import json
import ssl
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager, suppress
from dataclasses import dataclass
from typing import Any

from aiohttp import WSMsgType, web

from lcu_mock.scenario import Event, Scenario

HOST = "127.0.0.1"
SUBSCRIBE, UNSUBSCRIBE, EVENT = 5, 6, 8

READY_CHECK = "/lol-matchmaking/v1/ready-check"
CHAMP_SELECT = "/lol-champ-select/v1/session"
PERK_PAGES = "/lol-perks/v1/pages"
CURRENT_PAGE = "/lol-perks/v1/currentpage"

Sleep = Callable[[float], Awaitable[None]]
JSON_BODY = web.RequestKey("json_body", object)


@dataclass(frozen=True)
class Write:
    method: str
    path: str
    body: Any
    status: int


def topic_for(uri: str) -> str:
    return "OnJsonApiEvent" + uri.replace("/", "_")


def error_body(status: int, message: str) -> dict[str, Any]:
    """Approximates the client's error body; only the status is relied upon."""
    return {"errorCode": "RPC_ERROR", "httpStatus": status, "message": message}


def lcu_error(status: int, message: str) -> web.Response:
    return web.json_response(error_body(status, message), status=status)


def _is_int(value: Any) -> bool:
    return type(value) is int


def _valid_page(body: Any) -> bool:
    return (
        isinstance(body, dict)
        and isinstance(body.get("name"), str)
        and _is_int(body.get("primaryStyleId"))
        and _is_int(body.get("subStyleId"))
        and isinstance(body.get("selectedPerkIds"), list)
        and all(_is_int(perk) for perk in body["selectedPerkIds"])
        and isinstance(body.get("current", False), bool)
    )


class MockLCU:
    """One scenario's REST state, its WAMP subscribers, and the write log."""

    def __init__(
        self,
        scenario: Scenario,
        password: str,
        speed: float = 1.0,
        sleep: Sleep = asyncio.sleep,
    ) -> None:
        if speed <= 0:
            raise ValueError("speed must be positive")
        self.state: dict[str, tuple[int, Any]] = copy.deepcopy(scenario.rest)
        self.writes: list[Write] = []
        self._events = scenario.events
        self.password = password
        self._auth = "Basic " + base64.b64encode(f"riot:{password}".encode()).decode()
        self._speed = speed
        self._sleep = sleep
        self._sockets: dict[web.WebSocketResponse, set[str]] = {}
        self._replay: asyncio.Task[None] | None = None

    def subscriptions(self) -> set[str]:
        return set().union(*self._sockets.values())

    async def replayed(self) -> None:
        if self._replay is not None:
            await self._replay

    def app(self) -> web.Application:
        app = web.Application(middlewares=[self._authenticate])
        app.router.add_get("/", self._websocket)
        app.router.add_post(f"{READY_CHECK}/accept", self._answer_ready_check("Accepted"))
        app.router.add_post(f"{READY_CHECK}/decline", self._answer_ready_check("Declined"))
        app.router.add_patch(f"{CHAMP_SELECT}/my-selection", self._my_selection)
        app.router.add_post(PERK_PAGES, self._create_page)
        app.router.add_put(PERK_PAGES + "/{id:-?\\d+}", self._edit_page)
        app.router.add_delete(PERK_PAGES + "/{id:-?\\d+}", self._delete_page)
        app.router.add_put("/lol-item-sets/v1/item-sets/{summoner:\\d+}/sets", self._item_sets)
        app.router.add_route("*", "/{tail:.*}", self._rest)
        return app

    @web.middleware
    async def _authenticate(self, request: web.Request, handler: Any) -> web.StreamResponse:
        if request.headers.get("Authorization") != self._auth:
            return web.Response(status=401, headers={"WWW-Authenticate": 'Basic realm="LCU"'})
        response = await handler(request)
        if request.method != "GET":
            body = request.get(JSON_BODY)
            self.writes.append(Write(request.method, request.path_qs, body, response.status))
        return response

    @staticmethod
    async def _json(request: web.Request) -> Any:
        if not request.can_read_body:
            return None
        try:
            request[JSON_BODY] = await request.json()
        except ValueError:
            request[JSON_BODY] = None
        return request[JSON_BODY]

    async def _rest(self, request: web.Request) -> web.Response:
        if request.method != "GET":
            await self._json(request)
            return lcu_error(404, f"No mock handler for {request.method} {request.path}")
        found = self.state.get(request.path_qs) or self.state.get(request.path)
        if found is None:
            return lcu_error(404, f"Resource not found: {request.path}")
        status, body = found
        if body is None:
            return web.Response(status=status)
        return web.json_response(body, status=status)

    async def _set(self, uri: str, body: Any, event_type: str = "Update") -> None:
        self.state[uri] = (200, body)
        await self._publish(topic_for(uri), uri, event_type, body)

    def _body(self, uri: str) -> Any:
        status, body = self.state.get(uri, (404, None))
        return copy.deepcopy(body) if status == 200 else None

    def _answer_ready_check(self, answer: str) -> Callable[[web.Request], Awaitable[web.Response]]:
        async def handler(request: web.Request) -> web.Response:
            await self._json(request)
            ready_check = self._body(READY_CHECK)
            if not isinstance(ready_check, dict):
                return lcu_error(404, "No ready check")
            ready_check["playerResponse"] = answer
            await self._set(READY_CHECK, ready_check)
            return web.Response(status=204)

        return handler

    async def _my_selection(self, request: web.Request) -> web.Response:
        body = await self._json(request)
        spells = ("spell1Id", "spell2Id")
        if (
            not isinstance(body, dict)
            or not any(key in body for key in spells)
            or not all(_is_int(body[key]) for key in spells if key in body)
        ):
            return lcu_error(400, "Expected spell1Id and/or spell2Id as integers")
        session = self._body(CHAMP_SELECT)
        if not isinstance(session, dict):
            return lcu_error(404, "No champ select session")
        local = session.get("localPlayerCellId")
        for member in session.get("myTeam", []):
            if isinstance(member, dict) and member.get("cellId") == local:
                member.update({key: body[key] for key in spells if key in body})
        await self._set(CHAMP_SELECT, session)
        return web.Response(status=204)

    def _pages(self) -> list[dict[str, Any]]:
        pages = self._body(PERK_PAGES)
        return pages if isinstance(pages, list) else []

    async def _store_pages(self, pages: list[dict[str, Any]], changed: dict[str, Any]) -> None:
        if changed.get("current"):
            for page in pages:
                page["current"] = page is changed
            await self._set(CURRENT_PAGE, changed)
        await self._set(PERK_PAGES, pages)

    async def _create_page(self, request: web.Request) -> web.Response:
        body = await self._json(request)
        if not _valid_page(body):
            return lcu_error(400, "Invalid perk page")
        pages = self._pages()
        page = {**body, "id": max((p.get("id", 0) for p in pages), default=0) + 1}
        pages.append(page)
        await self._store_pages(pages, page)
        return web.json_response(page)

    async def _edit_page(self, request: web.Request) -> web.Response:
        body = await self._json(request)
        if not _valid_page(body):
            return lcu_error(400, "Invalid perk page")
        page_id = int(request.match_info["id"])
        pages = self._pages()
        for index, page in enumerate(pages):
            if page.get("id") == page_id:
                pages[index] = {**body, "id": page_id}
                await self._store_pages(pages, pages[index])
                return web.json_response(pages[index])
        return lcu_error(404, f"No perk page {page_id}")

    async def _delete_page(self, request: web.Request) -> web.Response:
        page_id = int(request.match_info["id"])
        pages = self._pages()
        kept = [page for page in pages if page.get("id") != page_id]
        if len(kept) == len(pages):
            return lcu_error(404, f"No perk page {page_id}")
        await self._set(PERK_PAGES, kept)
        return web.Response(status=204)

    async def _item_sets(self, request: web.Request) -> web.Response:
        body = await self._json(request)
        if (
            not isinstance(body, dict)
            or not isinstance(body.get("itemSets"), list)
            or not all(isinstance(item_set, dict) for item_set in body["itemSets"])
        ):
            return lcu_error(400, "Expected an object with an itemSets array of objects")
        await self._set(request.path, body)
        return web.Response(status=204)

    async def _websocket(self, request: web.Request) -> web.StreamResponse:
        if request.headers.get("Upgrade", "").lower() != "websocket":
            return await self._rest(request)
        socket = web.WebSocketResponse(protocols=("wamp",))
        await socket.prepare(request)
        self._sockets[socket] = set()
        try:
            async for message in socket:
                if message.type == WSMsgType.TEXT:
                    self._handle_frame(socket, message.data)
        finally:
            del self._sockets[socket]
        return socket

    def _handle_frame(self, socket: web.WebSocketResponse, text: str) -> None:
        try:
            frame = json.loads(text)
        except ValueError:
            return
        if not isinstance(frame, list) or len(frame) < 2 or not isinstance(frame[1], str):
            return
        opcode, topic = frame[0], frame[1]
        if _is_int(opcode) and opcode == SUBSCRIBE:
            self._sockets[socket].add(topic)
            if self._replay is None:
                self._replay = asyncio.create_task(self._run_replay())
        elif _is_int(opcode) and opcode == UNSUBSCRIBE:
            self._sockets[socket].discard(topic)

    async def _run_replay(self) -> None:
        previous_ms = 0
        for event in self._events:
            await self._sleep(max(0, event.t_ms - previous_ms) / 1000 / self._speed)
            previous_ms = event.t_ms
            await self._apply(event)

    async def _apply(self, event: Event) -> None:
        if event.event_type == "Delete":
            self.state[event.uri] = (404, error_body(404, f"Resource not found: {event.uri}"))
        else:
            self.state[event.uri] = (200, copy.deepcopy(event.data))
        await self._publish(event.topic, event.uri, event.event_type, event.data)

    async def _publish(self, topic: str, uri: str, event_type: str, data: Any) -> None:
        frame = json.dumps([EVENT, topic, {"data": data, "eventType": event_type, "uri": uri}])
        for socket, topics in list(self._sockets.items()):
            if topic in topics:
                with suppress(ConnectionError):
                    await socket.send_str(frame)

    async def close(self) -> None:
        if self._replay is not None:
            self._replay.cancel()
            with suppress(asyncio.CancelledError):
                await self._replay
        for socket in list(self._sockets):
            await socket.close()


@asynccontextmanager
async def serve(
    mock: MockLCU, ssl_context: ssl.SSLContext, host: str = HOST, port: int = 0
) -> AsyncIterator[int]:
    """Serves on the loopback address only and yields the bound port."""
    if host != HOST:
        raise ValueError(f"lcu-mock binds only to {HOST}, not {host!r}")
    runner = web.AppRunner(mock.app(), access_log=None)
    await runner.setup()
    try:
        site = web.TCPSite(runner, HOST, port, ssl_context=ssl_context)
        await site.start()
        yield runner.addresses[0][1]
    finally:
        await mock.close()
        await runner.cleanup()
