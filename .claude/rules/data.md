---
paths:
  - "data/**"
  - "tools/**"
---

# Data pipeline and tools conventions

Governing sections: `MITO_CONTEXT.md` §7, §14–17, §23.

## Stack

- Python 3.12+, managed with `uv` (commit the lockfile). httpx async, pydantic models for
  match-v5, Parquet raw store, DuckDB + Polars for aggregation, typer CLI.
- Aggregation SQL lives versioned in `data/sql/`, not inline strings.

## Riot API

- The API key comes from the environment only. Never committed, never logged, never written
  into the snapshot.
- Every request goes through the shared rate limiter and honors `Retry-After`. No ad-hoc
  clients.

## Snapshot contract

- The exported SQLite schema is a contract with `MitoStore`. Any schema change bumps
  `schema_version`, updates `MITO_CONTEXT.md` §17, and keeps the contract test green.

## Tools

- `tools/lcu-recorder` anonymizes PUUIDs, names, and IDs before writing fixtures. A fixture
  with real identifiers is never committed.
- `tools/lcu-mock` only binds to `127.0.0.1`.

## Tests

- pytest under `data/tests/` and `tools/<tool>/tests/`, on small fixed datasets. Never hit
  the live Riot API in tests.
