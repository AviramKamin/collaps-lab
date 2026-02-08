#!/usr/bin/env bash
set -euo pipefail

RUNS_DIR="${1:-$HOME/project/day8/runs}"

echo "run_name | off | probes | program | fileMB | cycles | marks | hb_lines | mem_lines | cycles_present | retry_outside_dtms"
echo "-------- | --- | ------ | ------- | ------ | ------ | ----- | -------- | --------- | ------------- | ------------------"

shopt -s nullglob
for d in "$RUNS_DIR"/*_day8_off*_n*; do
  [ -d "$d" ] || continue
  run="$(basename "$d")"
  meta="$d/meta.env"
  marks="$d/heartbeat_marks.log"
  hb="$d/heartbeat.log"
  mem="$d/meminfo.log"

  # Defaults if missing
  off="?"
  probes="?"
  program="?"
  filemb="?"
  cycles="?"

  if [ -f "$meta" ]; then
    off="$(awk -F= '$1=="OFF_SEC"{print $2}' "$meta" | tail -n1)"
    probes="$(awk -F= '$1=="ENABLE_PROBES"{print $2}' "$meta" | tail -n1)"
    program="$(awk -F= '$1=="PROBE_PROGRAM"{print $2}' "$meta" | tail -n1)"
    filemb="$(awk -F= '$1=="PROBE_FILE_MB"{print $2}' "$meta" | tail -n1)"
    cycles="$(awk -F= '$1=="N_CYCLES"{print $2}' "$meta" | tail -n1)"
  fi

  marks_lines=$([ -f "$marks" ] && wc -l < "$marks" || echo 0)
  hb_lines=$([ -f "$hb" ] && wc -l < "$hb" || echo 0)
  mem_lines=$([ -f "$mem" ] && wc -l < "$mem" || echo 0)

  # cycles present check (based on N_CYCLES, fallback 3)
  n="${cycles:-3}"
  if ! [[ "$n" =~ ^[0-9]+$ ]]; then n=3; fi
  present_ok=1
  for c in $(seq 1 "$n"); do
    [ -d "$d/cycle_$c" ] || present_ok=0
    [ -f "$d/cycle_$c/retries.log" ] || present_ok=0
    [ -f "$d/cycle_$c/bursts.log" ] || present_ok=0
    [ -f "$d/cycle_$c/probes.log" ] || present_ok=0
  done
  cycles_present=$([ "$present_ok" -eq 1 ] && echo "yes" || echo "no")

  # retry containment: count dt_ms lines outside intervention per cycle (sum)
  retry_out=0
  if [ -f "$marks" ]; then
    for c in $(seq 1 "$n"); do
      rlog="$d/cycle_$c/retries.log"
      [ -f "$rlog" ] || continue
      I_START="$(awk -v c="$c" '$2==("C"c"_INTERVENTION_START"){print $1}' "$marks" | tail -n1)"
      I_END="$(awk -v c="$c" '$2==("C"c"_INTERVENTION_END"){print $1}' "$marks" | tail -n1)"
      if [ -n "${I_START:-}" ] && [ -n "${I_END:-}" ]; then
        out_c="$(awk -v s="$I_START" -v e="$I_END" '$2 ~ /^dt_ms=/ { if ($1 < s || $1 > e) out++ } END { print out+0 }' "$rlog")"
        retry_out=$((retry_out + out_c))
      fi
    done
  fi

  echo "$run | $off | $probes | $program | $filemb | $cycles | $marks_lines | $hb_lines | $mem_lines | $cycles_present | $retry_out"
done | sort
