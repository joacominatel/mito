# 0009 — Sparkle updates, off until configured

- **Status**: accepted
- **Date**: 2026-10-21
- **Extends**: [0002](0002-project-and-build-configuration.md), [0008](0008-grdb.md)

## Context

Mito ships outside the Mac App Store (§24), so it needs its own updater. `MITO_CONTEXT.md` §24
already settles Sparkle with an EdDSA-signed appcast, and a beta that is a Release published on
Sparkle's `beta` channel rather than a separate build configuration. Two inputs belong to the
CEO and are still open (roadmap Q5): the EdDSA key pair and where the appcast is hosted. The
integration has to land before them without ever checking a feed that does not exist.

## Decision

- **Version.** Sparkle 2.10.0 (the latest stable release on 2026-10-21, published 2026-09-13;
  it requires macOS 12, below our macOS 15 target), pinned with `exactVersion` in the
  pbxproj's `XCRemoteSwiftPackageReference` for `https://github.com/sparkle-project/Sparkle`.
  It is a dependency of the app target only, never MitoKit. An upgrade is a deliberate change
  to the pbxproj and the workspace `Package.resolved`, checked against Sparkle's release notes.
- **Configuration.** `apps/macos/Config/Info.plist` is merged into the generated Info.plist
  (`INFOPLIST_FILE` in `Base.xcconfig`, cleared for the test bundle) and carries
  `SUFeedURL = $(MITO_SPARKLE_FEED_URL)`, `SUPublicEDKey = $(MITO_SPARKLE_PUBLIC_ED_KEY)` and
  `SUEnableAutomaticChecks = YES`. Both build settings are empty in `Base.xcconfig`, so Debug
  has no feed. `Release.xcconfig` sets the feed to `https://updates.mito.invalid/appcast.xml`
  and leaves the key empty.
- **Off until configured.** `UpdaterConfiguration.isComplete(info:)` accepts a build only when
  it is not Debug, `SUFeedURL` is HTTPS on a host that is not `invalid` or `*.invalid`, and
  `SUPublicEDKey` decodes from base64 to 32 bytes (an Ed25519 public key). Otherwise, and
  always under XCTest, `UpdaterModel` never creates `SPUStandardUpdaterController`: no checks,
  no network, no Sparkle misconfiguration alert. "Buscar actualizaciones…" is disabled and
  Settings → General says updates are not configured yet, without an error.
- **Settings.** `general.automaticallyCheckForUpdates` (default on) and
  `general.receiveBetaUpdates` (default off) live in `MitoSettings`, like every other setting.
  `MitoSettings` is the source of truth: at start, and on every toggle, `UpdaterModel` writes
  the value to `SPUUpdater.automaticallyChecksForUpdates` when it differs. Sparkle keeps its
  own copy in user defaults; we accept the duplicate so all settings live in one file, and
  `SUEnableAutomaticChecks` suppresses Sparkle's second-launch permission prompt, since the
  toggle already asks.
- **Channels.** Every appcast item without `<sparkle:channel>` is the default channel. A beta
  is published as an item with `<sparkle:channel>beta</sparkle:channel>`.
  `allowedChannels(for:)` returns `["beta"]` when `receiveBetaUpdates` is on and `[]` otherwise;
  the default channel is always included. Changing the toggle resets Sparkle's update cycle.
- **Behavior.** Sparkle's defaults otherwise: scheduled checks once a day, no automatic
  download or install (`SUAutomaticallyUpdate` unset). As a menu-bar (`LSUIElement`) app Mito
  declares `supportsGentleScheduledUpdateReminders`, so a scheduled update alert opens behind
  the active app instead of stealing focus. Nothing is automated during a match.
- **Keys.** The EdDSA private key lives only in the CEO's login Keychain, where Sparkle's
  `generate_keys` stores it. It never enters the repository, CI, or an xcconfig. The public key
  is not secret and is committed in `Release.xcconfig`.
- **Entitlements.** None. With the App Sandbox off, Sparkle needs no XPC services or
  entitlements, and Release keeps the hardened runtime (ADR 0002).

## Turning it on (roadmap Q5)

Q5 must provide:

1. The public EdDSA key printed by `generate_keys` (base64, 44 characters), set as
   `MITO_SPARKLE_PUBLIC_ED_KEY` in `Release.xcconfig`.
2. The HTTPS URL where `appcast.xml` will be served, set as `MITO_SPARKLE_FEED_URL` in
   `Release.xcconfig` (written `https:/$()/host/path` so `//` is not an xcconfig comment).

Nothing else changes in code. The release pipeline (P10-02) signs each archive with
`sign_update` from the same Keychain and publishes the appcast.

## Consequences

- A Release built today is inert, and the first configured Release is the first that can
  update. Builds before it never find updates on their own.
- Losing the private key means no existing install can accept a new update; it is backed up
  with the CEO's Keychain, never copied into the repo.
- The update preference exists in both `settings.json` and Sparkle's user defaults; Mito's
  copy wins at every start.
- Follow-up: Sparkle can still show a scheduled alert while League is in the foreground
  (behind it, without focus). Deferring scheduled prompts while a game is running
  (`standardUserDriverShouldHandleShowingScheduledUpdate(_:andInImmediateFocus:)`, or a power
  assertion during the match) is not built here.
