# 0011 — R2 bucket layout

- **Status**: accepted
- **Date**: 2026-10-21
- **Extends**: [0005](0005-data-pipeline-and-snapshot-distribution.md), [0009](0009-sparkle.md), [0010](0010-release-pipeline.md)

## Context

ADR 0005 puts the snapshots, the tips and `manifest.json` on Cloudflare R2. The bucket now
exists, served at `https://data.jminatel.dev/`, and `mito-data` publishes to it. The app
release (the Sparkle appcast and DMGs) will be served from the same host. The CEO asked for a
layout that stays tidy as it grows: no repeated folders, and every publish traceable and
auditable after the fact. A cache in front of R2 must never serve a stale manifest, and a
snapshot an install is downloading must not change under it.

## Decision

- **Layout.**

  ```
  manifest.json                                             mutable, Cache-Control: no-cache
  snapshots/v1/<patch>/<queue>/<bracket>/<build>.sqlite.xz  immutable
  tips/v1/<locale>/<build>.json                             immutable
  audit/publishes/<build>.json                              one record per publish
  audit/prunes/<UTC timestamp>.json                         one record per prune
  app/appcast.xml                                           release pipeline only
  app/releases/<version>/Mito.dmg                           release pipeline only
  ```

- **Build IDs.** `<build>` is `<UTC yyyymmddTHHMMSSZ>-<first 8 hex of the mito-data commit>`,
  for example `20261021T120000Z-1a2b3c4d`. It sorts by time and names the code that made it.
  One publish shares one build ID across every file it writes.
- **Versions.** `v1` is the snapshot `schema_version` under `snapshots/` and the tips
  `format_version` under `tips/`. A schema change publishes under `v2/` beside `v1/` during
  the transition (ADR 0005).
- **Immutability.** `manifest.json` is the only data object ever overwritten, with
  `Cache-Control: no-cache`. Snapshot and tips files are written once under a new build ID
  with `Cache-Control: public, max-age=31536000, immutable`, and never rewritten. A republish
  is a new build, never a new body at an old key.
- **The manifest leads.** Its `url` fields are absolute. The app knows only the base URL and
  `manifest.json` at its root; it follows the manifest for everything else, so the folders
  below can change without an app release. The manifest is written last, after every file it
  names is uploaded and verified.
- **Audit trail.** Each publish writes `audit/publishes/<build>.json`: the manifest it
  published, verbatim; the `mito-data` commit; the crawl window and match counts; every key it
  wrote with its `sha256` and `bytes`; the build it replaced; and the UTC time. A prune writes
  `audit/prunes/<UTC timestamp>.json` listing each key it deleted and why. Audit records are
  never modified or deleted.
- **Retention.** Keep every file the current manifest references, plus the last build of the
  previous patch, so a rollback is one manifest write. Everything else may be pruned, only by
  an explicit prune command that writes its audit record. No bucket lifecycle rules: nothing
  disappears without a record.
- **Ownership.** `mito-data` writes everything except `app/**`. The release pipeline (ADR 0010)
  owns `app/**` and writes nothing else; the appcast is `app/appcast.xml` and each DMG is
  `app/releases/<version>/Mito.dmg`. `app/appcast.xml` is mutable like the manifest.
- **Credentials.** R2 access keys live only in the CEO's macOS Keychain, item `mito-r2`. They
  are read at publish time and never enter this repository, `mito-data`'s repository, CI, a
  log, or the app. The app reads the bucket anonymously over HTTPS.
- **App configuration.** The base URL is the build setting `MITO_DATA_BASE_URL`
  (`https://data.jminatel.dev/` in Debug and Release), carried into Info.plist as
  `MitoDataBaseURL`. A missing, non-HTTPS or `.invalid` value means the app never downloads.
  Tests never download, whatever the value.

## Consequences

- Any file the app ever downloaded can be traced to its publish, its commit and its crawl, and
  a deletion can be traced to its prune.
- Caches can hold snapshots and tips for a year; only the manifest is revalidated on each
  check, so a new build reaches every install on its next launch.
- A rollback rewrites `manifest.json` to point at a retained build.
- Storage grows by one build per publish until a prune. Builds are 1–2 MB, so pruning is a
  tidiness task, not a cost one.
- The app's host is in an xcconfig, not in code: moving the bucket is a configuration change
  plus a manifest on the new host.
