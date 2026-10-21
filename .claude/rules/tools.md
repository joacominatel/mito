---
paths:
  - "tools/**"
  - "fixtures/**"
---

# Tools and fixtures conventions

Governing sections: `MITO_CONTEXT.md` §17, §23.

## Tools

- Python 3.12+, managed with `uv` per tool (commit the lockfile).
- `tools/lcu-recorder` anonymizes PUUIDs, names, and IDs before writing fixtures. A fixture
  with real identifiers is never committed.
- `tools/lcu-mock` only binds to `127.0.0.1`.
- pytest under `tools/<tool>/tests/`. Never hit a live client or the Riot API in tests.

## Snapshot fixture

- `fixtures/snapshot/` holds a small sample snapshot and its schema, exported by `mito-data`.
  It is the contract the app's `MitoStore` tests run against. Never hand-edit the `.sqlite`;
  regenerate it from `mito-data` and bump `schema_version` when the schema changes.
