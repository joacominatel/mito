# Charter

## Identity

- **Repository**: mito (`git@github.com:joacominatel/mito.git`)
- **Owned by the CEO**: yes
- **What it is**: a native macOS companion app for League of Legends (pre-game: auto-accept,
  champ select recommendations, rune/spell/item import) plus the Python pipeline that builds
  its per-patch stats snapshot. The pipeline lives in the private repo `mito-data`; this repo
  only consumes the published snapshot.
- **Source of truth for domain and decisions**: `MITO_CONTEXT.md` (Spanish), then `docs/adr/`.

## Branches

- **Base branch**: `dev`. Phase 0 commits directly on `dev`; from Phase 1, units land on
  `dev` by local squash merge (see exceptions).
- **Protected**: `main`. Agents never commit, push, or merge here.
- **Branch naming**: `unit/<id>-<slug>` (for example `unit/P1-01-lcu-discovery`), checked out
  in the worktree `.worktrees/<id>-<slug>`. Local only, never pushed.
- **Promotion**: only the CEO promotes `dev` to `main`, fast-forward only, then tags `vX.Y.Z`.
  The first promotion is the testable beta. See `docs/adr/0004-branching-and-merge-strategy.md`
  and `docs/adr/0006-parallel-unit-workflow.md`.

## Commits

- **Prefixes**: Conventional Commits — `feat`, `fix`, `test`, `refactor`, `docs`, `chore`,
  `ci` — with the lane name as scope. Example: `feat(lcu): add lockfile discovery`.
- **Landing commit**: the dispatcher's squash commit on `dev` is `<type>(<lane>): <summary>`
  with `Unit: <id>` in the body.
- **Granularity**: one logical responsibility per commit; documentation may be grouped.
- **Forbidden**: `--amend`, `rebase`, `reset`, `add -A`, `add .`, attribution trailers.

## Issues and labels

- **Tracker**: `docs/roadmap.md`, one row per unit with its lane, write set, documentation
  sections, dependencies, and status. Only the dispatcher edits it, on `dev`. No GitHub
  issues before the beta.

## Lanes

Paths are relative to `apps/macos/` unless they start at the repository root. The lane name
is the commit scope. Paths marked † are created in Phase 0 blocks B/C; paths marked ‡ are
created by the first unit that writes there.

| Lane | May write | Must not touch |
| --- | --- | --- |
| `core` (serial, contracts) | `MitoKit/Sources/MitoCore/**`, `MitoKit/Tests/MitoCoreTests/**` | everything else |
| `lcu` | `MitoKit/Sources/LCUKit/**` except `Contracts/`, `MitoKit/Tests/LCUKitTests/**` | other modules, `Mito/**`, `Package.swift` |
| `store` | `MitoKit/Sources/MitoStore/**`, `MitoKit/Tests/MitoStoreTests/**` | other modules, `Mito/**`, `Package.swift`; `Snapshot/` is snapshot-contract critical |
| `engine` | `MitoKit/Sources/MitoEngine/**`, `MitoKit/Tests/MitoEngineTests/**` | other modules, `Mito/**`, `Package.swift` |
| `assets` | `MitoKit/Sources/MitoAssets/**`, `MitoKit/Tests/MitoAssetsTests/**` | other modules, `Mito/**`, `Package.swift` |
| `import` | `MitoKit/Sources/MitoImport/**`†, `MitoKit/Tests/MitoImportTests/**`† | other modules, `Mito/**`, `Package.swift` |
| `shell` (serial) | `Mito/MitoApp.swift`, `Mito/App/**`†, `Mito/Scenes/**`, `Mito/Resources/**` | features, MitoKit |
| `<feature>` | `Mito/Features/<Name>/**`†, `MitoTests/Features/<Name>/**`† | other features, shell, MitoKit, pbxproj |
| `design` | `Mito/DesignSystem/**`‡, `MitoTests/DesignSystem/**`‡ | features |
| `tools-<name>` | `tools/<name>/**`‡ (root) | `apps/**` |
| `release` | `scripts/release/**`‡ (root) | `apps/**` |
| `fixtures-<scenario>` | `fixtures/lcu/<scenario>/**`‡ (root) | `fixtures/snapshot/**` |
| `arch` | `MitoKit/Tests/ArchitectureTests/**`† | everything else |
| `docs` | `docs/**` except `docs/roadmap.md`, plus the `MITO_CONTEXT.md` sections listed in the card (root) | code |
| `tests` (audit) | `MitoKit/Tests/**`, `MitoTests/**`†, `tools/*/tests/**`‡ (root) | non-test code |

Feature lanes and their folders: `connection` (Connection), `gameflow` (Gameflow),
`champ-select` (ChampSelect), `import-ui` (Import), `champions` (Champions), `analysis`
(Analysis), `profile` (Profile), `onboarding` (Onboarding), `overrides` (Overrides), `about`
(About). Each feature owns its `<Name>.xcstrings` string table inside its folder.

