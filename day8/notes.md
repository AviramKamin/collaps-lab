Day 8 hypothesis
---------------------
After Day 7 showed that recovery is metastable and probe-sensitive, we hypothesize:
Recovery is not only metastable but bistable.
Below a probe-intensity threshold, recovery perturbations are transient and leave no lasting effect.
Above a threshold applied during recovery,
perturbations can push the system into a persistently altered internal state (“recovery scarring”), 
expressed as increased sensitivity or altered recovery dynamics in subsequent cycles, 
even when steady-state metrics appear nominal.

Experimental objective
-----------------------
Determine whether probe-induced recovery spikes can transition from a transient phenomenon (Day 7) into persistent aftereffects:

Does probing during recovery change future recovery sensitivity?

Does it create measurable drift in post-recovery baseline?

Does it change spike rate or max severity distribution over cycles?

Is there a clear threshold or dose response?

Method overview
----------------
Keep the Day 7 structure but introduce controlled “dose levels” of probing during recovery and compare against controls.

Core idea: A/B/C recovery probing intensity

You run the same collapse forcing, but vary probe load during R2:

Control: no probes at all (ENABLE_PROBES=0)

Low: the same Day 7 probe schedule (baseline dose)

High: increased probe frequency or slightly heavier probes

Optional: Late-only probes (apply only near end of R2) to test timing sensitivity

You want at least N=3 cycles per run, like you’ve been doing, because “scarring” is about cross-cycle effects.

Cycle definition
----------------
Same as Day 7:

B → I → R1 → R2 → B2

But Day 8 changes R2 into a parameterized probe program.

R2 probe programs (examples)

Program L (Low, Day 7-like)

idle 60s

probe A 60s (cache touch)

idle 30s

probe B 60s (small file create/read)

idle 30s

probe C 60s (tiny fs metadata walk)

Program H (High)

shorten idle gaps

run probes back-to-back more often

or increase file size mildly

or add sync calls carefully

Program Late-only

R2 first 2/3 idle

last 1/3 probes

Metrics
---------
Primary outcome: “scarring” indicators

You want metrics that compare across cycles and across runs:

Spike rate in R2

spikes per minute above thresholds

example thresholds: >5ms, >50ms, >500ms, >1s

Spike alignment
fraction of spikes within X seconds of a probe event
example: within 2s, 5s
Post-recovery baseline shift
B2 p99 vs B p99 (same cycle)
B2 p99 vs Cycle 1 baseline p99 (across cycles)
Next-cycle susceptibility
Does Cycle 2 or 3 show larger spikes for the same probe program?
Secondary signals
meminfo trends across R2 and B2
retries containment (should remain within intervention)
any evidence of delayed writeback or slab growth that correlates with spikes

Analysis plan
--------------

For each OFF setting (start with OFF=3 and OFF=2 like Day 7):
Run A: Control (no probes)
Run B: Low probes
Run C: High probes

Then compare:
R2 spike rate A vs B vs C
B2 stability A vs B vs C
Cycle-to-cycle changes within each run
What “support for scarring” looks like
Any one of these is meaningful:
High probe program causes higher spike rate not just during R2, but also lingering into B2
High probe program makes Cycle 2 and 3 more sensitive than Cycle 1, even if forcing is identical
Control remains clean while probed runs show persistent anomalies

What would falsify scarring
spikes occur during R2 but do not change B2
later cycles show no increased sensitivity
differences between Low and High are negligible

Safety and termination conditions
------------------------------------
Stop early if:

retries or IO appear outside intervention windows

heartbeat max goes into multi-second territory repeatedly (not rare)

system becomes unusable or logs start dropping

Results
-------

Overview
Day 8 examined whether probe activity during recovery can produce persistent or dose-dependent aftereffects ("scarring"),
by comparing recovery behavior under three conditions:

Control: no probes during recovery
LOW: Day 7–level probe intensity
HIGH: increased probe intensity

All runs used identical collapse forcing.
Analysis focuses on heartbeat latency statistics during RECOVERY_R2 and POSTBASELINE phases.

Unless stated otherwise, values are reported in nanoseconds (ns).


Control vs LOW (OFF = 3)

Control run: 2026-02-06_141146_day8_off3_low_n1
LOW run:     2026-02-06_141345_day8_off3_LOW_n1 and 2026-02-06_174855_day8_off3_LOW_n3

Baseline behavior
In the control run (no probes):
Baseline p99 = 103,119,883 ns
POSTBASELINE p99 = 102,610,390 ns

