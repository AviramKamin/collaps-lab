#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Day14 Runner (Block Layer Visibility and Writeback Interaction)
# Cycle: B -> I -> R1 -> R2(probe B fsync only + fine telemetry + disk watch) -> B2
# Focus: block-layer visibility during persistence-boundary stalls
# ---------------------------

cd -- "$(dirname -- "$0")"
SCRIPTS_DIR="$(pwd)"
PROJECT_DIR="$(cd .. && pwd)"
RUNS_DIR="${PROJECT_DIR}/runs"
WORKDIR="${PROJECT_DIR}/workdir"

mkdir -p "$RUNS_DIR" "$WORKDIR"

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

# ---- Day14 Locked Probe Settings ----
# Keep the known reproducer stable: probe B, low program, fsync on ext4 path
PROBE_PROGRAM="${PROBE_PROGRAM:-low}"          # control|low
PROBE_ACTIONS="B"                              # locked
PROBE_B_VARIANT="${PROBE_B_VARIANT:-fsync}"    # keep fsync for Day14 baseline

PROBE_TMPFS_DIR="${PROBE_TMPFS_DIR:-/dev/shm/probes}"
PROBE_FILE_MB="${PROBE_FILE_MB:-64}"
PROBE_ROOT="${PROBE_ROOT:-$WORKDIR/probes}"
mkdir -p "$PROBE_ROOT"

# R2 shape (kept from Day12 defaults)
R2_IDLE_B_SEC="${R2_IDLE_B_SEC:-60}"
R2_PROBE_B_SEC="${R2_PROBE_B_SEC:-180}"

# ---- Telemetry ----
ENABLE_TELEMETRY="${ENABLE_TELEMETRY:-1}"
TELEM_INTERVAL="${TELEM_INTERVAL:-0.2}"
TELEM_SCRIPT="${TELEM_SCRIPT:-$SCRIPTS_DIR/r2_telemetry_fine.sh}"
TELEM_DEV="${TELEM_DEV:-mmcblk0}"

# ---- Fine block visibility ----
ENABLE_DISK_WATCH="${ENABLE_DISK_WATCH:-1}"
DISK_WATCH_INTERVAL="${DISK_WATCH_INTERVAL:-0.1}"
DISK_WATCH_SCRIPT="${DISK_WATCH_SCRIPT:-$SCRIPTS_DIR/disk_watch.sh}"
DISK_WATCH_DEV="${DISK_WATCH_DEV:-$TELEM_DEV}"

# ---- Mount capture / optional remount controls ----
# If you want the runner to remount before the run, set:
# DO_REMOUNT=1 FS_MNT=/mnt/yourmount FS_OPTS="data=writeback,commit=5"
DO_REMOUNT="${DO_REMOUNT:-0}"
FS_MNT="${FS_MNT:-}"
FS_OPTS="${FS_OPTS:-}"
MOUNT_LABEL="${MOUNT_LABEL:-default}"

# ---- Run directory ----
TS="$(date +%Y-%m-%d_%H%M%S)"
RUN_NAME="${TS}_day14_${MOUNT_LABEL}_off${OFF_SEC}_bvar${PROBE_B_VARIANT}_n${N_CYCLES}"
RUN_DIR="${RUNS_DIR}/${RUN_NAME}"
mkdir -p "$RUN_DIR"

HB_LOG="$RUN_DIR/heartbeat.log"
HB_PIDFILE="$RUN_DIR/heartbeat.pid"
HB_MARKS="$RUN_DIR/heartbeat_marks.log"

MI_LOG="$RUN_DIR/meminfo.log"
MI_PIDFILE="$RUN_DIR/meminfo.pid"

echo "[INFO] Run dir: $RUN_DIR"
echo "[INFO] Cycles: $N_CYCLES | OFF=${OFF_SEC}s | MOUNT_LABEL=$MOUNT_LABEL"
echo "[INFO] Baseline=${BASELINE_SEC}s Intervention=${INTERVENTION_SEC}s R1=${RECOVERY_R1_SEC}s R2=${RECOVERY_R2_SEC}s PostBaseline=${POSTBASELINE_SEC}s"
echo "[INFO] Probe: program=$PROBE_PROGRAM actions=$PROBE_ACTIONS B_variant=$PROBE_B_VARIANT"
echo "[INFO] Probe RT: enabled=$PROBE_RT prio=$PROBE_RT_PRIO"
echo "[INFO] Telemetry: ENABLE_TELEMETRY=$ENABLE_TELEMETRY interval=${TELEM_INTERVAL}s dev=$TELEM_DEV script=$TELEM_SCRIPT"
echo "[INFO] Disk watch: ENABLE_DISK_WATCH=$ENABLE_DISK_WATCH interval=${DISK_WATCH_INTERVAL}s dev=$DISK_WATCH_DEV script=$DISK_WATCH_SCRIPT"

