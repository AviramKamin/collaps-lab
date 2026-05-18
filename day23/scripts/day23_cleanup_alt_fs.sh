#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-$HOME/project/day23}"
ALT_MOUNT="${ALT_MOUNT:-$BASE_DIR/altfs_mount}"

if mountpoint -q "$ALT_MOUNT"; then
  echo "[INFO] Unmounting $ALT_MOUNT"
  sudo umount "$ALT_MOUNT"
else
  echo "[INFO] Not mounted: $ALT_MOUNT"
fi