Baseline and post-recovery baseline distributions were statistically similar, with no evidence of persistent drift.

In LOW-probe runs:
Baseline p99 values ranged from 101,952,240 ns to 102,841,907 ns
POSTBASELINE p99 values ranged from 101,784,408 ns to 102,219,033 ns

Observation:
LOW probe runs did not produce measurable baseline degradation relative to control.


Recovery Phase (RECOVERY_R2)

Control:
RECOVERY_R2 p99 = 101,821,104 ns
Maximum observed latency = 104,746,380 ns
Sample count = 591

LOW (single-cycle run):
RECOVERY_R2 p99 = 102,685,422 ns
Maximum latency = 167,862,405 ns
Sample count = 2,947

LOW (3-cycle run, cycle 1):
RECOVERY_R2 p99 = 104,298,328 ns
Maximum latency = 143,932,449 ns
Sample count = 2,944

Observation:
Compared to control, LOW probes increased both:
- p99 latency during recovery (≈ +0.8–2.5 ms)
- Maximum latency (≈ 1.4×–1.6× higher)

These increases were confined to RECOVERY_R2 and did not propagate into POSTBASELINE.


Post-Recovery Baseline (B2)

Control:
POSTBASELINE p99 = 102,610,390 ns

LOW:
POSTBASELINE p99 values remained ≤ 102,219,033 ns across cycles

Observation:
Despite increased recovery volatility, LOW probe runs did not exhibit persistent post-recovery degradation.


HIGH vs LOW (OFF = 3)

HIGH run: 2026-02-06_215734_day8_off3_HIGH_n3 and 2026-02-07_142628_day8_off3_HIGH_n3

Recovery Phase Comparison

LOW (OFF=3):
RECOVERY_R2 p99 ≈ 102–104 ms
Maximum latency ≈ 140–168 ms

HIGH (OFF=3):
RECOVERY_R2 p99 values increased further
Maximum latencies exceeded LOW consistently (exact maxima varied by cycle)

Observation:
Increasing probe intensity produced a dose-dependent increase in:
- Recovery p99 latency
- Spike amplitude

However, the structure of recovery remained similar:
- Spikes remained rare
- Percentile metrics outside recovery were unaffected


OFF = 2 Comparison

Control (OFF=2):
RECOVERY_R2 p99 ≈ 101.82–101.93 ms
Maximum latency ≈ 102–103 ms

LOW (OFF=2):
RECOVERY_R2 p99 ≈ 101.82–101.93 ms
Maximum latency ≈ 102.5–102.8 ms

HIGH (OFF=2):
RECOVERY_R2 p99 increased modestly
Maximum latency increased relative to LOW

Observation:
Lower OFF values reduced overall recovery volatility,
but probe-induced amplification was still observable under HIGH probing.


Summary of Observed Effects

Across all OFF values:

- Control runs exhibited minimal recovery volatility
- LOW probes increased recovery spike amplitude without persistent effects
- HIGH probes further amplified recovery volatility
- No condition produced lasting post-recovery baseline degradation
- Effects were confined to the recovery window

Critically:
No evidence of irreversible scarring was observed within the tested probe intensities.
Instead, results indicate a graded, reversible sensitivity regime.

Conclusions
-----------

Day 8 results partially support and partially refute the scarring hypothesis.

Supported:
- Recovery is a uniquely sensitive phase
- Probe-induced disturbances are phase-dependent
- Spike amplitude scales with probe intensity
- Effects are repeatable and structured rather than random

Not Supported:
- No evidence of persistent scarring was observed
- Post-recovery baseline metrics (p95, p99) consistently returned to nominal ranges
- Recovery sensitivity did not increase across cycles
- No clear probe intensity threshold caused lasting aftereffects

Interpretation

Recovery behaves as a metastable but elastic system state.
Probes applied during recovery can induce large, transient coordination failures,
yet the system retains the ability to re-stabilize without lasting deformation.

Day 8 demonstrates that:
- Sensitivity does not imply damage
- High-amplitude recovery spikes alone are insufficient to cause scarring
- Collapse depth and probe intensity modulate severity, not permanence

Implications

- Recovery vulnerability windows exist but are self-healing under tested conditions
- Monitoring systems must inspect recovery dynamics, not only steady-state health
- Scarring likely requires stronger, denser, or differently structured perturbations
- Future experiments should explore multi-axis stress or overlapping collapse sources
