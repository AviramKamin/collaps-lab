#!/usr/bin/env bash
set -euo pipefail

DURATION_SEC="${1:-1200}" # default 20 minutes
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "${LOG_DIR}"

TS="$(date +%Y%m%d_%H%M%S)"
THERM="${LOG_DIR}/baseline_thermal_${TS}.log"
HB="${LOG_DIR}/baseline_heartbeat_${TS}.log"

echo "Baseline run: ${DURATION_SEC}s"
echo "thermal log: ${THERM}"
echo "heartbeat log: ${HB}"

# Start loggers in background
bash "${ROOT_DIR}/scripts/log_thermal.sh" "${THERM}" &
PID_THERM=$!
bash "${ROOT_DIR}/scripts/log_heartbeat.sh" "${HB}" &
PID_HB=$!

cleanup() {
  echo "Stopping..."
  kill "${PID_THERM}" "${PID_HB}" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep "${DURATION_SEC}"

echo "Done. Files:"
ls -lh "${THERM}" "${HB}"
