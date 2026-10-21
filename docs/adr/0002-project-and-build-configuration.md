# 0002 — Project and build configuration layout

- **Status**: accepted; module list extended by 0007
- **Date**: 2026-10-20

## Context

The app needs a signed, notarized `.app` with String Catalogs and, later, Sparkle, so pure
SwiftPM is not enough. Generators (Tuist, XcodeGen) add a tool and a generation step for every
contributor. A stable build and a development build should coexist on one Mac.

## Decision

- **Project**: a hand-maintained `apps/macos/Mito.xcodeproj` whose app sources are a
  file-system-synchronized group (`Mito/`). Adding or moving files never touches the pbxproj.
- **Settings**: all build settings live in `apps/macos/Config/*.xcconfig` (`Base`, `Debug`,
  `Release`, `Version`), with an optional git-ignored `Local.xcconfig` for `DEVELOPMENT_TEAM`.
  The pbxproj carries none.
- **Modules**: one local package, `apps/macos/MitoKit`, with one target and one library product
  per module (`MitoCore`, `LCUKit`, `MitoStore`, `MitoEngine`, `MitoAssets`). Dependency
  direction is unchanged from `MITO_CONTEXT.md` §9.2.
- **Configurations**: Debug and Release only. A beta is a Release build on Sparkle's `beta`
  channel, not a third configuration.
- **Debug identity**: `com.joacominatel.mito.debug`, displayed as "Mito Dev", hardened
  runtime off (ad-hoc signing plus library validation breaks Sparkle). Release keeps hardened
  runtime on.
- **Menu bar app**: `LSUIElement = YES`. The activation policy switches to `.regular` while
  the main window or Settings is open, according to the Dock setting (§21.1).
- **Entitlements**: none. Hardened runtime needs no exception for localhost networking or for
  reading another same-user process's arguments, and the sandbox is off.
- **Formatting**: the toolchain's `swift-format`, configured in `apps/macos/.swift-format`.

## Consequences

- Anything persisted per install (Application Support folder, UserDefaults) must derive its
  name from `Bundle.main.bundleIdentifier`, never a hard-coded "Mito", or the two builds share
  state.
- Adding a target or a package product is the only pbxproj edit, and it is serialized as a
  shared critical file.
- One `swift test --package-path apps/macos/MitoKit` runs every module's tests with one
  coverage report.