A unit's write set may be a narrower folder inside its lane (for example
`MitoKit/Sources/LCUKit/Discovery/**`); units in one module run in parallel when their
folders are disjoint. The agent writes its globs to `.claude/lane` in its worktree. Each unit
owns its tests; the `tests` lane is for `test-engineer` audits and never runs alongside the
unit it audits. Cross-lane edits require explicit authorization in the unit card, and the
commit message records it.

## Shared critical files

A unit touching any of these runs alone.

- `apps/macos/MitoKit/Package.swift` and `Package.resolved`
- `apps/macos/Mito.xcodeproj/project.pbxproj` and its shared scheme
- `apps/macos/Config/*.xcconfig`
- `.github/workflows/**`
- Contracts: `apps/macos/MitoKit/Sources/MitoCore/**`,
  `apps/macos/MitoKit/Sources/LCUKit/Contracts/**`†,
  `apps/macos/MitoKit/Tests/MitoTestSupport/**`†
- The `shell` lane
- The snapshot contract: `MITO_CONTEXT.md` §17, `fixtures/snapshot/**`, and its reader in
  `apps/macos/MitoKit/Sources/MitoStore/Snapshot/`. A change here is coordinated with
  `mito-data` (`docs/adr/0005-data-pipeline-and-snapshot-distribution.md`).
- `docs/roadmap.md`, `AGENTS.md`, `CLAUDE.md`, `.claude/**`
- `MITO_CONTEXT.md`, per section: a unit edits only the sections its card lists, and
  parallel units list disjoint sections. §17 and §26 are fully critical.

## Validation

Run all of these before committing (from the worktree for a unit):

```sh
swift format lint --strict -r apps/macos
swift test --package-path apps/macos/MitoKit --enable-code-coverage
xcodebuild -project apps/macos/Mito.xcodeproj -scheme Mito -destination 'platform=macOS' -derivedDataPath build/DerivedData build
xcodebuild -project apps/macos/Mito.xcodeproj -scheme Mito -destination 'platform=macOS' -derivedDataPath build/DerivedData test
```

The last command applies once the `MitoTests` target exists (Phase 0 block B).

`-derivedDataPath build/DerivedData` keeps each checkout's build cache inside it (`build/` is
git-ignored), so removing a worktree removes its cache and a launched app is unambiguous.

CI (`.github/workflows/tests.yml`) runs two jobs on pushes to `main`/`dev` and pull requests
targeting them: `mitokit` runs the MitoKit tests with warnings as errors, and `app` builds the
app and runs `MitoTests` with `xcodebuild test`, uploading the result bundle on failure.

For each Python tool (`tools/lcu-recorder`, `tools/lcu-mock`), from its folder: `uv run pytest`,
`uv run ruff check`, `uv run ruff format --check`. Not in CI yet.

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

- **Internal vault**: `MITO_CONTEXT.md` — updated in the same change as the code, only in the
  sections the unit card lists.
- **Backlog**: `docs/roadmap.md` — dispatcher only.
- **LCU endpoints**: `docs/lcu-endpoints.md` — a unit edits only its endpoint group.
- **Decision records**: `docs/adr/` — numbered (`NNNN-slug.md`), with a consequences section.
  The dispatcher reserves the number in the unit card.
- **User-facing surface**: none yet.

## Exceptions to global defaults

- **Pre-beta, local-first delivery** (`docs/adr/0006-parallel-unit-workflow.md`). Until the
  first beta lands on `main` there are no GitHub issues and no pull requests.
  - **Phase 0**: no branches and no worktrees; work is committed directly on `dev` and pushed
    to `origin/dev`.
  - **Phase 1 onward**: every unit runs on a local `unit/<id>-<slug>` branch in
    `.worktrees/<id>-<slug>`, created from `dev`, never pushed. The unit agent commits by
    responsibility on it, catches up with `git merge dev` (never rebase), and never merges.
    The dispatcher squash-merges units into `dev` one at a time, updates `docs/roadmap.md`,
    re-validates, and pushes `dev`. Deleting a squashed unit branch with `git branch -D` is
    pre-authorized; deleting `main` or `dev` never is. At most 3 units run at once, 4 once
    that has proven clean.
  - **After the beta**: work returns to branch + pull request into `dev`.
- **Documentation language.** `MITO_CONTEXT.md` stays in Spanish. Everything else is English.
- **UI language.** User-facing strings are Spanish (es-AR) first, through per-feature String
  Catalogs (`docs/adr/0007-parallel-ready-structure.md`).
- **License.** Source-available under PolyForm Shield 1.0.0, not OSI open source
  (`docs/adr/0003-license.md`).
