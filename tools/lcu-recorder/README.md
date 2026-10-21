# lcu-recorder

Records the League client's LCU traffic into `fixtures/lcu/<scenario>/` (format v0, see
`fixtures/lcu/README.md`). Read-only: it sends GET requests and WAMP subscribe/unsubscribe
frames to `127.0.0.1` and nothing else. Identifiers, the token, and the port are anonymized
in memory; nothing is written if any of them survives.

## Prerequisites

- macOS with the League client open and logged in.
- `uv` (`brew install uv`).

## Record

From `tools/lcu-recorder/`:

```sh
uv run lcu-recorder record <scenario>               # stop with Ctrl-C
uv run lcu-recorder record <scenario> --duration 300
```

`--out` changes the output root (default: the repo's `fixtures/lcu`), `--lockfile` points at a
non-standard install. Start recording before the step you want to capture; it refuses to
overwrite an existing scenario directory.

| Scenario | What to do in the client |
| --- | --- |
| `ready-check` | Open a lobby, queue, let the ready check appear; accept it yourself, then stop once champ select opens. |
| `champ-select` | Start recording while queued, before champ select opens (draft or ranked). Hover, ban, pick, and swap spells by hand until the game loads, then stop. |
| `lobby-to-game` | Start from the home screen: create a lobby, pick roles, queue, accept, finish champ select, and stop a few seconds after the loading screen shows. |

Do everything by hand: the recorder never accepts, picks, or bans. Stop at the loading screen;
there is nothing to record in game.

## Before committing

Open the three files and read them. Look for your Riot ID, friends' names, or anything that
could identify a player; if something slipped through, delete the directory, add the key to
`DENY_KEY_PATTERNS` in `src/lcu_recorder/anonymize.py`, and re-record. Check that phases,
champion IDs, and timers look intact too.

## Develop

```sh
uv run pytest && uv run ruff check && uv run ruff format --check
```
