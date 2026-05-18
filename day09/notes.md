Day 9 hypothesis
----------------
Day 8 demonstrated that recovery is highly sensitive to probe activity,
with probe-induced disturbances scaling with probe intensity,
yet remaining confined to the recovery window and fully reversible
under single-axis perturbation.

We hypothesize that recovery elasticity depends not only on probe intensity,
but also on **recovery isolation**.

Specifically:
Recovery remains elastic under single-axis perturbation during recovery,
but overlapping recovery probes with **mild background IO**
may transition recovery from a reversible, metastable state
into a persistently altered internal regime.

In this model, recovery scarring, if it exists,
is not triggered by spike amplitude alone,
but by **coupled stress during recovery**.

---

Experimental objective
----------------------
Determine whether recovery-phase perturbations that are benign in isolation
can produce persistent aftereffects when combined with background maintenance activity.

Key questions:

Does overlapping recovery probes with mild background IO
alter recovery dynamics beyond transient spike amplification?

Does coupling introduce measurable drift or instability
in post-recovery baseline behavior?

Does recovery sensitivity change across cycles
only when background IO overlaps with recovery probes?

Is recovery elasticity preserved when probes and background IO
are applied independently but degraded when they overlap?

---

Method overview
----------------
Extend the Day 8 recovery-probing framework by introducing
**mild background IO during recovery**.

Core idea:
Compare recovery behavior under isolated stressors
versus **coupled recovery probes and background IO**,
while keeping collapse forcing identical across runs.

Background IO represents routine system maintenance activity
that commonly occurs in large production systems
and is assumed to be safe when occurring alone.

---

Cycle definition
----------------
Same structure as Day 7 and Day 8:

B → I → R1 → R2 → B2

R2 is the experimental focus.

N = 3 cycles per run
(to detect cross-cycle effects or sensitivity changes)

---

Recovery conditions
-------------------
Four recovery conditions are defined:

Control A:
No probes and no background IO during R2

Control B:
Recovery probes only
(Day 8 LOW-equivalent probe program)

Control C:
Background IO only
(no recovery probes)

Experimental:
Recovery probes and background IO overlapping during R2

Background IO must be enabled only during R2
and disabled during B, I, R1, and B2.

---

Background IO definition
------------------------
Background IO is defined as **mild, bounded filesystem activity**
representing routine maintenance operations.

Requirements:

- Reversible when applied alone
- No measurable impact on baseline or post-recovery behavior in isolation
- Limited working set
- Predictable duration
- Active only during R2
- Must not trigger retries or IO outside recovery

If these conditions are violated,
the experiment must be aborted and recalibrated.

---

Metrics
---------
Primary outcomes: recovery elasticity indicators

Recovery variance shape
(time-ordered heartbeat behavior, not averages)

Spike characteristics in R2
- spike rate above thresholds
  example thresholds: >5ms, >50ms, >500ms, >1s
- clustering and temporal alignment

Post-recovery baseline stability
- B2 p99 vs B p99 (same cycle)
- B2 p99 vs Cycle 1 baseline (across cycles)

Cross-cycle susceptibility
- Does recovery behavior in Cycle 2 or 3
  differ from Cycle 1 under identical conditions?

Secondary signals
- meminfo trends across R2 and B2
- retries containment (must remain within intervention)
- evidence of delayed effects after R2 ends

---

Analysis plan
--------------
For a fixed OFF value (starting with OFF = 3):

Run A: Control A
Run B: Control B
Run C: Control C
Run D: Coupled recovery probes + background IO

Comparisons:
- R2 recovery behavior across A, B, C, D
- B2 baseline stability across A, B, C, D
- Cycle-to-cycle changes within each run

---

What would support loss of recovery elasticity
----------------------------------------------
Any of the following:

Coupled condition shows recovery instability
not present in either probes-only or background-IO-only controls

Post-recovery baseline behavior diverges
only under the coupled condition

Later cycles exhibit increased sensitivity
under coupled stress but not under controls

---

What would falsify the hypothesis
---------------------------------
Coupled condition behaves indistinguishably
from single-axis recovery probe runs

All effects remain confined to R2
with clean and stable post-recovery baselines

No cross-cycle sensitivity changes are observed

---

Safety and termination conditions
---------------------------------
Stop early if:

Background IO or probes leak outside R2

Retries or IO activity escape intervention boundaries

Heartbeat max repeatedly enters multi-second territory

System responsiveness degrades or logs begin dropping

results
--------

Experimental Matrix
Mode	Probes	Background IO	Cycles
A	     No	        No	        1
B	     Yes	    No			3
C		 No	 Yes (256 KiB/s write)	1
D		Yes	        Yes	        3

Heartbeat interval: 100ms
Background IO: 256 KiB/s sustained write via fio
Probe program: low

