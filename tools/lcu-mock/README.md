# lcu-mock

A fake League client (LCU) on `127.0.0.1` for developing and testing Mito without the game
(`MITO_CONTEXT.md` §23.1). It serves a scenario in recorder format v0 (`fixtures/lcu/README.md`),
so real recordings and the synthetic ones in `tests/scenarios/` are interchangeable.

## Run

From `tools/lcu-mock/`:

```sh
uv run lcu-mock --scenario tests/scenarios/ready-check --speed 4x
uv run lcu-mock --scenario ../../fixtures/lcu/ready-check --skip-lead-in
uv run lcu-mock --scenario ../../fixtures/lcu/<scenario> --lockfile /tmp/lcu/lockfile --port 54321
```

- Writes `LeagueClient:<pid>:<port>:<password>:https` to `--lockfile` (default `.run/lockfile`,
  git-ignored) and deletes it on exit, like the client. The password is random per run.
- HTTPS and WAMP (`wss://127.0.0.1:<port>/`) with a self-signed certificate generated at
  startup and never written to disk past loading. HTTP Basic `riot:<password>`; anything else is 401.
- **REST:** each path starts with its first `rest.jsonl` line; a replayed event then sets its
  `uri` to the event's `data` (`Delete` makes it 404). Unknown paths are 404.
- **Events:** replay starts at the first WAMP subscribe (`[5, topic]`), follows `events.jsonl`
  order with `t_ms` gaps divided by `--speed`, and reaches only sockets subscribed to that
  topic (`[6, topic]` stops it). `--skip-lead-in` sends the first event right away instead of
  after its `t_ms`; the recordings start long before anything happens (the ready check of
  `fixtures/lcu/ready-check` pops at 110 s).
- **Writes:** ready-check accept/decline, `PATCH …/session/my-selection`, perk pages
  (`POST`, `PUT`/`DELETE …/pages/{id}`), and `PUT /lol-item-sets/v1/item-sets/{id}/sets`.
  Each checks the payload shape (400 if wrong), updates the state, and publishes an `Update`.
  Every non-GET request is kept in `MockLCU.writes` for in-process tests.

Try it: `curl -k -u riot:$(cut -d: -f4 .run/lockfile) https://127.0.0.1:$(cut -d: -f3 .run/lockfile)/lol-gameflow/v1/gameflow-phase`.

## Pointing the app at it

With the mock running, launch a Debug build from the repository root with the lockfile's
absolute path:

```sh
open build/DerivedData/Build/Products/Debug/Mito.app --args -MitoLCULockfilePath "$PWD/tools/lcu-mock/.run/lockfile"
```

Discovery then reads only that lockfile and never the running processes, so an open League
client cannot win over the mock (`MITO_CONTEXT.md` §10.2). Release builds ignore the flag. The
app already accepts any certificate on `127.0.0.1` (§10.3), so nothing else changes. Quitting
the mock removes the lockfile, which the app sees as the client going away.

`open` passes `--args` only when Mito is not already running, so quit it first. At
`--speed 4x` the scenario's own accept lands as Mito's default 2 s auto-accept delay ends, so
Mito usually withdraws; use `--speed 1x` to see its `POST …/ready-check/accept` arrive.

## Recorded scenarios

`fixtures/lcu/ready-check`, `champ-select`, and `lobby-to-game` replay as recorded:

- **ready-check** starts queued (`Matchmaking`, ready check `Invalid`), pops the ready check,
  accepts it by hand at 2.7 s, and opens champ select.
- **champ-select** runs the same pop, then a normal draft through bans and most picks, and ends
  back at `None` with the session deleted.
- **lobby-to-game** goes from `None` to a lobby and into `Matchmaking`, and stops there.

lcu-recorder 0.1.0 anonymized the champ-select chat domain, which is the plugin's own name, in
every path and topic as well (`/anon-14/v1/session`). The loader restores
`/lol-champ-select/` and its topic until the scenarios are re-recorded.

## Limits

v0 REST lines carry no time: later lines for a path are ignored, and a path changes only
through events or writes. So in the recorded champ-select replay, `pickable-champion-ids` and
`bannable-champion-ids` stay 404, and a later recorded event overwrites an accept. Error bodies
only approximate the client's.

## Develop

```sh
uv run pytest && uv run ruff check && uv run ruff format --check
```
