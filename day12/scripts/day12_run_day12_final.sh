#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Day 12 Runner (Probe_B Micro-Attribution: Decomposition Ladder + R2 Telemetry)
# Cycle: B -> I -> R1 -> R2(probes by MODE + PROBE_ACTIONS, telemetry) -> B2
# Writes logs to ../runs/<timestamp>_day12_offX_<MODE>_actions<PROBE_ACTIONS>_bvar<PROBE_B_VARIANT>_nY/
# ---------------------------

cd -- "$(dirname -- "$0")"
SCRIPTS_DIR="$(pwd)"
PROJECT_DIR="$(cd .. && pwd)"
RUNS_DIR="${PROJECT_DIR}/runs"
WORKDIR="${PROJECT_DIR}/workdir"

# Create RUNS_DIR even if PROJECT_DIR/runs is a symlink
if [[ -L "$RUNS_DIR" ]]; then
  RUNS_DIR_REAL="$(readlink -f "$RUNS_DIR")"
  mkdir -p "$RUNS_DIR_REAL"
  RUNS_DIR="$RUNS_DIR_REAL"
else
  mkdir -p "$RUNS_DIR"
fi
mkdir -p "$WORKDIR"

# ---- Parameters (override via env) ----
N_CYCLES="${N_CYCLES:-3}"

HB_INTERVAL="${HB_INTERVAL:-0.1}"
MEMINFO_INTERVAL="${MEMINFO_INTERVAL:-1}"

BASELINE_SEC="${BASELINE_SEC:-60}"
INTERVENTION_SEC="${INTERVENTION_SEC:-180}"
RECOVERY_R1_SEC="${RECOVERY_R1_SEC:-180}"
RECOVERY_R2_SEC="${RECOVERY_R2_SEC:-300}"
POSTBASELINE_SEC="${POSTBASELINE_SEC:-60}"

# Intervention (reuse Day8/Day9)
ON_SEC="${ON_SEC:-3}"
OFF_SEC="${OFF_SEC:-3}"
BURSTS="${BURSTS:-50}"

TARGET="${TARGET:-$WORKDIR/retry_test}"
BUDGET_MS="${BUDGET_MS:-120}"
RETRIES="${RETRIES:-3}"
CLEAN_RETRY_EACH_CYCLE="${CLEAN_RETRY_EACH_CYCLE:-1}"

MEMINFO_FIELDS="${MEMINFO_FIELDS:-MemAvailable Dirty Writeback Slab}"

# Probes
ENABLE_PROBES="${ENABLE_PROBES:-1}"     # runner will override per MODE
PROBE_PROGRAM="${PROBE_PROGRAM:-low}"   # control|low|high|late (Day11 expected: low)
PROBE_ACTIONS="${PROBE_ACTIONS:-ABC}"   # A|B|C|ABC (Day11 PROBE_B decomposition)
  USER_SET_PROBE_B_VARIANT=0

# ======================
# Day12 CPU Scheduling Controls
# ======================
HB_CORE="${HB_CORE:-0}"                 # Heartbeat CPU core
PROBE_CORE="${PROBE_CORE:-1}"           # Probe CPU core
CPU_TREAT="${CPU_TREAT:-none}"          # none|hog|bursty
CPU_HOG_CORE="${CPU_HOG_CORE:-1}"       # Hog core
HOG_ON="${HOG_ON:-2}"                   # Bursty ON seconds
HOG_OFF="${HOG_OFF:-1}"                 # Bursty OFF seconds

  [[ -n "${PROBE_B_VARIANT+x}" ]] && USER_SET_PROBE_B_VARIANT=1

  PROBE_B_VARIANT="${PROBE_B_VARIANT:-noop}"  # noop|buffered|tmpfs|fsync|sync_only (Day11)

  # If B_SKELETON control requested and user did not set PROBE_B_VARIANT explicitly: force noop
  if [[ "${PROBE_ACTIONS}" == "B_SKELETON" && "${USER_SET_PROBE_B_VARIANT}" -eq 0 ]]; then
    PROBE_B_VARIANT="noop"
  fi

PROBE_TMPFS_DIR="${PROBE_TMPFS_DIR:-/dev/shm/probes}"
PROBE_FILE_MB="${PROBE_FILE_MB:-64}"
PROBE_ROOT="${PROBE_ROOT:-$WORKDIR/probes}"
mkdir -p "$PROBE_ROOT"

