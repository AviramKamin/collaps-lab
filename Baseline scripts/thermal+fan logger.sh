#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${ROOT_DIR}/logs"
mkdir -p "${LOG_DIR}"

FANDIR="$(bash "${ROOT_DIR}/scripts/fan_path.sh")"

# Force auto mode (2). If your platform refuses 2, this will be visible in logs.
echo 2 | sudo tee "${FANDIR}/pwm1_enable" >/dev/null || true

OUT="${1:-${LOG_DIR}/thermal_$(date +%Y%m%d_%H%M%S).log}"

echo "start_ts=$(date +%s%N)" | tee -a "${OUT}"
echo "FANDIR=${FANDIR}" | tee -a "${OUT}"
echo "format: ts temp throttled pwm_en pwm rpm" | tee -a "${OUT}"

while true; do
  ts="$(date +%s%N)"
  temp="$(vcgencmd measure_temp | tr -d "temp=")"
  thr="$(vcgencmd get_throttled | cut -d= -f2)"
  pwm_en="$(cat "${FANDIR}/pwm1_enable" 2>/dev/null || echo NA)"
  pwm="$(cat "${FANDIR}/pwm1" 2>/dev/null || echo NA)"
  rpm="$(cat "${FANDIR}/fan1_input" 2>/dev/null || echo NA)"

  printf "%s temp=%s throttled=%s pwm_en=%s pwm=%s rpm=%s\n" \
    "${ts}" "${temp}" "${thr}" "${pwm_en}" "${pwm}" "${rpm}" | tee -a "${OUT}"
  sleep 1
done
