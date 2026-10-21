import asyncio
import json

import aiohttp
import pytest
from support import (
    PASSWORD,
    TLS,
    GatedSleep,
    RecordingSleep,
    event,
    next_event,
    running,
    scenario,
    until,
)

from lcu_mock.scenario import Scenario
from lcu_mock.server import HOST, MockLCU, serve

PHASE = "/lol-gameflow/v1/gameflow-phase"
READY_CHECK = "/lol-matchmaking/v1/ready-check"
CHAMP_SELECT = "/lol-champ-select/v1/session"
PHASE_TOPIC = "OnJsonApiEvent_lol-gameflow_v1_gameflow-phase"
READY_TOPIC = "OnJsonApiEvent_lol-matchmaking_v1_ready-check"
PAGE = {
    "name": "Mito · Test",
    "primaryStyleId": 8100,
    "subStyleId": 8200,
    "selectedPerkIds": [8112, 8139, 8138, 8135, 8226, 8210, 5008, 5008, 5001],
    "current": True,
}


def mock(scenario_or_name="ready-check", **kwargs) -> MockLCU:
    loaded = scenario(scenario_or_name) if isinstance(scenario_or_name, str) else scenario_or_name
    return MockLCU(loaded, PASSWORD, **kwargs)


# Loopback only


@pytest.mark.parametrize("host", ["0.0.0.0", "localhost", "::1", "127.0.0.2", ""])
def test_refuses_any_bind_address_but_loopback(host):
    async def scenario():
        async with serve(mock(), TLS, host=host):
            pytest.fail("served on a non-loopback address")

    with pytest.raises(ValueError):
        asyncio.run(scenario())


def test_binds_to_loopback_on_an_ephemeral_port():
    async def scenario():
        server = mock()
        async with serve(server, TLS) as port:
            assert port > 0
            _, writer = await asyncio.open_connection(HOST, port, ssl=False)
            assert writer.get_extra_info("peername")[0] == HOST
            writer.close()

    asyncio.run(scenario())


# Auth


@pytest.mark.parametrize(
    "headers",
    [
        {},
        {"Authorization": aiohttp.encode_basic_auth("riot", "wrong")},
        {"Authorization": aiohttp.encode_basic_auth("admin", PASSWORD)},
        {"Authorization": f"Bearer {PASSWORD}"},
    ],
)
def test_rest_rejects_missing_or_wrong_credentials(headers):
    async def scenario():
        server = mock(_ready_check_in_progress())
        async with (
            running(server) as running_server,
            aiohttp.ClientSession(
                headers=headers, connector=aiohttp.TCPConnector(ssl=False)
            ) as other,
        ):
            assert (await other.get(f"{running_server.url}{PHASE}")).status == 401
            reply = await other.post(f"{running_server.url}{READY_CHECK}/accept")
            assert reply.status == 401
            assert server.writes == []
            assert server.state[READY_CHECK][1]["playerResponse"] == "None"

    asyncio.run(scenario())


def test_websocket_rejects_missing_credentials():
    async def scenario():
        async with (
            running(mock()) as server,
            aiohttp.ClientSession(connector=aiohttp.TCPConnector(ssl=False)) as anonymous,
        ):
            with pytest.raises(aiohttp.WSServerHandshakeError) as caught:
                await anonymous.ws_connect(f"wss://127.0.0.1:{server.port}/", protocols=("wamp",))
            assert caught.value.status == 401

    asyncio.run(scenario())


# REST from the scenario


def test_rest_serves_the_scenario_status_and_body():
    async def scenario():
        async with running(mock()) as server:
            phase = await server.http.get(PHASE)
            assert (phase.status, await phase.json()) == (200, "Lobby")
            summoner = await (await server.http.get("/lol-summoner/v1/current-summoner")).json()
            assert summoner["summonerId"] == 1
            assert (await server.http.get(READY_CHECK)).status == 404
            assert (await server.http.get("/lol-nothing/v1/here")).status == 404

    asyncio.run(scenario())


def test_rest_matches_a_recorded_query_string():
    path = "/lol-match-history/v1/products/lol/current-summoner/matches?begIndex=0&endIndex=20"
    loaded = Scenario(rest={path: (200, {"games": []})})

    async def scenario():
        async with running(mock(loaded)) as server:
            assert await (await server.http.get(path)).json() == {"games": []}

    asyncio.run(scenario())


# WAMP


