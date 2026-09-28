#!/bin/zsh
# Build the macOS app from the working tree and replace /Applications/TimeTracker.app,
# then relaunch it and prove the running process is the new bundle.
#
# Usage: scripts/install-mac.sh [Debug|Release]   (default: Debug)
#
# Why this exists: the Mac app is installed by hand, and a stale copy in /Applications
# once hid six months of fixes. Always install through this script, never by copying.
set -euo pipefail

CONFIG=${1:-Debug}
APP_NAME=TimeTracker
DEST=/Applications/$APP_NAME.app
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
cd "${0:A:h}/.."

echo "==> Building $APP_NAME ($CONFIG) for macOS"
BUILD_LOG=$(mktemp)
flowdeck build -w $APP_NAME.xcodeproj -s $APP_NAME -D "My Mac" -C "$CONFIG" --json > "$BUILD_LOG" 2>&1 || true
if ! grep -q '"message":"BUILD succeeded"' "$BUILD_LOG"; then
  grep -E '"type":"build_errors"' "$BUILD_LOG" | head -c 2000 || tail -20 "$BUILD_LOG"
  echo "\nBuild failed — /Applications was not touched. Full output: $BUILD_LOG" >&2
  exit 1
fi
DERIVED=$(grep -o '"derivedDataPath":"[^"]*"' "$BUILD_LOG" | head -1 | cut -d'"' -f4 | sed 's|\\/|/|g')
BUILT="$DERIVED/Build/Products/$CONFIG/$APP_NAME.app"
[[ -d "$BUILT" ]] || { echo "Built app not found at $BUILT" >&2; exit 1; }

echo "==> Replacing $DEST"
pkill -x $APP_NAME 2>/dev/null || true
for _ in {1..10}; do pgrep -x $APP_NAME >/dev/null || break; sleep 0.5; done
rm -rf "$DEST"
cp -R "$BUILT" "$DEST"
touch "$DEST"
"$LSREGISTER" -f "$DEST"

echo "==> Launching"
open "$DEST"
for _ in {1..20}; do pgrep -x $APP_NAME >/dev/null && break; sleep 0.5; done

RUNNING=$(ps -o command= -p "$(pgrep -x $APP_NAME | head -1)" 2>/dev/null || true)
if [[ "$RUNNING" == "$DEST/Contents/MacOS/$APP_NAME"* ]]; then
  echo "OK: running $DEST (built $(stat -f '%Sm' "$DEST/Contents/MacOS/$APP_NAME"))"
else
  echo "WARNING: running process is not the installed bundle: ${RUNNING:-<not running>}" >&2
  exit 1
fi
