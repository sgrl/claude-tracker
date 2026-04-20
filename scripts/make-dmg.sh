#!/usr/bin/env bash
# Bundle the Release build into a distributable DMG.
# Requires: scripts/build-release.sh has already run.
# Output: build/claudetracker.dmg
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Build/Products/Release/claudetracker.app"
DMG="build/claudetracker.dmg"
STAGE="build/dmg-stage"

if [ ! -d "$APP" ]; then
  echo "No Release build at $APP" >&2
  echo "Run ./scripts/build-release.sh first." >&2
  exit 1
fi

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "Claude Tracker" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

rm -rf "$STAGE"

echo
echo "DMG: $DMG"
ls -lh "$DMG"
