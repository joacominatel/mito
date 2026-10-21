import base64
import json
import ssl

import pytest

from lcu_recorder import lcu
from lcu_recorder.discovery import Credentials
from lcu_recorder.lcu import LCUEvents, LCUHttp, ReadOnlyError, auth_header, decode_body

CREDS = Credentials(port=54321, token="s3cr3t")


@pytest.mark.parametrize("method", ["POST", "PUT", "PATCH", "DELETE", "get", "HEAD"])
def test_http_refuses_every_method_but_get(method, monkeypatch):
    monkeypatch.setattr(lcu.http.client, "HTTPSConnection", _fail_if_connected)
    with pytest.raises(ReadOnlyError):
        LCUHttp(CREDS).request(method, "/lol-matchmaking/v1/ready-check/accept")


def test_get_connects_only_to_loopback_with_basic_auth(monkeypatch):
    seen = {}

    class FakeReply:
        status = 200

        def read(self):
            return b'"ChampSelect"'

    class FakeConnection:
        def __init__(self, host, port, timeout, context):
            seen.update(host=host, port=port, context=context)

        def request(self, method, path, headers):
            seen.update(method=method, path=path, headers=headers)

        def getresponse(self):
            return FakeReply()

        def close(self):
            seen["closed"] = True

    monkeypatch.setattr(lcu.http.client, "HTTPSConnection", FakeConnection)
    reply = LCUHttp(CREDS).get("/lol-gameflow/v1/gameflow-phase")

    assert (reply.status, reply.body) == (200, "ChampSelect")
    assert (seen["host"], seen["port"], seen["method"]) == ("127.0.0.1", 54321, "GET")
    assert seen["headers"]["Authorization"] == auth_header(CREDS)
    assert seen["closed"]


def test_auth_header_is_basic_riot_token():
    encoded = auth_header(CREDS).removeprefix("Basic ")
    assert base64.b64decode(encoded) == b"riot:s3cr3t"


def test_tls_context_skips_verification_only_because_the_host_is_fixed():
    assert lcu.HOST == "127.0.0.1"
    assert lcu.loopback_tls().verify_mode == ssl.CERT_NONE


def test_empty_and_undecodable_bodies_are_null():
    assert decode_body(b"") is None
    assert decode_body(b"<html>") is None
    assert decode_body(b'{"a": [1]}') == {"a": [1]}


class FakeSocket:
    def __init__(self):
        self.sent = []

    def send(self, frame):
        self.sent.append(json.loads(frame))


def test_socket_sends_only_subscribe_and_unsubscribe():
    socket = FakeSocket()
    events = LCUEvents(socket)
    events.subscribe(("A",))
    events.unsubscribe(("A",))
    for frame in ['[2, "id", "/lol-matchmaking/v1/ready-check/accept"]', '[5.0, "A"]', "{}"]:
        with pytest.raises(ReadOnlyError):
            events.send(frame)
    assert socket.sent == [[5, "A"], [6, "A"]]


def test_websocket_debug_logging_is_silenced():
    assert lcu._SILENT.disabled


def _fail_if_connected(*_args, **_kwargs):
    raise AssertionError("a refused method must not open a connection")
