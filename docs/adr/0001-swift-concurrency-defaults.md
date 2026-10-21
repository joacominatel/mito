# 0001 — Swift concurrency defaults

- **Status**: accepted
- **Date**: 2026-10-20

## Context

Swift 6.2 introduced approachable concurrency: main-actor-by-default isolation for executable
targets and caller-actor execution for nonisolated async functions
(`NonisolatedNonsendingByDefault`). Apple recommends main-actor-by-default for apps; libraries
should not be pinned to the main thread. Mito's logic lives in library modules (`LCUClient`
actor, a pure engine) and its app target is UI and wiring.

## Decision

- **App target**: Swift 6 language mode, `SWIFT_APPROACHABLE_CONCURRENCY = YES`,
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `MemberImportVisibility`. Work leaves the main
  actor explicitly with `@concurrent` or an actor.
- **MitoKit modules**: tools-version 6.2, default isolation left nonisolated, upcoming
  features `NonisolatedNonsendingByDefault`, `InferIsolatedConformances`,
  `MemberImportVisibility`, `InternalImportsByDefault`, and `strictMemorySafety()`.
- **Warnings as errors**: enforced in CI flags only, never in manifests or xcconfig, so a newer
  compiler's new warnings do not break local builds.

## Consequences

- Behavior matches the Swift 7 defaults, so the eventual language-mode bump is cheap.
- `InternalImportsByDefault` means a module must write `public import` to expose a dependency's
  types; GRDB stays internal to `MitoStore`.
- Unsafe pointer code (reading process arguments via `sysctl`) must be marked `unsafe` and is
  reviewable by grep.
- Tools-version 6.2 keeps Xcode 26 contributors able to build.
