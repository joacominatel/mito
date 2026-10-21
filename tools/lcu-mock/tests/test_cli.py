import argparse
import asyncio
import json

import aiohttp
import pytest
from support import SCENARIOS

from lcu_mock.cli import parse_args, parse_speed, run

PHASE_TOPIC = "OnJsonApiEvent_lol-gameflow_v1_gameflow-phase"
READY_TOPIC = "OnJsonApiEvent_lol-matchmaking_v1_ready-check"
CHAMP_TOPIC = "OnJsonApiEvent_lol-champ-select_v1_session"


@pytest.mark.parametrize(("text", "speed"), [("4x", 4.0), ("4", 4.0), ("0.5x", 0.5), ("1x", 1.0)])
def test_parse_speed_accepts_a_positive_multiplier(text, speed):
    assert parse_speed(text) == speed


@pytest.mark.parametrize("text", ["0x", "-2x", "fast", "x", "nanx", "infx"])
def test_parse_speed_rejects_anything_else(text):
    with pytest.raises(argparse.ArgumentTypeError):
        parse_speed(text)


def test_cli_defaults_to_real_time_on_a_free_port():
    args = parse_args(["--scenario", "s"])
    assert (args.speed, args.port, args.skip_lead_in) == (1.0, 0, False)


def test_ready_check_scenario_end_to_end_from_the_lockfile(tmp_path):
    lockfile = tmp_path / "lockfile"
    args = parse_args(
        [
            "--scenario",
            str(SCENARIOS / "ready-check"),
            "--speed",
            "200x",
            "--lockfile",
            str(lockfile),
        ]
    )

    async def scenario():
        stop = asyncio.Event()
        serving = asyncio.create_task(run(args, stop))
        async with asyncio.timeout(5):
            while not lockfile.exists():
                await asyncio.sleep(0.01)
        _, _, port, password, protocol = lockfile.read_text().split(":")
        assert protocol == "https"
        base = f"https://127.0.0.1:{port}"
        async with aiohttp.ClientSession(
            headers={"Authorization": aiohttp.encode_basic_auth("riot", password)},
            connector=aiohttp.TCPConnector(ssl=False),
        ) as http:
            phase = await http.get(f"{base}/lol-gameflow/v1/gameflow-phase")
            assert await phase.json() == "Lobby"
            socket = await http.ws_connect(f"wss://127.0.0.1:{port}/", protocols=("wamp",))
            for topic in (PHASE_TOPIC, READY_TOPIC, CHAMP_TOPIC):
                await socket.send_str(json.dumps([5, topic]))

            seen = []
            accepted = None
            while not seen or seen[-1] != (CHAMP_TOPIC, "Create"):
                _, topic, payload = json.loads(await socket.receive_str(timeout=5))
                seen.append((topic, payload["eventType"]))
                if topic == READY_TOPIC and payload["eventType"] == "Create":
                    reply = await http.post(f"{base}/lol-matchmaking/v1/ready-check/accept")
                    accepted = reply.status
                if topic == PHASE_TOPIC:
                    seen[-1] = (topic, payload["data"])

            assert accepted == 204
            assert [s for s in seen if s[0] == PHASE_TOPIC] == [
                (PHASE_TOPIC, "Matchmaking"),
                (PHASE_TOPIC, "ReadyCheck"),
                (PHASE_TOPIC, "ChampSelect"),
            ]
            assert (READY_TOPIC, "Delete") in seen
            session = await (await http.get(f"{base}/lol-champ-select/v1/session")).json()
            assert session["timer"]["phase"] == "PLANNING"
            assert (await http.get(f"{base}/lol-matchmaking/v1/ready-check")).status == 404
            await socket.close()
        stop.set()
        await serving
        assert not lockfile.exists()

    asyncio.run(scenario())
