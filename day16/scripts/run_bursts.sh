#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
set -euo pipefail

# Always run relative to this script (prevents cwd bugs)
cd -- "$(dirname -- "$0")"

BURSTS="${BURSTS:-50}"
ON_SEC="${ON_SEC:-3}"      # seconds of IO
OFF_SEC="${OFF_SEC:-2}"    # silence between bursts
FIO_JOB="${FIO_JOB:-$SCRIPT_DIR/bgio.fio}"

cleanup() {
  if [[ -n "${FIO_PID:-}" ]] && kill -0 "$FIO_PID" 2>/dev/null; then
    kill "$FIO_PID" 2>/dev/null || true
    wait "$FIO_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

for i in $(seq 1 "$BURSTS"); do
  echo "Burst $i"
  fio "$FIO_JOB" &
  FIO_PID=$!
  sleep "$ON_SEC"
  kill "$FIO_PID" 2>/dev/null || true
  wait "$FIO_PID" 2>/dev/null || true
  sleep "$OFF_SEC"
done
