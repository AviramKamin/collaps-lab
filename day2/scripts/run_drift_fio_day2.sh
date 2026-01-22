#!/usr/bin/env bash
set -euo pipefail

# Day 2 drift injector: increase concurrency (numjobs=2), keep iodepth=1.
# This script is intentionally conservative: one knob change only.

DURATION_SEC="${1:-600}"

# REQUIRED: where fio should write.
# Example: export FIO_TARGET=/home/observer/sys-observe/experiments/fiofile.dat
: "${FIO_TARGET:?You must set FIO_TARGET to a writable file path for fio (example: export FIO_TARGET=...)}"

# Safe defaults (match Day 1 intent)
BS="${BS:-4k}"
RW="${RW:-randwrite}"
IODEPTH="${IODEPTH:-1}"
NUMJOBS="${NUMJOBS:-2}"          # Day 2 knob change (was 1 in Day 1)
SIZE="${SIZE:-512M}"             # initial file size if it needs to be created
DIRECT="${DIRECT:-1}"
TIME_BASED="${TIME_BASED:-1}"
ENGINE="${ENGINE:-libaio}"

command -v fio >/dev/null 2>&1 || { echo "ERROR: fio not found in PATH"; exit 1; }

echo "Day 2 drift injector starting"
echo "duration_sec=${DURATION_SEC}"
echo "target=${FIO_TARGET}"
echo "rw=${RW} bs=${BS} iodepth=${IODEPTH} numjobs=${NUMJOBS} size=${SIZE} direct=${DIRECT} engine=${ENGINE}"

fio \
  --name=day2_drift \
  --filename="${FIO_TARGET}" \
  --rw="${RW}" \
  --bs="${BS}" \
  --iodepth="${IODEPTH}" \
  --numjobs="${NUMJOBS}" \
  --size="${SIZE}" \
  --direct="${DIRECT}" \
  --ioengine="${ENGINE}" \
  --time_based="${TIME_BASED}" \
  --runtime="${DURATION_SEC}" \
  --group_reporting

echo "Day 2 drift injector done"
