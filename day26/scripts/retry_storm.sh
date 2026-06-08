#!/usr/bin/env bash
set -euo pipefail

TARGET="${TARGET:?TARGET must be provided by the runner}"
BUDGET_MS="${BUDGET_MS:-50}"
RETRIES="${RETRIES:-5}"
IO_MODE="${IO_MODE:-buffered}"
COMPLETION_MODE="${COMPLETION_MODE:-none}"   # none | fdatasync | delay
ARTIFICIAL_DELAY_MS="${ARTIFICIAL_DELAY_MS:-0}"
RUN_TAG="${RUN_TAG:-run}"

mkdir -p "$TARGET"

echo "$(date +%s%N) retry_storm_start RUN_TAG=$RUN_TAG TARGET=$TARGET BUDGET_MS=$BUDGET_MS RETRIES=$RETRIES IO_MODE=$IO_MODE COMPLETION_MODE=$COMPLETION_MODE ARTIFICIAL_DELAY_MS=$ARTIFICIAL_DELAY_MS"

sleep_ms() {
  local ms="$1"
  sleep "$(awk -v ms="$ms" 'BEGIN { printf "%.6f", ms / 1000 }')"
}

write_once() {
  local out_file="$1"

  if [[ "$IO_MODE" != "buffered" ]]; then
    echo "[ERROR] Day26 expects IO_MODE=buffered, got IO_MODE=$IO_MODE" >&2
    exit 1
  fi

  case "$COMPLETION_MODE" in
    none)
      dd if=/dev/zero of="$out_file" bs=4k count=1 2>/dev/null || true
      ;;
    fdatasync)
      dd if=/dev/zero of="$out_file" bs=4k count=1 conv=fdatasync 2>/dev/null || true
      ;;
    delay)
      dd if=/dev/zero of="$out_file" bs=4k count=1 2>/dev/null || true
      sleep_ms "$ARTIFICIAL_DELAY_MS"
      ;;
    *)
      echo "[ERROR] Invalid COMPLETION_MODE=$COMPLETION_MODE (expected none|fdatasync|delay)" >&2
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
      echo "$(date +%s%N) dt_ms=$dt retries=$RETRIES io_mode=$IO_MODE completion_mode=$COMPLETION_MODE artificial_delay_ms=$ARTIFICIAL_DELAY_MS run_tag=$RUN_TAG"
      for r in $(seq 1 "$RETRIES"); do
        write_once "$TARGET/file_retry_$r"
      done
    fi
  done
done
