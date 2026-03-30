#!/usr/bin/env bash
set -euo pipefail

# Day14 disk watcher
# Logs raw /proc/diskstats lines for a single device with nanosecond timestamps.
# This complements aggregated telemetry by preserving request-service counters
# at finer temporal resolution.

DEV="${DEV:-mmcblk0}"
INTERVAL="${INTERVAL:-0.1}"

while true; do
  ts="$(date +%s%N)"
  line="$(awk -v dev="$DEV" '$3==dev {print; exit}' /proc/diskstats 2>/dev/null || true)"
  if [[ -n "$line" ]]; then
    printf "%s %s
" "$ts" "$line"
  else
    printf "%s device_not_found=%s
" "$ts" "$DEV"
  fi
  sleep "$INTERVAL"
done
