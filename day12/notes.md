Day12 – Scheduling Mediation of Storage-Induced Latency Spikes
----------------------------------------------------------------
1. Purpose
---------------
Day10 and Day11 identified rare but repeatable >200ms heartbeat stalls during storage-related intervention windows.
Day11 decomposition showed:
B_SKELETON (no-op scheduling structure) → no spikes
tmpfs writes → no spikes
fsync and some buffered storage paths → rare >200ms spikes
Central distribution (p50, p95, p99) remained stable
Spikes were discrete and did not deform the full latency tail
The working interpretation was that storage flush boundaries can trigger collapse-like latency artifacts without destabilizing the system.

Day12 tests an alternative explanation:
Are these storage-induced spikes actually mediated by CPU scheduling effects?
Specifically:
Is the heartbeat being descheduled or delayed due to scheduling contention triggered by storage activity, rather than storage latency alone?

2. Research Question
--------------------
When fsync-related storage activity occurs, are the observed >200ms heartbeat stalls:
A direct storage path effect, or
A scheduling artifact caused by CPU contention, wakeup latency, or core placement?

Day12 isolates scheduling as the independent variable while keeping the storage stimulus constant.

3. Hypotheses
--------------
H1 – Scheduling Mediation Hypothesis
If stalls are scheduling-mediated, then controlling CPU affinity will significantly alter spike frequency or severity while running the same storage trigger.

H2 – Core Contention Sensitivity
If heartbeat and storage trigger share the same CPU core:
Spike count and/or spike magnitude will increase.
If heartbeat is isolated to a different core:
Spike frequency will decrease or disappear.

H0 – Pure Storage Hypothesis
If stalls are primarily a storage IO path phenomenon:
Changing CPU affinity will not materially change spike behavior.

Experimental Design
-------------------
Controlled Variables
Across all Day12 variants:
Same cycle structure as Day11
Same RECOVERY_R2 window
Same heartbeat sampling configuration
Same spike threshold (>200ms)
Same telemetry collection strategy
Same PROBE B stimulus (fsync variant selected as primary trigger)
N_CYCLES ≥ 3 per variant

No additional IO amplification is introduced in the base experiment.
Only scheduling placement changes.

Experimental Matrix
----------------------
V0 – Baseline Scheduling Control
No storage probes
Heartbeat pinned to fixed CPU core
No additional load

Goal:
Establish scheduling stability and spike-free baseline under affinity control.

V1 – Storage Trigger, Default Scheduling
PROBE B with fsync
No explicit affinity controls (or default system placement)

Goal:
Reproduce previously observed spike signature.

V2 – Storage Trigger, Isolated Heartbeat Core
PROBE B with fsync
Heartbeat pinned to CPU0
Probe pinned to CPU1

Goal:
If spike frequency decreases relative to V1, scheduling mediation is likely.

V3 – Storage Trigger, Forced Same-Core Contention
PROBE B with fsync
Heartbeat pinned to CPU0
Probe pinned to CPU0

Goal:
If spike frequency increases relative to V2, scheduling mediation is strongly supported.

Optional Variants (Only if Needed)
-------------------------------------
These are secondary and not required for core attribution:
Add minimal CPU background noise pinned to a third core
Compare governor modes (performance vs ondemand)

These will only be used if V2 and V3 results are inconclusive.

Measurement Strategy
---------------------
Primary metrics per run (R2 only):
Sample count
spikes_gt_200ms
p50_ns
p95_ns
p99_ns
max_ns

Per-spike attribution:
For each dt >200ms:
Align with nearest probes.log marker
Align with nearest telemetry sample

Evaluate:
cpu_some and cpu_full PSI
io_some and io_full PSI
disk write deltas
writeback and dirty deltas
reclaim indicators (pgscan, pgsteal)

The goal is not to prove CPU is busy.
The goal is to determine whether scheduling placement changes the symptom.

Collapse Signature Consistency
-------------------------------
The collapse symptom definition remains unchanged from Day10 and Day11:
A collapse-like artifact is defined as:
dt_ns > 200,000,000
Occurring within RECOVERY_R2
Without systemic tail deformation
With stable p50 and p95
Maintaining a stable definition ensures cross-day comparability.

Interpretation Framework
--------------------------
Evidence of Scheduling Mediation

If:
V3 (same-core contention) > V2 (isolated cores) in spike count
Spike timing aligns more tightly with probe windows under same-core placement

Then:
Scheduling is a mediating mechanism for storage-induced stalls.

Evidence of Storage Dominance

If:
V2 and V3 show similar spike behavior
Core isolation does not reduce stall frequency

Then:
The primary mechanism is likely storage path latency rather than CPU scheduling.

Actionable Implications

If scheduling mediation is confirmed:
Core isolation may mitigate latency artifacts in production
CPU affinity becomes a control lever
Collapse symptoms may be preventable without storage redesign

If storage dominance is confirmed:
Attention remains on flush boundaries and IO scheduling
CPU isolation provides limited mitigation
Both outcomes provide practical system insight.

