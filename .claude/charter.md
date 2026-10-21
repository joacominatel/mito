# Charter

## Identity

- **Repository**: mito (`git@github.com:joacominatel/mito.git`)
- **Owned by the CEO**: yes
- **What it is**: a native macOS companion app for League of Legends (pre-game: auto-accept,
  champ select recommendations, rune/spell/item import) plus the Python pipeline that builds
  its per-patch stats snapshot.
- **Source of truth for domain and decisions**: `MITO_CONTEXT.md` (Spanish), then `docs/adr/`.

## Branches

- **Base branch**: `dev`. All work is committed directly on `dev` and pushed to `origin/dev`.
- **Protected**: `main`. Agents never commit, push, or merge here.
- **Branch naming**: none during the pre-beta phase (see exceptions).
- **Promotion**: only the CEO promotes `dev` to `main`, fast-forward only, then tags `vX.Y.Z`.
  The first promotion is the testable beta. See `docs/adr/0004-branching-and-merge-strategy.md`.

## Commits

- **Prefixes**: Conventional Commits with the lane as scope — `feat`, `fix`, `test`,
  `refactor`, `docs`, `chore`, `ci`. Example: `feat(app): add LCU lockfile discovery`.
- **Granularity**: one logical responsibility per commit; documentation may be grouped.
- **Forbidden**: `--amend`, `rebase`, `reset`, `add -A`, `add .`, attribution trailers.

## Issues and labels

- **Tracker**: none during the pre-beta phase. The roadmap in `MITO_CONTEXT.md` §26 is the
  backlog.

## Lanes

| Lane | May write | Must not touch |
| --- | --- | --- |
| app | `apps/macos/**` | `data/**`, `tools/**` |
| data | `data/**` | `apps/**`, `tools/**` |
| tools | `tools/**` | `apps/**`, `data/**` |
| tests | `apps/macos/MitoKit/Tests/**`, `apps/macos/MitoTests/**`, `data/tests/**`, `tools/*/tests/**` | all non-test code |
| docs | `docs/**`, `*.md` | all application code |

Cross-lane edits require explicit authorization in the dispatch prompt, and the commit message
records it.

## Shared critical files

A unit touching any of these forces serial execution.

- `MITO_CONTEXT.md`
- `apps/macos/Mito.xcodeproj/project.pbxproj`
- `apps/macos/MitoKit/Package.swift`
- `apps/macos/Config/*.xcconfig`
- `.github/workflows/**`
- The snapshot schema: the exporter in `data/src/mito_data/export/` and its reader in
  `apps/macos/MitoKit/Sources/MitoStore/` (contract test in `MITO_CONTEXT.md` §23.3)
- `data/pyproject.toml`, `data/uv.lock`

## Validation

Run all of these before committing:

```sh
swift format lint --strict -r apps/macos
swift test --package-path apps/macos/MitoKit --enable-code-coverage
xcodebuild -project apps/macos/Mito.xcodeproj -scheme Mito -destination 'platform=macOS' build
```

CI (`.github/workflows/tests.yml`) runs only the MitoKit tests, with warnings as errors, on
pushes to `main`/`dev` and pull requests targeting them.

Pending until the `data/` and `tools/` projects exist: `uv run pytest`, `uv run ruff check`.

Not run locally: a real League client. Integration runs against `tools/lcu-mock`.

## Review dimensions

Every change must clear all of these:

1. **Correctness** — it does what it claims, with behavior-focused tests that prove it.
2. **Security** — no new exposure: the LCU token lives in memory only and is never logged;
   TLS is accepted only for `127.0.0.1`; the Riot API key never enters the app or the repo.
3. **Over-engineering** — no dead code, speculative abstraction, or hand-rolled stdlib.
4. **Riot compliance** — only official or semi-official APIs (LCU, Riot API, Data Dragon,
   CommunityDragon); zero memory access, injection, or process hooks; nothing automated
   in-game; no de-anonymization during champ select; auto-pick/auto-ban off by default.
   Checked against `MITO_CONTEXT.md` §5.

## Documentation

- **Internal vault**: `MITO_CONTEXT.md` — updated in the same change as the code.
- **Decision records**: `docs/adr/` — numbered (`NNNN-slug.md`), with a consequences section.
- **User-facing surface**: none yet.

## Exceptions to global defaults

- **Pre-beta, local-first delivery.** Until the first beta lands on `main`: no issues, no
  pull requests, no feature branches, no worktrees. Work is committed directly on `dev` and
  pushed to `origin/dev`. After the beta, work returns to branch + PR into `dev`.
- **Documentation language.** `MITO_CONTEXT.md` stays in Spanish. Everything else is English.
- **UI language.** User-facing strings are Spanish (es-AR) first, through String Catalogs.
- **License.** Source-available under PolyForm Shield 1.0.0, not OSI open source
  (`docs/adr/0003-license.md`).
