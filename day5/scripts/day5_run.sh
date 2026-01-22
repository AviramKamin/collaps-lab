#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Day 5 Runner (Collapse Memory)
# Cycles: Baseline -> Intervention -> Recovery -> PostBaseline
# Writes logs to ../runs/<timestamp>_day5_offX_nY/
# ---------------------------

cd -- "$(dirname -- "$0")"
SCRIPTS_DIR="$(pwd)"
PROJECT_DIR="$(cd .. && pwd)"
RUNS_DIR="${PROJECT_DIR}/runs"
WORKDIR="${PROJECT_DIR}/workdir"

mkdir -p "$RUNS_DIR" "$WORKDIR"

# ---- Parameters (override via env) ----
N_CYCLES="${N_CYCLES:-3}"

HB_INTERVAL="${HB_INTERVAL:-0.1}"     # seconds

BASELINE_SEC="${BASELINE_SEC:-60}"
INTERVENTION_SEC="${INTERVENTION_SEC:-180}"
RECOVERY_SEC="${RECOVERY_SEC:-120}"
POSTBASELINE_SEC="${POSTBASELINE_SEC:-60}"

ON_SEC="${ON_SEC:-3}"
OFF_SEC="${OFF_SEC:-3}"
BURSTS="${BURSTS:-50}"

# Retry storm tuning (passed to retry_storm.sh via env)
TARGET="${TARGET:-$WORKDIR/retry_test}"
BUDGET_MS="${BUDGET_MS:-120}"
RETRIES="${RETRIES:-3}"

# Optional: clean retry directory before each cycle intervention
CLEAN_RETRY_EACH_CYCLE="${CLEAN_RETRY_EACH_CYCLE:-1}"  # 1=yes, 0=no

# ---- Run directory ----
TS="$(date +%Y-%m-%d_%H%M%S)"
RUN_NAME="${TS}_day5_off${OFF_SEC}_n${N_CYCLES}"
RUN_DIR="${RUNS_DIR}/${RUN_NAME}"
mkdir -p "$RUN_DIR"

echo "[INFO] Run dir: $RUN_DIR"
echo "[INFO] Cycles: $N_CYCLES | OFF=${OFF_SEC}s | HB=${HB_INTERVAL}s"
echo "[INFO] Baseline=${BASELINE_SEC}s Intervention=${INTERVENTION_SEC}s Recovery=${RECOVERY_SEC}s PostBaseline=${POSTBASELINE_SEC}s"
echo "[INFO] Retry: TARGET=$TARGET BUDGET_MS=$BUDGET_MS RETRIES=$RETRIES"
echo "[INFO] Bursts: ON=${ON_SEC}s OFF=${OFF_SEC}s BURSTS=${BURSTS}"

# ---- Save metadata ----
cat > "$RUN_DIR/meta.env" <<EOF
RUN_NAME=$RUN_NAME
N_CYCLES=$N_CYCLES
HB_INTERVAL=$HB_INTERVAL
BASELINE_SEC=$BASELINE_SEC
INTERVENTION_SEC=$INTERVENTION_SEC
RECOVERY_SEC=$RECOVERY_SEC
POSTBASELINE_SEC=$POSTBASELINE_SEC
ON_SEC=$ON_SEC
OFF_SEC=$OFF_SEC
BURSTS=$BURSTS
TARGET=$TARGET
BUDGET_MS=$BUDGET_MS
RETRIES=$RETRIES
CLEAN_RETRY_EACH_CYCLE=$CLEAN_RETRY_EACH_CYCLE
EOF

# ---- Heartbeat logger (continuous) ----
HB_LOG="$RUN_DIR/heartbeat.log"
HB_PIDFILE="$RUN_DIR/heartbeat.pid"
HB_MARKS="$RUN_DIR/heartbeat_marks.log"

heartbeat() {
  local interval="$1"
  local last_ns now_ns dt_ns

  # initialize
  last_ns="$(date +%s%N)"
  while true; do
    sleep "$interval"
    now_ns="$(date +%s%N)"
    dt_ns=$((now_ns - last_ns))
    printf "%s %s\n" "$now_ns" "$dt_ns" >> "$HB_LOG"
    last_ns="$now_ns"
  done
}

echo "[INFO] Starting heartbeat"
heartbeat "$HB_INTERVAL" &
echo $! > "$HB_PIDFILE"

cleanup() {
  echo "[INFO] Stopping heartbeat"
  if [[ -f "$HB_PIDFILE" ]]; then
    kill "$(cat "$HB_PIDFILE")" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ---- Helpers ----
mark() {
  # stage marker aligned with heartbeat timestamps
  printf "%s %s\n" "$(date +%s%N)" "$1" >> "$HB_MARKS"
}

start_interference() {
  # bursts
  ( cd "$SCRIPTS_DIR" && env BURSTS="$BURSTS" ON_SEC="$ON_SEC" OFF_SEC="$OFF_SEC" bash ./run_bursts.sh ) \
    > "$1/bursts.log" 2>&1 &
  echo $! > "$1/bursts.pid"

  # retry storm
  ( cd "$SCRIPTS_DIR" && env TARGET="$TARGET" BUDGET_MS="$BUDGET_MS" RETRIES="$RETRIES" bash ./retry_storm.sh ) \
    > "$1/retries.log" 2>&1 &
  echo $! > "$1/retries.pid"
}

stop_interference() {
  if [[ -f "$1/bursts.pid" ]]; then
    kill "$(cat "$1/bursts.pid")" 2>/dev/null || true
  fi
  if [[ -f "$1/retries.pid" ]]; then
    kill "$(cat "$1/retries.pid")" 2>/dev/null || true
  fi
}

# ---- Run cycles ----
for c in $(seq 1 "$N_CYCLES"); do
  CYCLE_DIR="$RUN_DIR/cycle_${c}"
  mkdir -p "$CYCLE_DIR"

  echo "[INFO] Cycle $c/$N_CYCLES"

  # Baseline
  mark "C${c}_BASELINE_START"
  sleep "$BASELINE_SEC"
  mark "C${c}_BASELINE_END"

  # Intervention
  if [[ "$CLEAN_RETRY_EACH_CYCLE" == "1" ]]; then
    rm -rf "$TARGET"/* 2>/dev/null || true
  fi
  mkdir -p "$TARGET" || true

  mark "C${c}_INTERVENTION_START"
  start_interference "$CYCLE_DIR"
  sleep "$INTERVENTION_SEC"
  stop_interference "$CYCLE_DIR"
  mark "C${c}_INTERVENTION_END"

  # Recovery
  mark "C${c}_RECOVERY_START"
  sleep "$RECOVERY_SEC"
  mark "C${c}_RECOVERY_END"

  # Post-baseline probe
  mark "C${c}_POSTBASELINE_START"
  sleep "$POSTBASELINE_SEC"
  mark "C${c}_POSTBASELINE_END"
done

echo "[INFO] Run complete: $RUN_DIR"
