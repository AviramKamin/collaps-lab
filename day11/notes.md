Day 11 – PROBE_B Mechanism Isolation
--------------------------------------
Introduction
-------------
Day10 moved the study from detection to attribution.

Up to Day9 we knew that rare heartbeat stalls above 200 ms occurred during the R2 recovery window and were probe-driven rather than maintenance IO driven. 
Background IO at maintenance intensity did not inflate tail latency and did not increase stall frequency. Recovery remained bounded and reversible.

Day10 isolated the responsible action.

Across controlled variants:

PROBE_ACTIONS=A produced zero R2 stalls

PROBE_ACTIONS=C produced zero R2 stalls

PROBE_ACTIONS=ABC produced rare stalls

PROBE_ACTIONS=B alone reproduced stalls

Temporal alignment confirmed that all >200 ms stalls occurred within bounded proximity to PROBE_B execution windows. 
Telemetry showed transient disk queue activity during stall windows, while PSI metrics remained near zero and no sustained memory reclaim patterns were observed.

Conclusion from Day10:

Instability is action-specific.
It is not probe-generic.
It is not caused by sustained subsystem saturation.
It is localized and bounded.

However, Day10 identified which action is responsible, not why.

PROBE_B remains a composite operation. It includes multiple internal steps such as file writes, 
flush boundaries, and possibly global sync behavior. Any one of these could introduce short blocking in the storage or scheduler path.

Day11 therefore shifts focus from attribution to mechanism isolation.

The objective of Day11 is to decompose PROBE_B into controlled micro-variants and determine which internal operation is sufficient to reproduce the rare R2 stalls.

We will not escalate intensity.
We will not change system stress level.
We will isolate the minimal causal mechanism.

Hypotheses
------------
H1 – Mechanism Specificity

The rare R2 heartbeat stalls (>200 ms) observed in Day10 are not caused by PROBE_B as a whole, but by a specific internal operation within PROBE_B.
Only one of the following micro-operations is sufficient to reproduce stalls:
Buffered write only
Write followed by fsync
Write + metadata update
Explicit sync or global flush
File open/close boundary effects

If a reduced variant of PROBE_B reproduces the stall signature, that operation is the causal mechanism.

H2 – Flush Boundary Hypothesis

If stalls are caused by storage synchronization behavior, then:
Variants that include fsync or sync boundaries will reproduce >200 ms stalls.
Variants that perform buffered writes without forced flush will not.

This distinguishes:

Transient disk queue growth
from
Blocking flush semantics

H3 – No PSI Escalation

If stalls are micro-blocking events rather than systemic pressure, then during stall windows:

PSI cpu, io, and memory will remain near zero
No sustained reclaim or swap activity will occur
No progressive degradation across cycles will appear

This hypothesis carries forward Day10 findings.

H4 – Sufficiency and Minimality

If a single micro-operation is sufficient to reproduce the stall pattern observed in Day10, then:

Adding unrelated probe actions will not increase stall density
Removing the causal operation will eliminate stalls

The stall signature should collapse when the minimal causal element is removed.

H5 – Reversibility Remains Intact

Even if the causal mechanism is identified and isolated:

R2 recovery must remain bounded
Baseline following R2 must remain stable
No persistence or amplification across cycles should occur

If persistence appears, then the mechanism interacts with a larger feedback system.

Methodology Rationale – Control Strategy
------------------------------------------
Day11 decomposes PROBE_B into internal micro-operations in order to identify the minimal mechanism that is sufficient to reproduce rare R2 heartbeat stalls (>200 ms).

Once PROBE_B is decomposed, a single “no probes” control is no longer enough. Removing the entire probe loop changes multiple factors at once:

probe cadence and wakeups

logging and marker overhead

scheduler interference from the probe loop itself

filesystem interaction frequency

To preserve causal validity, Day11 uses a layered control strategy.

Each control retains the same probe schedule, markers, and R2 timing, while removing only the suspected blocking operation. 
This makes the variants comparable and keeps the experiment falsifiable.

The control ladder isolates causes in increasing “realism”:

B-skeleton no-op
Controls for scheduling, wakeups, and instrumentation overhead.
If stalls occur here, they are not storage-related and not PROBE_B-operation related.

