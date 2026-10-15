#!/usr/bin/env bash
#
# measure.sh — Compare SimpleMapper's RAM/CPU with Karabiner-Elements'.
#
# Samples the running SimpleMapper and every running Karabiner process with `top`
# (MEM = memory footprint; works for root-owned Karabiner processes without sudo),
# averages MEM and %CPU per process and prints a table, the totals per app and a
# final PASS/FAIL line.
#
# PASS = SimpleMapper total MEM < Karabiner total MEM
#        AND SimpleMapper total avg %CPU <= Karabiner total avg %CPU
#
# Usage:
#   scripts/measure.sh            # 10 one-second samples
#   scripts/measure.sh 30         # 30 one-second samples
#
# Exit: 0 PASS, 1 FAIL, 2 SimpleMapper or Karabiner-Elements not running.
#
set -euo pipefail

SAMPLES="${1:-10}"
if ! [[ "$SAMPLES" =~ ^[0-9]+$ ]] || (( SAMPLES < 1 )); then
  echo "usage: $0 [seconds]   (positive integer, default 10)" >&2
  exit 64
fi

SM_PIDS="$(pgrep -x SimpleMapper || true)"
if [[ -z "$SM_PIDS" ]]; then
  echo "SimpleMapper is not running." >&2
  echo "Start it, e.g.: open /Applications/SimpleMapper.app --args --background" >&2
  exit 2
fi

KE_PIDS=""
for pid in $(pgrep -f -i "org\.pqrs|Karabiner-[A-Za-z]*\.app|karabiner_" || true); do
  [[ "$pid" == "$$" || "$pid" == "$PPID" ]] && continue
  comm="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
  [[ -z "$comm" ]] && continue                      # already exited
  case "$(basename "$comm")" in grep|pgrep|measure.sh) continue ;; esac
  KE_PIDS+="$pid "
done
if [[ -z "$KE_PIDS" ]]; then
  echo "Karabiner-Elements is not running: nothing to compare." >&2
  echo "Start it with: open -a Karabiner-Elements (and enable its background services)" >&2
  exit 2
fi

# pid -> group / name maps for awk (top truncates COMMAND to 16 characters).
INFO=""
for pid in $SM_PIDS; do
  INFO+="$pid SimpleMapper $(basename "$(ps -o comm= -p "$pid")")"$'\n'
done
for pid in $KE_PIDS; do
  INFO+="$pid Karabiner-Elements $(basename "$(ps -o comm= -p "$pid")" | tr ' ' '_')"$'\n'
done

PID_ARGS=()
for pid in $SM_PIDS $KE_PIDS; do PID_ARGS+=(-pid "$pid"); done

echo "==> Sampling $SAMPLES s (top, 1 s interval, first sample ignored)…"
# One extra sample: the first one has no CPU delta and is ignored.
TOP_OUT="$(top -l "$((SAMPLES + 1))" -s 1 -stats pid,command,mem,cpu "${PID_ARGS[@]}")"

INFO="$INFO" awk '
  function mb(v,   n, u) {
    gsub(/[+-]$/, "", v)
    u = substr(v, length(v), 1)
    n = substr(v, 1, length(v) - 1) + 0
    if (u == "K") return n / 1024
    if (u == "M") return n
    if (u == "G") return n * 1024
    if (u == "B") return n / 1048576
    return v / 1048576                      # plain bytes
  }
  BEGIN {
    nlines = split(ENVIRON["INFO"], lines, "\n")
    for (i = 1; i <= nlines; i++) {
      if (split(lines[i], f, " ") < 3) continue
      group[f[1]] = f[2]; name[f[1]] = f[3]; order[++np] = f[1]
    }
  }
  /^PID[ \t]+COMMAND/ { sample++; next }
  sample >= 2 && ($1 in group) {
    mem[$1] += mb($(NF - 1)); cpu[$1] += $NF; cnt[$1]++
  }
  END {
    printf "\n%-50s %-20s %12s %8s\n", "PROCESS", "APP", "AVG MEM MB", "AVG %CPU"
    for (i = 1; i <= np; i++) {
      p = order[i]
      if (!cnt[p]) { printf "%-50s %-20s %12s %8s\n", name[p] " (" p ")", group[p], "n/a", "n/a"; continue }
      m = mem[p] / cnt[p]; c = cpu[p] / cnt[p]
      tm[group[p]] += m; tc[group[p]] += c
      printf "%-50s %-20s %12.1f %8.2f\n", name[p] " (" p ")", group[p], m, c
    }
    printf "\n%-71s %12s %8s\n", "TOTAL", "MEM MB", "%CPU"
    printf "%-71s %12.1f %8.2f\n", "SimpleMapper", tm["SimpleMapper"], tc["SimpleMapper"]
    printf "%-71s %12.1f %8.2f\n", "Karabiner-Elements", tm["Karabiner-Elements"], tc["Karabiner-Elements"]
    pass = (tm["SimpleMapper"] < tm["Karabiner-Elements"]) && (tc["SimpleMapper"] <= tc["Karabiner-Elements"])
    print ""
    print (pass ? "PASS" : "FAIL")
    exit (pass ? 0 : 1)
  }
' <<<"$TOP_OUT"
