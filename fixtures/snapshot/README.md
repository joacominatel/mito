# Snapshot fixture

A small sample of the per-patch stats snapshot and its schema, exported by `mito-data`. It
is the contract the app's `MitoStore` tests run against (`MITO_CONTEXT.md` §17,
`docs/adr/0005-data-pipeline-and-snapshot-distribution.md`).

- **Generated, never hand-edited.** Regenerate it from `mito-data`; when the schema changes,
  `schema_version` is bumped there and the fixture is replaced here in the same change as
  the reader.
- **Source:** `mito-data` commit `927a3b3`, regenerated with `uv run mito-data fixture`
  (deterministic). Files: `emerald_plus.sqlite`, its `.xz`, `schema.sql`, `manifest.json`
  (sha256, `bytes` and `raw_bytes` match the `.xz`), and `tips/es-AR.json`. The data is
  synthetic with real Riot IDs; Zed (238) JUNGLE exercises the final-items fallback, and
  Udyr (77) JUNGLE a 4-letter `max_order`. Every Phase 7 table is populated (matchups,
  synergies, vs-team, enemy profiles, per-opponent loadouts, ban stats) with curated
  `champion_flags` and the calibrated `meta.profile_rules`.
- **Shared critical.** Any change here is part of the snapshot contract and runs as a serial
  unit coordinated with `mito-data`.
