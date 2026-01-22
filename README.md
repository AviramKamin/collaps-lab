# Collapse Lab

This repository contains system-level collapse experiments conducted on a Raspberry Pi.

The goal of this project is to study:
- timing drift
- retry storms
- recovery dynamics
- collapse memory and reversibility

## Structure

day5/
  runs/       # raw experiment outputs (heartbeat, retry, marks)
  scripts/    # experiment control scripts
  notes.md    # experiment design, hypothesis, results, conclusions

All data is raw and reproducible.
No post-processing has been applied.

## Status

Day 5 complete  
Day 6 planned

## Reproducibility

Each run directory contains:
- heartbeat.log
- heartbeat_marks.log
- retries.log (per cycle)
- meta.env

Experiments can be replayed using the scripts directory.
