#!/usr/bin/env bash
# Builds a notarized, Sparkle-signed DMG of the current commit. See scripts/release/README.md.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release/release.sh [--dry-run] [--beta] [--appcast <file>] [--download-url-prefix <url>]

  --dry-run                  Build an ad-hoc signed archive and the DMG, check everything that
                             needs no credential, and list every step that would need one.
  --beta                     Publish the item on Sparkle's beta channel.
  --appcast <file>           The currently published appcast, to add the new item to.
  --download-url-prefix <url>
                             Where the DMG will be served from. Defaults to
                             <feed directory>/<version>/.

Environment (all optional):
  MITO_SIGNING_IDENTITY      Developer ID Application identity name or SHA-1, when the login
                             Keychain holds more than one.
  MITO_NOTARY_PROFILE        notarytool keychain profile (default: mito-notary).
  MITO_SPARKLE_ACCOUNT       Keychain account of Sparkle's EdDSA key (default: ed25519).
EOF
}

DRY_RUN=0
BETA=0
EXISTING_APPCAST=""
DOWNLOAD_URL_PREFIX=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --beta) BETA=1 ;;
    --appcast)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      EXISTING_APPCAST="$2"
      shift
      ;;
    --download-url-prefix)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      DOWNLOAD_URL_PREFIX="$2"
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    *) echo "release: unknown option '$1'" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

NOTARY_PROFILE="${MITO_NOTARY_PROFILE:-mito-notary}"
SPARKLE_ACCOUNT="${MITO_SPARKLE_ACCOUNT:-ed25519}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PROJECT="$ROOT/apps/macos/Mito.xcodeproj"
VERSION_XCCONFIG="$ROOT/apps/macos/Config/Version.xcconfig"
DERIVED_DATA="$ROOT/build/DerivedData"
SPARKLE_BIN="$DERIVED_DATA/SourcePackages/artifacts/sparkle/Sparkle/bin"

STEP="startup"
OUT=""
SKIPPED=""
PROBLEMS=""

log() { printf '%s\n' "$*"; }
section() { STEP="$1"; printf '\n==> %s\n' "$1"; }
fail() { printf 'release: error: %s\n' "$*" >&2; exit 1; }
problem() { PROBLEMS="${PROBLEMS}  - $*"$'\n'; }
skip() {
  SKIPPED="${SKIPPED}  - $*"$'\n'
  log "    [dry-run] skipped: $*"
}
on_error() {
  local status=$?
  printf 'release: error: step "%s" failed (exit %s).' "$STEP" "$status" >&2
  [[ -n "$OUT" && -d "$OUT/logs" ]] && printf ' Logs are in %s.' "$OUT/logs" >&2
  printf '\n' >&2
  exit "$status"
}
trap on_error ERR

# Prints the tail of a log and fails, so a failing tool never floods the terminal.
run_logged() {
  local logfile="$1"
  shift
  if ! "$@" >"$logfile" 2>&1; then
    tail -n 25 "$logfile" >&2
    fail "'$1' failed during \"$STEP\"; full log: $logfile"
  fi
}

xcconfig_value() {
  sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*([^[:space:]]+)[[:space:]]*$/\\1/p" "$VERSION_XCCONFIG" | head -n 1
}

release_setting() {
  printf '%s\n' "$RELEASE_SETTINGS" | sed -nE "s/^[[:space:]]+$1 = (.*)$/\\1/p" | head -n 1
}

# ---------------------------------------------------------------------------------------------
section "Preflight"

VERSION="$(xcconfig_value MARKETING_VERSION)"
BUILD="$(xcconfig_value CURRENT_PROJECT_VERSION)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "MARKETING_VERSION in $VERSION_XCCONFIG is '$VERSION', expected X.Y.Z."
[[ "$BUILD" =~ ^[0-9]+$ ]] \
  || fail "CURRENT_PROJECT_VERSION in $VERSION_XCCONFIG is '$BUILD', expected an integer."
COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"
log "    version $VERSION ($BUILD), commit $COMMIT"

if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  problem "The working tree has uncommitted changes. Commit or stash them; a release is built from a commit."
fi

if [[ -n "$EXISTING_APPCAST" && ! -f "$EXISTING_APPCAST" ]]; then
  problem "--appcast $EXISTING_APPCAST does not exist."
fi