R2_IDLE_A_SEC="${R2_IDLE_A_SEC:-60}"
R2_PROBE_A_SEC="${R2_PROBE_A_SEC:-60}"
R2_IDLE_B_SEC="${R2_IDLE_B_SEC:-30}"
R2_PROBE_B_SEC="${R2_PROBE_B_SEC:-60}"
R2_IDLE_C_SEC="${R2_IDLE_C_SEC:-30}"
R2_PROBE_C_SEC="${R2_PROBE_C_SEC:-60}"

# Background IO (kept for optional realism confirmation runs)
ENABLE_BGIO="${ENABLE_BGIO:-0}"                 # runner will override per MODE
BGIO_DIR="${BGIO_DIR:-$WORKDIR/bgio}"
BGIO_SCRIPT="${BGIO_SCRIPT:-$SCRIPTS_DIR/run_bgio.sh}"
BGIO_JOB="${BGIO_JOB:-$SCRIPTS_DIR/bgio.fio}"

# Telemetry (from Day10, kept for Day11)
ENABLE_TELEMETRY="${ENABLE_TELEMETRY:-1}"
TELEM_INTERVAL="${TELEM_INTERVAL:-1}"
TELEM_SCRIPT="${TELEM_SCRIPT:-$SCRIPTS_DIR/r2_telemetry.sh}"
TELEM_DEV="${TELEM_DEV:-mmcblk0}"

# Mode defines which stressors run in R2:
# A = none, B = probes only, C = bgio only, D = probes+bgio
MODE="${MODE:-B}"

# ---- Run directory ----
TS="$(date +%Y-%m-%d_%H%M%S)"
RUN_NAME="${TS}_day12_off${OFF_SEC}_${MODE}_actions${PROBE_ACTIONS}_bvar${PROBE_B_VARIANT}_n${N_CYCLES}"

RUN_DIR="${RUNS_DIR}/${RUN_NAME}"
mkdir -p "$RUN_DIR"

HB_LOG="$RUN_DIR/heartbeat.log"
HB_PIDFILE="$RUN_DIR/heartbeat.pid"
HB_MARKS="$RUN_DIR/heartbeat_marks.log"

MI_LOG="$RUN_DIR/meminfo.log"
MI_PIDFILE="$RUN_DIR/meminfo.pid"

echo "[INFO] Run dir: $RUN_DIR"
echo "[INFO] Cycles: $N_CYCLES | OFF=${OFF_SEC}s | MODE=$MODE | PROBE_ACTIONS=$PROBE_ACTIONS"
echo "[INFO] Baseline=${BASELINE_SEC}s Intervention=${INTERVENTION_SEC}s R1=${RECOVERY_R1_SEC}s R2=${RECOVERY_R2_SEC}s PostBaseline=${POSTBASELINE_SEC}s"
echo "[INFO] Probes: program=$PROBE_PROGRAM | ENABLE_PROBES=$ENABLE_PROBES | actions=$PROBE_ACTIONS | B_variant=$PROBE_B_VARIANT"
echo "[INFO] BGIO: ENABLE_BGIO=$ENABLE_BGIO dir=$BGIO_DIR job=$BGIO_JOB script=$BGIO_SCRIPT"
echo "[INFO] Telemetry: ENABLE_TELEMETRY=$ENABLE_TELEMETRY interval=${TELEM_INTERVAL}s dev=$TELEM_DEV script=$TELEM_SCRIPT"

# ---- Save metadata ----
cat > "$RUN_DIR/meta.env" <<META
RUN_NAME=$RUN_NAME
MODE=$MODE
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
PROBE_ACTIONS=$PROBE_ACTIONS
PROBE_B_VARIANT=$PROBE_B_VARIANT
PROBE_TMPFS_DIR=$PROBE_TMPFS_DIR
PROBE_FILE_MB=$PROBE_FILE_MB
PROBE_ROOT=$PROBE_ROOT
R2_IDLE_A_SEC=$R2_IDLE_A_SEC
R2_PROBE_A_SEC=$R2_PROBE_A_SEC
R2_IDLE_B_SEC=$R2_IDLE_B_SEC
R2_PROBE_B_SEC=$R2_PROBE_B_SEC
R2_IDLE_C_SEC=$R2_IDLE_C_SEC
R2_PROBE_C_SEC=$R2_PROBE_C_SEC
ENABLE_BGIO=$ENABLE_BGIO
BGIO_DIR=$BGIO_DIR
BGIO_JOB=$BGIO_JOB
BGIO_SCRIPT=$BGIO_SCRIPT
ENABLE_TELEMETRY=$ENABLE_TELEMETRY
TELEM_INTERVAL=$TELEM_INTERVAL
TELEM_SCRIPT=$TELEM_SCRIPT
TELEM_DEV=$TELEM_DEV
META

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

