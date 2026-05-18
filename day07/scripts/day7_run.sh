#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Day 7 Runner (Recovery Coupling + Rare Event Provocation)
# Cycles: Baseline -> Intervention -> RecoveryPassive(R1) -> RecoveryProvocation(R2) -> PostBaseline
# Adds probe windows during recovery to test whether rare heartbeat stalls are excitable and state dependent.
# Writes logs to ../runs/<timestamp>_day7_offX_nY/
# ---------------------------

cd -- "$(dirname -- "$0")"
SCRIPTS_DIR="$(pwd)"
PROJECT_DIR="$(cd .. && pwd)"
RUNS_DIR="${PROJECT_DIR}/runs"
WORKDIR="${PROJECT_DIR}/workdir"

mkdir -p "$RUNS_DIR" "$WORKDIR"

# ---- Parameters (override via env) ----
N_CYCLES="${N_CYCLES:-3}"

HB_INTERVAL="${HB_INTERVAL:-0.1}"           # seconds
MEMINFO_INTERVAL="${MEMINFO_INTERVAL:-1}"   # seconds

BASELINE_SEC="${BASELINE_SEC:-60}"
INTERVENTION_SEC="${INTERVENTION_SEC:-180}"

# Recovery split
RECOVERY_R1_SEC="${RECOVERY_R1_SEC:-180}"   # passive recovery
RECOVERY_R2_SEC="${RECOVERY_R2_SEC:-180}"   # provocation window total

POSTBASELINE_SEC="${POSTBASELINE_SEC:-60}"

# IO bursts
ON_SEC="${ON_SEC:-3}"
OFF_SEC="${OFF_SEC:-3}"
BURSTS="${BURSTS:-50}"

# Retry storm tuning
TARGET="${TARGET:-$WORKDIR/retry_test}"
BUDGET_MS="${BUDGET_MS:-120}"
RETRIES="${RETRIES:-3}"
CLEAN_RETRY_EACH_CYCLE="${CLEAN_RETRY_EACH_CYCLE:-1}"  # 1=yes, 0=no

# Meminfo fields
MEMINFO_FIELDS="${MEMINFO_FIELDS:-MemAvailable Dirty Writeback Slab}"

# ---- Day 7 probe controls ----
# Enable probes during R2
ENABLE_PROBES="${ENABLE_PROBES:-1}"     # 1=yes 0=no

# R2 schedule (seconds)
R2_IDLE_A_SEC="${R2_IDLE_A_SEC:-60}"
R2_PROBE_A_SEC="${R2_PROBE_A_SEC:-60}"
R2_IDLE_B_SEC="${R2_IDLE_B_SEC:-30}"
R2_PROBE_B_SEC="${R2_PROBE_B_SEC:-60}"
R2_IDLE_C_SEC="${R2_IDLE_C_SEC:-30}"
R2_PROBE_C_SEC="${R2_PROBE_C_SEC:-60}"

# Probe A: fsync micro write
PROBE_A_PERIOD_SEC="${PROBE_A_PERIOD_SEC:-5}"

# Probe B: cache pressure read
# If file does not exist, runner will create it.
PROBE_B_FILE="${PROBE_B_FILE:-$WORKDIR/probe_cache_blob.bin}"
PROBE_B_SIZE_MB="${PROBE_B_SIZE_MB:-64}"

# Probe C: mild cpu tickle
PROBE_C_PERIOD_SEC="${PROBE_C_PERIOD_SEC:-1}"
PROBE_C_BUSY_MS="${PROBE_C_BUSY_MS:-50}"

# ---- Run directory ----
TS="$(date +%Y-%m-%d_%H%M%S)"
RUN_NAME="${TS}_day7_off${OFF_SEC}_n${N_CYCLES}"
RUN_DIR="${RUNS_DIR}/${RUN_NAME}"
mkdir -p "$RUN_DIR"

