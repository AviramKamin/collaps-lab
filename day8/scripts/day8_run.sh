#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Day 8 Runner (Recovery Scarring / Dose Response)
# Cycle: B -> I -> R1 -> R2(probes optional program) -> B2
# Writes logs to ../runs/<timestamp>_day8_offX_<program>_nY/
# ---------------------------

cd -- "$(dirname -- "$0")"
SCRIPTS_DIR="$(pwd)"
PROJECT_DIR="$(cd .. && pwd)"
RUNS_DIR="${PROJECT_DIR}/runs"
WORKDIR="${PROJECT_DIR}/workdir"

mkdir -p "$RUNS_DIR" "$WORKDIR"

# ---- Parameters (override via env) ----
N_CYCLES="${N_CYCLES:-3}"

HB_INTERVAL="${HB_INTERVAL:-0.1}"            # seconds
MEMINFO_INTERVAL="${MEMINFO_INTERVAL:-1}"    # seconds

BASELINE_SEC="${BASELINE_SEC:-60}"
INTERVENTION_SEC="${INTERVENTION_SEC:-180}"
RECOVERY_R1_SEC="${RECOVERY_R1_SEC:-180}"
RECOVERY_R2_SEC="${RECOVERY_R2_SEC:-300}"
POSTBASELINE_SEC="${POSTBASELINE_SEC:-60}"

ON_SEC="${ON_SEC:-3}"
OFF_SEC="${OFF_SEC:-3}"
BURSTS="${BURSTS:-50}"

TARGET="${TARGET:-$WORKDIR/retry_test}"
BUDGET_MS="${BUDGET_MS:-120}"
RETRIES="${RETRIES:-3}"

CLEAN_RETRY_EACH_CYCLE="${CLEAN_RETRY_EACH_CYCLE:-1}"  # 1=yes 0=no

MEMINFO_FIELDS="${MEMINFO_FIELDS:-MemAvailable Dirty Writeback Slab}"

# Probes
ENABLE_PROBES="${ENABLE_PROBES:-1}"          # 0/1
PROBE_PROGRAM="${PROBE_PROGRAM:-low}"        # control|low|high|late
PROBE_FILE_MB="${PROBE_FILE_MB:-64}"         # used by some probe actions
PROBE_ROOT="${PROBE_ROOT:-$WORKDIR/probes}"
mkdir -p "$PROBE_ROOT"

# R2 schedule (seconds)
R2_IDLE_A_SEC="${R2_IDLE_A_SEC:-60}"
R2_PROBE_A_SEC="${R2_PROBE_A_SEC:-60}"
R2_IDLE_B_SEC="${R2_IDLE_B_SEC:-30}"
R2_PROBE_B_SEC="${R2_PROBE_B_SEC:-60}"
R2_IDLE_C_SEC="${R2_IDLE_C_SEC:-30}"
R2_PROBE_C_SEC="${R2_PROBE_C_SEC:-60}"

r2_schedule_sum=$((R2_IDLE_A_SEC+R2_PROBE_A_SEC+R2_IDLE_B_SEC+R2_PROBE_B_SEC+R2_IDLE_C_SEC+R2_PROBE_C_SEC))

# ---- Run directory ----
TS="$(date +%Y-%m-%d_%H%M%S)"
RUN_NAME="${TS}_day8_off${OFF_SEC}_${PROBE_PROGRAM}_n${N_CYCLES}"
RUN_DIR="${RUNS_DIR}/${RUN_NAME}"
mkdir -p "$RUN_DIR"

echo "[INFO] Run dir: $RUN_DIR"
echo "[INFO] Cycles: $N_CYCLES | OFF=${OFF_SEC}s | HB=${HB_INTERVAL}s | MEMINFO=${MEMINFO_INTERVAL}s"
echo "[INFO] Baseline=${BASELINE_SEC}s Intervention=${INTERVENTION_SEC}s R1=${RECOVERY_R1_SEC}s R2=${RECOVERY_R2_SEC}s PostBaseline=${POSTBASELINE_SEC}s"
echo "[INFO] Retry: TARGET=$TARGET BUDGET_MS=$BUDGET_MS RETRIES=$RETRIES"
echo "[INFO] Bursts: ON=${ON_SEC}s OFF=${OFF_SEC}s BURSTS=${BURSTS}"
echo "[INFO] Meminfo fields: $MEMINFO_FIELDS"
echo "[INFO] Probes enabled: $ENABLE_PROBES | program=$PROBE_PROGRAM | file=${PROBE_FILE_MB}MB"
echo "[INFO] R2 schedule: idleA=${R2_IDLE_A_SEC}s A=${R2_PROBE_A_SEC}s idleB=${R2_IDLE_B_SEC}s B=${R2_PROBE_B_SEC}s idleC=${R2_IDLE_C_SEC}s C=${R2_PROBE_C_SEC}s (sum=${r2_schedule_sum}s)"

