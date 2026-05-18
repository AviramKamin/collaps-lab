#!/usr/bin/env bash
set -euo pipefail

TARGET=/mnt/retry_test
BUDGET_MS=50
RETRIES=5

mkdir -p "$TARGET"

while true; do
  for i in $(seq 1 10); do
    t0=$(date +%s%3N)
    dd if=/dev/zero of="$TARGET/file_$i" bs=4k count=1 conv=fsync oflag=direct 2>/dev/null || true
    t1=$(date +%s%3N)
    dt=$((t1 - t0))

    if (( dt > BUDGET_MS )); then
      for r in $(seq 1 "$RETRIES"); do
        dd if=/dev/zero of="$TARGET/file_retry_$r" bs=4k count=1 conv=fsync oflag=direct 2>/dev/null || true
      done
    fi
  done
done
