#!/usr/bin/env bash
set -euo pipefail

BASE_DIR="${BASE_DIR:-$HOME/project/day23}"
ALT_IMG="${ALT_IMG:-$BASE_DIR/altfs/day23_altfs.img}"
ALT_MOUNT="${ALT_MOUNT:-$BASE_DIR/altfs_mount}"
ALT_SIZE_MB="${ALT_SIZE_MB:-256}"

mkdir -p "$(dirname "$ALT_IMG")" "$ALT_MOUNT"

if mountpoint -q "$ALT_MOUNT"; then
  echo "[INFO] Mount point already active: $ALT_MOUNT"
  findmnt "$ALT_MOUNT"
  exit 0
fi

if [[ ! -f "$ALT_IMG" ]]; then
  echo "[INFO] Creating loopback image: $ALT_IMG (${ALT_SIZE_MB}MB)"
  truncate -s "${ALT_SIZE_MB}M" "$ALT_IMG"
  mkfs.ext4 -F "$ALT_IMG"
fi

echo "[INFO] Mounting alternate disk-backed filesystem with reduced journal/writeback behavior"
sudo mount -o loop,data=writeback,commit=1,noatime "$ALT_IMG" "$ALT_MOUNT"
sudo chown -R "$USER:$USER" "$ALT_MOUNT"
mkdir -p "$ALT_MOUNT/retry_test"

echo "[INFO] Alternate target ready:"
echo "ALT_DISK_RETRY_TARGET=$ALT_MOUNT/retry_test"
findmnt "$ALT_MOUNT"