# Intervention: reuse Day8/Day9 scripts
start_interference() {
  ( cd "$SCRIPTS_DIR" && env BURSTS="$BURSTS" ON_SEC="$ON_SEC" OFF_SEC="$OFF_SEC" bash ./run_bursts.sh ) \
    > "$1/bursts.log" 2>&1 &
  echo $! > "$1/bursts.pid"

  ( cd "$SCRIPTS_DIR" && env TARGET="$TARGET" BUDGET_MS="$BUDGET_MS" RETRIES="$RETRIES" bash ./retry_storm.sh ) \
    > "$1/retries.log" 2>&1 &
  echo $! > "$1/retries.pid"
}

stop_interference() {
  [[ -f "$1/bursts.pid" ]] && kill "$(cat "$1/bursts.pid")" 2>/dev/null || true
  [[ -f "$1/retries.pid" ]] && kill "$(cat "$1/retries.pid")" 2>/dev/null || true
}

# Probes (same semantics as Day9)
probe_action_A() {
  local f="$PROBE_ROOT/probe_cache_blob.bin"
  if [[ ! -f "$f" ]]; then
    taskset -c "$PROBE_CORE" dd if=/dev/zero of="$f" bs=1M count="$PROBE_FILE_MB" status=none
  fi
  cat "$f" > /dev/null
}

probe_action_B() {
  local ts
  ts="$(date +%s%N)"

  # ext4 target (microSD path)
  local f_ext4="$PROBE_ROOT/probe_b_${ts}.bin"
  # tmpfs target (in-memory path)
  mkdir -p "$PROBE_TMPFS_DIR" 2>/dev/null || true
  local f_tmpfs="$PROBE_TMPFS_DIR/probe_b_${ts}.bin"

  case "$PROBE_B_VARIANT" in
    noop)
      : ;;
    buffered)
      # write to ext4, no fsync, no sync
      taskset -c "$PROBE_CORE" dd if=/dev/urandom of="$f_ext4" bs=1M count=1 status=none
      ;;
    tmpfs)
      # write to tmpfs, no fsync, no sync
      taskset -c "$PROBE_CORE" dd if=/dev/urandom of="$f_tmpfs" bs=1M count=1 status=none
      ;;
    fsync)
      # write + per-file fsync boundary (NOT global sync)
      taskset -c "$PROBE_CORE" dd if=/dev/urandom of="$f_ext4" bs=1M count=1 conv=fsync status=none
      ;;
    sync_only)
      # global flush boundary, no writes
      sync
      ;;
    *)
      echo "$(date +%s%N) [ERROR] Unknown PROBE_B_VARIANT=$PROBE_B_VARIANT" >&2
      return 2
      ;;
  esac
}

probe_action_C() {
  find "$PROBE_ROOT" -maxdepth 1 -type f -printf "%f\n" > /dev/null
}


# ======================
# Day12 CPU Hog Helpers
# ======================

start_cpu_hog() {
  ts=$(date +%s%N)
  echo "$ts HOG_START core=$CPU_HOG_CORE" >> "$CYCLE_DIR/probes.log"
  taskset -c "$CPU_HOG_CORE" bash -c 'while :; do :; done' &
  HOG_PID=$!
}

stop_cpu_hog() {
  if [[ -n "$HOG_PID" ]]; then
    kill "$HOG_PID" 2>/dev/null
    ts=$(date +%s%N)
    echo "$ts HOG_STOP" >> "$CYCLE_DIR/probes.log"
  fi
}

cpu_hog_bursty() {
  while true; do
    ts=$(date +%s%N)
    echo "$ts HOG_ON core=$CPU_HOG_CORE" >> "$CYCLE_DIR/probes.log"
    timeout "$HOG_ON"s taskset -c "$CPU_HOG_CORE" bash -c 'while :; do :; done'
    ts=$(date +%s%N)
    echo "$ts HOG_OFF" >> "$CYCLE_DIR/probes.log"
    sleep "$HOG_OFF"
  done
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

    if [[ "$repeats" -gt 1 ]]; then
      for _ in $(seq 2 "$repeats"); do
        case "$action" in
          A) probe_action_A ;;
          B) probe_action_B ;;
          C) probe_action_C ;;
        esac
      done
    fi
    sleep 0.2
  done
}

