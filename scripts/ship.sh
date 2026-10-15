#!/usr/bin/env bash
#
# ship.sh — End-to-end local release: build → sign → notarize → GitHub Release → appcast.
#
# Run this AFTER the version-bump commit (project.yml + CHANGELOG.md) is pushed to main.
# It chains the three release scripts in sequence with no interactive prompts.
#
# Prereqs (one-time — docs/RELEASING.md §0):
#   - "Developer ID Application" cert in the login Keychain
#   - notarytool credential profile (default "simplemapper-notary")
#   - Sparkle EdDSA key (generate_keys --account SimpleMapper) + SUPublicEDKey in Info.plist
#   - Xcode 26+ selected (required for the Icon Composer .icon) and xcodegen installed
#   - gh CLI authenticated
#
# Usage:
#   scripts/ship.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Tracked files only: untracked files are ignored.
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "error: commit or discard changes to tracked files before building a release" >&2
  exit 1
fi
release_sha="$(git rev-parse HEAD)"

# Version from the committed project.yml (tree is clean, so HEAD == working copy).
VERSION="$(git show HEAD:project.yml \
  | sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9]+\.[0-9]+\.[0-9]+)"?.*/\1/p' \
  | head -1)"
[[ -n "$VERSION" ]] || { echo "error: no MARKETING_VERSION found in project.yml" >&2; exit 1; }

# Refuse before building: a re-run must never overwrite release/export/ or spend a notarization.
TAG="v$VERSION"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null \
   || git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  echo "error: tag $TAG already exists; resume with /cf-ship (Resume) or see docs/RELEASING.md §2" >&2
  exit 1
fi

ZIP="release/export/SimpleMapper-$VERSION.zip"

echo "========================================"
echo "  Shipping SimpleMapper v$VERSION"
echo "========================================"
echo

# Step 1 — Build, sign, notarize, DMG (Keychain prompt → Always Allow)
echo "==> Step 1/3: build + notarize"
scripts/build-and-notarize.sh

if [[ "$(git rev-parse HEAD)" != "$release_sha" || -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "error: source changed during build; release was not published" >&2
  exit 1
fi

# Step 2 — Tag + GitHub Release (zip + DMG uploaded)
echo "==> Step 2/3: tag + GitHub Release"
scripts/publish-release.sh --yes "$ZIP"

# Step 3 — Generate + commit + push the appcast
echo "==> Step 3/3: appcast"
scripts/publish-appcast.sh "$ZIP"

echo
echo "========================================"
echo "  SimpleMapper v$VERSION shipped!"
echo "  GitHub : https://github.com/dinhanhthi/SimpleMapper/releases/tag/v$VERSION"
echo "  Appcast: https://dinhanhthi.github.io/SimpleMapper/appcast.xml (live in ~1 min)"
echo "========================================"
