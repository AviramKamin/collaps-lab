# Collapse Lab – System Observation Experiments

This repository contains controlled system-level collapse experiments conducted on a Raspberry Pi.

The project explores how real systems degrade *before* failure, focusing on timing distortion, retry amplification, and recovery behavior under sustained pressure.

This is **not a benchmarking project**.
It is an observational lab for understanding *system rot*.

---

## Core Questions

This project studies:

- Timing drift under load
- Retry storms and feedback amplification
- Recovery dynamics after pressure
- Collapse memory and hysteresis
- Reversibility vs irreversible degradation

The central question is:

**Does a system fully reset after stress, or does collapse leave residue?**

---

## Experiment Model

All experiments follow a consistent cycle:

1. **Baseline** – system at rest
2. **Intervention** – controlled pressure (I/O bursts, retry storms)
3. **Recovery** – pressure removed
4. **Post-baseline probe** – comparison against original baseline

Repeated cycles are used to detect:
- drift
- degradation
- memory effects
- reduced collapse thresholds

---

## Repository Structure
for example: 
day5/
runs/ # raw experiment outputs (heartbeat, retries, markers)
scripts/ # experiment runners and load generators
notes.md # hypothesis, design, results, conclusions


All data is **raw and reproducible**.  
No post-processing or smoothing has been applied.

---

## Current Status

- Day 5: Collapse memory experiments – **complete**
- Day 6: Extended hysteresis and recovery analysis – **planned**

---

## Reproducibility

Each run directory contains:

- `heartbeat.log` – high-resolution timing measurements
- `heartbeat_marks.log` – phase boundaries
- `retries.log` – retry storm triggers per cycle
- `meta.env` – full run configuration

Experiments can be replayed using the scripts under `day5/scripts`.

---

## Notes

This project is intentionally low-level.
It prioritizes observation, signal emergence, and behavioral patterns over synthetic benchmarks.

## Who This Is For

This project is intended for system engineers, SREs, and QA engineers who care about *behavior under stress*, not just functional correctness.

It is relevant to anyone working with systems where timing, retries, queues, or recovery behavior matter — distributed systems, embedded platforms, networking stacks, storage layers, or hardware–software integration.

This is **not** aimed at UI testing, application-level QA, or performance benchmarking in isolation.
It is for engineers who want to understand *how systems degrade*, *how collapse propagates*, and *why recovery is often imperfect* even when load is removed.