Buffered write only (ext4 on microSD)
Controls for file creation, buffered writes, metadata, and page cache dirtying, without flush boundaries.
If stalls appear here, simple writes or dirty-threshold behavior may be sufficient.

tmpfs write (write to /dev/shm)
Controls for the cost of writing bytes and filesystem syscalls while removing the storage device path.
If stalls disappear here but exist on ext4, the causal path implicates storage or filesystem flush behavior.

Treatments then test sufficiency of flush boundaries:

write + fsync (per-file flush)
Tests whether localized flush semantics are sufficient to reproduce stalls.

sync-only (global flush)
Tests whether global flush behavior is sufficient without any explicit write workload.

This structure allows Day11 to distinguish:

probe-loop scheduling noise
vs

buffered file operations
vs

storage device and filesystem flush boundaries

without escalating stress intensity or changing the recovery protocol.

Experimental Variants – Control Ladder and Treatments
------------------------------------------------------
All variants preserve:

MODE=B

PROBE_PROGRAM=low cadence

Identical R2 duration and cycle structure

Identical heartbeat and telemetry instrumentation

N_CYCLES=3 minimum per variant

Only the internal implementation of PROBE_B changes.
This ensures that differences in stall behavior can be attributed to the internal operation itself, not to scheduling structure or probe density.

control Layer 1 – Scheduler / Instrumentation Control
------------------------------------------------------
Variant: B_SKELETON_NOOP

Behavior:
Executes full PROBE_B timing window
Emits PROBE_B_START / PROBE_B_END markers
Performs no file operations
Performs no write, no flush, no sync

Purpose:
Controls for:

Probe loop wakeups
Scheduler context switches
Logging and marker overhead
Instrumentation artifacts

Interpretation:
If stalls occur here, they are unrelated to filesystem or storage activity and likely caused by scheduling contention or probe-loop design itself.

Control Layer 2 – Buffered Write Only (ext4)
---------------------------------------------
Variant: B_BUFFERED_WRITE

Behavior:
Writes small file to ext4 (microSD)
No fsync
No sync
Relies on page cache

Purpose:
Controls for:
File creation cost
Dirty page accumulation
Metadata updates
Page cache interaction

Interpretation:
If stalls occur here but not in B_SKELETON_NOOP, simple buffered writes may be sufficient to induce latency spikes.

Control Layer 3 – Device Path Isolation
------------------------------------------
Variant: B_TMPFS_WRITE

Behavior:
Writes identical data to tmpfs (/dev/shm)
No fsync
No sync

Purpose:
Controls for:
Syscall cost
File write logic
Memory copy overhead

Removes:
Block device interaction
Filesystem journal commit
Storage queue depth effects

Interpretation:
If stalls disappear in tmpfs but exist in ext4 buffered write, the storage device path is implicated.

Treatment Variants – Flush Semantics
--------------------------------------
Treatment 1 – Write + fsync
Variant: B_WRITE_FSYNC

Behavior:
Write file to ext4
Call fsync() per operation

Purpose:
Tests whether explicit per-file flush boundaries are sufficient to induce stalls.

Interpretation:
If stalls increase here relative to buffered write, fsync-induced blocking is causal.

Treatment 2 – Sync-Only
------------------------
Variant: B_SYNC_ONLY

Behavior:
No new write
Call sync or syncfs during probe window

Purpose:
Tests whether forcing global flush is sufficient without local write pressure.

Interpretation:
If stalls occur here, global writeback coordination is sufficient to block heartbeat.

Measurement Strategy
--------------------
For each variant:
R2 heartbeat distribution:
count
spikes >200 ms
p50 / p95 / p99
max
stall density per cycle

Stall alignment:
Occurs during active probe window?
Within bounded time after operation?
Repeats across cycles?

Telemetry alignment:
disk_wticks_d
disk_ioticks_d
disk_wq_d
Dirty / Writeback deltas
PSI cpu / io / memory

Decision Logic
------------------
The control ladder allows strong conclusions even if stalls remain rare.

Possible outcomes:

Stalls appear only in write + fsync
→ fsync boundary is sufficient cause.

Stalls appear in buffered write but not tmpfs
→ storage device path implicated.

Stalls appear even in skeleton no-op
→ scheduling / probe-loop structure is causal.