echo "[INFO] Run dir: $RUN_DIR"
echo "[INFO] Cycles: $N_CYCLES | OFF=${OFF_SEC}s | HB=${HB_INTERVAL}s | MEMINFO=${MEMINFO_INTERVAL}s"
echo "[INFO] Baseline=${BASELINE_SEC}s Intervention=${INTERVENTION_SEC}s R1=${RECOVERY_R1_SEC}s R2=${RECOVERY_R2_SEC}s PostBaseline=${POSTBASELINE_SEC}s"
echo "[INFO] Retry: TARGET=$TARGET BUDGET_MS=$BUDGET_MS RETRIES=$RETRIES"
echo "[INFO] Bursts: ON=${ON_SEC}s OFF=${OFF_SEC}s BURSTS=${BURSTS}"
echo "[INFO] Meminfo fields: $MEMINFO_FIELDS"
echo "[INFO] Probes enabled: $ENABLE_PROBES"
echo "[INFO] R2 schedule: idleA=${R2_IDLE_A_SEC}s A=${R2_PROBE_A_SEC}s idleB=${R2_IDLE_B_SEC}s B=${R2_PROBE_B_SEC}s idleC=${R2_IDLE_C_SEC}s C=${R2_PROBE_C_SEC}s"

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
R2_IDLE_A_SEC=$R2_IDLE_A_SEC
R2_PROBE_A_SEC=$R2_PROBE_A_SEC
R2_IDLE_B_SEC=$R2_IDLE_B_SEC
R2_PROBE_B_SEC=$R2_PROBE_B_SEC
R2_IDLE_C_SEC=$R2_IDLE_C_SEC
R2_PROBE_C_SEC=$R2_PROBE_C_SEC
PROBE_A_PERIOD_SEC=$PROBE_A_PERIOD_SEC
PROBE_B_FILE=$PROBE_B_FILE
PROBE_B_SIZE_MB=$PROBE_B_SIZE_MB
PROBE_C_PERIOD_SEC=$PROBE_C_PERIOD_SEC
PROBE_C_BUSY_MS=$PROBE_C_BUSY_MS
META

# ---- Logs / pidfiles ----
HB_LOG="$RUN_DIR/heartbeat.log"
HB_PIDFILE="$RUN_DIR/heartbeat.pid"
HB_MARKS="$RUN_DIR/heartbeat_marks.log"

MI_LOG="$RUN_DIR/meminfo.log"
MI_PIDFILE="$RUN_DIR/meminfo.pid"

# ---- Heartbeat logger (continuous) ----
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

