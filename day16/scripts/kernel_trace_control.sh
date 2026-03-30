#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-}"
OUTFILE="${2:-}"
TRACE_EVENTS="${TRACE_EVENTS:-sched:sched_switch,sched:sched_wakeup,sched:sched_wakeup_new}"
TRACEFS="/sys/kernel/tracing"
[[ -d "$TRACEFS" ]] || TRACEFS="/sys/kernel/debug/tracing"

if [[ ! -d "$TRACEFS" ]]; then
  echo "[ERROR] tracefs not found" >&2
  exit 1
fi

need_root() {
  if [[ "$EUID" -ne 0 ]]; then
    exec sudo TRACE_EVENTS="$TRACE_EVENTS" bash "$0" "$MODE" "$OUTFILE"
  fi
}

split_events() {
  awk -v s="$TRACE_EVENTS" 'BEGIN{n=split(s,a,","); for(i=1;i<=n;i++) print a[i]}'
}

case "$MODE" in
  start)
    need_root
    mkdir -p "$(dirname "$OUTFILE")"
    echo 0 > "$TRACEFS/tracing_on"
    : > "$TRACEFS/trace"
    : > "$TRACEFS/set_event"
    while IFS= read -r ev; do
      [[ -n "$ev" ]] || continue
      echo "$ev" >> "$TRACEFS/set_event"
    done < <(split_events)
    echo nop > "$TRACEFS/current_tracer" 2>/dev/null || true
    echo 1 > "$TRACEFS/options/overwrite" 2>/dev/null || true
    echo 1 > "$TRACEFS/tracing_on"
    {
      echo "$(date +%s%N) TRACE_START events=$TRACE_EVENTS tracefs=$TRACEFS"
    } >> "$OUTFILE"
    ;;
  stop)
    need_root
    echo 0 > "$TRACEFS/tracing_on"
    {
      echo "$(date +%s%N) TRACE_STOP events=$TRACE_EVENTS tracefs=$TRACEFS"
      cat "$TRACEFS/trace"
    } >> "$OUTFILE"
    : > "$TRACEFS/set_event"
    ;;
  *)
    echo "usage: $0 start|stop <outfile>" >&2
    exit 2
    ;;
esac
