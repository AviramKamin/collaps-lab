#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-$HOME/project/day18}"
CONDITION="${CONDITION:-A}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(pwd)}"

case "$CONDITION" in
  A)
    BASELINE_SEC=60
    INTERVENTION_SEC=10
    R1_SEC=60
    R2_SEC=60
    POST_SEC=60
    ;;
  B)
    BASELINE_SEC=60
    INTERVENTION_SEC=10
    R1_SEC=20
    R2_SEC=100
    POST_SEC=60
    ;;
  C)
    BASELINE_SEC=60
    INTERVENTION_SEC=20
    R1_SEC=60
    R2_SEC=60
    POST_SEC=60
    ;;
  *)
    echo "[ERROR] Unknown CONDITION=$CONDITION (expected A, B, or C)"
    exit 1
    ;;
esac

RUN_ID="$(date +%F_%H%M%S)_day18_${CONDITION}_transition_vs_state"
RUN_DIR="$BASE_DIR/runs/$RUN_ID"

N_CYCLES="${N_CYCLES:-3}"
HEARTBEAT_HZ="${HEARTBEAT_HZ:-50}"

ENABLE_PROC_SAMPLING=0
ENABLE_R2_TELEMETRY=0
ENABLE_DISK_WATCH=0

PROBE_ROOT="${PROBE_ROOT:-/dev/shm/day18_probes}"
BGIO_DIR="${BGIO_DIR:-/dev/shm/day18_bgio}"
BGIO_FILE="${BGIO_FILE:-$SCRIPTS_DIR/bgio.fio}"
RETRY_TARGET="${RETRY_TARGET:-$BASE_DIR/workdir/retry_test}"

mkdir -p "$RUN_DIR" "$BASE_DIR/workdir" "$PROBE_ROOT" "$BGIO_DIR" "$RETRY_TARGET"

LOG="$RUN_DIR/run.log"
HB_LOG="$RUN_DIR/heartbeat.log"
HB_MARKS="$RUN_DIR/heartbeat_marks.log"
PROBES_LOG="$RUN_DIR/probes.log"

echo "[INFO] Starting Day18 run: $RUN_ID" | tee -a "$LOG"
echo "[INFO] CONDITION=$CONDITION" | tee -a "$LOG"
echo "[INFO] SCRIPTS_DIR=$SCRIPTS_DIR" | tee -a "$LOG"
echo "[INFO] BASE_DIR=$BASE_DIR PROBE_ROOT=$PROBE_ROOT BGIO_FILE=$BGIO_FILE RETRY_TARGET=$RETRY_TARGET" | tee -a "$LOG"
echo "[INFO] Kernel: $(uname -a)" | tee -a "$LOG"
echo "[INFO] CPU_COUNT: $(nproc)" | tee -a "$LOG"
echo "[INFO] N_CYCLES=$N_CYCLES BASELINE_SEC=$BASELINE_SEC INTERVENTION_SEC=$INTERVENTION_SEC R1_SEC=$R1_SEC R2_SEC=$R2_SEC POST_SEC=$POST_SEC HEARTBEAT_HZ=$HEARTBEAT_HZ ENABLE_PROC_SAMPLING=$ENABLE_PROC_SAMPLING ENABLE_R2_TELEMETRY=$ENABLE_R2_TELEMETRY ENABLE_DISK_WATCH=$ENABLE_DISK_WATCH" | tee -a "$LOG"

require_script() {
    local p="$1"
    if [[ ! -f "$SCRIPTS_DIR/$p" ]]; then
        echo "[ERROR] Required helper script not found: $SCRIPTS_DIR/$p" | tee -a "$LOG"
        exit 1
    fi
}

require_script "run_bursts.sh"
require_script "retry_storm.sh"

if [[ ! -f "$BGIO_FILE" ]]; then
    echo "[ERROR] FIO job file not found: $BGIO_FILE" | tee -a "$LOG"
    exit 1
