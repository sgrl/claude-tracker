#!/usr/bin/env bash
# Generate Resources/AppIcon.icns from a SwiftUI-rendered gauge icon.
# Output: Resources/AppIcon.icns (ready for xcodegen to bundle).
set -euo pipefail

cd "$(dirname "$0")/.."

ICONSET="Resources/AppIcon.iconset"
ICNS="Resources/AppIcon.icns"

mkdir -p "$ICONSET"

swift scripts/make-icon.swift "$ICONSET"

iconutil -c icns "$ICONSET" -o "$ICNS"

echo
echo "Wrote $ICNS"