Results
--------
Baseline Scheduling Control (V0)

Under affinity-controlled conditions with no storage probe activity:
spikes_gt_200ms = 0
p50, p95, p99 remained stable
No tail deformation observed
No PSI anomalies

This establishes that CPU affinity manipulation alone does not introduce collapse-like artifacts.

The heartbeat mechanism remains stable under pinned execution.

Storage Trigger – Default Scheduling (V1)

With PROBE B (fsync variant) and default scheduler placement:
Representative spiky run (ext4 probe + ext4 logging):

spikes_gt_200ms = 11
max_ns ≈ 230ms
p50, p95, p99 stable
Spikes clustered within RECOVERY_R2

Per-spike correlation revealed:
Each spike aligned closely with PROBE_B_END
disk_wticks_d and disk_ioticks_d increased at spike boundary
cpu_some_avg10 = 0.00
io_some_avg10 = 0.00
No reclaim activity (pgscan, pgsteal ~ 0)

This confirms that spike artifacts coincide with synchronous flush boundaries.
The central distribution remained unaffected.
The artifact is discrete, not systemic.

Affinity-Controlled Variants (V2, V3)

CPU affinity manipulation experiments were executed to test scheduling mediation.

Key observation:
Changing CPU core placement did not materially alter spike behavior.
Specifically:
Isolating heartbeat to a dedicated core did not eliminate spikes.
Forcing same-core contention did not consistently amplify spike count or magnitude.
p50, p95, and p99 remained stable across affinity conditions.

No meaningful shift in spike frequency attributable to CPU placement was observed.

Topology Isolation Experiment

A decisive topology test was conducted:
Case A:
ext4 logging + ext4 probe (fsync)
→ spikes present (max ≈ 230ms)

Case B:
ext4 logging + tmpfs probe (fsync)
→ spikes_gt_200ms = 0
→ max ≈ 106ms

In both cases:
CPU configuration identical
Heartbeat identical
Scheduling unchanged
Only the probe storage path differed.

When the probe fsync path was moved to tmpfs:
Spikes disappeared entirely.

This isolates the phenomenon to:
Shared ext4 block device interaction between probe and logging.

PSI and Telemetry Observations

Across all spiky events:
cpu PSI remained 0.00
io PSI remained 0.00
No memory reclaim signals
No sustained IO pressure signature

However:
disk_wticks_d and disk_ioticks_d increased at spike alignment points.

This indicates:
The heartbeat was not blocked by CPU starvation nor direct task IO wait.
Instead, latency amplification occurred during synchronous flush activity at the block device layer.

Hypothesis Evaluation
----------------------
H1 – Scheduling Mediation Hypothesis
Not supported.
CPU affinity manipulation did not materially change spike behavior.

H2 – Core Contention Sensitivity
Not supported.
Same-core placement did not reliably increase spike frequency.

H0 – Pure Storage Hypothesis
Supported.
Spike presence depends on shared ext4 storage topology, not CPU placement.

Interpretation

The >200ms collapse-like artifacts are not CPU scheduling phenomena.
They are storage topology–dependent artifacts triggered by synchronous fsync activity when probe and logging share the same ext4 device.

The mechanism is consistent with:
Journal commit boundary
Writeback flush coordination
Block device service latency propagation

Importantly:
The system remains stable.
No tail deformation.
No systemic degradation.
No sustained pressure state.

The phenomenon is discrete and boundary-driven.

Conclusion
----------
Day12 investigated whether previously observed >200ms heartbeat stalls were mediated by CPU scheduling effects or driven primarily by storage path behavior.
The experimental results reject the Scheduling Mediation Hypothesis.
CPU affinity manipulation ,including isolated-core placement and forced same-core contention — did not materially change spike frequency or magnitude. 
The central latency distribution (p50, p95, p99) remained stable across scheduling configurations.
In contrast, topology isolation experiments demonstrated a decisive dependency on storage path placement.
When both probe fsync activity and logging occurred on the same ext4 device:
Discrete >200ms stalls were reproducible.
Spikes aligned temporally with PROBE_B_END boundaries.
disk_wticks_d and disk_ioticks_d increased at spike onset.
CPU PSI and IO PSI remained at 0.00.
No reclaim or systemic pressure signatures were observed.
When the probe fsync path was moved to tmpfs while logging remained on ext4:
Spikes disappeared completely.
Maximum latency returned to ~106ms.
Distribution symmetry was preserved.

This demonstrates that the collapse-like artifacts are not CPU starvation phenomena and are not generic fsync cost effects in isolation.
Rather, they are topology-dependent artifacts that emerge when synchronous flush activity interacts with concurrent write activity on a shared ext4 block device.
The system remains globally stable.
The artifact is discrete, boundary-driven, and non-systemic.
These findings narrow the causal surface to the storage flush and journal interaction layer.

Further topology investigation, including block layer behavior and flush boundary timing analysis, will be conducted in Day13.