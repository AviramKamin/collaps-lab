#!/usr/bin/env bash
set -euo pipefail

# Prints the hwmon directory for the cooling fan (contains pwm1_enable, pwm1, fan1_input)
FANDIR="$(dirname "$(find /sys/devices/platform/cooling_fan -type f -name pwm1_enable 2>/dev/null | head -n 1)")"

if [[ -z "${FANDIR}" || ! -d "${FANDIR}" ]]; then
  echo "ERROR: fan hwmon directory not found." >&2
  exit 1
fi

# Sanity check required files exist
for f in pwm1_enable pwm1 fan1_input name; do
  if [[ ! -e "${FANDIR}/${f}" ]]; then
    echo "ERROR: missing ${FANDIR}/${f}" >&2
    exit 1
  fi
done

echo "${FANDIR}"
