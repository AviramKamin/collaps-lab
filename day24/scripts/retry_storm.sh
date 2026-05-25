#!/usr/bin/env bash
set -euo pipefail

# Allow runner to override
TARGET="${TARGET:-$HOME/project/day24/workdir/retry_test}"
BUDGET_MS="${BUDGET_MS:-50}"
RETRIES="${RETRIES:-5}"
IO_MODE="${IO_MODE:-buffered}"
RUN_TAG="${RUN_TAG:-day24}"

mkdir -p "$TARGET"
echo "$(date +%s%N) retry_storm_start RUN_TAG=$RUN_TAG TARGET=$TARGET BUDGET_MS=$BUDGET_MS RETRIES=$RETRIES IO_MODE=$IO_MODE"

write_once() {
  local out_file="$1"

  if [[ "$IO_MODE" == "direct" ]]; then
    dd if=/dev/zero of="$out_file" bs=4k count=1 oflag=direct 2>/dev/null || true
  else
    dd if=/dev/zero of="$out_file" bs=4k count=1 conv=fsync 2>/dev/null || true
  fi
}

while true; do
  for i in $(seq 1 10); do
    t0=$(date +%s%3N)
    write_once "$TARGET/file_$i"
    t1=$(date +%s%3N)
    dt=$((t1 - t0))

    if (( dt > BUDGET_MS )); then
      echo "$(date +%s%N) dt_ms=$dt retries=$RETRIES io_mode=$IO_MODE run_tag=$RUN_TAG"
      for r in $(seq 1 "$RETRIES"); do
        write_once "$TARGET/file_retry_$r"
      done
    fi
  done
done
