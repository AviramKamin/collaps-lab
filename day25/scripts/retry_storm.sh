#!/usr/bin/env bash
set -euo pipefail

TARGET="${TARGET:-$HOME/project/day25/workdir/retry_test}"
BUDGET_MS="${BUDGET_MS:-50}"
RETRIES="${RETRIES:-5}"
IO_MODE="${IO_MODE:-buffered}"
SYNC_MODE="${SYNC_MODE:-none}"   # none | fsync | fdatasync
RUN_TAG="${RUN_TAG:-day25}"

mkdir -p "$TARGET"

echo "$(date +%s%N) retry_storm_start RUN_TAG=$RUN_TAG TARGET=$TARGET BUDGET_MS=$BUDGET_MS RETRIES=$RETRIES IO_MODE=$IO_MODE SYNC_MODE=$SYNC_MODE"

write_once() {
  local out_file="$1"

  if [[ "$IO_MODE" != "buffered" ]]; then
    echo "[ERROR] Day25 expects IO_MODE=buffered, got IO_MODE=$IO_MODE" >&2
    exit 1
  fi

  case "$SYNC_MODE" in
    none)
      dd if=/dev/zero of="$out_file" bs=4k count=1 2>/dev/null || true
      ;;
    fsync)
      dd if=/dev/zero of="$out_file" bs=4k count=1 conv=fsync 2>/dev/null || true
      ;;
    fdatasync)
      dd if=/dev/zero of="$out_file" bs=4k count=1 conv=fdatasync 2>/dev/null || true
      ;;
    *)
      echo "[ERROR] Invalid SYNC_MODE=$SYNC_MODE (expected none|fsync|fdatasync)" >&2
      exit 1
      ;;
  esac
}

while true; do
  for i in $(seq 1 10); do
    t0=$(date +%s%3N)
    write_once "$TARGET/file_$i"
    t1=$(date +%s%3N)
    dt=$((t1 - t0))

    if (( dt > BUDGET_MS )); then
      echo "$(date +%s%N) dt_ms=$dt retries=$RETRIES io_mode=$IO_MODE sync_mode=$SYNC_MODE run_tag=$RUN_TAG"
      for r in $(seq 1 "$RETRIES"); do
        write_once "$TARGET/file_retry_$r"
      done
    fi
  done
done