RELEASE_SETTINGS="$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme Mito \
  -configuration Release -derivedDataPath "$DERIVED_DATA" 2>/dev/null)" \
  || fail "xcodebuild -showBuildSettings failed. Is full Xcode selected (xcode-select -p)?"
FEED_URL="$(release_setting MITO_SPARKLE_FEED_URL)"
PUBLIC_ED_KEY="$(release_setting MITO_SPARKLE_PUBLIC_ED_KEY)"

feed_host="$(printf '%s' "$FEED_URL" | sed -nE 's#^https://([^/:]+).*#\1#p' | tr '[:upper:]' '[:lower:]')"
if [[ -z "$feed_host" || "$feed_host" == "invalid" || "$feed_host" == *.invalid ]]; then
  problem "MITO_SPARKLE_FEED_URL in Release.xcconfig is '${FEED_URL:-empty}', not a real HTTPS feed. Set it once roadmap Q5 picks the appcast host (ADR 0009)."
fi
if [[ "$(printf '%s' "$PUBLIC_ED_KEY" | base64 -D 2>/dev/null | wc -c | tr -d ' ')" != "32" ]]; then
  problem "MITO_SPARKLE_PUBLIC_ED_KEY in Release.xcconfig is not a base64 Ed25519 public key. Set it to the key generate_keys prints once roadmap Q5 is done (ADR 0009)."
fi
log "    feed: ${FEED_URL:-<empty>}"
log "    public EdDSA key: $([[ -n "$PUBLIC_ED_KEY" ]] && echo set || echo '<empty>')"

IDENTITY_NAME=""
IDENTITY_HASH=""
TEAM_ID=""
identities="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -nE 's/^[[:space:]]*[0-9]+\) ([0-9A-F]{40}) "(Developer ID Application: .*)"$/\1 \2/p')"
if [[ -n "${MITO_SIGNING_IDENTITY:-}" ]]; then
  identities="$(printf '%s\n' "$identities" | grep -F -- "$MITO_SIGNING_IDENTITY" || true)"
fi
identity_count="$(printf '%s' "$identities" | grep -c . || true)"
if [[ "$identity_count" == "1" ]]; then
  IDENTITY_HASH="${identities%% *}"
  IDENTITY_NAME="${identities#* }"
  TEAM_ID="$(printf '%s' "$IDENTITY_NAME" | sed -nE 's/.*\(([A-Z0-9]{10})\)$/\1/p')"
  log "    signing identity: $IDENTITY_NAME"
elif [[ "$identity_count" == "0" ]]; then
  problem "No valid 'Developer ID Application' identity${MITO_SIGNING_IDENTITY:+ matching \$MITO_SIGNING_IDENTITY} in the Keychain. Install the certificate and its private key from developer.apple.com."
else
  problem "$identity_count 'Developer ID Application' identities found. Pick one with MITO_SIGNING_IDENTITY (its name or SHA-1)."
fi

if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format json >/dev/null 2>&1; then
  log "    notary profile: $NOTARY_PROFILE"
else
  problem "The notarytool keychain profile '$NOTARY_PROFILE' is missing or rejected. Create it once with: xcrun notarytool store-credentials $NOTARY_PROFILE (or set MITO_NOTARY_PROFILE)."
fi

if security find-generic-password -s "https://sparkle-project.org" -a "$SPARKLE_ACCOUNT" >/dev/null 2>&1; then
  log "    Sparkle EdDSA key: in the Keychain (account $SPARKLE_ACCOUNT)"
else
  problem "No Sparkle EdDSA private key in the Keychain for account '$SPARKLE_ACCOUNT'. It comes from Sparkle's generate_keys (roadmap Q5)."
fi

OUT="$ROOT/build/release/$VERSION"
if [[ -e "$OUT" && ! -f "$OUT/.dry-run" ]]; then
  problem "$OUT already holds a real release. Bump the version in Version.xcconfig, or remove that folder yourself."
fi

if [[ -n "$PROBLEMS" ]]; then
  if [[ $DRY_RUN -eq 0 ]]; then
    printf 'release: preflight failed, nothing was built:\n%s' "$PROBLEMS" >&2
    exit 1
  fi
  log "    [dry-run] a real release would stop here:"
  printf '%s' "$PROBLEMS"
  [[ -e "$OUT" && ! -f "$OUT/.dry-run" ]] && fail "refusing to overwrite the real release in $OUT."
fi

