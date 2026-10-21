# 0005 — Data pipeline and snapshot distribution

- **Status**: accepted
- **Date**: 2026-10-20

## Context

Mito's recommendations need aggregated statistics over hundreds of thousands of matches per
patch. The app cannot call the Riot API itself: the API key would ship inside the app (Riot
policy and `MITO_CONTEXT.md` §5 forbid it), every install would share one rate limit, and a
30-second champ select leaves no time for network round trips. An online database or API
would solve the key problem but adds a server to run, scale, and pay for, and breaks offline
use. The alternative is a precomputed file the app downloads, which only works if it stays
small: it is fetched again every patch, and the decoder must be one macOS ships (Apple's
Compression framework decodes LZMA/xz, not zstd).

## Decision

- **Separate private repo**: the pipeline (crawler, raw store, aggregation, export, publish)
  lives in `mito-data`. This repo only consumes what it publishes. The two meet at the
  snapshot contract in `MITO_CONTEXT.md` §17.
- **Static distribution, no online backend in v1**: one SQLite snapshot per patch, queue, and
  bracket plus a `manifest.json`, on Cloudflare R2. Only queue 420 is crawled; Flex (440) and
  Normal Draft (400) reuse its snapshot.
- **Brackets**: `emerald_plus` is the base and is always downloaded; `diamond_plus` is an
  optional overlay the user enables; `master_plus` is not published until measured volume
  supports it. Backing off to a wider bracket means querying the base file. Regions are always
  merged.
- **Compression**: `VACUUM`, then xz (`.sqlite.xz`).
- **Size budget**, enforced by the exporter per file: warn at 4 MB compressed; hard limit
  8 MB compressed and 32 MB uncompressed. On a breach it prunes in this order, re-measuring
  after each step, and fails the export if still over: (1) per-opponent `item_builds` except
  `start`; (2) per-opponent rune pages and spell pairs under 300 games; (3) `synergy_stats`
  minimum raised to 100; (4) `vs_team_stats` minimum raised to 100; (5) `item_vs_profile`
  capped at the top 10 per champion, role, and profile. Never pruned: `meta`, `champions`,
  `champion_roles`, `champ_role_stats`, `champion_profiles`, `duration_curves`, general
  loadouts, `matchup_stats` rows with 30+ games, `champ_vs_profile`, `item_classes`,
  `champion_flags`. The measured estimate is 1.2–1.9 MB compressed per `emerald_plus` file.
- **Completeness rule**: in the base file, every `champ_role_stats` row has a general rune
  page, spell pair, start, core, boots, and skill order. The crawler always fetches the
  timeline for a match containing a (champion, role) with fewer than ~150 timelines this
  patch; core and boots fall back to final items when timelines are still short. The export
  fails if the rule cannot be met.
- **Cold start**: the exporter blends the previous patch into the counts and records it in
  `meta` (`blend_patches`, `blend_k`). The app keeps only the current file.
- **Curated matchup tips** ship in v1 but not in the snapshot: they are written by hand in
  `mito-data`, exported as a separate file per locale (es-AR first) listed in the manifest,
  updated on their own schedule, and each tip records the patch it was last reviewed for.
- **ARAM** is a degraded mode in v1: personal data and the user's fixed pages only. ARAM
  statistics come later, as a separate file.
- **Contract rules**:
  - Every primary key column is `NOT NULL`; "no opponent" is `opp_id = 0`.
  - Every table is `WITHOUT ROWID` except `rune_page_defs`.
  - No JSON in keys or hot columns. Only some `meta` values are JSON, read once at open.
  - Raw counts and sums only. Smoothing priors, sample thresholds, tier cut-offs, and
    enemy-profile rules travel in `meta`, so the exporter and the app apply the same numbers.
  - File identity is (schema_version, patch, queue, bracket), stored in `meta` and in each
    manifest entry; `schema_version` is also in the URL path. `sha256` and `bytes` describe
    the compressed file; `raw_bytes` describes the decompressed one.
  - Any schema change (table, column, semantics, or `meta` key) bumps `schema_version`.
  - `mito-data` generates a small sample snapshot committed under `fixtures/snapshot/`; the
    app's contract test runs against it.

## Consequences

- The Riot API key never leaves `mito-data`, and the app works offline once a snapshot is
  downloaded. Hosting is static files on R2, with no egress cost.
- Statistics refresh at the pipeline's cadence (12–24 h), not live.
- A schema change is a coordinated change across both repos: §17, the fixture, and the
  `MitoStore` reader move together. The app ignores manifest entries with a `schema_version`
  it does not support, so the pipeline publishes both versions during a transition.
- Rare data gets pruned before core data. A size breach shows up as a failed export, never as
  an oversized download.
- Tips can be fixed or added without republishing a snapshot. They are a manual workload that
  can lag behind patches; the app shows when a tip was last reviewed.
- A `master_plus` overlay ships only after its volume is measured, as one more manifest
  entry with the same schema. ARAM statistics need their own file and contract.
