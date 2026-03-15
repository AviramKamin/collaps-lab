#!/usr/bin/env bash
set -euo pipefail

# Day14 fine telemetry
# Higher-frequency R2 sampling focused on short persistence-boundary events.


TELEM_INTERVAL="${TELEM_INTERVAL:-0.2}"
TELEM_DEV="${TELEM_DEV:-mmcblk0}"

# Selected vmstat fields (absolute counters; we will output deltas)
VM_FIELDS=(
  nr_dirty
  nr_writeback
  pgscan_kswapd
  pgscan_direct
  pgsteal_kswapd
  pgsteal_direct
  pswpin
  pswpout
)

read_psi() {
  # prints: prefix_some_avg10 prefix_full_avg10
  local prefix="$1"
  local path="$2"
  local some_avg10="0.00"
  local full_avg10="0.00"

  # some line
  if read -r line < <(grep -m1 '^some ' "$path" 2>/dev/null || true); then
    some_avg10="$(sed -n 's/.*avg10=\([0-9.]*\).*/\1/p' <<<"$line")"
    [[ -n "$some_avg10" ]] || some_avg10="0.00"
  fi

  # full line
  if read -r line < <(grep -m1 '^full ' "$path" 2>/dev/null || true); then
    full_avg10="$(sed -n 's/.*avg10=\([0-9.]*\).*/\1/p' <<<"$line")"
    [[ -n "$full_avg10" ]] || full_avg10="0.00"
  fi

  printf "%s_some_avg10=%s %s_full_avg10=%s " "$prefix" "$some_avg10" "$prefix" "$full_avg10"
}

read_meminfo_kb() {
  local key="$1"
  awk -v k="$key" '$1==k":" {print $2; exit}' /proc/meminfo 2>/dev/null || echo 0
}

declare -A vm_prev
read_vmstat() {
  local out=""
  while read -r k v; do
    for want in "${VM_FIELDS[@]}"; do
      if [[ "$k" == "$want" ]]; then
        local prev="${vm_prev[$k]:-0}"
        local d=$((v - prev))
        vm_prev[$k]="$v"
        out+="${k}_d=${d} "
      fi
    done
  done < /proc/vmstat
  printf "%s" "$out"
}

# diskstats: we output deltas for writes + queue time
disk_prev_wios=0
disk_prev_wticks=0
disk_prev_ioticks=0
disk_prev_wq=0

read_diskstats() {
  # fields for Linux diskstats:
  # 1 major 2 minor 3 name
  # 4 reads completed
  # 5 reads merged
  # 6 sectors read
  # 7 time reading (ms)
  # 8 writes completed
  # 9 writes merged
  # 10 sectors written
  # 11 time writing (ms)
  # 12 I/Os in progress
  # 13 time doing I/Os (ms)
  # 14 weighted time doing I/Os (ms)
  local line
  line="$(awk -v dev="$TELEM_DEV" '$3==dev {print; exit}' /proc/diskstats 2>/dev/null || true)"
  if [[ -z "$line" ]]; then
    printf "disk_wios_d=0 disk_wticks_d=0 disk_ioticks_d=0 disk_wq_d=0 "
    return
  fi

  # shellcheck disable=SC2206
  local f=($line)
  local wios="${f[7]}"
  local wticks="${f[10]}"
  local ioticks="${f[12]}"
  local wq="${f[13]}"

  local dwios=$((wios - disk_prev_wios))
  local dwticks=$((wticks - disk_prev_wticks))
  local dioticks=$((ioticks - disk_prev_ioticks))
  local dwq=$((wq - disk_prev_wq))

  disk_prev_wios="$wios"
  disk_prev_wticks="$wticks"
  disk_prev_ioticks="$ioticks"
  disk_prev_wq="$wq"

  printf "disk_wios_d=%s disk_wticks_d=%s disk_ioticks_d=%s disk_wq_d=%s " "$dwios" "$dwticks" "$dioticks" "$dwq"
}

# initialize prev values
read_vmstat >/dev/null
read_diskstats >/dev/null

while true; do
  sleep "$TELEM_INTERVAL"
  ts="$(date +%s%N)"

  cpu_psi="$(read_psi cpu /proc/pressure/cpu)"
  io_psi="$(read_psi io /proc/pressure/io)"
  mem_psi="$(read_psi mem /proc/pressure/memory)"

  memavail="$(read_meminfo_kb MemAvailable)"
  dirty="$(read_meminfo_kb Dirty)"
  writeback="$(read_meminfo_kb Writeback)"

  vm_deltas="$(read_vmstat)"
  disk_deltas="$(read_diskstats)"

  printf "%s %smemavail_kb=%s dirty_kb=%s writeback_kb=%s %s%s\n" \
    "$ts" \
    "${cpu_psi}${io_psi}${mem_psi}" \
    "$memavail" "$dirty" "$writeback" \
    "$vm_deltas" "$disk_deltas"
done