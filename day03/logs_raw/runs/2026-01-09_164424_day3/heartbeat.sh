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
