cat > ~/sys-observe/day1/run_day1.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$HOME/sys-observe"
LOGDIR="$ROOT/logs/day1"
mkdir -p "$LOGDIR"

TS="$(date +%Y%m%d_%H%M%S)"
THERM="$LOGDIR/day1_thermal_${TS}.log"
HB="$LOGDIR/day1_heartbeat_${TS}.log"

THERM_LOGGER="$ROOT/baseline/thermal_fan_logger.sh"
HB_LOGGER="$ROOT/baseline/heartbeat_logger.sh"
DRIFT="$ROOT/day1/scripts/run_drift_fio.sh"

PRE_SEC="${PRE_SEC:-120}"
DRIFT_SEC="${DRIFT_SEC:-600}"
POST_SEC="${POST_SEC:-120}"

[[ -x "$THERM_LOGGER" ]] || { echo "ERROR: missing or not executable: $THERM_LOGGER"; exit 1; }
[[ -x "$HB_LOGGER" ]] || { echo "ERROR: missing or not executable: $HB_LOGGER"; exit 1; }
[[ -x "$DRIFT" ]] || { echo "ERROR: missing or not executable: $DRIFT"; exit 1; }

echo "Day 1 run starting"
echo "thermal log:   $THERM"
echo "heartbeat log: $HB"
echo "pre=${PRE_SEC}s drift=${DRIFT_SEC}s post=${POST_SEC}s"

"$THERM_LOGGER" > "$THERM" &
PID_T=$!
"$HB_LOGGER" > "$HB" &
PID_H=$!

cleanup() {
  echo "Stopping loggers..."
  kill "$PID_T" "$PID_H" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "Pre drift window..."
sleep "$PRE_SEC"

echo "Running drift injector..."
"$DRIFT" "$DRIFT_SEC"

echo "Post drift window..."
sleep "$POST_SEC"

echo "Done. Output files:"
ls -lh "$THERM" "$HB"
EOF

chmod +x ~/sys-observe/day1/run_day1.sh
chmod +x ~/sys-observe/day1/scripts/run_drift_fio.sh
