#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-$HOME/project/day16}"
RUN_ID="$(date +%F_%H%M%S)_day16_sampling"
RUN_DIR="$BASE_DIR/runs/$RUN_ID"
SCRIPTS_DIR="${SCRIPTS_DIR:-$(pwd)}"

N_CYCLES="${N_CYCLES:-3}"
BASELINE_SEC="${BASELINE_SEC:-60}"
INTERVENTION_SEC="${INTERVENTION_SEC:-10}"
R1_SEC="${R1_SEC:-60}"
R2_SEC="${R2_SEC:-60}"
POST_SEC="${POST_SEC:-60}"
SAMPLE_HZ="${SAMPLE_HZ:-10}"
HEARTBEAT_HZ="${HEARTBEAT_HZ:-20}"

mkdir -p "$RUN_DIR/proc_samples"
LOG="$RUN_DIR/run.log"
HB_LOG="$RUN_DIR/heartbeat.log"
HB_MARKS="$RUN_DIR/heartbeat_marks.log"
PROBES_LOG="$RUN_DIR/probes.log"

echo "[INFO] Starting Day16 run: $RUN_ID" | tee -a "$LOG"
echo "[INFO] SCRIPTS_DIR=$SCRIPTS_DIR" | tee -a "$LOG"
echo "[INFO] N_CYCLES=$N_CYCLES BASELINE_SEC=$BASELINE_SEC INTERVENTION_SEC=$INTERVENTION_SEC R1_SEC=$R1_SEC R2_SEC=$R2_SEC POST_SEC=$POST_SEC SAMPLE_HZ=$SAMPLE_HZ HEARTBEAT_HZ=$HEARTBEAT_HZ" | tee -a "$LOG"

require_script() {
    local p="$1"
    if [[ ! -f "$SCRIPTS_DIR/$p" ]]; then
        echo "[ERROR] Required helper script not found: $SCRIPTS_DIR/$p" | tee -a "$LOG"
        exit 1
    fi
}

require_script "run_bursts.sh"
require_script "retry_storm.sh"
require_script "r2_telemetry_fine.sh"
require_script "disk_watch.sh"

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

run_phase_command() {
    local sec="$1"
    local script_name="$2"
    local rc=0

    echo "[INFO] timeout ${sec}s bash $script_name" | tee -a "$LOG"
    timeout "${sec}s" bash "$SCRIPTS_DIR/$script_name" >> "$LOG" 2>&1 || rc=$?

    case "$rc" in
        0|124)
            return 0
            ;;
        *)
            echo "[ERROR] $script_name failed with rc=$rc" | tee -a "$LOG"
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

sample_proc &
SAMPLE_PID=$!
echo "[INFO] Sampler PID: $SAMPLE_PID" | tee -a "$LOG"

for (( CYCLE=1; CYCLE<=N_CYCLES; CYCLE++ )); do
    mark "C${CYCLE}_BASELINE_START"
    echo "=== CYCLE_${CYCLE}_START ===" | tee -a "$LOG"

    echo "--- BASELINE ---" | tee -a "$LOG"
    sleep "$BASELINE_SEC"
    mark "C${CYCLE}_BASELINE_END"

    mark "C${CYCLE}_INTERVENTION_START"
    echo "--- INTERVENTION ---" | tee -a "$LOG"
    echo "$(date +%s%N) PROBE_B_START" >> "$PROBES_LOG"
    run_phase_command "$INTERVENTION_SEC" "run_bursts.sh"
    echo "$(date +%s%N) PROBE_B_END" >> "$PROBES_LOG"
    mark "C${CYCLE}_INTERVENTION_END"

    mark "C${CYCLE}_RECOVERY_R1_START"
    echo "--- RECOVERY_R1 ---" | tee -a "$LOG"
    sleep "$R1_SEC"
    mark "C${CYCLE}_RECOVERY_R1_END"

    mark "C${CYCLE}_RECOVERY_R2_START"
    echo "--- RECOVERY_R2 ---" | tee -a "$LOG"
    run_phase_command "$R2_SEC" "retry_storm.sh"
    run_phase_command "$R2_SEC" "r2_telemetry_fine.sh"
    mark "C${CYCLE}_RECOVERY_R2_END"

    mark "C${CYCLE}_POSTBASELINE_START"
    echo "--- POST_BASELINE ---" | tee -a "$LOG"
    sleep "$POST_SEC"

    echo "[INFO] disk_watch snapshot" | tee -a "$LOG"
    timeout 2s bash "$SCRIPTS_DIR/disk_watch.sh" >> "$LOG" 2>&1 || true

    mark "C${CYCLE}_POSTBASELINE_END"
    echo "=== CYCLE_${CYCLE}_END ===" | tee -a "$LOG"
done

echo "[INFO] Day16 run complete: $RUN_DIR" | tee -a "$LOG"
