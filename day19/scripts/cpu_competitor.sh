#!/usr/bin/env bash
set -euo pipefail

echo "$(date +%s%N) cpu_competitor_start pid=$$"
# Deliberately pure CPU pressure. No sleeps, no IO, no logging in the loop.
while :; do
  :
done
