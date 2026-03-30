#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="$HOME/project/day16"
RUN_ID="$(date +%F_%H%M%S)_day16_sampling"
RUN_DIR="$BASE_DIR/runs/$RUN_ID"

mkdir -p "$RUN_DIR/proc_samples"
LOG="$RUN_DIR/run.log"

echo "[INFO] Starting Day16 run: $RUN_ID" | tee -a "$LOG"

cleanup() {
    echo "[INFO] Cleaning up..." | tee -a "$LOG"
    if [[ -n "${SAMPLE_PID:-}" ]]; then
        kill "$SAMPLE_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

sample_proc() {
    echo "[INFO] Sampling started (10Hz)" >> "$LOG"
    while true; do
        TS=$(date +%s.%N)

        echo "TS=$TS" >> "$RUN_DIR/proc_samples/proc_stat.log"
        cat /proc/stat >> "$RUN_DIR/proc_samples/proc_stat.log"

        echo "TS=$TS" >> "$RUN_DIR/proc_samples/proc_interrupts.log"
        cat /proc/interrupts >> "$RUN_DIR/proc_samples/proc_interrupts.log"

        echo "TS=$TS" >> "$RUN_DIR/proc_samples/proc_softirqs.log"
        cat /proc/softirqs >> "$RUN_DIR/proc_samples/proc_softirqs.log"

        sleep 0.1
    done
}

sample_proc &
SAMPLE_PID=$!

echo "[INFO] Sampler PID: $SAMPLE_PID" | tee -a "$LOG"

for CYCLE in 1 2 3; do
    echo "=== CYCLE_$CYCLE_START ===" | tee -a "$LOG"

    echo "--- BASELINE ---" | tee -a "$LOG"
    sleep 2

    echo "--- INTERVENTION ---" | tee -a "$LOG"
    bash run_bursts.sh >> "$LOG" 2>&1

    echo "--- RECOVERY_R1 ---" | tee -a "$LOG"
    sleep 2

    echo "--- RECOVERY_R2 ---" | tee -a "$LOG"
    bash retry_storm.sh >> "$LOG" 2>&1
    bash r2_telemetry_fine.sh >> "$LOG" 2>&1

    echo "--- POST_BASELINE ---" | tee -a "$LOG"
    sleep 2

    echo "=== CYCLE_$CYCLE_END ===" | tee -a "$LOG"
done

kill "$SAMPLE_PID"

echo "[INFO] Day16 run complete: $RUN_DIR" | tee -a "$LOG"