Stalls appear only in sync-only
→ global flush coordination is sufficient.

No variant reproduces Day10 behavior
→ PROBE_B’s interaction pattern, not individual micro-ops, is necessary.

DAY11 – PROBE_B DECOMPOSITION MATRIX

Legend:
Y = yes
N = no
EXT4 = microSD ext4 filesystem
TMPFS = in memory filesystem (/dev/shm)

Variant Name | Scheduler Window | File Write | Filesystem | Page Cache | fsync() | sync() | Block Device Path | Purpose
B_SKELETON_NOOP | Y | N | N | N | N | N | N | Control scheduling + instrumentation only
B_BUFFERED_WRITE | Y | Y | EXT4 | Y | N | N | Y | Control buffered write without flush
B_TMPFS_WRITE | Y | Y | TMPFS | Y | N | N | N | Remove device path, keep write logic
B_WRITE_FSYNC | Y | Y | EXT4 | Y | Y | N | Y | Treatment: explicit file-level flush
B_SYNC_ONLY | Y | N | EXT4 | N | N | Y | Y | Treatment: global flush boundary

Results
-------
Experimental Scope

All reported results include:

MODE=B
PROBE_PROGRAM=low
N_CYCLES=3
Telemetry enabled during R2
No background IO escalation

Each variant isolates a specific persistence boundary within probe_action_B.
Only _n3 runs are included in aggregate analysis.

| Variant    | Description                     | R2 Spikes (>200 ms) | Max Stall (ns) |
| ---------- | ------------------------------- | ------------------- | -------------- |
| B_SKELETON | No-op control (scheduling only) | 0                   | ~105M          |
| tmpfs      | Write to tmpfs (no device path) | 0                   | ~106M          |
| sync_only  | Global `sync` without write     | 0–1                 | ~209M          |
| fsync      | Write + per-file `fsync`        | 5–7                 | 226–297M       |
| buffered   | Write to ext4, no `fsync`       | 3–6                 | 326M–1.30B     |
---------------------------------------------------------------------------------------

Control Validation

B_SKELETON (noop)

Representative n3 runs:

count ≈ 8833–8846
p50_ns ≈ 101.7M
p95_ns ≈ 101.9M
p99_ns ≈ 102.1–102.3M
spikes_gt_200ms = 0
max_ns ≈ 105M


Interpretation:

Scheduling loop alone does not induce stalls.
Instrumentation overhead is negligible.
Heartbeat stability remains intact.
This validates the control baseline.

tmpfs (in-memory write)
Representative n3 runs:

count ≈ 8839–8845
p50_ns ≈ 101.7M
p95_ns ≈ 101.9M
p99_ns ≈ 102.15–102.22M
spikes_gt_200ms = 0
max_ns ≈ 106M


Interpretation:

Memory dirties alone do not generate stalls.
No PSI pressure observed.
No reclaim or swap activity.
Write activity without device persistence does not cause R2 latency spikes.

Treatment Results
sync_only (global flush)

Runs:
spikes_gt_200ms = 0–1
max_ns = 105M–209M


Interpretation:
Global flush boundaries can occasionally produce mild spikes.
Effect is weak and inconsistent.
No amplification across cycles.

fsync (per-file flush boundary)

Multiple independent n3 runs:

spikes_gt_200ms = 5–7
max_ns = 226M–297M
p99 elevated relative to controls


Interpretation:
Consistent stall reproduction.
Spikes align temporally with PROBE_B_END.
No PSI escalation during events.
Disk queue metrics show transient elevation.
Per-file flush boundary is a strong stall trigger.

buffered (write without fsync)
Runs:

spikes_gt_200ms = 3–6
max_ns = 326M–1.30B


Notable outlier:
max_ns = 1,308,155,159 ns (~1.3 seconds)


Interpretation:

Delayed writeback can generate severe outliers.
Even without explicit fsync, persistence pressure accumulates.
Writeback thread activity likely responsible.
Buffered writes alone are sufficient to produce large tail events.

Tail Behavior Summary
----------------------
Across all variants:

p50 remains stable (~101.7 ms)
p95 tightly bounded (~101.9–102.0 ms)
p99 minimally elevated except under fsync/buffered
No cumulative drift across cycles
No baseline degradation after R2

