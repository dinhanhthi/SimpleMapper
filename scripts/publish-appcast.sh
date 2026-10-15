#!/usr/bin/env bash
#
# publish-appcast.sh — Generate + commit + push the Sparkle appcast (docs/RELEASING.md §1).
#
# Finds Sparkle's generate_appcast in DerivedData, runs it over a FRESH
# release/appcast-archives/ that holds only the new zip plus a copy of the repo-root
# appcast.xml (so older items keep their original download URLs, and the history
# survives a deleted release/ folder), copies the result back to the repo root,
# commits, and pushes to main (the Pages workflow then deploys it).
#
# The zip must already be notarized + stapled (build-and-notarize.sh) and the GitHub
# Release must exist (publish-release.sh), since the appcast points at its asset URL.
#
# Prereqs (one-time — docs/RELEASING.md §0):
#   - Sparkle EdDSA key in the login Keychain under the account "SimpleMapper"
#     (generate_keys --account SimpleMapper); click "Always Allow" on the Keychain prompt
#   - one build of the project, so DerivedData holds the Sparkle tools
#
# Usage:
#   scripts/publish-appcast.sh release/export/SimpleMapper-1.0.0.zip
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_REPO="dinhanhthi/SimpleMapper"
ARCHIVES="release/appcast-archives"

ZIP="${1:-}"
[[ -n "$ZIP" ]] || { echo "usage: scripts/publish-appcast.sh <notarized-zip>" >&2; exit 1; }
# Resolve the zip before cd so a path relative to the caller's directory still works.
[[ -f "$ZIP" ]] || { echo "error: zip not found: $ZIP" >&2; exit 1; }
ZIP="$(cd "$(dirname "$ZIP")" && pwd)/$(basename "$ZIP")"

cd "$REPO_ROOT"

# Version from the zip name (SimpleMapper-X.Y.Z.zip), else from the committed project.yml.
VERSION="$(basename "$ZIP" .zip | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)"
if [[ -z "$VERSION" ]]; then
  VERSION="$(git show HEAD:project.yml \
    | sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([0-9]+\.[0-9]+\.[0-9]+)"?.*/\1/p' \
    | head -1)"
fi
[[ -n "$VERSION" ]] || { echo "error: cannot derive the version from $ZIP or HEAD:project.yml" >&2; exit 1; }

# Commit + `git push origin main` below: make sure the commit lands on main.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" == "main" ]] \
  || { echo "error: the appcast must be committed on 'main' (you are on '$BRANCH')." >&2; exit 1; }

# generate_appcast ships inside the Sparkle SPM binary artifact.
G="$(find ~/Library/Developer/Xcode/DerivedData/SimpleMapper-*/SourcePackages/artifacts \
  -name generate_appcast -type f 2>/dev/null | head -1 || true)"
[[ -n "$G" ]] || {
  echo "error: generate_appcast not found in DerivedData." >&2
  echo "       Build the project first (scripts/dev.sh or scripts/build-and-notarize.sh)." >&2
  exit 1
}

echo "==> Generating appcast for v$VERSION"
echo "    generate_appcast: $G"

rm -rf "$ARCHIVES"
mkdir -p "$ARCHIVES"
# Zip only — no .md notes file (keeps the in-app update prompt compact; full release
# notes live on GitHub via --full-release-notes-url).
cp "$ZIP" "$ARCHIVES/"
[[ -f appcast.xml ]] && cp appcast.xml "$ARCHIVES/"
# --maximum-deltas 0: deltas would be listed in the appcast but never uploaded.
# --maximum-versions 0: keep every item (the default prunes to the last 3 versions).
"$G" --account SimpleMapper \
  --maximum-deltas 0 \
  --maximum-versions 0 \
  --download-url-prefix "https://github.com/$GH_REPO/releases/download/v$VERSION/" \
  --full-release-notes-url "https://github.com/$GH_REPO/releases" \
  "$ARCHIVES"
cp "$ARCHIVES/appcast.xml" appcast.xml

echo "==> Committing and pushing appcast.xml"
git add appcast.xml
git commit -m "chore(release): appcast v$VERSION" -- appcast.xml
git push origin main

echo
echo "Done. appcast.xml pushed — Pages deploy triggered (~1 min to go live)."
echo "  Verify: curl -fsSL https://dinhanhthi.github.io/SimpleMapper/appcast.xml | grep shortVersionString"
