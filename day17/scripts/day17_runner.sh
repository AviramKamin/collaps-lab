#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-$HOME/project/day17}"
RUN_ID="$(date +%F_%H%M%S)_day17_transition_timing"
RUN_DIR="$BASE_DIR/runs/$RUN_ID"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(pwd)}"

N_CYCLES="${N_CYCLES:-3}"
BASELINE_SEC="${BASELINE_SEC:-60}"
INTERVENTION_SEC="${INTERVENTION_SEC:-10}"
R1_SEC="${R1_SEC:-60}"
R2_SEC="${R2_SEC:-60}"
POST_SEC="${POST_SEC:-60}"

HEARTBEAT_HZ="${HEARTBEAT_HZ:-50}"

# Day17 defaults: narrower, higher-resolution timing; broad coarse sampling disabled by default.
ENABLE_PROC_SAMPLING="${ENABLE_PROC_SAMPLING:-0}"
SAMPLE_HZ="${SAMPLE_HZ:-10}"
ENABLE_R2_TELEMETRY="${ENABLE_R2_TELEMETRY:-0}"
ENABLE_DISK_WATCH="${ENABLE_DISK_WATCH:-0}"

PROBE_ROOT="${PROBE_ROOT:-/dev/shm/day17_probes}"
BGIO_DIR="${BGIO_DIR:-/dev/shm/day17_bgio}"
BGIO_FILE="${BGIO_FILE:-$SCRIPTS_DIR/bgio.fio}"
RETRY_TARGET="${RETRY_TARGET:-$BASE_DIR/workdir/retry_test}"

mkdir -p "$RUN_DIR" "$RUN_DIR/proc_samples" "$BASE_DIR/workdir" "$PROBE_ROOT" "$BGIO_DIR" "$RETRY_TARGET"

LOG="$RUN_DIR/run.log"
HB_LOG="$RUN_DIR/heartbeat.log"
HB_MARKS="$RUN_DIR/heartbeat_marks.log"
PROBES_LOG="$RUN_DIR/probes.log"

echo "[INFO] Starting Day17 run: $RUN_ID" | tee -a "$LOG"
echo "[INFO] SCRIPTS_DIR=$SCRIPTS_DIR" | tee -a "$LOG"
echo "[INFO] BASE_DIR=$BASE_DIR PROBE_ROOT=$PROBE_ROOT BGIO_FILE=$BGIO_FILE RETRY_TARGET=$RETRY_TARGET" | tee -a "$LOG"
echo "[INFO] N_CYCLES=$N_CYCLES BASELINE_SEC=$BASELINE_SEC INTERVENTION_SEC=$INTERVENTION_SEC R1_SEC=$R1_SEC R2_SEC=$R2_SEC POST_SEC=$POST_SEC HEARTBEAT_HZ=$HEARTBEAT_HZ ENABLE_PROC_SAMPLING=$ENABLE_PROC_SAMPLING SAMPLE_HZ=$SAMPLE_HZ ENABLE_R2_TELEMETRY=$ENABLE_R2_TELEMETRY ENABLE_DISK_WATCH=$ENABLE_DISK_WATCH" | tee -a "$LOG"

require_script() {
    local p="$1"
    if [[ ! -f "$SCRIPTS_DIR/$p" ]]; then
        echo "[ERROR] Required helper script not found: $SCRIPTS_DIR/$p" | tee -a "$LOG"
        exit 1
    fi
}

require_script "run_bursts.sh"
require_script "retry_storm.sh"

if [[ "$ENABLE_R2_TELEMETRY" == "1" ]]; then
    require_script "r2_telemetry_fine.sh"
fi

if [[ "$ENABLE_DISK_WATCH" == "1" ]]; then
    require_script "disk_watch.sh"
fi

if [[ ! -f "$BGIO_FILE" ]]; then
    echo "[ERROR] FIO job file not found: $BGIO_FILE" | tee -a "$LOG"
    exit 1
fi

