#!/usr/bin/env bash
set -euo pipefail

# Day 3 Runner
# Baseline -> Intervention -> Recovery
# Runs from scripts dir, writes outputs into ../runs/<timestamp>_day3

cd -- "$(dirname -- "$0")"
SCRIPTS_DIR="$(pwd)"
PROJECT_DIR="$(cd .. && pwd)"
RUNS_DIR="${PROJECT_DIR}/runs"
WORKDIR="${PROJECT_DIR}/workdir"

# Phase durations (seconds)
BASELINE_SEC="${BASELINE_SEC:-360}"           # 6m
INTERVENTION_SEC="${INTERVENTION_SEC:-900}"   # 15m
RECOVERY_SEC="${RECOVERY_SEC:-600}"           # 10m

# Heartbeat interval
HB_INTERVAL="${HB_INTERVAL:-0.1}"

# Targets default to a writable location
STORM_TARGET="${STORM_TARGET:-${WORKDIR}/retry_test}"
FIO_TARGET="${FIO_TARGET:-${WORKDIR}/fiofile}"

# Tunables
STORM_BUDGET_MS="${STORM_BUDGET_MS:-50}"
STORM_RETRIES="${STORM_RETRIES:-5}"
BURSTS="${BURSTS:-50}"
BURST_ON_SEC="${BURST_ON_SEC:-3}"
BURST_OFF_SEC="${BURST_OFF_SEC:-2}"

timestamp="$(date +%F_%H%M%S)"
RUN_DIR="${RUNS_DIR}/${timestamp}_day3"

log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
die() { echo "[ERROR] $*" >&2; exit 1; }

require_exec() {
  [[ -x "$1" ]] || die "Missing or not executable: $1"
}

# -------- preflight --------
mkdir -p "$RUN_DIR" "$WORKDIR" || die "Cannot create run/work dirs"
mkdir -p "$STORM_TARGET" || die "Cannot create STORM_TARGET=$STORM_TARGET"

# make sure scripts are executable
chmod +x "${SCRIPTS_DIR}"/*.sh 2>/dev/null || true

require_exec "${SCRIPTS_DIR}/run_bursts.sh"
require_exec "${SCRIPTS_DIR}/retry_storm.sh"

# Export knobs for child scripts (if they read env)
export BURSTS BURST_ON_SEC BURST_OFF_SEC
export STORM_TARGET STORM_BUDGET_MS STORM_RETRIES
export FIO_TARGET

cd "$RUN_DIR"

log "Run dir: $RUN_DIR"
log "Baseline ${BASELINE_SEC}s | Intervention ${INTERVENTION_SEC}s | Recovery ${RECOVERY_SEC}s"
log "HB interval: ${HB_INTERVAL}s"
log "STORM_TARGET: $STORM_TARGET"
log "FIO_TARGET: $FIO_TARGET"
log "Storm budget ${STORM_BUDGET_MS}ms retries ${STORM_RETRIES}"
log "Bursts ${BURSTS} on ${BURST_ON_SEC}s off ${BURST_OFF_SEC}s"

{
  echo "timestamp=$timestamp"
  echo "hostname=$(hostname)"
  echo "uname=$(uname -a)"
  echo "whoami=$(whoami)"
  echo "scripts_dir=$SCRIPTS_DIR"
  echo "project_dir=$PROJECT_DIR"
  echo "run_dir=$RUN_DIR"
  echo "BASELINE_SEC=$BASELINE_SEC"
  echo "INTERVENTION_SEC=$INTERVENTION_SEC"
  echo "RECOVERY_SEC=$RECOVERY_SEC"
  echo "HB_INTERVAL=$HB_INTERVAL"
  echo "STORM_TARGET=$STORM_TARGET"
  echo "FIO_TARGET=$FIO_TARGET"
  echo "STORM_BUDGET_MS=$STORM_BUDGET_MS"
  echo "STORM_RETRIES=$STORM_RETRIES"
  echo "BURSTS=$BURSTS"
  echo "BURST_ON_SEC=$BURST_ON_SEC"
  echo "BURST_OFF_SEC=$BURST_OFF_SEC"
} > meta.env

# Heartbeat logger
cat > heartbeat.sh <<'HBEOF'
#!/usr/bin/env bash
set -euo pipefail
interval="${1:-0.1}"
while true; do
  t0=$(date +%s%N)
  sleep "$interval"
  t1=$(date +%s%N)
  dt=$((t1 - t0))
  echo "$t1 $dt"
done
HBEOF
chmod +x heartbeat.sh

stop_pidfile() {
  local pidfile="$1"
  [[ -f "$pidfile" ]] || return 0
  local pid
  pid="$(cat "$pidfile" 2>/dev/null || true)"
  [[ -n "${pid:-}" ]] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    # give it a moment to exit
    for _ in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.2
    done
    # hard kill if needed
    kill -9 "$pid" 2>/dev/null || true
  fi
}

cleanup_on_exit() {
  # only stop intervention processes if still alive
  stop_pidfile bursts.pid
  stop_pidfile retries.pid
}
trap cleanup_on_exit EXIT

# -------- run --------
log "Starting heartbeat"
./heartbeat.sh "$HB_INTERVAL" > heartbeat.log &
echo $! > heartbeat.pid

log "Baseline window"
sleep "$BASELINE_SEC"

log "Starting intervention"
"${SCRIPTS_DIR}/run_bursts.sh" > bursts.log 2>&1 &
echo $! > bursts.pid

"${SCRIPTS_DIR}/retry_storm.sh" > retries.log 2>&1 &
echo $! > retries.pid

sleep "$INTERVENTION_SEC"

log "Stopping intervention"
stop_pidfile bursts.pid
stop_pidfile retries.pid

log "Recovery window"
sleep "$RECOVERY_SEC"

log "Stopping heartbeat"
stop_pidfile heartbeat.pid

trap - EXIT

log "Outputs:"
ls -lh
log "Run complete: $RUN_DIR"