fi

mark() {
    local label="$1"
    local ts
    ts="$(date +%s%N)"
    echo "$ts ${CONDITION}_${label}" | tee -a "$HB_MARKS" >> "$LOG"
}

heartbeat_loop() {
    local interval
    interval=$(awk -v hz="$HEARTBEAT_HZ" 'BEGIN { printf "%.6f", 1.0/hz }')
    local prev now dt_ns
    prev="$(date +%s%N)"
    while true; do
        sleep "$interval"
        now="$(date +%s%N)"
        dt_ns=$((now - prev))
        echo "$now $dt_ns" >> "$HB_LOG"
        prev="$now"
    done
}

run_with_timeout() {
    local sec="$1"
    shift
    local rc=0

    echo "[INFO] timeout ${sec}s $*" | tee -a "$LOG"
    timeout "${sec}s" "$@" >> "$LOG" 2>&1 || rc=$?

    case "$rc" in
        0|124)
            return 0
            ;;
        *)
            echo "[ERROR] Command failed with rc=$rc :: $*" | tee -a "$LOG"
            return "$rc"
            ;;
    esac
}

cleanup() {
    echo "[INFO] Cleaning up..." | tee -a "$LOG"
    if [[ -n "${HB_PID:-}" ]]; then
        kill "$HB_PID" 2>/dev/null || true
        wait "$HB_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

: > "$HB_LOG"
: > "$HB_MARKS"
: > "$PROBES_LOG"

heartbeat_loop &
HB_PID=$!
echo "[INFO] Heartbeat PID: $HB_PID" | tee -a "$LOG"

rm -f "$BGIO_DIR/bgio.test"

for (( CYCLE=1; CYCLE<=N_CYCLES; CYCLE++ )); do
    mark "C${CYCLE}_BASELINE_START"
    echo "=== CONDITION_${CONDITION}_CYCLE_${CYCLE}_START ===" | tee -a "$LOG"

    echo "--- BASELINE ---" | tee -a "$LOG"
    sleep "$BASELINE_SEC"
    mark "C${CYCLE}_BASELINE_END"

    mark "C${CYCLE}_INTERVENTION_START"
    echo "--- INTERVENTION ---" | tee -a "$LOG"
    echo "$(date +%s%N) ${CONDITION}_C${CYCLE}_PROBE_B_START" >> "$PROBES_LOG"
    run_with_timeout "$INTERVENTION_SEC" env         FIO_JOB="$BGIO_FILE"         BURSTS=1         ON_SEC="$INTERVENTION_SEC"         OFF_SEC=0         bash "$SCRIPTS_DIR/run_bursts.sh"
    echo "$(date +%s%N) ${CONDITION}_C${CYCLE}_PROBE_B_END" >> "$PROBES_LOG"
    mark "C${CYCLE}_INTERVENTION_END"

    mark "C${CYCLE}_RECOVERY_R1_START"
    echo "--- RECOVERY_R1 ---" | tee -a "$LOG"
    sleep "$R1_SEC"
    mark "C${CYCLE}_RECOVERY_R1_END"

    mark "C${CYCLE}_RECOVERY_R2_START"
    echo "--- RECOVERY_R2 ---" | tee -a "$LOG"
    run_with_timeout "$R2_SEC" env         TARGET="$RETRY_TARGET"         bash "$SCRIPTS_DIR/retry_storm.sh"
    mark "C${CYCLE}_RECOVERY_R2_END"

    mark "C${CYCLE}_POSTBASELINE_START"
    echo "--- POST_BASELINE ---" | tee -a "$LOG"
    sleep "$POST_SEC"
    mark "C${CYCLE}_POSTBASELINE_END"

    echo "=== CONDITION_${CONDITION}_CYCLE_${CYCLE}_END ===" | tee -a "$LOG"
done

echo "[INFO] Day18 run complete: $RUN_DIR" | tee -a "$LOG"
