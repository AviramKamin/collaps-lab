Day 7: Recovery Sensitivity and Probe-Induced Destabilization
--------------------------------------------------------------
hypothesis
-----------
In light of Day 6 results showing that collapse memory is expressed through altered recovery structure rather than persistent steady-state degradation, 
we hypothesize that the recovery phase itself constitutes a fragile and metastable system state.

Specifically, we hypothesize that:
During recovery, the system exhibits heightened sensitivity to otherwise benign, localized perturbations.
Small probes applied during recovery can induce disproportionate latency spikes or coordination failures that are not observed when the same probes are applied during baseline or post-recovery steady-state operation.
This sensitivity decays over time, such that once recovery is complete, identical probes no longer produce anomalous effects, even if steady-state metrics appear similar.
In this framing, collapse memory is not only encoded in recovery structure, but also in recovery susceptibility:
the degree to which recovery can be disrupted by minimal external interaction.

Experimental objective
-----------------------
To determine whether the recovery phase represents a uniquely sensitive system state, distinct from both collapse and steady-state operation.

Day 7 tests whether:

Identical probes produce phase-dependent effects

Recovery phases exhibit increased spike amplitude, variance, or coordination failures relative to baseline

Probe-induced effects during recovery are repeatable and structured, rather than random noise

Probe sensitivity diminishes as recovery progresses

Method Overview
----------------
Day 7 extends the Day 6 recovery framework by introducing controlled, low-intensity probes during recovery.
The experiment separates recovery into two phases:
R1: Passive recovery (no probes)
R2: Active recovery with structured probes
The same collapse forcing is used across all cycles to isolate recovery behavior as the variable of interest.

Cycle Definition
------------------
Each cycle consists of the following ordered stages:

Baseline (B)
Heartbeat sampling
Optional meminfo sampling
No IO
No retries
Purpose: establish steady-state reference behavior

Intervention (I)
Identical to Day 5 and Day 6
Fixed IO bursts and retry storm
Purpose: induce collapse under controlled conditions

Recovery Phase 1 (R1 – Passive Recovery)
Heartbeat sampling
No IO
No probes
Purpose: allow initial recovery without disturbance

Recovery Phase 2 (R2 – Probed Recovery)
Heartbeat sampling
Structured, low-intensity probes applied at predefined intervals
Purpose: test recovery sensitivity to minimal perturbations

Post-Recovery Baseline (B2)
Heartbeat sampling
No IO
No probes
Purpose: verify return to steady-state behavior

Cycle notation:
B → I → R1 → R2 → B2

Probes
--------
Probes are designed to be:
Localized
Short-lived
Low resource intensity
Examples include:
Small file creation and cache interaction
Minimal IO touches
Lightweight filesystem activity
Probes are not intended to cause collapse, only to test susceptibility.

Metrics Collected
---------------
Heartbeat

dt_ns samples

p95, p99

max latency

spike frequency and amplitude

Probe Interaction

Temporal alignment between probes and latency spikes

Recovery-stage-specific response patterns

Optional:

meminfo as a secondary hidden-state signal (not a primary success metric)

Results
--------
Overview:
Day 7 executed repeated collapse cycles with structured, low-intensity probes applied during recovery.
Probes were deliberately designed to be benign under normal conditions and were identical across system phases.
Across all runs (OFF = 3, OFF = 2; N = 3 cycles), the following conditions were verified:
All logs were complete and phase-aligned
Probe activity was strictly confined to R2 windows
No IO or retry activity leaked into baseline or post-recovery phases
Timestamp monotonicity and phase containment were preserved
Baseline and Post-Recovery Probe Response
During Baseline (B) and Post-Recovery Baseline (B2):
Probe activity did not produce measurable heartbeat spikes
Heartbeat max latency remained within the normal baseline envelope
No clustering of latency spikes around probe timestamps was observed


Observation:
Identical probes were effectively invisible to the system outside of recovery.
Recovery Phase Sensitivity (R2)
During Recovery Phase 2 (R2), when probes were introduced:
Heartbeat max latency increased sharply relative to baseline
Large, isolated latency spikes appeared temporally aligned with probe execution
These spikes were not reflected in p95 or p99 metrics due to their rarity
Spike amplitude during R2 exceeded baseline and post-recovery levels by orders of magnitude

Critically:
The same probes that were harmless during baseline produced disproportionate effects during recovery.
Temporal Decay of Sensitivity
Within each recovery window:
Probe-induced spike amplitude decreased over time
Early R2 probes produced larger and more frequent spikes than later probes
By the end of R2 and into B2, probe effects diminished or disappeared

Observation:
Recovery sensitivity is transient and decays as recovery progresses.
Repeatability Across Cycles
Across cycles within the same OFF configuration:
Probe-induced spike patterns were consistent in structure
Sensitivity did not monotonically worsen across cycles
Recovery susceptibility appeared stable rather than cumulative

Observation:
Recovery sensitivity represents a repeatable system property, not accumulating damage.

Conclusions
------------
Day 7 results support the hypothesis that recovery constitutes a fragile and metastable system phase.
Specifically:
Recovery exhibits heightened sensitivity to otherwise benign perturbations
Identical probes produce phase-dependent effects
Recovery can appear complete by steady-state metrics while remaining structurally vulnerable
Sensitivity decays over time, indicating gradual stabilization rather than instantaneous recovery
Importantly, these effects are invisible to percentile-based monitoring and would be missed by conventional health checks.
Interpretation
Collapse memory is not only encoded in recovery structure (Day 6), but also in recovery susceptibility.
The system retains a transient vulnerability window during which minimal interactions can trigger disproportionate coordination failures.
Recovery should therefore be treated as an active, vulnerable process rather than a binary success state.
Implications
------------
These findings suggest that:

Systems may pass health checks while remaining operationally fragile

Recovery actions themselves can influence observed stability

Monitoring strategies must consider recovery-phase behavior explicitly

Declaring recovery completion based solely on steady-state metrics is insufficient