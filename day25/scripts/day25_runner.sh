#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
RUNS_DIR="${RUNS_DIR:-$BASE_DIR/runs}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$BASE_DIR/scripts}"

CONDITION="${CONDITION:-A}"   # A | B | C

# Timing
BASELINE_SEC="${BASELINE_SEC:-60}"
INTERVENTION_SEC="${INTERVENTION_SEC:-10}"
R1_SEC="${R1_SEC:-60}"
R2_SEC="${R2_SEC:-60}"
POST_SEC="${POST_SEC:-60}"
N_CYCLES="${N_CYCLES:-3}"

# Workload params
RETRIES="${RETRIES:-5}"
BUDGET_MS="${BUDGET_MS:-50}"

# Observation
HEARTBEAT_SLEEP_SEC="${HEARTBEAT_SLEEP_SEC:-0.01}"

# Day25 keeps the target and IO mode constant.
IO_MODE="buffered"
RETRY_TARGET="${RETRY_TARGET:-$BASE_DIR/workdir/retry_test}"

mkdir -p "$RUNS_DIR" "$RETRY_TARGET"

case "$CONDITION" in
  A)
    SYNC_MODE="none"
    ;;
  B)
    SYNC_MODE="fsync"
    ;;
  C)
    SYNC_MODE="fdatasync"
    ;;
  *)
    echo "[ERROR] Invalid CONDITION=$CONDITION (A/B/C)"
    exit 1
    ;;
esac

RUN_ID="$(date +%Y%m%d_%H%M%S)_day25_${CONDITION}"
RUN_DIR="$RUNS_DIR/$RUN_ID"
mkdir -p "$RUN_DIR"

LOG="$RUN_DIR/run.log"
HB_LOG="$RUN_DIR/heartbeat.log"
MARKS="$RUN_DIR/heartbeat_marks.log"
META="$RUN_DIR/meta.env"

write_meta() {
  {
    echo "RUN_ID=$RUN_ID"
    echo "CONDITION=$CONDITION"
    echo "SYNC_MODE=$SYNC_MODE"
    echo "IO_MODE=$IO_MODE"
    echo "RETRY_TARGET=$RETRY_TARGET"
    echo "BASELINE_SEC=$BASELINE_SEC"
    echo "INTERVENTION_SEC=$INTERVENTION_SEC"
    echo "R1_SEC=$R1_SEC"
    echo "R2_SEC=$R2_SEC"
    echo "POST_SEC=$POST_SEC"
    echo "N_CYCLES=$N_CYCLES"
    echo "RETRIES=$RETRIES"
    echo "BUDGET_MS=$BUDGET_MS"
    echo "HEARTBEAT_SLEEP_SEC=$HEARTBEAT_SLEEP_SEC"
    echo "SCRIPT_RUNNER=$0"
    echo "SCRIPT_RETRY_STORM=$SCRIPTS_DIR/retry_storm.sh"
  } > "$META"
}

heartbeat() {
  local prev now dt
  prev=$(date +%s%N)
  while true; do
    sleep "$HEARTBEAT_SLEEP_SEC"
    now=$(date +%s%N)
    dt=$((now - prev))
    echo "$now $dt" >> "$HB_LOG"
    prev=$now
  done
}

mark() {
  echo "$(date +%s%N) $1" >> "$MARKS"
}

run_with_timeout() {
  local sec="$1"
  shift
  timeout "${sec}s" "$@" >> "$LOG" 2>&1 || true
}

cleanup() {
  kill "${HB_PID:-}" 2>/dev/null || true
  wait "${HB_PID:-}" 2>/dev/null || true
}
trap cleanup EXIT

write_meta
echo "[INFO] Starting run $RUN_ID CONDITION=$CONDITION SYNC_MODE=$SYNC_MODE" | tee -a "$LOG"

# Preflight
touch "$RETRY_TARGET/.write_test" && rm -f "$RETRY_TARGET/.write_test"

heartbeat &
HB_PID=$!

for ((CYCLE=1; CYCLE<=N_CYCLES; CYCLE++)); do
  echo "=== CONDITION_${CONDITION}_CYCLE_${CYCLE}_START ===" | tee -a "$LOG"

  mark "${CONDITION}_C${CYCLE}_BASELINE_START"
  sleep "$BASELINE_SEC"
  mark "${CONDITION}_C${CYCLE}_BASELINE_END"

  mark "${CONDITION}_C${CYCLE}_INTERVENTION_START"
  sleep "$INTERVENTION_SEC"
  mark "${CONDITION}_C${CYCLE}_INTERVENTION_END"

  mark "${CONDITION}_C${CYCLE}_RECOVERY_R1_START"
  sleep "$R1_SEC"
  mark "${CONDITION}_C${CYCLE}_RECOVERY_R1_END"

  mark "${CONDITION}_C${CYCLE}_RECOVERY_R2_START"
  run_with_timeout "$R2_SEC" env \
    TARGET="$RETRY_TARGET" \
    BUDGET_MS="$BUDGET_MS" \
    RETRIES="$RETRIES" \
    IO_MODE="$IO_MODE" \
    SYNC_MODE="$SYNC_MODE" \
    RUN_TAG="${RUN_ID}_C${CYCLE}" \
    bash "$SCRIPTS_DIR/retry_storm.sh"
  mark "${CONDITION}_C${CYCLE}_RECOVERY_R2_END"

  mark "${CONDITION}_C${CYCLE}_POSTBASELINE_START"
  sleep "$POST_SEC"
  mark "${CONDITION}_C${CYCLE}_POSTBASELINE_END"

  echo "=== CONDITION_${CONDITION}_CYCLE_${CYCLE}_END ===" | tee -a "$LOG"
done

echo "[INFO] Completed run: $RUN_DIR" | tee -a "$LOG"
