#!/usr/bin/env bash
#
# screenshots.sh — Capture the README screenshots into assets/screenshots/.
#
# Builds Debug, then launches the app in demo mode (SIMPLEMAPPER_DEMO=1, Debug builds only): fixed demo
# settings in a temp folder, iCloud off, and hidutil is never run. The appearance is set per app with the
# -AppleInterfaceStyle launch argument; the system appearance is never changed.
#
# The running SimpleMapper (the user's own copy) is quit for the capture and relaunched in the background at
# the end, so its mapping is active again.
#
# Needs Screen Recording permission for the terminal running it (else the PNGs show no window content).
# The menu bar menu cannot be opened without Accessibility permission: capture menu.png by hand.
#
# Usage:
#   scripts/screenshots.sh
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OUT="$REPO_ROOT/assets/screenshots"
WORK="$(mktemp -d)"
DEMO_PID=""
APP=""
USER_APP=""

running() { ps -axo command= | grep '[S]impleMapper.app/Contents/MacOS/SimpleMapper' || true; }
mapping_count() { hidutil property --get UserKeyMapping | grep -c HIDKeyboardModifierMappingSrc || true; }

wait_gone() {
  for _ in $(seq 1 50); do
    [[ -z "$(running)" ]] && return 0
    sleep 0.2
  done
  echo "error: SimpleMapper did not quit" >&2
  return 1
}

cleanup() {
  if [[ -n "$DEMO_PID" ]] && kill -0 "$DEMO_PID" 2>/dev/null; then
    kill "$DEMO_PID" 2>/dev/null || true
    wait "$DEMO_PID" 2>/dev/null || true
  fi
  # Only relaunch the copy that was running before; never start one that was quit on purpose.
  if [[ -n "$USER_APP" && -z "$(running)" ]]; then
    echo "==> Relaunching $USER_APP in the background"
    open "$USER_APP" --args --background || true
  fi
  # Demo preference files (UserDefaults suites, flushed by cfprefsd shortly after quit) and settings folders.
  sleep 2
  local plist
  for plist in "$HOME"/Library/Preferences/SimpleMapperDemo-*.plist; do
    [[ -e "$plist" ]] || continue
    defaults delete "$(basename "$plist" .plist)" 2>/dev/null || true
    rm -f "$plist"
  done
  rm -rf "${TMPDIR:-/tmp}"/SimpleMapperDemo-* "$WORK"
}
trap cleanup EXIT

# (a) Never interfere with a session run from Xcode.
if running | grep -q -- '-NSDocumentRevisionsDebugMode'; then
  echo "error: SimpleMapper is running from Xcode; stop it there first." >&2
  exit 1
fi
USER_EXEC="$(running | head -n 1 | sed -E 's/ -.*$//')"
if [[ -n "$USER_EXEC" ]]; then
  USER_APP="${USER_EXEC%/Contents/MacOS/SimpleMapper}"
  echo "==> SimpleMapper is running: $USER_APP (relaunched at the end)"
fi

# (b) Build Debug (Xcode's default DerivedData).
echo "==> Generating SimpleMapper.xcodeproj…"
xcodegen generate

echo "==> Building (Debug)…"
if ! xcodebuild -project SimpleMapper.xcodeproj -scheme SimpleMapper -configuration Debug build \
  >"$WORK/xcodebuild.txt" 2>&1; then
  grep -E 'error:' "$WORK/xcodebuild.txt" >&2 || tail -n 30 "$WORK/xcodebuild.txt" >&2
  echo "error: Debug build failed" >&2
  exit 1
fi

PRODUCTS="$(xcodebuild -project SimpleMapper.xcodeproj -scheme SimpleMapper -configuration Debug \
  -showBuildSettings 2>/dev/null \
  | awk -F' = ' '!found && /^ *BUILT_PRODUCTS_DIR = /{print $2; found=1}')"
APP="$PRODUCTS/SimpleMapper.app"
EXEC="$APP/Contents/MacOS/SimpleMapper"
[[ -x "$EXEC" ]] || { echo "error: $EXEC not found" >&2; exit 1; }

