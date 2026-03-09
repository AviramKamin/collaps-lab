Day13 – Journal and Flush Boundary Attribution
--------------------------------------------------

Purpose
-------
Day12 established that the previously observed >200ms heartbeat stalls are not mediated by CPU scheduling effects.

CPU affinity manipulation, including isolated-core placement and forced same-core contention, did not materially change spike frequency or magnitude.
The central latency distribution (p50, p95, p99) remained stable across all scheduling configurations.

Most critically, topology isolation revealed:

ext4 logging + ext4 probe (fsync) → reproducible >200ms spikes
ext4 logging + tmpfs probe (fsync) → spikes disappeared
CPU PSI and IO PSI remained 0.00
No reclaim activity
disk_wticks_d and disk_ioticks_d increased at spike alignment points

This demonstrated that the artifact is:

Storage topology dependent
Boundary driven
Discrete (no tail deformation)
Non-systemic
The phenomenon requires shared interaction with the ext4 block device.


Day12 therefore narrowed the causal surface from:

CPU scheduling effectsto
Storage flush and commit boundary behavior

However, Day12 did not distinguish between two remaining mechanisms:
ext4 journal commit semantics
Lower block-layer flush / barrier / device service latency effects

Both mechanisms can produce synchronous latency amplification near fsync boundaries.

Day13 isolates these mechanisms.
The goal is not to amplify the symptom.
The goal is attribution.

Hypotheses
----------
H1 – Journal Mediation Hypothesis

If spike amplification is driven primarily by ext4 journal commit semantics,
then altering ext4 mount behavior will materially change spike frequency, timing, or magnitude while keeping the storage stimulus identical.

Specifically:

Changing to data=writeback should alter ordering guarantees and therefore modify spike behavior.
Changing commit= interval should shift spike clustering relative to journal boundary timing.
Spike alignment relative to PROBE_B_END may shift under different commit intervals.
Spike count or amplitude may change under altered journal semantics.

If these effects are observed, journal ordering behavior is a primary mediating layer.

H2 – Commit Interval Sensitivity Hypothesis

If journal transaction boundary timing is the dominant amplification mechanism,
then reducing commit interval (e.g., commit=1) should:
Increase boundary frequency
Potentially increase spike frequency
Possibly reduce amplitude due to smaller transaction batching

Conversely, increasing commit interval (e.g., commit=30) should:
Reduce boundary frequenc
Potentially reduce spike frequency
Possibly increase amplitude if larger transactions are flushed synchronously

Observable differences in spike clustering or magnitude across commit intervals would support journal boundary involvement.

Experimental Design
--------------------
Controlled Variables

Across all Day13 variants:

Same cycle structure as Day12
Same RECOVERY_R2 window
Same heartbeat sampling interval (100ms)
Same spike threshold (>200ms)
Same PROBE B stimulus (fsync variant selected in Day12)
Same logging path
Same hardware (Raspberry Pi 5 + microSD)
Same CPU topology (no affinity manipulation)
Same telemetry collection strategy
N_CYCLES ≥ 3 per variant

No CPU scheduling experiments are introduced.
No additional IO amplification is introduced.
No probe intensity change is introduced.

Only ext4 mount semantics change.

Experimental Constraint
------------------------
The root filesystem (/dev/mmcblk0p2) is mounted as ext4 and cannot change
data journaling mode via remount.

The kernel reports:

EXT4-fs: Cannot change data mode on remount

To allow controlled ext4 mount parameter variation, a loop-backed ext4
filesystem will be created and mounted for the Day13 experiments.

Experiment directories (runs/ and workdir/) will be placed on this
filesystem via bind mounts.

This enables mount-option experimentation without modifying the root
device configuration.

The resulting topology becomes:

ext4 (loop filesystem)
- loop device
- ext4 (root)
- mmcblk0p2

Experimental Matrix
--------------------
V13-A – Baseline ext4 (Reference)

Mount configuration identical to Day12.

