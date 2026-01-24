#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "${LOG_DIR}"

OUT="${1:-${LOG_DIR}/heartbeat_$(date +%Y%m%d_%H%M%S).log}"

echo "start_ts=$(date +%s%N)" | tee -a "${OUT}"
echo "format: ts dt_ns (sleep=0.1s)" | tee -a "${OUT}"

while true; do
  t0="$(date +%s%N)"
  sleep 0.1
  t1="$(date +%s%N)"
  dt=$((t1 - t0))
  printf "%s dt_ns=%s\n" "${t1}" "${dt}" | tee -a "${OUT}"
done