# ---- Meminfo logger (continuous) ----
meminfo_logger() {
  local interval="$1"
  local fields="$2"
  while true; do
    sleep "$interval"
    local ts
    ts="$(date +%s%N)"
    local line
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

# ---- Helpers ----
mark() {
  printf "%s %s\n" "$(date +%s%N)" "$1" >> "$HB_MARKS"
}

# Interference (same as Day 6)
start_interference() {
  ( cd "$SCRIPTS_DIR" && env BURSTS="$BURSTS" ON_SEC="$ON_SEC" OFF_SEC="$OFF_SEC" bash ./run_bursts.sh ) \
    > "$1/bursts.log" 2>&1 &
  echo $! > "$1/bursts.pid"

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

cleanup() {
  echo "[INFO] Cleanup: stopping background loggers"
  if [[ -f "$HB_PIDFILE" ]]; then kill "$(cat "$HB_PIDFILE")" 2>/dev/null || true; fi
  if [[ -f "$MI_PIDFILE" ]]; then kill "$(cat "$MI_PIDFILE")" 2>/dev/null || true; fi
}
trap cleanup EXIT

# ---- Probe helpers ----
probe_log() {
  local logfile="$1"
  shift
  printf "%s %s\n" "$(date +%s%N)" "$*" >> "$logfile"
}

probe_A_fsync_micro() {
  local dur="$1"
  local period="$2"
  local logfile="$3"
  local end_ts
  end_ts=$(( $(date +%s) + dur ))
  probe_log "$logfile" "PROBE_A_START fsync_micro dur_sec=$dur period_sec=$period"
  while [[ $(date +%s) -lt $end_ts ]]; do
    local f="$WORKDIR/probe_fsync_$$.tmp"
    printf "%s\n" "$(date +%s%N)" > "$f"
    sync -f "$f" 2>/dev/null || true
    rm -f "$f" 2>/dev/null || true
    sleep "$period"
  done
  probe_log "$logfile" "PROBE_A_END"
}

ensure_probe_B_file() {
  local file="$1"
  local size_mb="$2"
  if [[ -f "$file" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  echo "[INFO] Creating probe B file: $file (${size_mb}MB)"
  dd if=/dev/urandom of="$file" bs=1M count="$size_mb" status=none
  sync
}

probe_B_cache_read() {
  local dur="$1"
  local file="$2"
  local logfile="$3"
  local end_ts
  end_ts=$(( $(date +%s) + dur ))
  probe_log "$logfile" "PROBE_B_START cache_read dur_sec=$dur file=$file"
  while [[ $(date +%s) -lt $end_ts ]]; do
    dd if="$file" of=/dev/null bs=4M status=none || true
  done
  probe_log "$logfile" "PROBE_B_END"
}

probe_C_cpu_tickle() {
  local dur="$1"
  local period="$2"
  local busy_ms="$3"
  local logfile="$4"
  local end_ts
  end_ts=$(( $(date +%s) + dur ))
  probe_log "$logfile" "PROBE_C_START cpu_tickle dur_sec=$dur period_sec=$period busy_ms=$busy_ms"

  while [[ $(date +%s) -lt $end_ts ]]; do
    # Busy loop for busy_ms using nanoseconds
    local start_ns now_ns target_ns
    start_ns="$(date +%s%N)"
    target_ns=$((start_ns + busy_ms*1000000))
    while true; do
      now_ns="$(date +%s%N)"
      [[ "$now_ns" -ge "$target_ns" ]] && break
      : # spin
    done
    # sleep rest of the period
    local rest
    rest=$(awk -v p="$period" -v b="$busy_ms" 'BEGIN{r=p-(b/1000.0); if(r<0) r=0; printf "%.3f", r}')
    sleep "$rest"
  done

  probe_log "$logfile" "PROBE_C_END"
}

run_R2_probes() {
  local logfile="$1"

  probe_log "$logfile" "R2_IDLE_A_START sec=$R2_IDLE_A_SEC"
  sleep "$R2_IDLE_A_SEC"
  probe_log "$logfile" "R2_IDLE_A_END"

  if [[ "$ENABLE_PROBES" == "1" ]]; then
    mark "R2_PROBE_A_START"
    probe_A_fsync_micro "$R2_PROBE_A_SEC" "$PROBE_A_PERIOD_SEC" "$logfile"
    mark "R2_PROBE_A_END"
  else
    probe_log "$logfile" "PROBES_DISABLED skipping A"
    sleep "$R2_PROBE_A_SEC"
  fi

  probe_log "$logfile" "R2_IDLE_B_START sec=$R2_IDLE_B_SEC"
  sleep "$R2_IDLE_B_SEC"
  probe_log "$logfile" "R2_IDLE_B_END"

  if [[ "$ENABLE_PROBES" == "1" ]]; then
    ensure_probe_B_file "$PROBE_B_FILE" "$PROBE_B_SIZE_MB"
    mark "R2_PROBE_B_START"
    probe_B_cache_read "$R2_PROBE_B_SEC" "$PROBE_B_FILE" "$logfile"
    mark "R2_PROBE_B_END"
  else
    probe_log "$logfile" "PROBES_DISABLED skipping B"
    sleep "$R2_PROBE_B_SEC"
  fi

  probe_log "$logfile" "R2_IDLE_C_START sec=$R2_IDLE_C_SEC"
  sleep "$R2_IDLE_C_SEC"
  probe_log "$logfile" "R2_IDLE_C_END"

  if [[ "$ENABLE_PROBES" == "1" ]]; then
    mark "R2_PROBE_C_START"
    probe_C_cpu_tickle "$R2_PROBE_C_SEC" "$PROBE_C_PERIOD_SEC" "$PROBE_C_BUSY_MS" "$logfile"
    mark "R2_PROBE_C_END"
  else
    probe_log "$logfile" "PROBES_DISABLED skipping C"
    sleep "$R2_PROBE_C_SEC"
  fi
}

# ---- Start loggers ----
echo "[INFO] Starting heartbeat"
heartbeat "$HB_INTERVAL" &
echo $! > "$HB_PIDFILE"

echo "[INFO] Starting meminfo logger"
meminfo_logger "$MEMINFO_INTERVAL" "$MEMINFO_FIELDS" &
echo $! > "$MI_PIDFILE"

# ---- Run cycles ----
for c in $(seq 1 "$N_CYCLES"); do
  CYCLE_DIR="$RUN_DIR/cycle_${c}"
  mkdir -p "$CYCLE_DIR"
  PROBES_LOG="$CYCLE_DIR/probes.log"

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

  # Recovery R1 passive
  mark "C${c}_RECOVERY_R1_START"
  sleep "$RECOVERY_R1_SEC"
  mark "C${c}_RECOVERY_R1_END"

  # Recovery R2 provocation window
  mark "C${c}_RECOVERY_R2_START"

  # Ensure total R2 matches sum of segments
  r2_sum=$((R2_IDLE_A_SEC + R2_PROBE_A_SEC + R2_IDLE_B_SEC + R2_PROBE_B_SEC + R2_IDLE_C_SEC + R2_PROBE_C_SEC))
  if [[ "$r2_sum" -ne "$RECOVERY_R2_SEC" ]]; then
    echo "[WARN] RECOVERY_R2_SEC=$RECOVERY_R2_SEC but schedule sum=$r2_sum. Using schedule sum and ignoring RECOVERY_R2_SEC."
  fi

  run_R2_probes "$PROBES_LOG"
  mark "C${c}_RECOVERY_R2_END"

  # Post-baseline probe
  mark "C${c}_POSTBASELINE_START"
  sleep "$POSTBASELINE_SEC"
  mark "C${c}_POSTBASELINE_END"
done

echo "[INFO] Run complete: $RUN_DIR"
