#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "$0")"

BGIO_DIR="${BGIO_DIR:?BGIO_DIR not set}"
BGIO_JOB="${BGIO_JOB:-./bgio.fio}"
BGIO_RUNTIME="${BGIO_RUNTIME:?BGIO_RUNTIME not set}"

mkdir -p "$BGIO_DIR"

echo "$(date +%s%N) BGIO_START runtime=${BGIO_RUNTIME}s dir=${BGIO_DIR} job=${BGIO_JOB}"
fio "$BGIO_JOB" --directory="$BGIO_DIR" --time_based=1 --runtime="$BGIO_RUNTIME"
echo "$(date +%s%N) BGIO_END"
