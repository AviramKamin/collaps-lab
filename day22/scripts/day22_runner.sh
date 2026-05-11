#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-$HOME/project/day22}"
CONDITION="${CONDITION:-A}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(pwd)}"
RUN_TAG="${RUN_TAG:-intermediate_observation_regime}"

# Reference timings
BASELINE_SEC="${BASELINE_SEC:-60}"
INTERVENTION_SEC="${INTERVENTION_SEC:-10}"
R1_SEC="${R1_SEC:-60}"
R2_SEC="${R2_SEC:-60}"
POST_SEC="${POST_SEC:-60}"
N_CYCLES="${N_CYCLES:-3}"
HEARTBEAT_HZ="${HEARTBEAT_HZ:-50}"

# Retry settings - active system condition is fixed across all observation regimes
BUDGET_MS="${BUDGET_MS:-50}"
RETRIES="${RETRIES:-5}"
IO_MODE="${IO_MODE:-buffered}"
ENABLE_INTERVENTION_IO="${ENABLE_INTERVENTION_IO:-0}"

# Observation settings
OBS_SAMPLE_INTERVAL_SEC="${OBS_SAMPLE_INTERVAL_SEC:-1}"
TRACE_SECONDS="${TRACE_SECONDS:-10}"
TRACE_FILE_BASENAME="${TRACE_FILE_BASENAME:-trace_r2}"
VMSTAT_LOG_BASENAME="${VMSTAT_LOG_BASENAME:-vmstat_r2.log}"
IOSTAT_LOG_BASENAME="${IOSTAT_LOG_BASENAME:-iostat_r2.log}"

# Paths
DISK_RETRY_TARGET_DEFAULT="${DISK_RETRY_TARGET_DEFAULT:-$BASE_DIR/workdir/retry_test}"
TMPFS_RETRY_TARGET_DEFAULT="${TMPFS_RETRY_TARGET_DEFAULT:-/dev/shm/day22_retry_test}"
RETRY_TARGET="$DISK_RETRY_TARGET_DEFAULT"
OBS_REGIME="heartbeat_only"

# Condition lock for Day22:
# A = heartbeat only
# B = bounded sampling during R2
# C = narrow trace window during first 10s of R2
case "$CONDITION" in
  A)
    OBS_REGIME="heartbeat_only"
    RETRY_TARGET="$DISK_RETRY_TARGET_DEFAULT"
    IO_MODE=buffered
    ENABLE_INTERVENTION_IO=0
    ;;
  B)
    OBS_REGIME="bounded_sampling"
    RETRY_TARGET="$DISK_RETRY_TARGET_DEFAULT"
    IO_MODE=buffered
    ENABLE_INTERVENTION_IO=0
    ;;
  C)
    OBS_REGIME="narrow_trace"
    RETRY_TARGET="$DISK_RETRY_TARGET_DEFAULT"
    IO_MODE=buffered
    ENABLE_INTERVENTION_IO=0
    ;;
  *)
    echo "[ERROR] Unknown CONDITION=$CONDITION (expected A, B, or C)"
    exit 1
    ;;
esac

RUN_ID="$(date +%F_%H%M%S)_day22_${CONDITION}_${RUN_TAG}"
RUN_DIR="$BASE_DIR/runs/$RUN_ID"
LOG="$RUN_DIR/run.log"
HB_LOG="$RUN_DIR/heartbeat.log"
HB_MARKS="$RUN_DIR/heartbeat_marks.log"
PROBES_LOG="$RUN_DIR/probes.log"
META_ENV="$RUN_DIR/meta.env"

mkdir -p "$RUN_DIR" "$BASE_DIR/workdir" "$DISK_RETRY_TARGET_DEFAULT" "$TMPFS_RETRY_TARGET_DEFAULT"

require_file() {
    local p="$1"
    if [[ ! -f "$p" ]]; then
        echo "[ERROR] Required file not found: $p" | tee -a "$LOG"
        exit 1
    fi
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[ERROR] Required command not found: $cmd" | tee -a "$LOG"
        exit 1
    fi
}

require_script() {
    local p="$1"
    require_file "$SCRIPTS_DIR/$p"
}

