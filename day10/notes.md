Day 10 – Probe Stall Attribution
----------------------------------
Objective
-----------
Identify which probe action (A, B, or C) is responsible for rare heartbeat stalls (>200 ms) during R2, 
and attribute those stalls to a specific subsystem signal.
Day10 focuses on attribution, not escalation.

Context from Day9
-----------------
Day9 established:

-Maintenance-level background IO (256 KiB/s sustained write) does not inflate tail latency.
-Probe activity can induce rare 500–640 ms stalls.
-Coupling with mild background IO does not amplify stall frequency.
-Recovery remains reversible and bounded.
Therefore, instability is probe-driven.

Day10 isolates and explains that instability.

Hypotheses
----------
H1 – Action Specificity
Rare stalls are predominantly associated with one probe action (A, B, or C).

H2 – Subsystem Correlation
Each >200 ms stall correlates with measurable stress in at least one subsystem:

IO pressure (PSI io)

Writeback activity (Dirty / nr_writeback)

Memory reclaim (pgscan / pgsteal)

CPU scheduling pressure (PSI cpu)

H3 – Temporal Causality
Stalls occur within a bounded window following a probe action marker, not randomly across R2.

H4 – No Persistence
Despite stalls, baseline following R2 remains stable.

Experimental Design
-------------------
Fixed Parameters:

Runner structure unchanged: B → I → R1 → R2 → B2
Intervention phase unchanged from Day8/Day9
No increase in maintenance IO intensity
PROBE_PROGRAM=low
N_CYCLES=3 per variant (minimum)

Telemetry Strategy (Per Cycle, R2 Only)
---------------------------------------
Telemetry is collected per cycle:

cycle_N/telemetry.log
Sampling interval:
1 second (default)
Enabled by:
ENABLE_TELEMETRY=1

Tier 1 Telemetry Signals
-------------------------
PSI:

cpu
io
memory

Memory:
Dirty
Writeback
MemAvailable

VM counters (deltas):
nr_dirty
nr_writeback
pgscan_kswapd
pgscan_direct
pgsteal_kswapd
pgsteal_direct
pswpin
pswpout

Disk:
mmcblk0 diskstats deltas
time-in-queue fields

Format:
timestamp_ns key=value key=value ...


Telemetry runs only between:
RECOVERY_R2_START and RECOVERY_R2_END.

Alignment Strategy
--------------------
For each heartbeat spike >200 ms:
Identify active probe action window.
Locate nearest telemetry sample.

Record:

PSI values
Dirty / Writeback
vmstat deltas
Disk queue activity

Metrics

For each PROBE_ACTIONS variant:

R2 sample count
Spike count (>200 ms)
p50 / p95 / p99
Maximum stall
Stall density per cycle

For each stall:
Probe action active
Subsystem signals at time of stall

Success Criteria
------------------
Day10 is successful if:
-A specific probe action shows higher stall density.
-At least one subsystem signal correlates consistently with stall events.
-No persistent baseline drift occurs after R2.


Results
----------
Experimental Variants Executed:

All runs used:
-MODE=B
-PROBE_PROGRAM=low
-N_CYCLES=3
-Telemetry enabled during R2 only
-No background IO escalation

Variants:
-PROBE_ACTIONS=ABC
-PROBE_ACTIONS=B
-PROBE_ACTIONS=A
-PROBE_ACTIONS=C

Only ABC and B produced measurable stalls in this dataset.

R2 Aggregate Metrics
----------------------
Variant: PROBE_ACTIONS=ABC

count: 8833
spikes_gt_200ms: 3
p50_ns: 101709971
p95_ns: 102013008
p99_ns: 103507692
max_ns: 395327622

Observations:

-Median and p95 remain near baseline (~101–102 ms).
-p99 increases slightly.
-Three discrete spikes exceed 200 ms.
-Maximum stall reaches ~395 ms.
-Spikes occurred in C1 and C3.

Variant: PROBE_ACTIONS=B

count: 8830
spikes_gt_200ms: 4
p50_ns: 101681017
p95_ns: 101925157
p99_ns: 102715467
max_ns: 327074010

Observations:

-Central tendency remains stable.
-p99 slightly elevated relative to baseline.
-Four spikes exceed 200 ms.
-Maximum stall ~327 ms.
-Spikes observed primarily in C1 and C3.

Variant: PROBE_ACTIONS=A

spikes_gt_200ms: 0
No R2 stalls above 200 ms observed.

Variant: PROBE_ACTIONS=C
spikes_gt_200ms: 0
No R2 stalls above 200 ms observed.

Spike Attribution
------------------
For each >200 ms spike:

-Timestamp aligned with heartbeat log.
-Nearest probe event located in probes.log.
-Telemetry sample aligned within ±1 second.

Findings:

-All observed stalls in ABC and B variants align with PROBE_B windows.
-No stall was temporally associated with isolated A or C activity.
-Telemetry during spike windows shows increased disk write activity:
disk_wticks_d elevated
-disk_ioticks_d elevated
-disk_wq increased
-PSI metrics remain near zero in most cases.
-Dirty and writeback fields show transient fluctuations but no sustained pressure.
-No sustained memory reclaim patterns observed.

This supports probe-action specificity rather than generalized system pressure.

Distribution Shape
-------------------
Across all variants:

-p50 remains stable near 101–102 ms.
-p95 remains tightly bounded.
-p99 slightly expands when PROBE_B is active.
-Spikes are rare, discrete, and non-clustered.
-No progressive degradation across cycles.

Stalls are episodic, not cumulative.

Conclusions
-----------
1. Action Specificity Confirmed

H1 supported.

Rare R2 stalls are associated specifically with PROBE_B activity.

Evidence:

-ABC and B variants produced stalls.
-A-only and C-only variants did not.
-Temporal alignment consistently links spikes to PROBE_B_END windows.

Instability is not probe-generic.
It is action-specific.

2. Subsystem Correlation

H2 partially supported.

Observed during spike windows:
-Elevated disk queue metrics.
-Increased write ticks and IO ticks.
M-inor writeback deltas.

However:
-PSI cpu, io, memory remain near zero.
-No persistent memory reclaim.
-No swap activity.
Stalls coincide with transient disk activity rather than sustained subsystem pressure.
Interpretation:

Stalls are likely caused by short synchronous disk interactions or scheduler contention related to PROBE_B behavior, not systemic pressure.

This is micro-level blocking, not macro saturation.

3. Temporal Causality

H3 supported.

All >200 ms stalls occurred within bounded proximity to PROBE_B activity.

No random R2 spikes detected.

No baseline-phase spikes observed.

Stalls are causally linked to probe execution windows.

4. No Persistence

H4 supported.

After R2:

-Baseline metrics return to stable levels.
-No drift in p50/p95.
-No cumulative effect across cycles.
-No system instability cascade.

Recovery remains bounded and reversible.

5. Stability Profile of the System

Under:

-Realistic maintenance IO (Day9)
-Controlled probe activity (Day10)
-Per-cycle telemetry attribution

The system demonstrates:
-High central stability
-Rare, bounded probe-induced stalls

-No escalation behavior
-No feedback amplification
-No persistence of instability

This is a resilient system with localized probe sensitivity.

6. Practical Interpretation

In real-world terms:

If PROBE_B represents a diagnostic or health-check routine touching disk or scheduler-sensitive paths:

-It can introduce rare 200–400 ms pauses.
-These pauses are isolated.
-They do not degrade overall system health.
-They do not accumulate.

This is consistent with production systems where rare maintenance operations momentarily block a path but do not threaten availability.