Goal:
Reproduce the previously observed spike signature under shared ext4 topology.

This establishes a stable reference for comparison.

V13-B – data=writeback Mount Variant

Mount option:
data=writeback

All other parameters identical to V13-A.

Goal:
Relax journal data ordering guarantees while preserving fsync stimulus.

If spike behavior materially changes relative to V13-A,
journal ordering semantics are implicated.

V13-C – Commit Interval Variation

Two controlled sub-variants:

V13-C1 – commit=1
V13-C2 – commit=30

All other parameters identical to V13-A.

Goal:
Alter journal transaction commit timing frequency without changing workload intensity.

If spike timing or clustering shifts with commit interval,
journal boundary involvement is likely.

If spike behavior remains invariant,
journal boundary timing is unlikely to be the dominant factor.

Measurement Strategy
---------------------
Primary Metrics (R2 Only):
sample_count
spikes_gt_200ms
p50_ns
p95_ns
p99_ns
max_ns

Per-Spike Attribution:

For each dt >200ms:

Align with:

PROBE_B_END marker
disk_wticks_d
disk_ioticks_d
Dirty pages delta
Writeback pages delta

Additionally:
Observe whether spike timing clusters around commit interval boundaries in commit=1 or commit=30 variants.

The goal is not to prove mount option changes performance.
The goal is to detect boundary-behavior sensitivity.

Collapse Signature Consistency
-------------------------------
The collapse-like artifact definition remains unchanged:

dt_ns > 200,000,000
Occurs within RECOVERY_R2
Stable p50 and p95
No sustained PSI pressure
No systemic tail deformation

Interpretation Framework
-------------------------
Evidence of Journal Mediation

If:

data=writeback materially alters spike frequency or amplitude
commit=1 or commit=30 shifts spike clustering or magnitude
Spike alignment changes relative to commit timing

Then:
Journal commit semantics are a primary mediating layer.
This suggests boundary-driven amplification occurs at the ext4 journal transaction layer.

Evidence of Block-Layer Dominance

If:
Spike behavior remains materially invariant across mount options
Spike amplitude remains ~230ms range
Spike alignment remains tightly coupled to fsync boundaries
No clustering change under commit interval variation

Then:
The dominant mechanism likely resides below journal semantics,
in block-layer flush or device service latency behavior.

This would justify escalation in Day14 toward:
Block queue inspection
Flush/barrier tracing
MMC service timing exploration

Results
--------

Experimental Matrix

All runs used the same workload parameters:

fsync-heavy probe workload (Probe B variant)
ON=3s / OFF=3s burst cycle
3 cycles per run
Baseline / Intervention / Recovery phases identical across runs
Heartbeat sampling interval: 100 ms
Probe density stayed consistent across runs (~800–900 probes per cycle), confirming the system remained active and the workload executed normally.

The experiment compared five storage configurations:

ID	Storage topology	ext4 options
R1	Root filesystem	ext4 (default)
L1	Loop filesystem	ext4 (default)
L2	Loop filesystem	ext4 data=writeback
L3	Loop filesystem	ext4 commit=1
L4	Loop filesystem	ext4 commit=30

Loop filesystem runs used an ext4 image (day13fs.img) mounted via loop at /mnt/day13fs and bind-mounted into the experiment directories.

Root ext4 Baseline (R1)

Filesystem:
/dev/mmcblk0p2 ext4 rw,noatime
Observed heartbeat behavior:
spikes >200 ms: 58
maximum observed latency: 1334 ms

Largest observed spikes:

1334 ms
463 ms
249 ms
244 ms
241 ms
237 ms
235 ms

A consistent spike cluster appears around ~230–250 ms.

Loop ext4 Baseline (L1)

Filesystem:
ext4 rw,relatime
(loop device backed by day13fs.img)
Observed heartbeat behavior:
spikes >200 ms: 0
maximum latency: ~116 ms
Largest gaps:

116 ms
110 ms
108 ms
106 ms