require_script "retry_storm.sh"

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

start_sampling() {
    : > "$VMSTAT_LOG"
    : > "$IOSTAT_LOG"
    echo "$(date +%s%N) sampling_start interval=${OBS_SAMPLE_INTERVAL_SEC}s" >> "$PROBES_LOG"

    require_cmd vmstat
    require_cmd iostat

    vmstat "$OBS_SAMPLE_INTERVAL_SEC" > "$VMSTAT_LOG" 2>&1 &
    VMSTAT_PID=$!

    iostat -x "$OBS_SAMPLE_INTERVAL_SEC" > "$IOSTAT_LOG" 2>&1 &
    IOSTAT_PID=$!

    echo "[INFO] Started bounded sampling: vmstat_pid=$VMSTAT_PID iostat_pid=$IOSTAT_PID" | tee -a "$LOG"
}

stop_sampling() {
    echo "$(date +%s%N) sampling_stop" >> "$PROBES_LOG"
    if [[ -n "${VMSTAT_PID:-}" ]]; then
        kill "$VMSTAT_PID" 2>/dev/null || true
        wait "$VMSTAT_PID" 2>/dev/null || true
        unset VMSTAT_PID
    fi
    if [[ -n "${IOSTAT_PID:-}" ]]; then
        kill "$IOSTAT_PID" 2>/dev/null || true
        wait "$IOSTAT_PID" 2>/dev/null || true
        unset IOSTAT_PID
    fi
    echo "[INFO] Stopped bounded sampling" | tee -a "$LOG"
}

start_trace_window() {
    echo "$(date +%s%N) trace_start duration=${TRACE_SECONDS}s file=$TRACE_DAT" >> "$PROBES_LOG"

    require_cmd trace-cmd

    trace-cmd record \
        -e sched:sched_switch \
        -e sched:sched_wakeup \
        -o "$TRACE_DAT" \
        sleep "$TRACE_SECONDS" >> "$LOG" 2>&1 &
    TRACE_PID=$!

    echo "[INFO] Started narrow trace window: trace_pid=$TRACE_PID duration=${TRACE_SECONDS}s output=$TRACE_DAT" | tee -a "$LOG"
}

stop_trace_window() {
    echo "$(date +%s%N) trace_stop" >> "$PROBES_LOG"
    if [[ -n "${TRACE_PID:-}" ]]; then
        wait "$TRACE_PID" 2>/dev/null || true
        unset TRACE_PID
    fi
    echo "[INFO] Narrow trace window completed" | tee -a "$LOG"
}

