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

# Observation params
HEARTBEAT_SLEEP_SEC="${HEARTBEAT_SLEEP_SEC:-0.01}"
SAMPLE_MS="${SAMPLE_MS:-50}"

# Day24 keeps the active path constant
IO_MODE="buffered"
RETRY_TARGET="${RETRY_TARGET:-$BASE_DIR/workdir/retry_test}"

mkdir -p "$RUNS_DIR" "$RETRY_TARGET"

RUN_ID="$(date +%Y%m%d_%H%M%S)_day24_${CONDITION}"
RUN_DIR="$RUNS_DIR/$RUN_ID"
mkdir -p "$RUN_DIR"

LOG="$RUN_DIR/run.log"
HB_LOG="$RUN_DIR/heartbeat.log"
MARKS="$RUN_DIR/heartbeat_marks.log"
META="$RUN_DIR/meta.env"
WRITEBACK_LOG="$RUN_DIR/writeback.log"
VMSTAT_LOG="$RUN_DIR/vmstat_writeback.log"

# Original kernel values captured before applying condition
ORIG_DIRTY_BACKGROUND_RATIO="$(sysctl -n vm.dirty_background_ratio)"
ORIG_DIRTY_RATIO="$(sysctl -n vm.dirty_ratio)"
ORIG_DIRTY_WRITEBACK_CENTISECS="$(sysctl -n vm.dirty_writeback_centisecs)"
ORIG_DIRTY_EXPIRE_CENTISECS="$(sysctl -n vm.dirty_expire_centisecs)"

case "$CONDITION" in
  A)
    COND_DIRTY_BACKGROUND_RATIO="$ORIG_DIRTY_BACKGROUND_RATIO"
    COND_DIRTY_RATIO="$ORIG_DIRTY_RATIO"
    COND_DIRTY_WRITEBACK_CENTISECS="$ORIG_DIRTY_WRITEBACK_CENTISECS"
    COND_DIRTY_EXPIRE_CENTISECS="$ORIG_DIRTY_EXPIRE_CENTISECS"
    ;;
  B)
    COND_DIRTY_BACKGROUND_RATIO="${COND_DIRTY_BACKGROUND_RATIO:-2}"
    COND_DIRTY_RATIO="${COND_DIRTY_RATIO:-5}"
    COND_DIRTY_WRITEBACK_CENTISECS="${COND_DIRTY_WRITEBACK_CENTISECS:-100}"
    COND_DIRTY_EXPIRE_CENTISECS="${COND_DIRTY_EXPIRE_CENTISECS:-500}"
    ;;
  C)
    COND_DIRTY_BACKGROUND_RATIO="${COND_DIRTY_BACKGROUND_RATIO:-20}"
    COND_DIRTY_RATIO="${COND_DIRTY_RATIO:-40}"
    COND_DIRTY_WRITEBACK_CENTISECS="${COND_DIRTY_WRITEBACK_CENTISECS:-500}"
    COND_DIRTY_EXPIRE_CENTISECS="${COND_DIRTY_EXPIRE_CENTISECS:-3000}"
    ;;
  *)
    echo "[ERROR] Invalid CONDITION=$CONDITION (A/B/C)"
    exit 1
    ;;
esac

write_meta() {
  {
    echo "RUN_ID=$RUN_ID"
    echo "CONDITION=$CONDITION"
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
    echo "SAMPLE_MS=$SAMPLE_MS"
    echo "HEARTBEAT_SLEEP_SEC=$HEARTBEAT_SLEEP_SEC"
    echo "ORIG_DIRTY_BACKGROUND_RATIO=$ORIG_DIRTY_BACKGROUND_RATIO"
    echo "ORIG_DIRTY_RATIO=$ORIG_DIRTY_RATIO"
    echo "ORIG_DIRTY_WRITEBACK_CENTISECS=$ORIG_DIRTY_WRITEBACK_CENTISECS"
    echo "ORIG_DIRTY_EXPIRE_CENTISECS=$ORIG_DIRTY_EXPIRE_CENTISECS"
    echo "COND_DIRTY_BACKGROUND_RATIO=$COND_DIRTY_BACKGROUND_RATIO"
    echo "COND_DIRTY_RATIO=$COND_DIRTY_RATIO"
    echo "COND_DIRTY_WRITEBACK_CENTISECS=$COND_DIRTY_WRITEBACK_CENTISECS"
    echo "COND_DIRTY_EXPIRE_CENTISECS=$COND_DIRTY_EXPIRE_CENTISECS"
  } > "$META"
}