def test_replay_starts_on_first_subscribe_and_follows_file_order_scaled_by_speed():
    loaded = Scenario(
        rest={PHASE: (200, "Lobby")},
        events=[
            event(1000, PHASE, "Matchmaking"),
            event(6000, PHASE, "ReadyCheck"),
            event(6000, PHASE, "ChampSelect"),
            event(7000, PHASE, "GameStart"),
        ],
    )
    sleep = RecordingSleep()

    async def scenario():
        server = mock(loaded, speed=4.0, sleep=sleep)
        async with running(server) as running_server:
            socket = await running_server.wamp()
            await asyncio.sleep(0.05)
            assert sleep.delays == []
            await socket.send_json([5, PHASE_TOPIC])
            phases = [(await next_event(socket))[2]["data"] for _ in range(4)]
            assert phases == ["Matchmaking", "ReadyCheck", "ChampSelect", "GameStart"]
            assert sleep.delays == [0.25, 1.25, 0.0, 0.25]

    asyncio.run(scenario())


def test_frames_use_the_wamp_event_shape():
    loaded = Scenario(events=[event(0, PHASE, "Matchmaking")])

    async def scenario():
        async with running(mock(loaded, sleep=RecordingSleep())) as server:
            socket = await server.wamp()
            assert socket.protocol == "wamp"
            await socket.send_str(json.dumps([5, PHASE_TOPIC]))
            assert await next_event(socket) == [
                8,
                PHASE_TOPIC,
                {"data": "Matchmaking", "eventType": "Update", "uri": PHASE},
            ]

    asyncio.run(scenario())


def test_events_reach_only_subscribed_topics_until_unsubscribed():
    loaded = Scenario(
        events=[
            event(0, READY_CHECK, {"state": "InProgress"}, "Create"),
            event(0, PHASE, "ReadyCheck"),
            event(0, PHASE, "ChampSelect"),
            event(0, READY_CHECK, None, "Delete"),
            event(0, PHASE, "GameStart"),
        ]
    )
    gate = GatedSleep()

    async def scenario():
        server = mock(loaded, sleep=gate)
        async with running(server) as running_server:
            both, phase_only = await running_server.wamp(), await running_server.wamp()
            await both.send_json([5, PHASE_TOPIC])
            await both.send_json([5, READY_TOPIC])
            await phase_only.send_json([5, PHASE_TOPIC])
            await until(lambda: len([t for t in server._sockets.values() if t]) == 2)
            await until(lambda: READY_TOPIC in server.subscriptions())

            gate.release()
            assert (await next_event(both))[1] == READY_TOPIC
            gate.release()
            assert (await next_event(both))[2]["data"] == "ReadyCheck"
            assert (await next_event(phase_only))[2]["data"] == "ReadyCheck"

            await both.send_json([6, PHASE_TOPIC])
            await until(lambda: PHASE_TOPIC not in next(iter(server._sockets.values())))
            for _ in range(3):
                gate.release()
            await server.replayed()

            assert (await next_event(both))[2]["eventType"] == "Delete"
            assert [(await next_event(phase_only))[2]["data"] for _ in range(2)] == [
                "ChampSelect",
                "GameStart",
            ]
            with pytest.raises(TimeoutError):
                await both.receive_str(timeout=0.1)

    asyncio.run(scenario())


def test_replayed_events_update_rest_state():
    loaded = Scenario(
        rest={PHASE: (200, "Lobby"), READY_CHECK: (404, None)},
        events=[
            event(0, READY_CHECK, {"state": "InProgress", "playerResponse": "None"}, "Create"),
            event(0, PHASE, "ReadyCheck"),
            event(0, READY_CHECK, None, "Delete"),
        ],
    )
    gate = GatedSleep()

    async def scenario():
        server = mock(loaded, sleep=gate)
        async with running(server) as running_server:
            socket = await running_server.wamp()
            await socket.send_json([5, PHASE_TOPIC])
            await until(lambda: server.subscriptions() == {PHASE_TOPIC})
            gate.release()
            gate.release()
            await next_event(socket)
            ready = await running_server.http.get(READY_CHECK)
            assert (ready.status, (await ready.json())["state"]) == (200, "InProgress")
            assert await (await running_server.http.get(PHASE)).json() == "ReadyCheck"
            gate.release()
            await server.replayed()
            assert (await running_server.http.get(READY_CHECK)).status == 404

    asyncio.run(scenario())


# Writes


def _ready_check_in_progress() -> Scenario:
    return Scenario(rest={READY_CHECK: (200, {"state": "InProgress", "playerResponse": "None"})})


def test_accepting_the_ready_check_records_it_mutates_state_and_publishes():
    async def scenario():
        server = mock(_ready_check_in_progress())
        async with running(server) as running_server:
            socket = await running_server.wamp()
            await socket.send_json([5, READY_TOPIC])
            await until(lambda: READY_TOPIC in server.subscriptions())

            reply = await running_server.http.post(f"{READY_CHECK}/accept")
            assert reply.status == 204
            body = await (await running_server.http.get(READY_CHECK)).json()
            assert body["playerResponse"] == "Accepted"
            frame = await next_event(socket)
            assert frame[2]["data"]["playerResponse"] == "Accepted"
            assert [(w.method, w.path, w.status) for w in server.writes] == [
                ("POST", f"{READY_CHECK}/accept", 204)
            ]

    asyncio.run(scenario())