has_action() {
  local a="$1"
  [[ "$PROBE_ACTIONS" == "ABC" ]] && return 0
  [[ "$PROBE_ACTIONS" == *"$a"* ]]
}

run_r2_probes() {
  local probes_log="$1"

  if [[ "$ENABLE_PROBES" != "1" || "$PROBE_PROGRAM" == "control" ]]; then
    echo "$(date +%s%N) PROBES_DISABLED program=$PROBE_PROGRAM" >> "$probes_log"
    sleep "$RECOVERY_R2_SEC"
    return
  fi

  local repA=1 repB=1 repC=1
  if [[ "$PROBE_PROGRAM" == "high" ]]; then
    repA=3; repB=3; repC=2
  fi

  # late program preserved (Day11 expected to use low, but keep compatibility)
  if [[ "$PROBE_PROGRAM" == "late" ]]; then
    local idle=$(( (RECOVERY_R2_SEC*2)/3 ))
    local active=$(( RECOVERY_R2_SEC - idle ))
    echo "$(date +%s%N) R2_LATE_IDLE seconds=$idle actions=$PROBE_ACTIONS" >> "$probes_log"
    sleep "$idle"
    echo "$(date +%s%N) R2_LATE_ACTIVE seconds=$active actions=$PROBE_ACTIONS" >> "$probes_log"

    # split active into 3 parts; run only selected actions, otherwise sleep the window
    local w1=$((active/3))
    local w2=$((active/3))
    local w3=$((active - w1 - w2))

    if has_action A; then run_probe_window "$w1" A "$repA" >> "$probes_log" 2>&1 || true; else echo "$(date +%s%N) SKIP_PROBE_A seconds=$w1" >> "$probes_log"; sleep "$w1"; fi
    if has_action B; then run_probe_window "$w2" B "$repB" >> "$probes_log" 2>&1 || true; else echo "$(date +%s%N) SKIP_PROBE_B seconds=$w2" >> "$probes_log"; sleep "$w2"; fi
    if has_action C; then run_probe_window "$w3" C "$repC" >> "$probes_log" 2>&1 || true; else echo "$(date +%s%N) SKIP_PROBE_C seconds=$w3" >> "$probes_log"; sleep "$w3"; fi
    return
  fi

  echo "$(date +%s%N) R2_IDLE_A seconds=$R2_IDLE_A_SEC actions=$PROBE_ACTIONS" >> "$probes_log"
  sleep "$R2_IDLE_A_SEC"
  if has_action A; then
    run_probe_window "$R2_PROBE_A_SEC" A "$repA" >> "$probes_log" 2>&1 || true
  else
    echo "$(date +%s%N) SKIP_PROBE_A seconds=$R2_PROBE_A_SEC" >> "$probes_log"
    sleep "$R2_PROBE_A_SEC"
  fi

  echo "$(date +%s%N) R2_IDLE_B seconds=$R2_IDLE_B_SEC actions=$PROBE_ACTIONS" >> "$probes_log"
  sleep "$R2_IDLE_B_SEC"
  if has_action B; then
    run_probe_window "$R2_PROBE_B_SEC" B "$repB" >> "$probes_log" 2>&1 || true
  else
    echo "$(date +%s%N) SKIP_PROBE_B seconds=$R2_PROBE_B_SEC" >> "$probes_log"
    sleep "$R2_PROBE_B_SEC"
  fi

  echo "$(date +%s%N) R2_IDLE_C seconds=$R2_IDLE_C_SEC actions=$PROBE_ACTIONS" >> "$probes_log"
  sleep "$R2_IDLE_C_SEC"
  if has_action C; then
    run_probe_window "$R2_PROBE_C_SEC" C "$repC" >> "$probes_log" 2>&1 || true
  else
    echo "$(date +%s%N) SKIP_PROBE_C seconds=$R2_PROBE_C_SEC" >> "$probes_log"
    sleep "$R2_PROBE_C_SEC"
  fi
}