Baseline Stability (Mode A)
---------------------------
R2 latency distribution:

p50 ≈ 101.66 ms

p95 ≈ 101.75 ms

p99 ≈ 101.79 ms

max ≈ 102.80 ms

Observation:
Baseline jitter window remains within ~+1.2 ms worst case.
R2 behavior is indistinguishable from baseline, confirming instrumentation stability.

Background IO Only (Mode C)
--------------------------
R2 latency distribution:

p50 ≈ 101.69 ms

p95 ≈ 101.76 ms

p99 ≈ 101.81 ms

max ≈ 102.76 ms

spikes >200ms: 0

Observation:
Sustained 256 KiB/s background write does not inflate tail latency and does not introduce long scheduling stalls.
Background IO at this intensity behaves as benign maintenance load.

Probes Only (Mode B)
---------------------
Aggregated R2 (3 cycles):

p50 ≈ 101.72 ms

p95 ≈ 101.90 ms

p99 ≈ 102.64 ms

max ≈ 641.49 ms

spikes >200ms: 3

Observation:
Probe activity introduces rare but significant latency stalls (500–640 ms range).
Central tendency remains stable, but tail inflation is measurable.

Coupled (Probes + Background IO) (Mode D)
-----------------------------------------
Aggregated R2 (3 cycles):

p50 ≈ 101.73 ms

p95 ≈ 101.89 ms

p99 ≈ 102.54 ms

max ≈ 604.79 ms

spikes >200ms: 1

Observation:
Coupling does not increase spike frequency or tail inflation beyond probes alone.
Background IO does not amplify probe-induced stalls at this load level.

conclusions
-----------
Instrumentation Stability Confirmed

Mode A demonstrated that baseline and R2 latency distributions are statistically indistinguishable.
This confirms:

-Phase transitions do not introduce measurement artifacts.
-The heartbeat instrumentation is stable.
-R2 is not inherently noisier than baseline.

This is important because all further interpretation relies on instrumentation integrity.

Background IO at Maintenance Level is Non-Disruptive
------------------------------------------------------
Mode C showed that sustained background IO at 256 KiB/s:

-Does not inflate p99 latency.
-Does not increase maximum latency beyond baseline noise.
-Does not introduce long scheduling stalls.
-Does not create >200 ms spikes.

This indicates that low-rate continuous writes — representative of log rotation, 
telemetry persistence, journaling, or light maintenance operations — are effectively transparent to the recovery loop at this scale.
The system absorbs this background activity without measurable degradation.

Probe Activity is the Primary Source of Tail Instability
---------------------------------------------------------
Mode B revealed:

-Stable median latency.
-Measurable p99 inflation.
-Three long stalls (>200 ms).
-Worst-case stall ≈ 641 ms.

This indicates that:
Central scheduling behavior remains intact.
However, probe-triggered operations occasionally interact with kernel scheduling, memory pressure, or IO pathways in a way that produces rare hard stalls.
These stalls are not systemic collapse. They are tail events.
The dominant stressor in Day 9 is probe activity, not background IO.

No Nonlinear Amplification Under Coupling
------------------------------------------
Mode D (probes + background IO) showed:

-Similar p99 to Mode B.
-Lower spike count than Mode B.
-Comparable worst-case latency.

Critically:
--------------
Background IO does not amplify probe-induced tail events.

-There is no evidence of nonlinear coupling at this load level.
-The system does not exhibit collapse behavior when probe and maintenance load overlap.
-This suggests that maintenance IO at this intensity remains orthogonal to probe-induced instability.

Recovery Elasticity Survives Realistic Overlap
-----------------------------------------------
The original Day 9 question was:

Does recovery elasticity survive overlap with routine maintenance IO?

The data supports:
Yes.

Recovery phases under coupled load do not degrade beyond probe-only behavior.

This implies:

-Elasticity mechanisms are robust to mild persistent IO noise.
-Maintenance load at realistic levels does not compromise recovery stability.
-The system exhibits isolation between passive background activity and active probe stress.

Practical Interpretation for Real Systems
------------------------------------------
In practical terms:

A server undergoing:

-Log writes
-Journaling activity
-Background flush
-Light maintenance churn

should not experience amplified instability during recovery phases purely due to that maintenance activity.
Instability is driven by active workload interactions, not passive background persistence at this intensity.

Boundary of Validity
-----------------------
These conclusions apply to:

256 KiB/s sustained write load.

Single fio job.

Low probe program.

Current kernel and storage configuration.

microSD-backed filesystem.

Day 9 does not claim:

Immunity under high IO saturation.

Immunity under queue depth escalation.

Immunity under multi-source contention.

Absence of threshold behavior at higher maintenance loads.

It demonstrates stability under realistic maintenance intensity, not under synthetic stress escalation.