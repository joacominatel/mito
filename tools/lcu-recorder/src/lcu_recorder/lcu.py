import base64
import http.client
import json
import logging
import ssl
from dataclasses import dataclass
from typing import Any

from websockets.sync.client import ClientConnection, connect

from lcu_recorder import wamp
from lcu_recorder.discovery import Credentials

HOST = "127.0.0.1"
TIMEOUT_S = 5.0

# websockets logs request headers (the Authorization token) and frames at DEBUG.
_SILENT = logging.getLogger("lcu_recorder.silent")
_SILENT.disabled = True
_SILENT.propagate = False


class ReadOnlyError(Exception):
    pass


@dataclass(frozen=True)
class Response:
    status: int
    body: Any


def loopback_tls() -> ssl.SSLContext:
    """Accepts the client's self-signed certificate. Only ever handed to connections to HOST."""
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    return context


def auth_header(credentials: Credentials) -> str:
    raw = f"riot:{credentials.token}".encode()
    return "Basic " + base64.b64encode(raw).decode()


def decode_body(raw: bytes) -> Any:
    if not raw.strip():
        return None
    try:
        return json.loads(raw)
    except ValueError:
        return None


class LCUHttp:
    def __init__(self, credentials: Credentials) -> None:
        self._credentials = credentials
        self._tls = loopback_tls()

    def get(self, path: str) -> Response:
        return self.request("GET", path)

    def request(self, method: str, path: str) -> Response:
        if method != "GET":
            raise ReadOnlyError(f"the recorder never sends {method}")
        if not path.startswith("/"):
            raise ValueError("path must be absolute")
        conn = http.client.HTTPSConnection(
            HOST, self._credentials.port, timeout=TIMEOUT_S, context=self._tls
        )
        try:
            conn.request(
                "GET",
                path,
                headers={
                    "Authorization": auth_header(self._credentials),
                    "Accept": "application/json",
                },
            )
            reply = conn.getresponse()
            return Response(status=reply.status, body=decode_body(reply.read()))
        finally:
            conn.close()


class LCUEvents:
    """The WAMP socket, restricted to subscribe and unsubscribe frames."""

    _ALLOWED = (wamp.SUBSCRIBE, wamp.UNSUBSCRIBE)

    def __init__(self, socket: ClientConnection) -> None:
        self._socket = socket

    @classmethod
    def open(cls, credentials: Credentials) -> "LCUEvents":
        socket = connect(
            f"wss://{HOST}:{credentials.port}/",
            ssl=loopback_tls(),
            subprotocols=["wamp"],
            additional_headers={"Authorization": auth_header(credentials)},
            proxy=None,
            max_size=None,
            logger=_SILENT,
        )
        return cls(socket)

    def send(self, frame: str) -> None:
        decoded = json.loads(frame)
        if not isinstance(decoded, list) or not decoded or not self._allowed(decoded[0]):
            raise ReadOnlyError("the recorder only sends WAMP subscribe and unsubscribe")
        self._socket.send(frame)

    @classmethod
    def _allowed(cls, opcode: object) -> bool:
        return type(opcode) is int and opcode in cls._ALLOWED

    def subscribe(self, topics: tuple[str, ...]) -> None:
        for topic in topics:
            self.send(wamp.subscribe_frame(topic))

    def unsubscribe(self, topics: tuple[str, ...]) -> None:
        for topic in topics:
            self.send(wamp.unsubscribe_frame(topic))

    def receive(self, timeout: float) -> str | bytes | None:
        try:
            return self._socket.recv(timeout=timeout)
        except TimeoutError:
            return None

    def close(self) -> None:
        self._socket.close()