cleanup() {
    echo "[INFO] Cleaning up..." | tee -a "$LOG"
    if [[ -n "${VMSTAT_PID:-}" ]]; then
        kill "$VMSTAT_PID" 2>/dev/null || true
        wait "$VMSTAT_PID" 2>/dev/null || true
    fi
    if [[ -n "${IOSTAT_PID:-}" ]]; then
        kill "$IOSTAT_PID" 2>/dev/null || true
        wait "$IOSTAT_PID" 2>/dev/null || true
    fi
    if [[ -n "${TRACE_PID:-}" ]]; then
        wait "$TRACE_PID" 2>/dev/null || true
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

{
    echo "RUN_ID=$RUN_ID"
    echo "CONDITION=$CONDITION"
    echo "RUN_TAG=$RUN_TAG"
    echo "BASE_DIR=$BASE_DIR"
    echo "RUN_DIR=$RUN_DIR"
    echo "SCRIPTS_DIR=$SCRIPTS_DIR"
    echo "BASELINE_SEC=$BASELINE_SEC"
    echo "INTERVENTION_SEC=$INTERVENTION_SEC"
    echo "R1_SEC=$R1_SEC"
    echo "R2_SEC=$R2_SEC"
    echo "POST_SEC=$POST_SEC"
    echo "N_CYCLES=$N_CYCLES"
    echo "HEARTBEAT_HZ=$HEARTBEAT_HZ"
    echo "BUDGET_MS=$BUDGET_MS"
    echo "RETRIES=$RETRIES"
    echo "IO_MODE=$IO_MODE"
    echo "ENABLE_INTERVENTION_IO=$ENABLE_INTERVENTION_IO"
    echo "OBS_REGIME=$OBS_REGIME"
    echo "OBS_SAMPLE_INTERVAL_SEC=$OBS_SAMPLE_INTERVAL_SEC"
    echo "TRACE_SECONDS=$TRACE_SECONDS"
    echo "RETRY_TARGET=$RETRY_TARGET"
    echo "DISK_RETRY_TARGET_DEFAULT=$DISK_RETRY_TARGET_DEFAULT"
    echo "TMPFS_RETRY_TARGET_DEFAULT=$TMPFS_RETRY_TARGET_DEFAULT"
    echo "VMSTAT_LOG_BASENAME=$VMSTAT_LOG_BASENAME"
    echo "IOSTAT_LOG_BASENAME=$IOSTAT_LOG_BASENAME"
    echo "TRACE_FILE_BASENAME=$TRACE_FILE_BASENAME"
    echo "KERNEL=$(uname -a)"
    echo "CPU_COUNT=$(nproc)"
} > "$META_ENV"

{
    echo "[INFO] Starting Day22 run: $RUN_ID"
    echo "[INFO] CONDITION=$CONDITION"
    echo "[INFO] OBS_REGIME=$OBS_REGIME"
    echo "[INFO] BASE_DIR=$BASE_DIR"
    echo "[INFO] RUN_DIR=$RUN_DIR"
    echo "[INFO] RETRY_TARGET=$RETRY_TARGET"
    echo "[INFO] RETRIES=$RETRIES BUDGET_MS=$BUDGET_MS"
    echo "[INFO] IO_MODE=$IO_MODE"
    echo "[INFO] ENABLE_INTERVENTION_IO=$ENABLE_INTERVENTION_IO"
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
    echo "[INFO] Intervention IO disabled for Day22 CONDITION=$CONDITION" | tee -a "$LOG"
    sleep "$INTERVENTION_SEC"
    mark "C${CYCLE}_INTERVENTION_END"

    mark "C${CYCLE}_RECOVERY_R1_START"
    echo "--- RECOVERY_R1 ---" | tee -a "$LOG"
    sleep "$R1_SEC"
    mark "C${CYCLE}_RECOVERY_R1_END"

    mark "C${CYCLE}_RECOVERY_R2_START"
    echo "--- RECOVERY_R2 ---" | tee -a "$LOG"

    VMSTAT_LOG="$RUN_DIR/vmstat_c${CYCLE}_r2.log"
    IOSTAT_LOG="$RUN_DIR/iostat_c${CYCLE}_r2.log"
    TRACE_DAT="$RUN_DIR/trace_c${CYCLE}_r2.dat"

    case "$OBS_REGIME" in
      heartbeat_only)
        ;;
      bounded_sampling)
        start_sampling
        ;;
      narrow_trace)
        start_trace_window
        ;;
      *)
        echo "[ERROR] Unknown OBS_REGIME=$OBS_REGIME" | tee -a "$LOG"
        exit 1
        ;;
    esac

    run_with_timeout "$R2_SEC" env \
        TARGET="$RETRY_TARGET" \
        BUDGET_MS="$BUDGET_MS" \
        RETRIES="$RETRIES" \
        IO_MODE="$IO_MODE" \
        bash "$SCRIPTS_DIR/retry_storm.sh"

    case "$OBS_REGIME" in
      heartbeat_only)
        ;;
      bounded_sampling)
        stop_sampling
        ;;
      narrow_trace)
        stop_trace_window
        ;;
    esac

    mark "C${CYCLE}_RECOVERY_R2_END"

    mark "C${CYCLE}_POSTBASELINE_START"
    echo "--- POST_BASELINE ---" | tee -a "$LOG"
    sleep "$POST_SEC"
    mark "C${CYCLE}_POSTBASELINE_END"

    echo "=== CONDITION_${CONDITION}_CYCLE_${CYCLE}_END ===" | tee -a "$LOG"
done

echo "[INFO] Day22 run complete: $RUN_DIR" | tee -a "$LOG"
