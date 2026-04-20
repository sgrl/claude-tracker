#!/usr/bin/env bash
# Create a versioned GitHub release:
#   1. Ensures the repo is clean and on main
#   2. Builds the Release .app (via build-release.sh)
#   3. Packages it as claudetracker-<version>.dmg
#   4. Tags v<version> and pushes
#   5. Creates a GitHub release with the DMG attached
#   6. Prints the DMG's sha256 for updating the Homebrew cask
#
# Requires: gh (authenticated), xcodegen, /Applications/Xcode.app
#
# Usage: bash scripts/release.sh <version>
# Example: bash scripts/release.sh 0.1.0
set -euo pipefail

cd "$(dirname "$0")/.."

if [ $# -lt 1 ]; then
  echo "usage: bash scripts/release.sh <version>" >&2
  exit 1
fi
VERSION="$1"
TAG="v${VERSION}"

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI not found — brew install gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "gh is not authenticated — run: gh auth login" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "working tree has uncommitted changes — aborting" >&2
  git status --short >&2
  exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  echo "not on main (current: $BRANCH) — aborting" >&2
  exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "tag $TAG already exists — bump the version" >&2
  exit 1
fi

# Bake version into project.yml
sed -i '' "s/^    MARKETING_VERSION: .*/    MARKETING_VERSION: \"${VERSION}\"/" project.yml

# Build + package
bash scripts/build-release.sh
bash scripts/make-dmg.sh

ARTIFACT="build/claudetracker-${VERSION}.dmg"
mv build/claudetracker.dmg "$ARTIFACT"
SHA=$(shasum -a 256 "$ARTIFACT" | awk '{print $1}')

# Commit version bump + tag + push
if [ -n "$(git status --porcelain project.yml)" ]; then
  git add project.yml
  git commit -m "Release ${TAG}"
fi
git tag -a "$TAG" -m "${TAG}"
git push origin main
git push origin "$TAG"

# Create the release with the DMG attached
gh release create "$TAG" \
  --title "$TAG" \
  --notes "Release ${VERSION}." \
  "$ARTIFACT"

URL="https://github.com/sgrl/claude-tracker/releases/download/${TAG}/claudetracker-${VERSION}.dmg"

echo
echo "======================================"
echo "Released $TAG"
echo "DMG:     $ARTIFACT"
echo "URL:     $URL"
echo "sha256:  $SHA"
echo
echo "Update homebrew-claude-tracker/Casks/claude-tracker.rb with:"
echo "  version \"${VERSION}\""
echo "  sha256 \"${SHA}\""
echo "======================================"
