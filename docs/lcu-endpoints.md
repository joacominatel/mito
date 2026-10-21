# LCU endpoints

What Mito has verified about each League Client (LCU) endpoint it uses: path, method, the
fields Mito reads or sends, and the client patch and fixture each was checked against. The
list of endpoints and what they are for is `MITO_CONTEXT.md` §10.6; this file records what
the real client actually returns.

A unit edits only the group its card names. Field names come from recorded fixtures
(`fixtures/lcu/`), never from memory.

The recordings so far are `ready-check`, `champ-select`, and `lobby-to-game`, all on client
`16.21.8298620` (patch `16.21`). Between them they cover a lobby, queueing, a ready check
accepted by hand, and a normal draft (queue 400) through bans and most picks. They do not
reach finalization or a game: `lobby-to-game` stops in `Matchmaking`, and `champ-select` ends
back at `None` before `FINALIZATION`.

lcu-recorder 0.1.0 anonymized the champ-select chat domain (`chatDetails.mucJwtDto.domain`,
which is `lol-champ-select`) in every path and topic too, so the `ready-check` and
`champ-select` recordings show `/anon-14/v1/session` and `OnJsonApiEvent_anon-14_v1_session`.
The tests and `tools/lcu-mock` restore it; the payloads are intact.

WAMP subscriptions match by path prefix: `OnJsonApiEvent_lol-lobby_v2_lobby` also delivers
`/lol-lobby/v2/lobby/members`, `/countdown`, and `/matchmaking/search-state`, and
`OnJsonApiEvent_lol-summoner_v1_current-summoner` delivers only
`/current-summoner/summoner-profile` and `/current-summoner/account-and-summoner-ids`, never
the resource itself. The other topics carried only their own URI.

## Session

**`GET /lol-summoner/v1/current-summoner`** — Verified against recording `ready-check`,
`champ-select`, `lobby-to-game` (2026-10-21). `puuid` (string), `summonerId` (int),
`gameName`, `tagLine` (strings), and `summonerLevel` (int) are all present. The body also
carries `accountId`, `displayName` and `internalName` (both `""`), `profileIconId`,
`privacy`, `rerollPoints`, `xpSinceLastLevel`, and more, none of which Mito reads.

**`GET /lol-patch/v1/game-version`** — Verified against recording `ready-check`,
`champ-select`, `lobby-to-game` (2026-10-21). Corrected: the body is
`"16.21.8298620+branch.releases-16-21.code.public.content.release.anticheat.vanguard"`, not a
bare dotted version. `GameVersion` now drops everything from the `+` (build metadata), so
`rawValue` is `16.21.8298620` and `patch` is `16.21`. Before, the `+` made it a decoding
error and the app ran with no client version.

**`OnJsonApiEvent_lol-summoner_v1_current-summoner`** — Verified against recording
`champ-select`, `lobby-to-game` (2026-10-21): an `Update` of `/summoner-profile` and a
`Delete` of `/account-and-summoner-ids` (data `null`). Mito only re-reads the summoner on any
event, so both just trigger a read.

Not yet verified: `/lol-champion-mastery/v1/local-player/champion-mastery`,
`/lol-ranked/v1/current-ranked-stats`, `/lol-champions/v1/inventories/{summonerId}/champions-minimal`,
`/lol-region-locale/v1/region-locale`.

## Gameflow/lobby

**`GET /lol-gameflow/v1/gameflow-phase`** and **`OnJsonApiEvent_lol-gameflow_v1_gameflow-phase`**
— Verified against recording `lobby-to-game`, `ready-check`, `champ-select` (2026-10-21). A
bare JSON string in both, `Update` events only. Seen: `None`, `Lobby`, `Matchmaking`,
`ReadyCheck`, `ChampSelect`; spelled as `GameflowPhase` has them. `lobby-to-game` goes
`None → Lobby → Matchmaking`; `champ-select` goes `Matchmaking → ReadyCheck → ChampSelect →
None`. Not yet seen: `GameStart`, `InProgress`, `WaitingForStats`, `PreEndOfGame`,
`EndOfGame`, `Reconnect`, `CheckedIntoTournament`.

**`GET /lol-gameflow/v1/session`** — Verified against recording `lobby-to-game`,
`ready-check`, `champ-select` (2026-10-21). 404 at `None`. In a lobby and after,
`gameData.queue.id` (int, `420` and `400`) and `gameData.queue.mapId` (int, `11`) are
present; the body also has `phase`, `map`, `gameClient`, `gameDodge`.