mark() {
    local label="$1"
    local ts
    ts="$(date +%s%N)"
    echo "$ts $label" | tee -a "$HB_MARKS" >> "$LOG"
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

sample_proc() {
    local interval
    interval=$(awk -v hz="$SAMPLE_HZ" 'BEGIN { printf "%.6f", 1.0/hz }')
    echo "[INFO] Sampling started (${SAMPLE_HZ}Hz, interval=${interval}s)" >> "$LOG"

    while true; do
        local ts
        ts=$(date +%s.%N)

        echo "TS=$ts" >> "$RUN_DIR/proc_samples/proc_stat.log"
        cat /proc/stat >> "$RUN_DIR/proc_samples/proc_stat.log"

        echo "TS=$ts" >> "$RUN_DIR/proc_samples/proc_interrupts.log"
        cat /proc/interrupts >> "$RUN_DIR/proc_samples/proc_interrupts.log"

        echo "TS=$ts" >> "$RUN_DIR/proc_samples/proc_softirqs.log"
        cat /proc/softirqs >> "$RUN_DIR/proc_samples/proc_softirqs.log"

        sleep "$interval"
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
    for pidvar in SAMPLE_PID HB_PID; do
        if [[ -n "${!pidvar:-}" ]]; then
            kill "${!pidvar}" 2>/dev/null || true
            wait "${!pidvar}" 2>/dev/null || true
        fi
    done
}
trap cleanup EXIT

: > "$HB_LOG"
: > "$HB_MARKS"
: > "$PROBES_LOG"

heartbeat_loop &
HB_PID=$!
echo "[INFO] Heartbeat PID: $HB_PID" | tee -a "$LOG"

if [[ "$ENABLE_PROC_SAMPLING" == "1" ]]; then
    sample_proc &
    SAMPLE_PID=$!
    echo "[INFO] Sampler PID: $SAMPLE_PID" | tee -a "$LOG"
fi

# Start each run from a clean tmpfs payload file.
rm -f "$BGIO_DIR/bgio.test"

for (( CYCLE=1; CYCLE<=N_CYCLES; CYCLE++ )); do
    mark "C${CYCLE}_BASELINE_START"
    echo "=== CYCLE_${CYCLE}_START ===" | tee -a "$LOG"

    echo "--- BASELINE ---" | tee -a "$LOG"
    sleep "$BASELINE_SEC"
    mark "C${CYCLE}_BASELINE_END"

    mark "C${CYCLE}_INTERVENTION_START"
    echo "--- INTERVENTION ---" | tee -a "$LOG"
    echo "$(date +%s%N) PROBE_B_START" >> "$PROBES_LOG"
    run_with_timeout "$INTERVENTION_SEC" env \
        FIO_JOB="$BGIO_FILE" \
        BURSTS="${BURSTS:-1}" \
        ON_SEC="$INTERVENTION_SEC" \
        OFF_SEC=0 \
        bash "$SCRIPTS_DIR/run_bursts.sh"
    echo "$(date +%s%N) PROBE_B_END" >> "$PROBES_LOG"
    mark "C${CYCLE}_INTERVENTION_END"

    mark "C${CYCLE}_RECOVERY_R1_START"
    echo "--- RECOVERY_R1 ---" | tee -a "$LOG"
    sleep "$R1_SEC"
    mark "C${CYCLE}_RECOVERY_R1_END"

    mark "C${CYCLE}_RECOVERY_R2_START"
    echo "--- RECOVERY_R2 ---" | tee -a "$LOG"
    run_with_timeout "$R2_SEC" env \
        TARGET="$RETRY_TARGET" \
        bash "$SCRIPTS_DIR/retry_storm.sh"

    if [[ "$ENABLE_R2_TELEMETRY" == "1" ]]; then
        run_with_timeout "$R2_SEC" bash "$SCRIPTS_DIR/r2_telemetry_fine.sh"
    fi

    mark "C${CYCLE}_RECOVERY_R2_END"

    mark "C${CYCLE}_POSTBASELINE_START"
    echo "--- POST_BASELINE ---" | tee -a "$LOG"
    sleep "$POST_SEC"

    if [[ "$ENABLE_DISK_WATCH" == "1" ]]; then
        echo "[INFO] disk_watch snapshot" | tee -a "$LOG"
        run_with_timeout 2 bash "$SCRIPTS_DIR/disk_watch.sh"
    fi

    mark "C${CYCLE}_POSTBASELINE_END"
    echo "=== CYCLE_${CYCLE}_END ===" | tee -a "$LOG"
done

echo "[INFO] Day17 run complete: $RUN_DIR" | tee -a "$LOG"
