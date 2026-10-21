import json

import pytest

from lcu_recorder.anonymize import REDACTED, Anonymizer, LeakError, is_denied

TOKEN = "s3cr3tT0ken"
PORT = 54321
PUUID = "6f1c2b3a-1111-4222-8333-944455556666"
ALLY_PUUID = "0a0b0c0d-aaaa-4bbb-8ccc-ddddeeeeffff"
SUMMONER_ID = 2345678901


def champ_select() -> dict:
    return {
        "localPlayerCellId": 2,
        "gameId": 7012345678,
        "chatDetails": {
            "multiUserChatId": f"{PUUID}@champ-select.pvp.net",
            "multiUserChatPassword": "pw-xyz-123",
            "mucJwtDto": {"jwt": "eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl", "targetRegion": "la2"},
        },
        "myTeam": [
            {
                "cellId": 2,
                "championId": 103,
                "championPickIntent": 0,
                "assignedPosition": "middle",
                "spell1Id": 4,
                "spell2Id": 14,
                "puuid": PUUID,
                "summonerId": SUMMONER_ID,
                "gameName": "RealPlayer",
                "tagLine": "LAS",
                "nameVisibilityType": "HIDDEN",
                "obfuscatedPuuid": "",
                "obfuscatedSummonerId": 0,
                "team": 1,
            },
            {"cellId": 3, "championId": 0, "puuid": ALLY_PUUID, "summonerId": 0, "team": 1},
        ],
        "theirTeam": [{"cellId": 7, "championId": 238, "assignedPosition": ""}],
        "actions": [
            [{"id": 1, "actorCellId": 0, "championId": 0, "type": "ban", "isInProgress": True}],
            [{"id": 11, "actorCellId": 2, "championId": 103, "type": "pick", "completed": False}],
        ],
        "bans": {"myTeamBans": [], "theirTeamBans": []},
        "timer": {"phase": "BAN_PICK", "adjustedTimeLeftInPhase": 27000},
    }


def anonymize(*payloads):
    anonymizer = Anonymizer(secrets=[TOKEN], port=PORT)
    for payload in payloads:
        anonymizer.collect(payload)
    out = [anonymizer.apply(payload) for payload in payloads]
    for value in out:
        anonymizer.verify(value)
    return anonymizer, out


def test_replaces_identifiers_and_keeps_draft_data():
    _, [out] = anonymize(champ_select())
    me = out["myTeam"][0]

    assert me["puuid"] != PUUID and me["puuid"].startswith("00000000-0000-4000-8000-")
    assert me["summonerId"] != SUMMONER_ID and isinstance(me["summonerId"], int)
    assert me["gameName"].startswith("anon-") and me["tagLine"].startswith("anon-")
    assert out["gameId"] != 7012345678

    assert out["localPlayerCellId"] == 2
    kept = ("cellId", "championId", "assignedPosition", "spell1Id", "spell2Id", "team")
    assert {k: me[k] for k in kept} == {k: champ_select()["myTeam"][0][k] for k in kept}
    assert me["nameVisibilityType"] == "HIDDEN"
    assert out["actions"] == champ_select()["actions"]
    assert out["timer"] == champ_select()["timer"]
    assert out["theirTeam"] == champ_select()["theirTeam"]


def test_whole_identifying_subtrees_are_replaced_but_keep_their_shape():
    _, [out] = anonymize(champ_select())
    chat = out["chatDetails"]
    assert set(chat) == {"multiUserChatId", "multiUserChatPassword", "mucJwtDto"}
    assert set(chat["mucJwtDto"]) == {"jwt", "targetRegion"}
    assert "pw-xyz-123" not in json.dumps(out)
    assert "eyJ" not in json.dumps(out)


def test_sentinels_stay_as_they_are():
    _, [out] = anonymize(champ_select())
    assert out["myTeam"][0]["obfuscatedPuuid"] == ""
    assert out["myTeam"][0]["obfuscatedSummonerId"] == 0
    assert out["myTeam"][1]["summonerId"] == 0


