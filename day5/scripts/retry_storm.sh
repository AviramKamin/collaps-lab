#!/usr/bin/env bash
set -euo pipefail

# Allow runner to override
TARGET="${TARGET:-$HOME/project/day4/workdir/retry_test}"
BUDGET_MS="${BUDGET_MS:-50}"
RETRIES="${RETRIES:-5}"

mkdir -p "$TARGET"

while true; do
  for i in $(seq 1 10); do
    t0=$(date +%s%3N)

    # keep it simple: small writes, force flush, don't require special mounts
    dd if=/dev/zero of="$TARGET/file_$i" bs=4k count=1 conv=fsync 2>/dev/null || true

    t1=$(date +%s%3N)
    dt=$((t1 - t0))

    if (( dt > BUDGET_MS )); then
      for r in $(seq 1 "$RETRIES"); do
        dd if=/dev/zero of="$TARGET/file_retry_$r" bs=4k count=1 conv=fsync 2>/dev/null || true
      done
    fi
  done
done
