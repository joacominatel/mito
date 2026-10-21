# Release pipeline

`release.sh` turns the current commit into a notarized DMG and a Sparkle appcast item, in
`build/release/<version>/`. Decisions and the reasoning live in
[ADR 0010](../../docs/adr/0010-release-pipeline.md).

```sh
scripts/release/release.sh --dry-run          # no credentials needed
scripts/release/release.sh                    # default channel
scripts/release/release.sh --beta             # Sparkle beta channel
scripts/release/release.sh --appcast ~/Downloads/appcast.xml   # add to the published feed
```

Run it from any checkout of the repository; paths resolve from the git root. The version comes
from `apps/macos/Config/Version.xcconfig`: bump it there, commit, then release.

## Steps

1. **Preflight**: clean tree, version, a real Release Sparkle config (feed not `.invalid`,
   public key set), one Developer ID Application identity, a working notarytool profile, and
   Sparkle's private key in the Keychain. A real run reports every failure at once and stops
   before writing anything.
2. **Archive** for Release with Developer ID manual signing and the hardened runtime, then
   **export** with `ExportOptions.plist` (`developer-id`). Every Sparkle helper is checked for
   the Developer ID authority, the team, the hardened runtime, and a secure timestamp.
3. **Notarize the app**, staple it, and check it with `stapler validate` and `spctl`.
4. **DMG** with `hdiutil` (APFS, lzfse, an Applications symlink), checked by mounting it;
   then sign, notarize, staple and check the DMG.
5. **Appcast** with Sparkle's `generate_appcast`, which EdDSA-signs the DMG. `--beta` puts the
   item on the `beta` channel.

## Output

`build/release/<version>/` (git-ignored): `Mito.app`, `Mito.dmg`, `appcast.xml`,
`notarization/` (Apple's submission results and logs), and `logs/`. The script ends by
printing what to upload where; it never uploads.

## One-time setup (CEO)

- A **Developer ID Application** certificate with its private key in the login Keychain.
  If the Keychain holds several, set `MITO_SIGNING_IDENTITY` to the one to use.
- `xcrun notarytool store-credentials mito-notary` (an App Store Connect API key or an
  app-specific password). Another profile name works with `MITO_NOTARY_PROFILE`.
- Roadmap Q5: Sparkle's `generate_keys` (the private key stays in the Keychain, account
  `ed25519` or `MITO_SPARKLE_ACCOUNT`), and the public key and HTTPS feed URL set in
  `apps/macos/Config/Release.xcconfig`.

No secret is passed on the command line, written to a file, or printed.

## Dry run

`--dry-run` needs no credential. It builds an ad-hoc signed Release archive, the app, and the
DMG, runs every check that needs no secret, and writes `dry-run-report.txt` listing each step
it skipped and each preflight failure a real run would stop on.

## Checks

```sh
uvx --from shellcheck-py shellcheck scripts/release/release.sh
```
