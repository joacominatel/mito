#!/usr/bin/env bash
# Builds an ad-hoc signed Release of the current checkout and installs it. See README.md.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/release/install-local.sh [--dest <dir>]

  --dest <dir>   Install into <dir>/Mito.app instead of /Applications/Mito.app.

Builds Release ad-hoc signed (no Developer ID), quits a Mito running from the destination,
and replaces the bundle. Application Support, settings, the personal database and caches
are keyed by bundle ID outside the bundle, so they are kept. The app is never launched.
EOF
}

DEST_DIR="/Applications"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dest)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      DEST_DIR="$2"
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    *) echo "install-local: unknown option '$1'" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

fail() { printf 'install-local: error: %s\n' "$*" >&2; exit 1; }
log() { printf '%s\n' "$*"; }

[[ -d "$DEST_DIR" ]] || fail "$DEST_DIR is not a directory."
DEST_DIR="$(cd "$DEST_DIR" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
DERIVED_DATA="$ROOT/build/DerivedData"
LOG_DIR="$ROOT/build/install-local"
BUILT_APP="$DERIVED_DATA/Build/Products/Release/Mito.app"
DEST_APP="$DEST_DIR/Mito.app"
STAGED_APP="$DEST_DIR/.Mito.app.installing"
EXECUTABLE="$DEST_APP/Contents/MacOS/Mito"

mkdir -p "$LOG_DIR"
log "==> Building Release (ad-hoc signed) from $(git -C "$ROOT" rev-parse --short HEAD)"
# Ad-hoc signing plus library validation keeps Sparkle.framework from loading (Debug.xcconfig);
# only a notarized Developer ID build needs the hardened runtime.
if ! xcodebuild build -project "$ROOT/apps/macos/Mito.xcodeproj" -scheme Mito \
  -configuration Release -destination 'platform=macOS' -derivedDataPath "$DERIVED_DATA" \
  ENABLE_HARDENED_RUNTIME=NO >"$LOG_DIR/build.log" 2>&1; then
  tail -n 25 "$LOG_DIR/build.log" >&2
  fail "the build failed; $DEST_APP was not touched. Full log: $LOG_DIR/build.log"
fi
codesign --verify --strict --deep "$BUILT_APP" || fail "the built app's signature does not verify."

info() { /usr/libexec/PlistBuddy -c "Print :$1" "$BUILT_APP/Contents/Info.plist"; }
BUNDLE_ID="$(info CFBundleIdentifier)"
VERSION="$(info CFBundleShortVersionString) ($(info CFBundleVersion))"
log "    $BUILT_APP: $BUNDLE_ID $VERSION"

rm -rf "$STAGED_APP"
ditto "$BUILT_APP" "$STAGED_APP"

running() { pgrep -f "^$EXECUTABLE( |$)" >/dev/null; }
if running; then
  log "==> Quitting the running Mito"
  osascript -e "tell application \"$DEST_APP\" to quit" >/dev/null || true
  for _ in $(seq 1 30); do
    running || break
    sleep 0.5
  done
  if running; then
    rm -rf "$STAGED_APP"
    fail "Mito did not quit within 15 s; quit it yourself and run this again. Nothing was replaced."
  fi
fi

log "==> Installing into $DEST_APP"
rm -rf "$DEST_APP"
mv "$STAGED_APP" "$DEST_APP"

log
log "Installed Mito $VERSION ($BUNDLE_ID) at $DEST_APP."
log "Open it with: open \"$DEST_APP\""
