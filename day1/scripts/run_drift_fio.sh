#!/usr/bin/env bash
set -euo pipefail

# Gentle drift: change behavior without collapse.
# This uses direct IO with small blocks, single depth, time-based.

RUNTIME="${1:-600}" # default 10 minutes

# Safety: make file in /tmp so it doesn't wear SD unnecessarily
FILE="${2:-/tmp/fio_drift.dat}"

echo "Starting fio drift for ${RUNTIME}s using ${FILE}"

fio --name=drift \
    --filename="${FILE}" --size=512M \
    --rw=randwrite --bs=4k --iodepth=1 --numjobs=1 \
    --direct=1 --time_based --runtime="${RUNTIME}" --group_reporting