# ---- Optional remount ----
maybe_remount() {
  if [[ "$DO_REMOUNT" != "1" ]]; then
    return
  fi
  if [[ -z "$FS_MNT" || -z "$FS_OPTS" ]]; then
    echo "[ERROR] DO_REMOUNT=1 requires FS_MNT and FS_OPTS"
    exit 2
  fi
  echo "[INFO] Remounting $FS_MNT with opts: $FS_OPTS"
  # requires root or sudo privileges
  if ! mount -o "remount,${FS_OPTS}" "$FS_MNT"; then
    echo "[ERROR] Remount failed. Run as root or configure sudo."
    exit 3
  fi
}

# ---- Capture mount / topology state (critical for reproducibility) ----
capture_mount_state() {
  {
    echo "=== date ==="
    date -Is
    echo
    echo "=== uname ==="
    uname -a
    echo
    echo "=== findmnt WORKDIR ==="
    findmnt -T "$WORKDIR" || true
    echo
    echo "=== findmnt RUNS_DIR ==="
    findmnt -T "$RUNS_DIR" || true
    echo
    echo "=== findmnt PROBE_ROOT ==="
    findmnt -T "$PROBE_ROOT" || true
    echo
    echo "=== findmnt TARGET ==="
    findmnt -T "$TARGET" || true
    echo
    echo "=== mount (filtered: ext4) ==="
    mount | grep -E ' type ext4 ' || true
    echo
    if [[ -n "${FS_MNT}" ]]; then
      echo "=== findmnt FS_MNT ==="
      findmnt "$FS_MNT" || true
    fi
  } > "$RUN_DIR/mount_state.txt"
}

# ---- Save metadata ----
cat > "$RUN_DIR/meta.env" <<META
RUN_NAME=$RUN_NAME
MOUNT_LABEL=$MOUNT_LABEL
DO_REMOUNT=$DO_REMOUNT
FS_MNT=$FS_MNT
FS_OPTS=$FS_OPTS
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
PROBE_PROGRAM=$PROBE_PROGRAM
PROBE_ACTIONS=$PROBE_ACTIONS
PROBE_B_VARIANT=$PROBE_B_VARIANT
PROBE_RT=$PROBE_RT
PROBE_RT_PRIO=$PROBE_RT_PRIO
PROBE_TMPFS_DIR=$PROBE_TMPFS_DIR
PROBE_FILE_MB=$PROBE_FILE_MB
PROBE_ROOT=$PROBE_ROOT
R2_IDLE_B_SEC=$R2_IDLE_B_SEC
R2_PROBE_B_SEC=$R2_PROBE_B_SEC
ENABLE_TELEMETRY=$ENABLE_TELEMETRY
TELEM_INTERVAL=$TELEM_INTERVAL
TELEM_SCRIPT=$TELEM_SCRIPT
TELEM_DEV=$TELEM_DEV
ENABLE_DISK_WATCH=$ENABLE_DISK_WATCH
DISK_WATCH_INTERVAL=$DISK_WATCH_INTERVAL
DISK_WATCH_SCRIPT=$DISK_WATCH_SCRIPT
DISK_WATCH_DEV=$DISK_WATCH_DEV
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

# ---- Probe B only ----
probe_action_B_impl() {
  local ts
  ts="$(date +%s%N)"

  local f_ext4="$PROBE_ROOT/probe_b_${ts}.bin"
  mkdir -p "$PROBE_TMPFS_DIR" 2>/dev/null || true
  local f_tmpfs="$PROBE_TMPFS_DIR/probe_b_${ts}.bin"

  case "$PROBE_B_VARIANT" in
    fsync)
      dd if=/dev/urandom of="$f_ext4" bs=1M count=1 conv=fsync status=none
      ;;
    buffered)
      dd if=/dev/urandom of="$f_ext4" bs=1M count=1 status=none
      ;;
    tmpfs)
      dd if=/dev/urandom of="$f_tmpfs" bs=1M count=1 status=none
      ;;
    sync_only)
      sync
      ;;
    *)
      echo "$(date +%s%N) [ERROR] Unknown PROBE_B_VARIANT=$PROBE_B_VARIANT" >&2
      return 2
      ;;
  esac
}

probe_action_B() {
  if [[ "$PROBE_RT" == "1" ]]; then
    sudo chrt -f "$PROBE_RT_PRIO" bash -c "$(declare -f probe_action_B_impl); probe_action_B_impl"
  else
    probe_action_B_impl
  fi
}

