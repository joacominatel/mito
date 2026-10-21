# LCU fixtures

Recorded and hand-written League Client (LCU) payloads. Tests read them through
`Fixtures.url(_:)` in `MitoTestSupport` (resolved from the repository root via `#filePath`,
no SwiftPM resources); `tools/lcu-mock` serves the same scenarios. Nothing here comes from a
live client at test time.

## Recording format v0

One directory per scenario, written by `tools/lcu-recorder` (`MITO_CONTEXT.md` §23.2):

```
fixtures/lcu/<scenario>/
├── scenario.json
├── rest.jsonl
└── events.jsonl
```

- **`scenario.json`** — one object describing the recording:

  ```json
  { "format": 0, "clientPatch": "25.20", "queueId": 420, "recorderVersion": "0.1.0", "anonymized": true }
  ```

- **`rest.jsonl`** — one REST exchange per line, in recording order:

  ```json
  { "method": "GET", "path": "/lol-gameflow/v1/gameflow-phase", "status": 200, "body": "ChampSelect" }
  ```

  `body` is the decoded JSON response (any JSON value), or `null` for an empty body.

- **`events.jsonl`** — one WAMP event per line, in arrival order:

  ```json
  { "t_ms": 1532, "topic": "OnJsonApiEvent_lol-gameflow_v1_gameflow-phase", "uri": "/lol-gameflow/v1/gameflow-phase", "eventType": "Update", "data": "ChampSelect" }
  ```

  `t_ms` is milliseconds since the recording started; `topic` is the subscribed event name;
  `uri`, `eventType`, and `data` are the event payload as the client sent it.

A change to these shapes bumps `format` in `scenario.json` and updates this file.

## Hand-written decoding cases

Small payloads that pin one decoding behavior (an unknown enum value, a missing field, an
extra field) live in `fixtures/lcu/cases/<group>/<case>.json`, where `<group>` matches a
heading in `docs/lcu-endpoints.md`. Each file is the raw response body, nothing else.

## Rules

- **Anonymized, always.** No real PUUIDs, summoner IDs, Riot IDs, names, tokens, or ports.
  `anonymized: true` is required; the recorder replaces identifiers before writing.
- **One scenario per directory, owned by one unit.** A unit writes only the scenario
  directories its card lists (lane `fixtures-<scenario>`).
- **Never edit a recording by hand.** Re-record it, or add a hand-written case instead.