rm -rf "$OUT"
mkdir -p "$OUT/logs" "$OUT/notarization"
[[ $DRY_RUN -eq 1 ]] && : >"$OUT/.dry-run"

# ---------------------------------------------------------------------------------------------
section "Archive (Release)"

ARCHIVE="$OUT/Mito.xcarchive"
archive_cmd=(xcodebuild archive -project "$PROJECT" -scheme Mito -configuration Release
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED_DATA" -archivePath "$ARCHIVE")
if [[ $DRY_RUN -eq 1 ]]; then
  skip "Developer ID signing of the archive (CODE_SIGN_STYLE=Manual, CODE_SIGN_IDENTITY='Developer ID Application: …', DEVELOPMENT_TEAM from the identity); archived ad-hoc instead"
else
  archive_cmd+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$IDENTITY_NAME" "DEVELOPMENT_TEAM=$TEAM_ID")
fi
run_logged "$OUT/logs/archive.log" "${archive_cmd[@]}"
log "    $ARCHIVE"

# ---------------------------------------------------------------------------------------------
section "Export (developer-id)"

APP="$OUT/Mito.app"
if [[ $DRY_RUN -eq 1 ]]; then
  skip "xcodebuild -exportArchive with ExportOptions.plist (method developer-id), which re-signs the app and Sparkle's helpers with the Developer ID identity and a secure timestamp"
  ditto "$ARCHIVE/Products/Applications/Mito.app" "$APP"
else
  export_options="$OUT/logs/ExportOptions.plist"
  cp "$SCRIPT_DIR/ExportOptions.plist" "$export_options"
  plutil -replace signingCertificate -string "$IDENTITY_HASH" "$export_options"
  plutil -replace teamID -string "$TEAM_ID" "$export_options"
  run_logged "$OUT/logs/export.log" xcodebuild -exportArchive -archivePath "$ARCHIVE" \
    -exportPath "$OUT/export" -exportOptionsPlist "$export_options"
  mv "$OUT/export/Mito.app" "$APP"
  rm -rf "$OUT/export"
fi

info_value() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist" 2>/dev/null || true; }
[[ "$(info_value CFBundleShortVersionString)" == "$VERSION" && "$(info_value CFBundleVersion)" == "$BUILD" ]] \
  || fail "the built app is $(info_value CFBundleShortVersionString) ($(info_value CFBundleVersion)), expected $VERSION ($BUILD)."
[[ "$(info_value SUFeedURL)" == "$FEED_URL" && "$(info_value SUPublicEDKey)" == "$PUBLIC_ED_KEY" ]] \
  || fail "the built app's SUFeedURL/SUPublicEDKey do not match the Release build settings."
log "    $APP ($(info_value CFBundleIdentifier) $VERSION, $BUILD)"

# ---------------------------------------------------------------------------------------------
section "Code signature check"

SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSIONED="$SPARKLE_FW/Versions/Current"
signed_items=(
  "$SPARKLE_VERSIONED/XPCServices/Downloader.xpc"
  "$SPARKLE_VERSIONED/XPCServices/Installer.xpc"
  "$SPARKLE_VERSIONED/Autoupdate"
  "$SPARKLE_VERSIONED/Updater.app"
  "$SPARKLE_FW"
  "$APP"
)
for item in "${signed_items[@]}"; do
  [[ -e "$item" ]] || fail "expected $item in the app bundle."
  details="$(codesign -dvv "$item" 2>&1)"
  authority="$(printf '%s\n' "$details" | sed -nE 's/^Authority=(.*)$/\1/p' | head -n 1)"
  team="$(printf '%s\n' "$details" | sed -nE 's/^TeamIdentifier=(.*)$/\1/p')"
  runtime=no
  printf '%s\n' "$details" | grep -Eq '^CodeDirectory .*flags=0x[0-9a-f]+\([^)]*runtime' && runtime=yes
  timestamp=no
  printf '%s\n' "$details" | grep -q '^Timestamp=' && timestamp=yes
  label="${item#"$APP"/}"
  [[ "$item" == "$APP" ]] && label="Mito.app"
  log "    $label: ${authority:-ad-hoc}, hardened runtime $runtime, timestamp $timestamp"
  [[ $runtime == yes ]] || fail "$label is not signed with the hardened runtime."
  if [[ $DRY_RUN -eq 0 ]]; then
    [[ "$authority" == "Developer ID Application: "* && "$team" == "$TEAM_ID" && $timestamp == yes ]] \
      || fail "$label is not signed with $IDENTITY_NAME and a secure timestamp."
  fi
done
codesign --verify --strict --deep "$APP" || fail "codesign --verify --strict --deep rejected $APP."
if codesign -d --entitlements - --xml "$APP" 2>/dev/null | grep -q 'get-task-allow'; then
  fail "Mito.app carries com.apple.security.get-task-allow, which notarization rejects."
fi
if [[ $DRY_RUN -eq 1 ]]; then
  skip "requiring 'Developer ID Application' authority, team $([[ -n "$TEAM_ID" ]] && echo "$TEAM_ID" || echo '<from identity>') and a secure timestamp on every item above"
fi

# ---------------------------------------------------------------------------------------------
# Writes <name>-submit.json and <name>-log.json, and fails unless Apple accepted the file.
notarize() {
  local file="$1" name="$2"
  local result="$OUT/notarization/$name-submit.json"
  local status_code=0
  xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait \
    --output-format json >"$result" 2>"$OUT/logs/$name-notarytool.log" || status_code=$?
  local id status
  id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
  status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
  if [[ -n "$id" ]]; then
    xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" \
      "$OUT/notarization/$name-log.json" >/dev/null 2>&1 || true
  fi
  log "    $name: submission ${id:-<none>}, status ${status:-unknown}"
  [[ $status_code -eq 0 && "$status" == "Accepted" ]] \
    || fail "notarization of $name was not accepted; see $OUT/notarization/ and $OUT/logs/$name-notarytool.log."
}

section "Notarize the app"

if [[ $DRY_RUN -eq 1 ]]; then
  skip "notarytool submit --wait --keychain-profile $NOTARY_PROFILE of Mito.app (zipped with ditto), then stapler staple, stapler validate and spctl -a -t exec -vv"
else
  app_zip="$OUT/notarization/Mito-app.zip"
  ditto -c -k --keepParent "$APP" "$app_zip"
  notarize "$app_zip" app
  rm -f "$app_zip"
  run_logged "$OUT/logs/staple-app.log" xcrun stapler staple "$APP"
  run_logged "$OUT/logs/validate-app.log" xcrun stapler validate "$APP"
  run_logged "$OUT/logs/spctl-app.log" spctl -a -t exec -vv "$APP"
  log "    stapled and accepted by Gatekeeper"
fi

# ---------------------------------------------------------------------------------------------
section "DMG"

DMG="$OUT/Mito.dmg"
dmg_root="$OUT/dmg-root"
mkdir "$dmg_root"
ditto "$APP" "$dmg_root/Mito.app"
ln -s /Applications "$dmg_root/Applications"
# APFS with lzfse is what Sparkle recommends for DMG updates.
run_logged "$OUT/logs/hdiutil-create.log" hdiutil create -volname Mito -srcfolder "$dmg_root" \
  -fs APFS -format ULFO -ov "$DMG"
rm -rf "$dmg_root"

mount_point="$(mktemp -d "${TMPDIR:-/tmp}/mito-dmg.XXXXXX")"
run_logged "$OUT/logs/hdiutil-attach.log" hdiutil attach -nobrowse -readonly -noautoopen \
  -mountpoint "$mount_point" "$DMG"
dmg_ok=1
[[ -d "$mount_point/Mito.app" ]] || dmg_ok=0
[[ "$(readlink "$mount_point/Applications" 2>/dev/null)" == "/Applications" ]] || dmg_ok=0
codesign --verify --strict --deep "$mount_point/Mito.app" 2>/dev/null || dmg_ok=0
hdiutil detach "$mount_point" -quiet || hdiutil detach "$mount_point" -force -quiet
rmdir "$mount_point" 2>/dev/null || true
[[ $dmg_ok -eq 1 ]] || fail "the DMG does not contain a valid Mito.app and an Applications symlink."
log "    $DMG ($(du -h "$DMG" | cut -f1 | tr -d ' ')): Mito.app + Applications symlink, signature intact"

if [[ $DRY_RUN -eq 1 ]]; then
  skip "codesign --sign 'Developer ID Application: …' --timestamp Mito.dmg"
  skip "notarytool submit --wait of Mito.dmg, stapler staple, stapler validate and spctl -a -t open --context context:primary-signature -vv"
else
  run_logged "$OUT/logs/codesign-dmg.log" codesign --sign "$IDENTITY_HASH" --timestamp "$DMG"
  notarize "$DMG" dmg
  run_logged "$OUT/logs/staple-dmg.log" xcrun stapler staple "$DMG"
  run_logged "$OUT/logs/validate-dmg.log" xcrun stapler validate "$DMG"
  run_logged "$OUT/logs/spctl-dmg.log" spctl -a -t open --context context:primary-signature -vv "$DMG"
  log "    signed, notarized, stapled and accepted by Gatekeeper"
fi

# ---------------------------------------------------------------------------------------------
section "Sparkle appcast"

GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"
[[ -x "$GENERATE_APPCAST" ]] || fail "Sparkle's generate_appcast is not at $GENERATE_APPCAST; the archive should have resolved the Sparkle package there."
FEED_NAME="$(basename "${FEED_URL:-appcast.xml}")"
if [[ -z "$DOWNLOAD_URL_PREFIX" ]]; then
  DOWNLOAD_URL_PREFIX="${FEED_URL%/*}/$VERSION/"
fi
[[ "$DOWNLOAD_URL_PREFIX" == */ ]] || DOWNLOAD_URL_PREFIX="$DOWNLOAD_URL_PREFIX/"
appcast_cmd=("$GENERATE_APPCAST" --account "$SPARKLE_ACCOUNT" --download-url-prefix "$DOWNLOAD_URL_PREFIX")
[[ $BETA -eq 1 ]] && appcast_cmd+=(--channel beta)
log "    generate_appcast: $GENERATE_APPCAST"

if [[ $DRY_RUN -eq 1 ]]; then
  skip "generate_appcast (EdDSA-signs Mito.dmg with the Keychain key, account $SPARKLE_ACCOUNT) into $FEED_NAME, enclosure ${DOWNLOAD_URL_PREFIX}Mito.dmg$([[ $BETA -eq 1 ]] && echo ', item marked <sparkle:channel>beta</sparkle:channel>')$([[ -n "$EXISTING_APPCAST" ]] && echo ", added to $EXISTING_APPCAST")"
else
  appcast_dir="$OUT/appcast-work"
  mkdir "$appcast_dir"
  cp -c "$DMG" "$appcast_dir/Mito.dmg" 2>/dev/null || cp "$DMG" "$appcast_dir/Mito.dmg"
  [[ -n "$EXISTING_APPCAST" ]] && cp "$EXISTING_APPCAST" "$appcast_dir/$FEED_NAME"
  run_logged "$OUT/logs/generate_appcast.log" "${appcast_cmd[@]}" "$appcast_dir"
  [[ -f "$appcast_dir/$FEED_NAME" ]] || fail "generate_appcast did not write $FEED_NAME; see $OUT/logs/generate_appcast.log."
  grep -q "sparkle:edSignature" "$appcast_dir/$FEED_NAME" \
    || fail "the appcast item has no sparkle:edSignature."
  mv "$appcast_dir/$FEED_NAME" "$OUT/$FEED_NAME"
  rm -rf "$appcast_dir"
  log "    $OUT/$FEED_NAME$([[ $BETA -eq 1 ]] && echo ' (beta channel)')"
fi

# ---------------------------------------------------------------------------------------------
section "Done"

rm -rf "$ARCHIVE"
if [[ $DRY_RUN -eq 1 ]]; then
  report="$OUT/dry-run-report.txt"
  {
    echo "Mito $VERSION ($BUILD), commit $COMMIT: dry run"
    echo
    echo "Built: $APP (ad-hoc), $DMG"
    echo
    echo "Skipped, because they need the CEO's credentials:"
    printf '%s' "$SKIPPED"
    if [[ -n "$PROBLEMS" ]]; then
      echo
      echo "A real release would stop in preflight:"
      printf '%s' "$PROBLEMS"
    fi
  } >"$report"
  log "    dry-run report: $report"
  log
  cat "$report"
else
  log "Mito $VERSION ($BUILD) is ready in $OUT. Upload, in this order:"
  log "  1. $DMG  ->  ${DOWNLOAD_URL_PREFIX}Mito.dmg"
  log "  2. $OUT/$FEED_NAME  ->  $FEED_URL"
  log "Keep $OUT/notarization/ with the release; it is not uploaded."
fi
