# Snapshot fixture

A small sample of the per-patch stats snapshot and its schema, exported by `mito-data`. It
is the contract the app's `MitoStore` tests run against (`MITO_CONTEXT.md` §17,
`docs/adr/0005-data-pipeline-and-snapshot-distribution.md`).

- **Generated, never hand-edited.** Regenerate it from `mito-data`; when the schema changes,
  `schema_version` is bumped there and the fixture is replaced here in the same change as
  the reader.
- **Arrives in unit P5-01** (`docs/roadmap.md`). Until then this folder holds only this file.
- **Shared critical.** Any change here is part of the snapshot contract and runs as a serial
  unit coordinated with `mito-data`.