**`GET /lol-matchmaking/v1/ready-check`** and **`OnJsonApiEvent_lol-matchmaking_v1_ready-check`**
— Verified against recording `ready-check`, `champ-select`, `lobby-to-game` (2026-10-21).
`state` and `playerResponse` are strings; the body also has `timer` (a float of seconds),
`declinerIds`, `dodgeWarning`, `suppressUx`. Seen: `state` `InProgress`, `EveryoneReady`,
`Invalid`; `playerResponse` `None`, `Accepted`. The ready check opens with an `Update` (not a
`Create`), goes `InProgress/None` → `InProgress/Accepted` when the player accepts →
`EveryoneReady/Accepted`, then a `Delete` with `null` data. Corrected: the read is 404 only
before queueing; while searching and after the ready check it answers 200 with
`state: "Invalid"`, which the auto-accepter already treats as "not in progress". Not yet seen:
`StrangerNotReady`, `PartyNotReady`, `Error`, `Declined`.

**`OnJsonApiEvent_lol-lobby_v2_lobby`** — Recorded (2026-10-21) but not decoded by Mito: see
the prefix note above.

Not yet verified: `POST /lol-matchmaking/v1/ready-check/accept` and `/decline` (the recorder
sends only GETs), and the lobby writes.

## Champ select

**`GET /lol-champ-select/v1/session`** and **`OnJsonApiEvent_lol-champ-select_v1_session`**
— Verified against recording `ready-check`, `champ-select` (2026-10-21), queue 400 (normal
draft). The session opens with a `Create` and changes with `Update`s. Every field
`ChampSelectSession` reads is present with the documented name and type:
`localPlayerCellId`, `myTeam[]`/`theirTeam[]` (`cellId`, `championId`, `championPickIntent`,
`assignedPosition`, `spell1Id`, `spell2Id`, `team`), `actions[][]` (`id`, `actorCellId`,
`championId`, `type`, `isInProgress`, `completed`, `isAllyAction`), `bans.myTeamBans`,
`bans.theirTeamBans`, and `timer.phase` / `timer.adjustedTimeLeftInPhase` (an int of ms).

- `assignedPosition`: allies `utility`, `jungle`, `middle`, `bottom`, `top`; enemies `""`.
- `type`: `ban`, `ten_bans_reveal` (its `actorCellId` is `-1`), `pick`. The draft is ten
  simultaneous bans, the reveal, then picks `1-2-2-2-2-1`.
- `timer.phase`: `PLANNING`, then `BAN_PICK` for bans and picks alike. `FINALIZATION` is not
  in the recordings.
- Hover: `championPickIntent` holds the hover (also outside the player's turn), and the
  player's in-progress pick action carries it as its `championId`. A member's `championId`
  stays `0` until its pick completes.
- Corrected: `bans.myTeamBans` and `bans.theirTeamBans` stay `[]` for the whole normal draft,
  even after the reveal (`numBans` is `0`). The bans are only in the completed ban actions,
  which `draftContext` already reads.
- Corrected: a skipped ban completes with `championId: -1`. `-1` (like `0`) now decodes as no
  champion for `championId`, `championPickIntent`, the spells, and the `bans` arrays; before,
  it reached `DraftContext.bans` as a champion with id `-1`.
- The closing `Delete` carries a full, empty session (`localPlayerCellId: -1`,
  `timer.phase: ""`, empty teams and actions), not `null`. It maps to no draft.
- The body also carries identity per member (`puuid`, `summonerId`, `gameName`, `tagLine`,
  `obfuscatedPuuid`, `nameVisibilityType`), which is never decoded (§5).

**`GET /lol-champ-select/v1/pickable-champion-ids`** — Verified against recording
`ready-check`, `champ-select` (2026-10-21): an array of 173 positive ints, 404 outside champ
select.

**`GET /lol-champ-select/v1/bannable-champion-ids`** — Verified against recording
`ready-check`, `champ-select` (2026-10-21). Corrected: the first read, in planning, is
`[-1]`; later reads are either `[-1]` or the 173 bannable ids plus a `-1`. Negative ids are now
dropped, so `[-1]` is an empty set.

Not yet verified: `PATCH /lol-champ-select/v1/session/my-selection` and the action writes (the
recorder sends only GETs).

## Runes

Not yet verified.

## Item sets

Not yet verified.

## History

Not yet verified.

## Assets

Not yet verified.