apply_writeback_policy() {
  echo "[INFO] Applying writeback policy for CONDITION=$CONDITION" | tee -a "$LOG"
  sudo sysctl -w "vm.dirty_background_ratio=$COND_DIRTY_BACKGROUND_RATIO" >> "$LOG" 2>&1
  sudo sysctl -w "vm.dirty_ratio=$COND_DIRTY_RATIO" >> "$LOG" 2>&1
  sudo sysctl -w "vm.dirty_writeback_centisecs=$COND_DIRTY_WRITEBACK_CENTISECS" >> "$LOG" 2>&1
  sudo sysctl -w "vm.dirty_expire_centisecs=$COND_DIRTY_EXPIRE_CENTISECS" >> "$LOG" 2>&1

  {
    echo "ACTIVE_DIRTY_BACKGROUND_RATIO=$(sysctl -n vm.dirty_background_ratio)"
    echo "ACTIVE_DIRTY_RATIO=$(sysctl -n vm.dirty_ratio)"
    echo "ACTIVE_DIRTY_WRITEBACK_CENTISECS=$(sysctl -n vm.dirty_writeback_centisecs)"
    echo "ACTIVE_DIRTY_EXPIRE_CENTISECS=$(sysctl -n vm.dirty_expire_centisecs)"
  } >> "$META"
}

restore_writeback_policy() {
  sudo sysctl -w "vm.dirty_background_ratio=$ORIG_DIRTY_BACKGROUND_RATIO" >/dev/null 2>&1 || true
  sudo sysctl -w "vm.dirty_ratio=$ORIG_DIRTY_RATIO" >/dev/null 2>&1 || true
  sudo sysctl -w "vm.dirty_writeback_centisecs=$ORIG_DIRTY_WRITEBACK_CENTISECS" >/dev/null 2>&1 || true
  sudo sysctl -w "vm.dirty_expire_centisecs=$ORIG_DIRTY_EXPIRE_CENTISECS" >/dev/null 2>&1 || true
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

sample_writeback_state() {
  while true; do
    local ts dirty_kb writeback_kb nr_dirty nr_writeback
    ts=$(date +%s%N)

    dirty_kb="$(awk '/^Dirty:/ {print $2}' /proc/meminfo)"
    writeback_kb="$(awk '/^Writeback:/ {print $2}' /proc/meminfo)"
    echo "$ts Dirty_kB=$dirty_kb Writeback_kB=$writeback_kb" >> "$WRITEBACK_LOG"

    nr_dirty="$(awk '$1=="nr_dirty" {print $2}' /proc/vmstat)"
    nr_writeback="$(awk '$1=="nr_writeback" {print $2}' /proc/vmstat)"
    echo "$ts nr_dirty=$nr_dirty nr_writeback=$nr_writeback" >> "$VMSTAT_LOG"

    sleep "$(awk "BEGIN { printf \"%.6f\", $SAMPLE_MS / 1000 }")"
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

  kill "${WB_PID:-}" 2>/dev/null || true
  wait "${WB_PID:-}" 2>/dev/null || true

  restore_writeback_policy
}
trap cleanup EXIT

write_meta
echo "[INFO] Starting run $RUN_ID CONDITION=$CONDITION" | tee -a "$LOG"

# Preflight
touch "$RETRY_TARGET/.write_test" && rm -f "$RETRY_TARGET/.write_test"
apply_writeback_policy

heartbeat &
HB_PID=$!

sample_writeback_state &
WB_PID=$!

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
    RUN_TAG="${RUN_ID}_C${CYCLE}" \
    bash "$SCRIPTS_DIR/retry_storm.sh"
  mark "${CONDITION}_C${CYCLE}_RECOVERY_R2_END"

  mark "${CONDITION}_C${CYCLE}_POSTBASELINE_START"
  sleep "$POST_SEC"
  mark "${CONDITION}_C${CYCLE}_POSTBASELINE_END"

  echo "=== CONDITION_${CONDITION}_CYCLE_${CYCLE}_END ===" | tee -a "$LOG"
done

echo "[INFO] Completed run: $RUN_DIR" | tee -a "$LOG"