# ---- Save metadata ----
cat > "$RUN_DIR/meta.env" <<META
RUN_NAME=$RUN_NAME
N_CYCLES=$N_CYCLES
HB_INTERVAL=$HB_INTERVAL
MEMINFO_INTERVAL=$MEMINFO_INTERVAL
BASELINE_SEC=$BASELINE_SEC
INTERVENTION_SEC=$INTERVENTION_SEC
RECOVERY_R1_SEC=$RECOVERY_R1_SEC
RECOVERY_R2_SEC=$RECOVERY_R2_SEC
POSTBASELINE_SEC=$POSTBASELINE_SEC
ON_SEC=$ON_SEC
OFF_SEC=$OFF_SEC
BURSTS=$BURSTS
TARGET=$TARGET
BUDGET_MS=$BUDGET_MS
RETRIES=$RETRIES
CLEAN_RETRY_EACH_CYCLE=$CLEAN_RETRY_EACH_CYCLE
MEMINFO_FIELDS=$MEMINFO_FIELDS
ENABLE_PROBES=$ENABLE_PROBES
PROBE_PROGRAM=$PROBE_PROGRAM
PROBE_FILE_MB=$PROBE_FILE_MB
R2_IDLE_A_SEC=$R2_IDLE_A_SEC
R2_PROBE_A_SEC=$R2_PROBE_A_SEC
R2_IDLE_B_SEC=$R2_IDLE_B_SEC
R2_PROBE_B_SEC=$R2_PROBE_B_SEC
R2_IDLE_C_SEC=$R2_IDLE_C_SEC
R2_PROBE_C_SEC=$R2_PROBE_C_SEC
META

HB_LOG="$RUN_DIR/heartbeat.log"
HB_PIDFILE="$RUN_DIR/heartbeat.pid"
HB_MARKS="$RUN_DIR/heartbeat_marks.log"

MI_LOG="$RUN_DIR/meminfo.log"
MI_PIDFILE="$RUN_DIR/meminfo.pid"

heartbeat() {
  local interval="$1"
  local last_ns now_ns dt_ns
  last_ns="$(date +%s%N)"
  while true; do
    sleep "$interval"
    now_ns="$(date +%s%N)"
    dt_ns=$((now_ns - last_ns))
    printf "%s %s\n" "$now_ns" "$dt_ns" >> "$HB_LOG"
    last_ns="$now_ns"
  done
}

meminfo_logger() {
  local interval="$1"
  local fields="$2"
  while true; do
    sleep "$interval"
    local ts line
    ts="$(date +%s%N)"
    line="$(awk -v want="$fields" '
      BEGIN{
        n=split(want,arr," ");
        for(i=1;i<=n;i++) wanted[arr[i]]=1;
      }
      {
        key=$1; sub(/:$/,"",key);
        if (wanted[key]) printf "%s_kB=%s ", key, $2;
      }
      END{ print "" }
    ' /proc/meminfo)"
    printf "%s %s\n" "$ts" "$line" >> "$MI_LOG"
  done
}

mark() { printf "%s %s\n" "$(date +%s%N)" "$1" >> "$HB_MARKS"; }

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
  [[ -f "$1/bursts.pid" ]] && kill "$(cat "$1/bursts.pid")" 2>/dev/null || true
  [[ -f "$1/retries.pid" ]] && kill "$(cat "$1/retries.pid")" 2>/dev/null || true
}

probe_action_A() {
  # cache touch / read
  local f="$PROBE_ROOT/probe_cache_blob.bin"
  if [[ ! -f "$f" ]]; then
    dd if=/dev/zero of="$f" bs=1M count="$PROBE_FILE_MB" status=none
  fi
  # read through page cache
  cat "$f" > /dev/null
}

probe_action_B() {
  # small file create + fsync (high program can repeat)
  local f="$PROBE_ROOT/probe_small_$(date +%s%N).bin"
  dd if=/dev/urandom of="$f" bs=1M count=1 status=none
  sync
}

probe_action_C() {
  # metadata walk
  find "$PROBE_ROOT" -maxdepth 1 -type f -printf "%f\n" > /dev/null
}

run_probe_window() {
  local seconds="$1"
  local action="$2"
  local repeats="${3:-1}"

  local end=$(( $(date +%s) + seconds ))
  while [[ $(date +%s) -lt $end ]]; do
    printf "%s PROBE_%s_START program=%s\n" "$(date +%s%N)" "$action" "$PROBE_PROGRAM" 
    case "$action" in
      A) probe_action_A ;;
      B) probe_action_B ;;
      C) probe_action_C ;;
      *) : ;;
    esac
    printf "%s PROBE_%s_END program=%s\n" "$(date +%s%N)" "$action" "$PROBE_PROGRAM"

    # repeats>1 makes “high” denser without changing schedule times
    if [[ "$repeats" -gt 1 ]]; then
      for _ in $(seq 2 "$repeats"); do
        case "$action" in
          A) probe_action_A ;;
          B) probe_action_B ;;
          C) probe_action_C ;;
        esac
      done
    fi

    # tiny pause so we don’t spin
    sleep 0.2
  done
}