run_probe_window_B_only() {
  local seconds="$1"
  local end=$(( $(date +%s) + seconds ))

  while [[ $(date +%s) -lt $end ]]; do
    printf "%s PROBE_B_START program=%s bvar=%s\n" "$(date +%s%N)" "$PROBE_PROGRAM" "$PROBE_B_VARIANT"
    probe_action_B
    printf "%s PROBE_B_END program=%s bvar=%s\n" "$(date +%s%N)" "$PROBE_PROGRAM" "$PROBE_B_VARIANT"
    sleep 0.2
  done
}

run_r2_probes() {
  local probes_log="$1"

  if [[ "$PROBE_PROGRAM" == "control" ]]; then
    echo "$(date +%s%N) PROBES_DISABLED program=$PROBE_PROGRAM" >> "$probes_log"
    sleep "$RECOVERY_R2_SEC"
    return
  fi

  echo "$(date +%s%N) R2_IDLE_B seconds=$R2_IDLE_B_SEC" >> "$probes_log"
  sleep "$R2_IDLE_B_SEC"

  local active=$(( RECOVERY_R2_SEC - R2_IDLE_B_SEC ))
  if (( active < 1 )); then
    echo "$(date +%s%N) R2_NO_ACTIVE_WINDOW" >> "$probes_log"
    return
  fi

  # Locked to B only
  echo "$(date +%s%N) R2_PROBE_B seconds=$active bvar=$PROBE_B_VARIANT program=$PROBE_PROGRAM" >> "$probes_log"
  run_probe_window_B_only "$active" >> "$probes_log" 2>&1 || true
}

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

  ( cd "$SCRIPTS_DIR" && env TELEM_INTERVAL="$TELEM_INTERVAL" TELEM_DEV="$TELEM_DEV" bash "$TELEM_SCRIPT" ) \
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

start_disk_watch() {
  local cycle_dir="$1"
  if [[ "$ENABLE_DISK_WATCH" != "1" ]]; then
    echo "$(date +%s%N) DISK_WATCH_DISABLED" >> "$cycle_dir/diskstats.log"
    return
  fi
  if [[ ! -x "$DISK_WATCH_SCRIPT" ]]; then
    echo "[ERROR] Disk watch script not executable: $DISK_WATCH_SCRIPT"
    exit 1
  fi

  ( cd "$SCRIPTS_DIR" && env DEV="$DISK_WATCH_DEV" INTERVAL="$DISK_WATCH_INTERVAL" bash "$DISK_WATCH_SCRIPT" )     >> "$cycle_dir/diskstats.log" 2>&1 &
  echo $! > "$cycle_dir/diskstats.pid"
  echo "$(date +%s%N) DISK_WATCH_START pid=$(cat "$cycle_dir/diskstats.pid") interval=$DISK_WATCH_INTERVAL dev=$DISK_WATCH_DEV" >> "$cycle_dir/diskstats.log"
}

stop_disk_watch() {
  local cycle_dir="$1"
  if [[ "$ENABLE_DISK_WATCH" != "1" ]]; then
    return
  fi
  if [[ -f "$cycle_dir/diskstats.pid" ]]; then
    local pid
    pid="$(cat "$cycle_dir/diskstats.pid")"
    echo "$(date +%s%N) DISK_WATCH_STOP pid=$pid" >> "$cycle_dir/diskstats.log" || true
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    echo "$(date +%s%N) DISK_WATCH_STOP_DONE pid=$pid" >> "$cycle_dir/diskstats.log" || true
  fi
}

cleanup() {
  [[ -f "$HB_PIDFILE" ]] && kill "$(cat "$HB_PIDFILE")" 2>/dev/null || true
  [[ -f "$MI_PIDFILE" ]] && kill "$(cat "$MI_PIDFILE")" 2>/dev/null || true
}
trap cleanup EXIT

# Execute remount if requested, then capture mount state
maybe_remount
capture_mount_state

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
  start_telemetry "$CYCLE_DIR"
  start_disk_watch "$CYCLE_DIR"
  run_r2_probes "$CYCLE_DIR/probes.log"
  stop_disk_watch "$CYCLE_DIR"
  stop_telemetry "$CYCLE_DIR"
  mark "C${c}_RECOVERY_R2_END"

  mark "C${c}_POSTBASELINE_START"
  sleep "$POSTBASELINE_SEC"
  mark "C${c}_POSTBASELINE_END"
done

echo "[INFO] Run complete: $RUN_DIR"