def test_same_value_maps_to_the_same_fake_across_payloads_and_positions():
    ready_check = {"state": "InProgress", "declinerIds": [SUMMONER_ID], "timer": 3.0}
    summoner = {"puuid": PUUID, "summonerId": SUMMONER_ID, "summonerLevel": 312}
    by_puuid = {PUUID: {"note": f"/lol-champions/v1/inventories/{SUMMONER_ID}/champions"}}
    _, [session, check, me, keyed] = anonymize(champ_select(), ready_check, summoner, by_puuid)

    fake_id = session["myTeam"][0]["summonerId"]
    fake_puuid = session["myTeam"][0]["puuid"]
    assert check["declinerIds"] == [fake_id]
    assert (me["puuid"], me["summonerId"]) == (fake_puuid, fake_id)
    assert keyed == {fake_puuid: {"note": f"/lol-champions/v1/inventories/{fake_id}/champions"}}
    assert check["state"] == "InProgress" and me["summonerLevel"] == 312
    assert session["chatDetails"]["multiUserChatId"] != session["myTeam"][0]["puuid"]


def test_names_found_elsewhere_are_replaced_inside_free_text():
    _, [_, text] = anonymize(champ_select(), {"message": "RealPlayer left the lobby"})
    assert "RealPlayer" not in text["message"] and text["message"].endswith(" left the lobby")


def test_unknown_uuid_shaped_values_are_replaced_wherever_they_appear():
    _, [out] = anonymize({"weirdField": ["x", f"prefix {ALLY_PUUID}"]})
    assert ALLY_PUUID not in json.dumps(out)


def test_mappings_do_not_carry_over_between_recordings():
    first = Anonymizer()
    first.collect({"puuid": "a" * 8})
    second = Anonymizer()
    second.collect({"puuid": "b" * 8, "summonerId": 10})
    second.collect({"puuid": "a" * 8})
    assert first.apply({"puuid": "a" * 8}) != second.apply({"puuid": "a" * 8})


def test_scrubs_the_token_and_port_from_payload_strings():
    payload = {"url": f"https://127.0.0.1:{PORT}/x?t={TOKEN}", "port": PORT}
    _, [out] = anonymize(payload)
    assert out["url"] == f"https://127.0.0.1:{REDACTED}/x?t={REDACTED}"
    assert out["port"] != PORT


@pytest.mark.parametrize(
    "key",
    [
        "puuid",
        "summonerId",
        "accountId",
        "playerId",
        "declinerIds",
        "gameName",
        "tagLine",
        "displayName",
        "summonerInternalName",
        "riotId",
        "riotIdTagline",
        "profileIconId",
        "partyId",
        "invitationId",
        "chatRoomName",
        "mucJwtDto",
        "conversationId",
        "token",
        "password",
        "serverIp",
        "serverPort",
        "observerEncryptionKey",
    ],
)
def test_denies_identifier_shaped_keys(key):
    assert is_denied(key)


@pytest.mark.parametrize(
    "key",
    [
        "championId",
        "cellId",
        "actorCellId",
        "localPlayerCellId",
        "queueId",
        "id",
        "teamId",
        "spell1Id",
        "selectedSkinId",
        "phase",
        "championName",
        "nameVisibilityType",
        "assignedPosition",
        "playerResponse",
        "summonerLevel",
        "championShip",
        "isSpectating",
    ],
)
def test_keeps_data_keys(key):
    assert not is_denied(key)


def test_verify_fails_when_a_collected_identifier_survives():
    anonymizer = Anonymizer(secrets=[TOKEN], port=PORT)
    anonymizer.collect(champ_select())
    for leaked in [
        {"x": "RealPlayer"},
        {"x": f"chat {PUUID}"},
        {"x": SUMMONER_ID},
        {"x": f"id {SUMMONER_ID}"},
        {"x": f"Basic {TOKEN}"},
        {"x": f"127.0.0.1:{PORT}"},
        {"x": "eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl"},
        {PUUID: 1},
    ]:
        with pytest.raises(LeakError) as raised:
            anonymizer.verify(leaked)
        assert "RealPlayer" not in str(raised.value) and TOKEN not in str(raised.value)


def test_verify_text_catches_the_token_in_serialized_output():
    with pytest.raises(LeakError):
        Anonymizer(secrets=[TOKEN]).verify_text(f'{{"a":"{TOKEN}"}}')


def test_apply_refuses_identifiers_it_never_collected():
    with pytest.raises(LeakError):
        Anonymizer().apply({"puuid": "never-collected"})