# Background IO control (kept)
start_bgio() {
  local cycle_dir="$1"
  if [[ "$ENABLE_BGIO" != "1" ]]; then
    echo "$(date +%s%N) BGIO_DISABLED" >> "$cycle_dir/bgio.log"
    return
  fi

  mkdir -p "$BGIO_DIR"
  ( cd "$SCRIPTS_DIR" && \
      env BGIO_DIR="$BGIO_DIR" \
          BGIO_JOB="$BGIO_JOB" \
          BGIO_RUNTIME="$RECOVERY_R2_SEC" \
      bash "$BGIO_SCRIPT" ) \
    >> "$cycle_dir/bgio.log" 2>&1 &

  echo $! > "$cycle_dir/bgio.pid"
}

stop_bgio() {
  local cycle_dir="$1"
  echo "$(date +%s%N) BGIO_STOP_REQUEST" >> "$cycle_dir/bgio.log" || true

  if [[ -f "$cycle_dir/bgio.pid" ]]; then
    local pid
    pid="$(cat "$cycle_dir/bgio.pid")"
    echo "$(date +%s%N) BGIO_STOP pid=$pid" >> "$cycle_dir/bgio.log" || true

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true

    echo "$(date +%s%N) BGIO_STOP_DONE pid=$pid" >> "$cycle_dir/bgio.log" || true
  else
    echo "$(date +%s%N) BGIO_STOP_NO_PID" >> "$cycle_dir/bgio.log" || true
  fi
}

# Telemetry control (new)
start_telemetry() {
  local cycle_dir="$1"
  if [[ "$ENABLE_TELEMETRY" != "1" ]]; then
    echo "$(date +%s%N) TELEMETRY_DISABLED" >> "$cycle_dir/telemetry.log"
    return
  fi

  if [[ ! -x "$TELEM_SCRIPT" ]]; then
    echo "[ERROR] Telemetry script not executable: $TELEM_SCRIPT"
    exit 1
  fi

  ( cd "$SCRIPTS_DIR" && \
      env TELEM_INTERVAL="$TELEM_INTERVAL" TELEM_DEV="$TELEM_DEV" bash "$TELEM_SCRIPT" ) \
    >> "$cycle_dir/telemetry.log" 2>&1 &

  echo $! > "$cycle_dir/telemetry.pid"
  echo "$(date +%s%N) TELEMETRY_START pid=$(cat "$cycle_dir/telemetry.pid") interval=$TELEM_INTERVAL dev=$TELEM_DEV" >> "$cycle_dir/telemetry.log"
}

stop_telemetry() {
  local cycle_dir="$1"
  if [[ "$ENABLE_TELEMETRY" != "1" ]]; then
    return
  fi

  if [[ -f "$cycle_dir/telemetry.pid" ]]; then
    local pid
    pid="$(cat "$cycle_dir/telemetry.pid")"
    echo "$(date +%s%N) TELEMETRY_STOP pid=$pid" >> "$cycle_dir/telemetry.log" || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo "$(date +%s%N) TELEMETRY_STOP_DONE pid=$pid" >> "$cycle_dir/telemetry.log" || true
  fi
}

apply_mode() {
  case "$MODE" in
    A) ENABLE_PROBES=0; ENABLE_BGIO=0 ;;
    B) ENABLE_PROBES=1; ENABLE_BGIO=0 ;;
    C) ENABLE_PROBES=0; ENABLE_BGIO=1 ;;
    D) ENABLE_PROBES=1; ENABLE_BGIO=1 ;;
    *) echo "[ERROR] Unknown MODE=$MODE (use A/B/C/D)"; exit 1 ;;
  esac
}

cleanup() {
  [[ -f "$HB_PIDFILE" ]] && kill "$(cat "$HB_PIDFILE")" 2>/dev/null || true
  [[ -f "$MI_PIDFILE" ]] && kill "$(cat "$MI_PIDFILE")" 2>/dev/null || true
}
trap cleanup EXIT

apply_mode

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
  start_bgio "$CYCLE_DIR"
  start_telemetry "$CYCLE_DIR"
  run_r2_probes "$CYCLE_DIR/probes.log"
  stop_telemetry "$CYCLE_DIR"
  stop_bgio "$CYCLE_DIR"
  mark "C${c}_RECOVERY_R2_END"

  mark "C${c}_POSTBASELINE_START"
  sleep "$POSTBASELINE_SEC"
  mark "C${c}_POSTBASELINE_END"
done

echo "[INFO] Run complete: $RUN_DIR"
