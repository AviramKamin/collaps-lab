#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNS_DIR="$BASE_DIR/runs"
SCRIPTS_DIR="$BASE_DIR/scripts"

CONDITION="${CONDITION:-A}"   # A | B | C

# Timing (same structure as previous days)
BASELINE_SEC="${BASELINE_SEC:-60}"
INTERVENTION_SEC="${INTERVENTION_SEC:-10}"
R1_SEC="${R1_SEC:-60}"
R2_SEC="${R2_SEC:-60}"
POST_SEC="${POST_SEC:-60}"
N_CYCLES="${N_CYCLES:-3}"

# Workload params
RETRIES="${RETRIES:-5}"
BUDGET_MS="${BUDGET_MS:-50}"

# Targets
DISK_RETRY_TARGET_DEFAULT="$BASE_DIR/workdir/retry_test"
ALT_DISK_RETRY_TARGET="$BASE_DIR/altfs_mount/retry_test"

mkdir -p "$RUNS_DIR" "$DISK_RETRY_TARGET_DEFAULT"

case "$CONDITION" in
  A)
    IO_MODE="buffered"
    RETRY_TARGET="$DISK_RETRY_TARGET_DEFAULT"
    ;;
  B)
    IO_MODE="direct"
    RETRY_TARGET="$DISK_RETRY_TARGET_DEFAULT"
    ;;
  C)
    IO_MODE="buffered"
    RETRY_TARGET="$ALT_DISK_RETRY_TARGET"
    ;;
  *)
    echo "[ERROR] Invalid CONDITION=$CONDITION (A/B/C)"
    exit 1
    ;;
esac

# Validate Condition C environment
if [[ "$CONDITION" == "C" && ! -d "$(dirname "$ALT_DISK_RETRY_TARGET")" ]]; then
  echo "[ERROR] Condition C requires prepared alt filesystem"
  echo "Run: ./day23_prepare_alt_fs.sh"
  exit 1
fi

RUN_ID="$(date +%Y%m%d_%H%M%S)_day23_${CONDITION}"
RUN_DIR="$RUNS_DIR/$RUN_ID"
mkdir -p "$RUN_DIR"

LOG="$RUN_DIR/run.log"
HB_LOG="$RUN_DIR/heartbeat.log"
MARKS="$RUN_DIR/heartbeat_marks.log"
META="$RUN_DIR/meta.env"

echo "RUN_ID=$RUN_ID" > "$META"
echo "CONDITION=$CONDITION" >> "$META"
echo "IO_MODE=$IO_MODE" >> "$META"
echo "RETRY_TARGET=$RETRY_TARGET" >> "$META"
echo "BASELINE_SEC=$BASELINE_SEC" >> "$META"
echo "INTERVENTION_SEC=$INTERVENTION_SEC" >> "$META"
echo "R1_SEC=$R1_SEC" >> "$META"
echo "R2_SEC=$R2_SEC" >> "$META"
echo "POST_SEC=$POST_SEC" >> "$META"
echo "N_CYCLES=$N_CYCLES" >> "$META"
echo "RETRIES=$RETRIES" >> "$META"
echo "BUDGET_MS=$BUDGET_MS" >> "$META"

heartbeat() {
  local prev now dt
  prev=$(date +%s%N)
  while true; do
    sleep 0.01
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

echo "[INFO] Starting run $RUN_ID CONDITION=$CONDITION" | tee -a "$LOG"

heartbeat &
HB_PID=$!

for ((CYCLE=1; CYCLE<=N_CYCLES; CYCLE++)); do
  echo "=== CONDITION_${CONDITION}_CYCLE_${CYCLE}_START ===" | tee -a "$LOG"

  # ---- BASELINE ----
  mark "${CONDITION}_C${CYCLE}_BASELINE_START"
  sleep "$BASELINE_SEC"
  mark "${CONDITION}_C${CYCLE}_BASELINE_END"

  # ---- INTERVENTION (NO LOAD) ----
  mark "${CONDITION}_C${CYCLE}_INTERVENTION_START"
  sleep "$INTERVENTION_SEC"
  mark "${CONDITION}_C${CYCLE}_INTERVENTION_END"

  # ---- RECOVERY R1 ----
  mark "${CONDITION}_C${CYCLE}_RECOVERY_R1_START"
  sleep "$R1_SEC"
  mark "${CONDITION}_C${CYCLE}_RECOVERY_R1_END"

  # ---- RECOVERY R2 (ACTIVE WORKLOAD) ----
  mark "${CONDITION}_C${CYCLE}_RECOVERY_R2_START"

  run_with_timeout "$R2_SEC" env \
    TARGET="$RETRY_TARGET" \
    BUDGET_MS="$BUDGET_MS" \
    RETRIES="$RETRIES" \
    IO_MODE="$IO_MODE" \
    bash "$SCRIPTS_DIR/retry_storm.sh"

  mark "${CONDITION}_C${CYCLE}_RECOVERY_R2_END"

  # ---- POST BASELINE ----
  mark "${CONDITION}_C${CYCLE}_POSTBASELINE_START"
  sleep "$POST_SEC"
  mark "${CONDITION}_C${CYCLE}_POSTBASELINE_END"

  echo "=== CONDITION_${CONDITION}_CYCLE_${CYCLE}_END ===" | tee -a "$LOG"
done

echo "[INFO] Completed run: $RUN_DIR" | tee -a "$LOG"