def test_declining_sets_declined_and_answering_without_a_ready_check_is_404():
    async def scenario():
        server = mock(_ready_check_in_progress())
        async with running(server) as running_server:
            assert (await running_server.http.post(f"{READY_CHECK}/decline")).status == 204
            body = await (await running_server.http.get(READY_CHECK)).json()
            assert body["playerResponse"] == "Declined"
        async with running(mock()) as running_server:
            assert (await running_server.http.post(f"{READY_CHECK}/accept")).status == 404

    asyncio.run(scenario())


def test_my_selection_sets_the_local_players_spells():
    async def scenario():
        server = mock("champ-select")
        async with running(server) as running_server:
            reply = await running_server.http.patch(
                f"{CHAMP_SELECT}/my-selection", json={"spell1Id": 14, "spell2Id": 4}
            )
            assert reply.status == 204
            session = await (await running_server.http.get(CHAMP_SELECT)).json()
            local, ally = session["myTeam"]
            assert (local["spell1Id"], local["spell2Id"]) == (14, 4)
            assert (ally["spell1Id"], ally["spell2Id"]) == (4, 11)
            assert server.writes[0].body == {"spell1Id": 14, "spell2Id": 4}

    asyncio.run(scenario())


@pytest.mark.parametrize("payload", [{}, {"spell1Id": "4"}, [4, 14], {"spell2Id": True}])
def test_my_selection_rejects_bad_shapes_without_changing_state(payload):
    async def scenario():
        server = mock("champ-select")
        async with running(server) as running_server:
            before = server.state[CHAMP_SELECT]
            reply = await running_server.http.patch(f"{CHAMP_SELECT}/my-selection", json=payload)
            assert reply.status == 400
            assert server.state[CHAMP_SELECT] == before
            assert (server.writes[0].body, server.writes[0].status) == (payload, 400)

    asyncio.run(scenario())


def test_perk_pages_can_be_created_edited_and_deleted():
    async def scenario():
        server = mock()
        async with running(server) as running_server:
            http = running_server.http
            created = await (await http.post("/lol-perks/v1/pages", json=PAGE)).json()
            assert created == {**PAGE, "id": 1}
            assert await (await http.get("/lol-perks/v1/pages")).json() == [created]
            assert await (await http.get("/lol-perks/v1/currentpage")).json() == created

            edited = {**PAGE, "name": "Mito · Edited"}
            reply = await http.put("/lol-perks/v1/pages/1", json=edited)
            assert (reply.status, (await reply.json())["name"]) == (200, "Mito · Edited")
            assert (await http.put("/lol-perks/v1/pages/9", json=edited)).status == 404

            assert (await http.delete("/lol-perks/v1/pages/1")).status == 204
            assert await (await http.get("/lol-perks/v1/pages")).json() == []
            assert [w.method for w in server.writes] == ["POST", "PUT", "PUT", "DELETE"]
            assert server.writes[1].body == edited

    asyncio.run(scenario())


@pytest.mark.parametrize(
    "payload",
    [
        {k: v for k, v in PAGE.items() if k != "name"},
        {**PAGE, "selectedPerkIds": ["8112"]},
        {**PAGE, "primaryStyleId": 81.5},
        "page",
    ],
)
def test_perk_pages_reject_bad_shapes(payload):
    async def scenario():
        server = mock()
        async with running(server) as running_server:
            reply = await running_server.http.post("/lol-perks/v1/pages", json=payload)
            assert reply.status == 400
            assert "/lol-perks/v1/pages" not in server.state

    asyncio.run(scenario())


def test_item_sets_put_replaces_the_list_and_validates_it():
    path = "/lol-item-sets/v1/item-sets/1/sets"
    sets = {"accountId": 1, "timestamp": 0, "itemSets": [{"uid": "mito-103", "title": "Mito · X"}]}

    async def scenario():
        server = mock()
        async with running(server) as running_server:
            http = running_server.http
            assert (await http.put(path, json=sets)).status == 204
            assert await (await http.get(path)).json() == sets
            assert (await http.put(path, json={"itemSets": ["x"]})).status == 400
            assert (await http.put(path, json=[])).status == 400
            assert await (await http.get(path)).json() == sets
            assert [w.body for w in server.writes] == [sets, {"itemSets": ["x"]}, []]

    asyncio.run(scenario())


def test_unknown_writes_are_404_and_still_recorded():
    async def scenario():
        server = mock()
        async with running(server) as running_server:
            reply = await running_server.http.post("/lol-lobby/v2/lobby", json={"queueId": 420})
            assert reply.status == 404
            assert server.writes[0].body == {"queueId": 420}

    asyncio.run(scenario())
