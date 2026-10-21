# 0010 — Release pipeline

- **Status**: accepted
- **Date**: 2026-10-21
- **Extends**: [0002](0002-project-and-build-configuration.md), [0009](0009-sparkle.md)

## Context

Mito ships outside the Mac App Store as a Developer ID signed, notarized DMG that Sparkle can
update (`MITO_CONTEXT.md` §24). Every input that makes a release trustworthy is a secret the
CEO holds: the Developer ID certificate, the notary service credentials, and Sparkle's EdDSA
private key. None of them may enter the repository, a log, or the build output. The DMG and the
appcast are hosted under `app/` in the data bucket (ADR 0011); the pipeline does not upload.

## Decision

- **One script.** `scripts/release/release.sh` (bash 3.2-compatible, `set -euo pipefail`)
  plus `scripts/release/ExportOptions.plist`. It uses only Xcode's tools (`xcodebuild`,
  `codesign`, `notarytool`, `stapler`, `spctl`), `hdiutil`, and the Sparkle tools that ship
  in the resolved package (`build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/`).
  No third-party DMG tool: `hdiutil` covers an APFS image with an Applications symlink.
- **Steps.** Preflight; `xcodebuild archive` for Release, signed manually with the Developer
  ID identity and its team passed as build settings on the command line (the xcconfigs keep
  ad-hoc automatic signing for everyday builds); `-exportArchive` with method `developer-id`;
  a signature check of the app, `Sparkle.framework`, `Autoupdate`, `Updater.app`, and both
  XPC services (Developer ID authority, the team, hardened runtime, secure timestamp, no
  `get-task-allow`); notarization of the zipped app, stapling, `stapler validate` and `spctl`;
  the DMG (`hdiutil create -fs APFS -format ULFO`, lzfse as Sparkle recommends), verified by
  mounting it; the DMG signed, notarized, stapled and checked; then the appcast.
- **Sparkle helpers.** Sparkle's documentation says that Xcode's archive and export re-sign
  its XPC services and helpers, keep the hardened runtime, and strip `get-task-allow`, so no
  manual `codesign` of nested code is done. The script verifies the result instead. The XPC
  services stay embedded: removing them is optional for a non-sandboxed app and would mean
  re-signing the framework by hand.
- **Appcast.** Sparkle's publishing guide recommends `generate_appcast`, which reads the DMG,
  infers the version and minimum macOS, signs the archive with the Keychain key, and updates
  an existing appcast. It replaces a separate `sign_update` call. The current appcast can be
  passed with `--appcast` so the new item is added to it. `--beta` passes `--channel beta`,
  producing `<sparkle:channel>beta</sparkle:channel>`. Each version's DMG is served from
  `https://<feed host>/app/releases/<version>/Mito.dmg` (ADR 0011) unless
  `--download-url-prefix` says otherwise.
- **Output.** `build/release/<version>/` (inside the git-ignored `/build/`): `Mito.app`,
  `Mito.dmg`, the appcast named after the feed URL, `notarization/` with Apple's results and
  logs, and `logs/`. The script prints what to upload and where, DMG first.
- **Refusals.** A dirty tree, a placeholder Sparkle config, a missing or ambiguous identity,
  a profile notarytool cannot use, or a missing EdDSA key stops a real run in preflight,
  listing every failure, before anything is written. A version folder that holds a real
  release is never overwritten.

## Where each secret lives

| Secret | Where | How the script uses it |
| --- | --- | --- |
| Developer ID Application certificate and key | CEO's login Keychain | Found by name with `security find-identity`; `codesign` and Xcode use it in place. `MITO_SIGNING_IDENTITY` picks one when there are several. |
| Notary service credentials | Keychain profile from `xcrun notarytool store-credentials` (default `mito-notary`, `MITO_NOTARY_PROFILE`) | Only ever `--keychain-profile <name>`; checked with `notarytool history`, output discarded. |
| Sparkle EdDSA private key | Keychain item from `generate_keys` (account `ed25519`, `MITO_SPARKLE_ACCOUNT`) | Checked with `security find-generic-password` without `-w`; read only by `generate_appcast`. |

No secret is passed as an argument, held in a variable, written to a file, or printed.

## Dry-run contract

`--dry-run` needs no credential and must pass on any Mac with Xcode. It runs preflight and
reports its failures without stopping, archives Release ad-hoc signed, copies the app out of
the archive, runs the signature check for the hardened runtime, builds and mounts the DMG, and
locates `generate_appcast`. Every step that needs a secret — Developer ID signing, export,
notarization, stapling, DMG signing, the EdDSA signature and appcast — is skipped and listed
in `dry-run-report.txt`. A dry-run folder is marked and may be replaced by a later run; a
real release folder never is.

## Still missing

- **P10-07**: a Developer ID, then the feed and public key recorded in ADR 0009 set in
  `Release.xcconfig`. Until then a real run stops in preflight; local builds are installed with
  `scripts/release/install-local.sh`.
- **Upload**: there is no upload step. `app/appcast.xml` and `app/releases/<version>/Mito.dmg`
  go to R2 by hand, following the printed list.
- **Release notes**: none are attached to the appcast item yet.
- The configured public key is not compared with the Keychain's private key. Builds before
  the first configured release are inert, so the first real check is updating from the first
  configured release to the second.

## Consequences

- A release is reproducible from a commit and a version bump, on the CEO's Mac only.
- The first real run is the first test of the signing, export and notarization steps; the
  dry run cannot exercise them.
- Upgrading Sparkle means rechecking its signing guidance and the helper list the script
  verifies.
