#!/usr/bin/env bash
#
# dev.sh — Generate the Xcode project, build Debug, and launch SimpleMapper.
#
# Uses Xcode's default DerivedData (no -derivedDataPath), so Xcode's Run reuses
# this build and the app path stays stable (Input Monitoring grant survives rebuilds).
#
# Usage:
#   scripts/dev.sh              # incremental build + launch
#   scripts/dev.sh --clean      # clean build first
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CLEAN_ACTION=""
[[ "${1:-}" == "--clean" ]] && CLEAN_ACTION="clean"

echo "==> Generating SimpleMapper.xcodeproj…"
xcodegen generate

echo "==> Stopping any running SimpleMapper…"
killall SimpleMapper 2>/dev/null || true

echo "==> Building (Debug)…"
xcodebuild \
  -project SimpleMapper.xcodeproj \
  -scheme SimpleMapper \
  -configuration Debug \
  $CLEAN_ACTION build

PRODUCTS="$(xcodebuild -project SimpleMapper.xcodeproj -scheme SimpleMapper -configuration Debug \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '!found && /^ *BUILT_PRODUCTS_DIR = /{print $2; found=1}')"
APP="$PRODUCTS/SimpleMapper.app"

echo "==> Launching $APP"
open "$APP"
