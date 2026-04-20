#!/usr/bin/env bash
# Build claudetracker.app in Release configuration.
# Output: build/Build/Products/Release/claudetracker.app
set -euo pipefail

cd "$(dirname "$0")/.."

XCODEGEN="${XCODEGEN:-/opt/homebrew/opt/xcodegen/bin/xcodegen}"
if [ ! -x "$XCODEGEN" ]; then
  XCODEGEN="$(command -v xcodegen || true)"
fi
if [ -z "$XCODEGEN" ]; then
  echo "xcodegen not found — install with: brew install xcodegen" >&2
  exit 1
fi

"$XCODEGEN" generate

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild \
  -project claudetracker.xcodeproj \
  -scheme claudetracker \
  -configuration Release \
  -derivedDataPath build \
  clean build \
  | xcbeautify 2>/dev/null \
  || DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
     xcodebuild \
       -project claudetracker.xcodeproj \
       -scheme claudetracker \
       -configuration Release \
       -derivedDataPath build \
       build \
       | grep -E "(error:|warning:|BUILD |\*\*)"

APP="build/Build/Products/Release/claudetracker.app"
if [ -d "$APP" ]; then
  echo
  echo "Built: $APP"
else
  echo "Build failed — no .app produced." >&2
  exit 1
fi