run_r2_probes() {
  local probes_log="$1"

  if [[ "$ENABLE_PROBES" != "1" || "$PROBE_PROGRAM" == "control" ]]; then
    echo "$(date +%s%N) PROBES_DISABLED program=$PROBE_PROGRAM" >> "$probes_log"
    sleep "$RECOVERY_R2_SEC"
    return
  fi

  # High = denser (repeat each action multiple times), same window sizes
  local repA=1 repB=1 repC=1
  if [[ "$PROBE_PROGRAM" == "high" ]]; then
    repA=3; repB=3; repC=2
  fi

  if [[ "$PROBE_PROGRAM" == "late" ]]; then
    # first 2/3 idle, last 1/3 run A then B then C quickly
    local idle=$(( (RECOVERY_R2_SEC*2)/3 ))
    local active=$(( RECOVERY_R2_SEC - idle ))
    echo "$(date +%s%N) R2_LATE_IDLE seconds=$idle" >> "$probes_log"
    sleep "$idle"
    echo "$(date +%s%N) R2_LATE_ACTIVE seconds=$active" >> "$probes_log"
    run_probe_window $((active/3)) A "$repA" >> "$probes_log" 2>&1 || true
    run_probe_window $((active/3)) B "$repB" >> "$probes_log" 2>&1 || true
    run_probe_window $((active - 2*(active/3))) C "$repC" >> "$probes_log" 2>&1 || true
    return
  fi

  # low/high schedule (fixed)
  echo "$(date +%s%N) R2_IDLE_A seconds=$R2_IDLE_A_SEC" >> "$probes_log"
  sleep "$R2_IDLE_A_SEC"

  run_probe_window "$R2_PROBE_A_SEC" A "$repA" >> "$probes_log" 2>&1 || true

  echo "$(date +%s%N) R2_IDLE_B seconds=$R2_IDLE_B_SEC" >> "$probes_log"
  sleep "$R2_IDLE_B_SEC"

  run_probe_window "$R2_PROBE_B_SEC" B "$repB" >> "$probes_log" 2>&1 || true

  echo "$(date +%s%N) R2_IDLE_C seconds=$R2_IDLE_C_SEC" >> "$probes_log"
  sleep "$R2_IDLE_C_SEC"

  run_probe_window "$R2_PROBE_C_SEC" C "$repC" >> "$probes_log" 2>&1 || true
}

cleanup() {
  echo "[INFO] Cleanup: stopping background loggers"
  [[ -f "$HB_PIDFILE" ]] && kill "$(cat "$HB_PIDFILE")" 2>/dev/null || true
  [[ -f "$MI_PIDFILE" ]] && kill "$(cat "$MI_PIDFILE")" 2>/dev/null || true
}
trap cleanup EXIT

echo "[INFO] Starting heartbeat"
heartbeat "$HB_INTERVAL" & echo $! > "$HB_PIDFILE"

echo "[INFO] Starting meminfo logger"
meminfo_logger "$MEMINFO_INTERVAL" "$MEMINFO_FIELDS" & echo $! > "$MI_PIDFILE"

for c in $(seq 1 "$N_CYCLES"); do
  CYCLE_DIR="$RUN_DIR/cycle_${c}"
  mkdir -p "$CYCLE_DIR"
  echo "[INFO] Cycle $c/$N_CYCLES"

  mark "C${c}_BASELINE_START"
  sleep "$BASELINE_SEC"
  mark "C${c}_BASELINE_END"

  if [[ "$CLEAN_RETRY_EACH_CYCLE" == "1" ]]; then
    rm -rf "$TARGET"/* 2>/dev/null || true
  fi
  mkdir -p "$TARGET" || true

  mark "C${c}_INTERVENTION_START"
  start_interference "$CYCLE_DIR"
  sleep "$INTERVENTION_SEC"
  stop_interference "$CYCLE_DIR"
  mark "C${c}_INTERVENTION_END"

  mark "C${c}_RECOVERY_R1_START"
  sleep "$RECOVERY_R1_SEC"
  mark "C${c}_RECOVERY_R1_END"

  mark "C${c}_RECOVERY_R2_START"
  run_r2_probes "$CYCLE_DIR/probes.log"
  mark "C${c}_RECOVERY_R2_END"

  mark "C${c}_POSTBASELINE_START"
  sleep "$POSTBASELINE_SEC"
  mark "C${c}_POSTBASELINE_END"
done

echo "[INFO] Run complete: $RUN_DIR"