No spike cluster observed.

Loop ext4 with data=writeback (L2)

Filesystem:
ext4 rw,relatime,data=writeback
Observed heartbeat behavior:
spikes >200 ms: 0
maximum latency: ~115 ms

Largest gaps:

115 ms
109 ms
108 ms
107 ms

Latency distribution remains similar to loop baseline.

Loop ext4 with commit=1 (L3)

Filesystem:
ext4 rw,relatime,commit=1
Observed heartbeat behavior:
spikes >200 ms: 1
maximum latency: ~394 ms

Largest gaps:

394 ms
111 ms
110 ms
107 ms

Probe density remained high:

cycle_1: 839 probes
cycle_2: 839 probes
cycle_3: 790 probes

Loop ext4 with commit=30 (L4)

Filesystem:
ext4 rw,relatime,commit=30
Observed heartbeat behavior:
spikes >200 ms: 0
maximum latency: ~108 ms

Largest gaps:

108 ms
107 ms
106 ms
105 ms

Probe density:

cycle_1: 847 probes
cycle_2: 895 probes
cycle_3: 855 probes

Summary of Observed Latency
Configuration	spikes >200 ms	max latency
Root ext4			58			1334 ms
Loop ext4			0			~116 ms
Loop writeback		0			~115 ms
Loop commit=1		1			~394 ms
Loop commit=30		0			~108 ms


Observational Facts

Across all loop filesystem configurations:
the ~230–250 ms spike cluster observed on root ext4 did not appear
probe execution remained dense and continuous
system remained responsive during all runs
The workload and instrumentation were identical across runs.

Conclusions
------------
Experimental goal

Day13 investigated whether the latency spikes observed in earlier runs could be explained by ext4 journaling behavior or filesystem configuration. The experiment compared the same fsync-heavy probe workload across multiple storage topologies and ext4 mount configurations.

The tested configurations were:

Root filesystem (ext4 on /dev/mmcblk0p2)
Loop-mounted ext4 filesystem on the same SD card
Loop ext4 with data=writeback
Loop ext4 with commit=1
Loop ext4 with commit=30

All runs used identical workload parameters and probe density remained stable across cycles.

Primary Findings
1. Latency spike cluster appears on root ext4

When the workload ran directly on the root filesystem, 
repeated latency spikes above 200 ms were observed. A consistent cluster appeared around approximately 230–250 ms, with rare extreme outliers reaching ~1334 ms.
These spikes occurred while the system remained responsive and probe execution continued normally.

2. Moving the workload to an isolated loop filesystem removes the spike cluster
When the same workload was moved to an ext4 filesystem backed by a loop-mounted image on the same device, the latency spike cluster disappeared.
Across multiple loopfs configurations:
spikes >200 ms: 0
maximum latency remained near ~105–116 ms
This indicates the spike pattern is not caused by the workload itself.

3. ext4 journaling mode alone does not reproduce the behavior

Testing multiple ext4 configurations on the loop filesystem showed:

Configuration	spikes >200ms	max latency
loop ext4				0		~116 ms
loop ext4 + writeback	0		~115 ms
loop ext4 + commit=1	1		~394 ms
loop ext4 + commit=30	0		~108 ms

Changing ext4 journaling mode did not reproduce the spike cluster seen on the root filesystem.

Observational conclusions
---------------------------
The results indicate that the dominant latency spikes observed in earlier experiments are not explained by ext4 journaling mode alone.

Instead, the spike cluster appears to depend on the interaction between:
the root filesystem environment
flush and writeback behavior
the underlying SD/MMC storage path
Isolating the workload on a dedicated filesystem significantly reduces the observed tail latency.

Limitations
------------
This experiment does not identify the precise root cause of the latency spikes. 
Possible contributing factors include:

SD card internal flash management
root filesystem background writers
block layer writeback timing
MMC queue behavior

Further investigation at the block layer would be required to distinguish between these possibilities.