# Window finder: prints the CGWindowID of the largest (or smallest) normal SimpleMapper window.
cat > "$WORK/find-window.swift" <<'SWIFT'
import CoreGraphics
import Foundation

let smallest = CommandLine.arguments.dropFirst().first == "smallest"
let infos = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
let windows = infos.compactMap { info -> (id: Int, area: Double)? in
    guard info[kCGWindowOwnerName as String] as? String == "SimpleMapper",
          info[kCGWindowLayer as String] as? Int == 0,
          let id = info[kCGWindowNumber as String] as? Int,
          let bounds = info[kCGWindowBounds as String] as? [String: Double],
          let width = bounds["Width"], let height = bounds["Height"], width > 50, height > 50
    else { return nil }
    return (id, width * height)
}.sorted { $0.area < $1.area }
guard let window = smallest ? windows.first : windows.last else { exit(1) }
print(window.id)
SWIFT
swiftc -O -o "$WORK/find-window" "$WORK/find-window.swift"

# (c) Quit the running SimpleMapper (it clears its mapping on quit).
echo "==> Quitting SimpleMapper…"
if running | grep -q -- '-NSDocumentRevisionsDebugMode'; then
  echo "error: SimpleMapper is now running from Xcode (debug session). Stop it, then run this script again." >&2
  exit 1
fi
killall SimpleMapper 2>/dev/null || true
wait_gone
BASELINE="$(mapping_count)"
echo "==> Key mappings with no SimpleMapper running: $BASELINE"

mkdir -p "$OUT"

front_pid() { lsappinfo info -only pid "$(lsappinfo front)" | sed -nE 's/.*pid"? = ([0-9]+).*/\1/p'; }

# (d) capture <file> <largest|smallest> [launch arguments…]; extra environment comes from the caller.
# A launch whose window did not come to the front (inactive look) is retried.
capture() {
  local file="$1" which="$2"
  shift 2
  local attempt id during
  for attempt in 1 2 3; do
    SIMPLEMAPPER_DEMO=1 "$EXEC" "$@" >/dev/null 2>&1 &
    DEMO_PID=$!
    sleep 4
    id="$("$WORK/find-window" "$which")" || { echo "error: no SimpleMapper window found for $file" >&2; exit 1; }
    screencapture -o -x -l "$id" "$OUT/$file"
    during="$(mapping_count)"
    if [[ "$during" != "$BASELINE" ]]; then
      echo "error: key mappings changed during the demo ($BASELINE -> $during)" >&2
      exit 1
    fi
    local front
    front="$(front_pid)"
    kill "$DEMO_PID"
    wait "$DEMO_PID" 2>/dev/null || true
    wait_gone
    if [[ "$front" == "$DEMO_PID" ]]; then
      DEMO_PID=""
      echo "==> Captured $file (window $id)"
      return 0
    fi
    DEMO_PID=""
    echo "    $file: SimpleMapper was not frontmost (attempt $attempt), retrying…"
  done
  echo "warning: $file was captured while SimpleMapper was not frontmost; check it" >&2
}

capture main-light.png largest -AppleInterfaceStyle Light
capture main-dark.png largest -AppleInterfaceStyle Dark
# --background: no main window, so the About panel is the key window.
SIMPLEMAPPER_DEMO_ABOUT=1 capture about.png smallest -AppleInterfaceStyle Light --background
echo "==> menu.png: capture manually (open the menu, Cmd-Shift-4 then Space)"

# (e) Keep each image at most 1600 px wide and under 500 KB.
for png in "$OUT"/main-light.png "$OUT"/main-dark.png "$OUT"/about.png; do
  width="$(sips -g pixelWidth "$png" | awk '/pixelWidth/{print $2}')"
  if (( width > 1600 )); then
    sips -Z 1600 "$png" >/dev/null
  fi
  size="$(stat -f %z "$png")"
  if (( size >= 500000 )); then
    echo "error: $png is $size bytes (limit 500 KB)" >&2
    exit 1
  fi
  echo "    $(basename "$png"): ${width}px wide, $size bytes"
done

# (f) cleanup (trap) relaunches the user's app in the background and removes the demo files.
echo "==> Done: $OUT"
