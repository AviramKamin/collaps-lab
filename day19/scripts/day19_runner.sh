#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-$HOME/project/day19}"
CONDITION="${CONDITION:-A}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(pwd)}"
RUN_TAG="${RUN_TAG:-mechanism_isolation}"

# Reference timings from Day18 condition A
BASELINE_SEC="${BASELINE_SEC:-60}"
INTERVENTION_SEC="${INTERVENTION_SEC:-10}"
R1_SEC="${R1_SEC:-60}"
R2_SEC="${R2_SEC:-60}"
POST_SEC="${POST_SEC:-60}"
N_CYCLES="${N_CYCLES:-3}"
HEARTBEAT_HZ="${HEARTBEAT_HZ:-50}"

# Core condition defaults
CPU_CORE="${CPU_CORE:-0}"
BUDGET_MS="${BUDGET_MS:-50}"
RETRIES="${RETRIES:-5}"
ENABLE_COMPETITOR=0
COMPETITOR_NICE="${COMPETITOR_NICE:-0}"

# Paths
BGIO_FILE="${BGIO_FILE:-$SCRIPTS_DIR/day19_bgio.fio}"
DISK_RETRY_TARGET_DEFAULT="${DISK_RETRY_TARGET_DEFAULT:-$BASE_DIR/workdir/retry_test}"
TMPFS_RETRY_TARGET_DEFAULT="${TMPFS_RETRY_TARGET_DEFAULT:-/dev/shm/day19_retry_test}"
RETRY_TARGET="$DISK_RETRY_TARGET_DEFAULT"

case "$CONDITION" in
  A)
    # Reference control: disk-backed retry target, reference retry intensity
    RETRIES="${RETRIES:-5}"
    ;;
  B)
    # IO-relief / tmpfs target: preserves retry logic, reduces block-layer pressure
    RETRY_TARGET="$TMPFS_RETRY_TARGET_DEFAULT"
    RETRIES="${RETRIES:-5}"
    ;;
  C)
    # Scheduler-sensitive: pin retry path and competitor to same core during R2
    ENABLE_COMPETITOR=1
    RETRIES="${RETRIES:-5}"
    ;;
  D)
    # Retry-intensity condition: caller should vary RETRIES externally, e.g. 1 / 5 / 10
    RETRIES="${RETRIES:-5}"
    ;;
  *)
    echo "[ERROR] Unknown CONDITION=$CONDITION (expected A, B, C, or D)"
    exit 1
    ;;
esac

RUN_ID="$(date +%F_%H%M%S)_day19_${CONDITION}_${RUN_TAG}"
RUN_DIR="$BASE_DIR/runs/$RUN_ID"
LOG="$RUN_DIR/run.log"
HB_LOG="$RUN_DIR/heartbeat.log"
HB_MARKS="$RUN_DIR/heartbeat_marks.log"
PROBES_LOG="$RUN_DIR/probes.log"
COMP_LOG="$RUN_DIR/competitor.log"
META_ENV="$RUN_DIR/meta.env"

mkdir -p "$RUN_DIR" "$BASE_DIR/workdir" "$DISK_RETRY_TARGET_DEFAULT" "$TMPFS_RETRY_TARGET_DEFAULT"

require_file() {
    local p="$1"
    if [[ ! -f "$p" ]]; then
        echo "[ERROR] Required file not found: $p" | tee -a "$LOG"
        exit 1
    fi
}

require_script() {
    local p="$1"
    require_file "$SCRIPTS_DIR/$p"
}

require_script "run_bursts.sh"
require_script "retry_storm.sh"
require_script "cpu_competitor.sh"
require_file "$BGIO_FILE"

mark() {
    local label="$1"
    local ts
    ts="$(date +%s%N)"
    echo "$ts ${CONDITION}_${label}" >> "$HB_MARKS"
    echo "[MARK] $ts ${CONDITION}_${label}" >> "$LOG"
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
        0|124) return 0 ;;
        *)
            echo "[ERROR] Command failed with rc=$rc :: $*" | tee -a "$LOG"
            return "$rc"
            ;;
    esac
}

