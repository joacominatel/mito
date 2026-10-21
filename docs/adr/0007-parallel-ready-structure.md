# 0007 — Parallel-ready structure

- **Status**: accepted
- **Date**: 2026-10-20
- **Extends**: [0002](0002-project-and-build-configuration.md), module list

## Context

From Phase 1 up to three units run in parallel (ADR 0006). Units only parallelize when their
write sets are disjoint, and a handful of files would otherwise be edited by almost every
unit: `Package.swift`, the pbxproj and scheme, the single `Localizable.xcstrings`,
`MitoApp.swift`, `AppModel`, the sidebar, the menu bar, and the Settings window. Shared types
(IDs, `Role`, `DraftContext`, `LCUConnection`) have the same problem: if each unit invents
the types it needs, parallel units collide on them or invent them twice.

## Decision

- **Modules.** `MitoKit` adds `MitoImport` (holds `LoadoutImporter`, `MITO_CONTEXT.md`
  §13.5; depends on MitoCore and LCUKit) to ADR 0002's five modules. `Package.swift` declares
  the full planned graph now; the only planned later edit is adding GRDB in unit P6-00.
- **Test support.** `MitoTestSupport` is a non-product target at
  `MitoKit/Tests/MitoTestSupport/` (MitoCore and LCUKit, Foundation only) holding
  `Fixtures`, `FakeLCUConnection`, and `InMemoryStatsProvider`. Every `<Module>Tests`
  depends on its module and on it. Fixtures live at the repository root in `fixtures/`, read
  through `#filePath`, shared with the Python tools.
- **Fitness functions.** `ArchitectureTests` enforces the per-module import allowlist of
  §9.2, source hygiene (no `print`, no logged secrets), and that `Localizable.xcstrings`
  stays empty.
- **App tests.** `MitoTests` is a hosted Swift Testing bundle in the `Mito` scheme, so feature
  models are tested with `xcodebuild test`.
- **String tables.** One String Catalog per feature, `Features/<Name>/<Name>.xcstrings`, used
  through `tableName:`; shell strings go in `Shell.xcstrings`. `Localizable.xcstrings` stays
  empty so no two units edit the same catalog.
- **Slots.** The shell is written once with a slot per feature: `AppModel` declares one
  model per feature (connection, gameflow, champ select, importing, champions, analysis,
  profile, onboarding, overrides) and runs each slot's `run()` in one task group; each
  feature model subscribes to its own LCU topics. `SidebarDestination` has the four §22.2
  destinations, the menu bar has the four §22.4 sections, Settings has the four §21.1–21.4
  tabs. Each slot points to a placeholder view or empty model in its feature folder.
- **Not speculative.** The slots are not an extensibility mechanism. Their membership is
  fixed by the product specification — §8 (feature folders), §21 (settings sections), §22.2
  (sidebar), §22.4 (menu bar) — so each slot has exactly one planned owner. There is no
  registry, event bus, or DI container; adding a slot later is an ordinary shell edit.
- **Contracts first.** Phase 0 builds only the shared contract types (§16.2 IDs, `Role`,
  `DraftContext`, loadout types, `MitoSettings`, a one-method `StatsProvider`, the LCU
  contracts and `LCUConnection`). Each later stage that needs new shared types starts with a
  serial contract unit (P4-00, P6-00, P7-00, P8-00) before its parallel units.
- **MITO_CONTEXT.md criticality is per section.** A unit card lists the sections it may
  edit; parallel units have disjoint sections. §17 (snapshot contract) and §26 (roadmap) are
  fully critical. Unit status lives in `docs/roadmap.md`, which only the dispatcher edits.

## Consequences

- Most units touch only their own module folder or feature folder, its tests, and its
  string table.
- `MitoCore`, `LCUKit/Contracts/`, `MitoTestSupport`, and the shell lane are shared critical;
  changing them is a serial unit.
- Placeholder views and empty models ship until their feature unit lands; they carry no
  logic and are replaced, not extended.
- A new feature outside §8, §21, §22.2, or §22.4 first updates the specification, then the
  shell, in a serial unit.