Stalls are:
Rare
Isolated
Non-cascading
Recovery remains bounded

Attribution Summary
--------------------
Day11 isolates the stall mechanism:

Not caused by:
Scheduling overhead
Probe loop structure
Memory dirties alone
Retry interference
PSI-level system pressure
Strongly associated with:
ext4 persistence boundaries
Per-file fsync
Delayed writeback flush

Stalls occur at device-level flush points, not at CPU or memory pressure boundaries.

Result Statement
-----------------
The R2 heartbeat stalls are causally linked to persistence boundary semantics on ext4.

Specifically:
Explicit fsync consistently reproduces >200 ms stalls.
Buffered writes can trigger delayed writeback spikes, including extreme outliers.
Memory-only writes (tmpfs) do not produce stalls.
No systemic instability or cumulative degradation observed.

The system demonstrates:
High central latency stability
Localized sensitivity to storage flush boundaries
Bounded and reversible stall behavior

Day11 successfully transitions attribution from “probe-specific” (Day10) to “persistence-boundary-specific.”

Conclusions
------------

Causal Mechanism Identified

Day10 established that stalls were probe specific and localized to PROBE_B.
Day11 isolates the internal boundary responsible for those stalls.

The evidence is consistent across independent n3 runs:
Scheduling alone does not cause stalls.
Memory dirties alone do not cause stalls.
tmpfs writes do not cause stalls.
Retry pressure does not amplify stalls.
PSI metrics remain near zero during spike windows.
Stalls occur when persistence boundaries are crossed on ext4.

Specifically:
fsync consistently produces 200 to 300 ms stalls.
Buffered writes can produce delayed writeback spikes.
Global sync produces weaker and inconsistent effects.

This establishes a storage flush boundary as the causal trigger.

Micro Blocking, Not System Saturation
Across all variants:

p50 remains stable.
p95 remains tightly bounded.
No progressive degradation across cycles.
No cumulative drift.
No persistent memory reclaim.
No PSI pressure escalation.
The system is not saturated.

The stalls represent micro blocking events at flush boundaries rather than macro level pressure or resource exhaustion.
This is a critical distinction.
The instability is localized and structural, not systemic.

Flush Semantics Matter

The decomposition shows three important behaviors:
Scheduling without IO has no effect.
Memory write without device persistence has no effect.
Device persistence boundary produces stalls.

This narrows the mechanism to:
Storage layer flush latency
Writeback commit boundary
Device level queue behavior

The extreme outlier under buffered writes suggests that delayed writeback can produce larger tail events than explicit fsync under some conditions.
This implies that implicit persistence can be more dangerous than explicit boundaries.

Determinism and Reproducibility

Stalls:

Reproduce consistently under fsync.
Align temporally with PROBE_B_END markers.
Do not appear in control variants.
Remain bounded and non cascading.

The phenomenon is:
Deterministic in mechanism
Stochastic in timing
Non progressive
Recoverable

This satisfies causal isolation.

Architectural Interpretation

In production systems, this pattern corresponds to:
Health checks touching persistence paths
Logging subsystems calling fsync
Checkpoint boundaries
Configuration writes
Journal commit boundaries

Under low background pressure, these boundaries can still introduce tail latency spikes.

However:
They do not imply instability.
They do not imply collapse.
They do not imply feedback amplification.

They represent flush latency sensitivity.

System Stability Profile

Under:

Sustained background retry patterns
Controlled burst interference
Probe decomposition
Per cycle telemetry attribution

The system demonstrates:
High central latency stability
Rare persistence boundary stalls
No amplification under realistic maintenance IO
Bounded recovery behavior

This is a resilient system with storage sensitivity, not an unstable one.

What Day11 Adds to Day10
Day10 answered:
Which probe action?

Day11 answers:
Which internal boundary inside that probe?

The answer is clear:
Persistence semantics on ext4, specifically flush boundaries, are responsible for R2 stalls.

What This Means Practically
If this were a production embedded system:
Avoid unnecessary fsync in high frequency diagnostic paths.
Batch writes where safe.
Separate critical latency paths from persistence boundaries.
Measure tail latency around commit operations, not just CPU or memory.
The risk is not average latency.
The risk is rare flush boundary blocking.