cleanup() {
    echo "[INFO] Cleaning up..." | tee -a "$LOG"
    if [[ -n "${COMP_PID:-}" ]]; then
        kill "$COMP_PID" 2>/dev/null || true
        wait "$COMP_PID" 2>/dev/null || true
    fi
    if [[ -n "${HB_PID:-}" ]]; then
        kill "$HB_PID" 2>/dev/null || true
        wait "$HB_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

: > "$HB_LOG"
: > "$HB_MARKS"
: > "$PROBES_LOG"
: > "$COMP_LOG"

# Persist exact environment for reproducibility
{
    echo "RUN_ID=$RUN_ID"
    echo "CONDITION=$CONDITION"
    echo "RUN_TAG=$RUN_TAG"
    echo "BASE_DIR=$BASE_DIR"
    echo "RUN_DIR=$RUN_DIR"
    echo "SCRIPTS_DIR=$SCRIPTS_DIR"
    echo "BGIO_FILE=$BGIO_FILE"
    echo "BASELINE_SEC=$BASELINE_SEC"
    echo "INTERVENTION_SEC=$INTERVENTION_SEC"
    echo "R1_SEC=$R1_SEC"
    echo "R2_SEC=$R2_SEC"
    echo "POST_SEC=$POST_SEC"
    echo "N_CYCLES=$N_CYCLES"
    echo "HEARTBEAT_HZ=$HEARTBEAT_HZ"
    echo "BUDGET_MS=$BUDGET_MS"
    echo "RETRIES=$RETRIES"
    echo "CPU_CORE=$CPU_CORE"
    echo "ENABLE_COMPETITOR=$ENABLE_COMPETITOR"
    echo "COMPETITOR_NICE=$COMPETITOR_NICE"
    echo "RETRY_TARGET=$RETRY_TARGET"
    echo "DISK_RETRY_TARGET_DEFAULT=$DISK_RETRY_TARGET_DEFAULT"
    echo "TMPFS_RETRY_TARGET_DEFAULT=$TMPFS_RETRY_TARGET_DEFAULT"
    echo "KERNEL=$(uname -a)"
    echo "CPU_COUNT=$(nproc)"
} > "$META_ENV"

{
    echo "[INFO] Starting Day19 run: $RUN_ID"
    echo "[INFO] CONDITION=$CONDITION"
    echo "[INFO] BASE_DIR=$BASE_DIR"
    echo "[INFO] RUN_DIR=$RUN_DIR"
    echo "[INFO] BGIO_FILE=$BGIO_FILE"
    echo "[INFO] RETRY_TARGET=$RETRY_TARGET"
    echo "[INFO] CPU_CORE=$CPU_CORE ENABLE_COMPETITOR=$ENABLE_COMPETITOR"
    echo "[INFO] RETRIES=$RETRIES BUDGET_MS=$BUDGET_MS"
    echo "[INFO] N_CYCLES=$N_CYCLES BASELINE_SEC=$BASELINE_SEC INTERVENTION_SEC=$INTERVENTION_SEC R1_SEC=$R1_SEC R2_SEC=$R2_SEC POST_SEC=$POST_SEC HEARTBEAT_HZ=$HEARTBEAT_HZ"
} | tee -a "$LOG"

heartbeat_loop &
HB_PID=$!
echo "[INFO] Heartbeat PID: $HB_PID" | tee -a "$LOG"

for (( CYCLE=1; CYCLE<=N_CYCLES; CYCLE++ )); do
    mark "C${CYCLE}_BASELINE_START"
    echo "=== CONDITION_${CONDITION}_CYCLE_${CYCLE}_START ===" | tee -a "$LOG"

    echo "--- BASELINE ---" | tee -a "$LOG"
    sleep "$BASELINE_SEC"
    mark "C${CYCLE}_BASELINE_END"

    mark "C${CYCLE}_INTERVENTION_START"
    echo "--- INTERVENTION ---" | tee -a "$LOG"
    echo "$(date +%s%N) ${CONDITION}_C${CYCLE}_PROBE_B_START" >> "$PROBES_LOG"
    run_with_timeout "$INTERVENTION_SEC" env \
        FIO_JOB="$BGIO_FILE" \
        BURSTS=1 \
        ON_SEC="$INTERVENTION_SEC" \
        OFF_SEC=0 \
        bash "$SCRIPTS_DIR/run_bursts.sh"
    echo "$(date +%s%N) ${CONDITION}_C${CYCLE}_PROBE_B_END" >> "$PROBES_LOG"
    mark "C${CYCLE}_INTERVENTION_END"

    mark "C${CYCLE}_RECOVERY_R1_START"
    echo "--- RECOVERY_R1 ---" | tee -a "$LOG"
    sleep "$R1_SEC"
    mark "C${CYCLE}_RECOVERY_R1_END"

    mark "C${CYCLE}_RECOVERY_R2_START"
    echo "--- RECOVERY_R2 ---" | tee -a "$LOG"

    COMP_PID=""
    if [[ "$ENABLE_COMPETITOR" -eq 1 ]]; then
        echo "$(date +%s%N) ${CONDITION}_C${CYCLE}_COMPETITOR_START core=$CPU_CORE" | tee -a "$COMP_LOG" >> "$LOG"
        taskset -c "$CPU_CORE" nice -n "$COMPETITOR_NICE" bash "$SCRIPTS_DIR/cpu_competitor.sh" >> "$COMP_LOG" 2>&1 &
        COMP_PID=$!
        echo "[INFO] Competitor PID: $COMP_PID" | tee -a "$LOG"
    fi

    if [[ "$CONDITION" == "C" ]]; then
        run_with_timeout "$R2_SEC" env \
            TARGET="$RETRY_TARGET" \
            BUDGET_MS="$BUDGET_MS" \
            RETRIES="$RETRIES" \
            taskset -c "$CPU_CORE" bash "$SCRIPTS_DIR/retry_storm.sh"
    else
        run_with_timeout "$R2_SEC" env \
            TARGET="$RETRY_TARGET" \
            BUDGET_MS="$BUDGET_MS" \
            RETRIES="$RETRIES" \
            bash "$SCRIPTS_DIR/retry_storm.sh"
    fi

    if [[ -n "$COMP_PID" ]]; then
        kill "$COMP_PID" 2>/dev/null || true
        wait "$COMP_PID" 2>/dev/null || true
        echo "$(date +%s%N) ${CONDITION}_C${CYCLE}_COMPETITOR_END core=$CPU_CORE" | tee -a "$COMP_LOG" >> "$LOG"
        COMP_PID=""
    fi

    mark "C${CYCLE}_RECOVERY_R2_END"

    mark "C${CYCLE}_POSTBASELINE_START"
    echo "--- POST_BASELINE ---" | tee -a "$LOG"
    sleep "$POST_SEC"
    mark "C${CYCLE}_POSTBASELINE_END"

    echo "=== CONDITION_${CONDITION}_CYCLE_${CYCLE}_END ===" | tee -a "$LOG"
done

echo "[INFO] Day19 run complete: $RUN_DIR" | tee -a "$LOG"
