# Collapse Lab – Study Inventory

This document summarizes the progression of the Collapse Lab study.
Each experimental day contributed a specific observation that shaped the current understanding of system collapse behavior.

The study investigates how systems transition from stable operation into timing instability, how they recover, and which subsystem mechanisms express latency spikes during recovery.

This document serves as a **research map** of the project.

---

# Study Timeline

## Day 1 – Measurement Validation

Objective:
Validate the heartbeat measurement method and establish baseline scheduler jitter.

Observation:
Small timing drift was measurable under light I/O pressure, and the system returned cleanly to baseline once load stopped.

Contribution:
Established the **elastic deformation regime** of the system and confirmed the sensitivity of the measurement instrumentation.

---

## Day 2 – Concurrency Paradox

Objective:
Increase I/O concurrency to amplify scheduling contention.

Observation:
Despite higher I/O activity, drift magnitude decreased and remained close to baseline scheduler jitter.

Contribution:
Revealed that **contention structure matters more than load magnitude**. Higher concurrency smoothed burstiness instead of amplifying instability.

---

## Day 3 – Elastic Deformation

Objective:
Apply heavier I/O and retry pressure while maintaining recovery windows.

Observation:
Tail latency increased, but the system fully recovered after load removal.

Contribution:
Confirmed the existence of a **stable elastic region** where timing distortion occurs without collapse.

---

## Day 4 – Collapse Boundary Discovery

Objective:
Reduce recovery windows to test system resilience under repeated load cycles.

Observation:
When OFF windows became too short, the system began exhibiting collapse-like behavior with visible latency spikes.

Contribution:
Identified the central principle of the study: collapse occurs when **recovery opportunity disappears**.

---

## Day 5 – Collapse Regime Exploration

Objective:
Observe behavior while operating near the collapse boundary.

Observation:
Retry subsystems exhibited severe instability while heartbeat latency metrics remained mostly stable.

Contribution:
Showed that collapse can be **subsystem-local**, not necessarily visible in global performance metrics.

---

## Day 6 – Recovery Fingerprint

Objective:
Examine the structure of the recovery phase.

Observation:
Recovery contained rare extreme latency outliers while baseline percentiles remained stable.

Contribution:
Collapse memory appears in **recovery behavior**, not permanent baseline drift.

---

## Day 7 – Recovery Metastability

Objective:
Test the sensitivity of recovery using benign probes.

Observation:
Operations harmless during baseline produced large spikes during recovery.

Contribution:
Revealed that recovery is a **metastable phase** with elevated sensitivity to perturbations.

---

## Day 8 – Recovery Scarring Test

Objective:
Increase probe intensity to test whether recovery damage accumulates.

Observation:
Spike amplitude increased but no lasting degradation occurred.

Contribution:
Distinguished **transient sensitivity** from **permanent system damage**.

---

## Day 9 – Coupled Recovery Stress

Objective:
Combine probe operations with background maintenance I/O.

Observation:
Low-rate background I/O did not significantly amplify recovery instability.

Contribution:
Demonstrated that collapse requires **specific stress structures**, not simply overlapping workloads.

---

## Day 10 – Action Attribution

Objective:
Identify which probe operations trigger latency spikes.

Observation:
Only probe action **B** consistently produced >200 ms spikes.

Contribution:
Established that collapse-like artifacts can be **operation-specific**.

---

## Day 11 – Persistence Boundary Isolation

Objective:
Test filesystem persistence mechanisms.

Observation:
Spikes appeared when fsync interacted with ext4 persistence boundaries. Tmpfs operations produced no spikes.

Contribution:
Identified filesystem persistence boundaries as a likely source of the ~200–250 ms latency cluster.

---

## Day 12 – Scheduling Mediation Test

Objective:
Determine whether CPU scheduling causes the spikes.

Observation:
CPU affinity changes did not remove spikes, while moving operations to tmpfs eliminated them.

Contribution:
Confirmed the phenomenon is tied to **shared storage interaction**, not CPU scheduling alone.

---

## Day 13 – Root Filesystem Interaction

Objective:
Compare root ext4 behavior with loop-mounted ext4.

Observation:
Root ext4 produced recurring ~200–250 ms spike clusters and rare ~1.3 s outliers, while loop-mounted ext4 largely eliminated them.

Contribution:
Suggested that the phenomenon depends on **filesystem topology and storage path interaction**, not simply journaling mode.

---

## Day 14 – Block Device Persistence Boundary

Objective:
Test whether block-device persistence is required for spike formation.

Observation:
Spike behavior correlated with disk-backed persistence activity, but related instability was not fully explained by the block device alone.

Contribution:
Narrowed the mechanism toward storage interaction while keeping open the possibility that timing, recovery phase, and filesystem behavior jointly shape spike expression.

---

## Day 15 – Scheduler Trace Visibility and Observer Effect

Objective:
Use scheduler tracing to inspect kernel activity around latency spikes.

Observation:
Tracing exposed useful scheduling activity but also disturbed the system, making it difficult to separate true system behavior from observer-induced effects.

Contribution:
Established that **observation method is itself an experimental variable**. Full or broad tracing can amplify or alter the phenomenon being measured.

---

## Day 16 – Low-Intrusion System Sampling

Objective:
Replace high-volume tracing with lower-intrusion sampling via `/proc` interfaces.

Observation:
Latency spikes persisted, including events above 200 ms and near ~800 ms, but sampled CPU, interrupt, and softirq metrics did not show corresponding abrupt anomalies.

Contribution:
Showed that the residual spike mechanism is not visible in coarse-grained system-wide metrics and is not directly explained by CPU, interrupt, or softirq activity at the sampled resolution.

---

## Day 17 – High-Resolution Timing Around Phase Transitions

Objective:
Increase heartbeat timing resolution and align spike events precisely with phase boundaries.

Observation:
The intervention phase did not produce high-latency events. A single extreme spike (~707 ms) appeared at the start of RECOVERY_R1, while smaller high-latency deviations clustered mainly around RECOVERY_R2.

Contribution:
Established that latency behavior is **phase-dependent** and not expressed during sustained load. Recovery is not a uniform state; R1 and R2 exhibit different latency characteristics.

---

## Day 18 – Transition-Driven vs State-Dependent Behavior

Objective:
Distinguish whether spikes are caused by phase transitions themselves or by accumulated system state released at transitions.

Observation:
Latency spikes consistently appeared after transition into RECOVERY_R2. Advancing the R2 transition shifted the spike cluster and increased spike density, while increasing prior intervention duration did not produce comparable amplification.

Contribution:
Supported a **boundary-triggered model**: the transition into RECOVERY_R2 acts as the trigger, while pre-transition state modulates intensity and persistence.

---

## Day 19 – Mechanism Isolation: Scheduler, I/O, and Retry Axes

Objective:
Move from behavioral characterization to subsystem-level mechanism isolation.

Observation:
RECOVERY_R2 spike expression appeared only under selected conditions. Retry intensity affected timing of spike onset, but did not proportionally scale spike count. Some conditions produced sustained R2 spike clusters, while others produced none.

Contribution:
Showed that RECOVERY_R2 entry alone is not sufficient. Spike expression is gated by additional condition-specific factors involving retry dynamics, storage path behavior, or their interaction.

---

## Day 20 – Storage Path Participation vs Retry Dynamics

Objective:
Determine whether retry dynamics alone are sufficient to generate instability, or whether the retry storage path is required.

Observation:
Disk-backed retry execution produced sustained RECOVERY_R2 spike clusters. Redirecting retry execution to tmpfs eliminated spike expression, regardless of prior intervention I/O.

Contribution:
Isolated the **disk-backed retry storage path** as a necessary trigger surface under the current design. Retry timing alone was not sufficient to produce spikes without disk-backed execution.

---

## Day 21 – Buffered Writeback vs Direct I/O Attempt

Objective:
Compare buffered disk-backed retry execution with direct I/O retry execution to test whether buffered writeback is required.

Observation:
Buffered execution produced multiple spikes, direct I/O produced sparse spike data, and tmpfs produced no recorded R2 data. Sample density varied sharply across conditions.

Contribution:
The experiment was **inconclusive** as a mechanism isolation step because observability collapsed across conditions. It demonstrated that the comparison framework itself needed stabilization before causal conclusions could be drawn.

---

## Day 22 – Intermediate Observation Regime

Objective:
Find an observation regime that preserves spike visibility without reproducing the disturbance associated with broad tracing.

Observation:
Spikes remained visible under heartbeat-only logging, bounded vmstat/iostat sampling, and a narrow 10-second scheduler trace window during RECOVERY_R2. Narrow tracing revealed repeated patterns involving `dd` entering D state, `jbd2/mmcblk0p2` wakeups, and `kworker` activity.

Contribution:
Established that bounded observation is sufficient to inspect the phenomenon without inducing collapse. The mechanism space narrowed toward intermittent blocking along the storage/filesystem interaction path during recovery.

---

## Day 23 – Buffered Writeback vs Filesystem Path Effects

Objective:
Determine whether RECOVERY_R2 spikes depend on filesystem-level path/layout behavior or on buffered I/O behavior.

Observation:
Buffered I/O on the default filesystem and buffered I/O on an alternate loopback-mounted filesystem both produced dense spike clusters. Direct I/O on the default filesystem sharply reduced spike activity, producing only one >120 ms spike and no comparable cluster.

Contribution:
Reduced support for a filesystem-path or mount-location explanation. Isolated the **buffered writeback path** as the critical factor associated with RECOVERY_R2 latency spikes under the current configuration.

---

# Current Collapse Model

Based on observations from Day 1–23, the system appears to exhibit several behavioral phases:

1. Elastic deformation under load
2. Collapse boundary when recovery time is insufficient
3. Subsystem-local collapse where retry or storage paths destabilize
4. Metastable recovery with heightened sensitivity
5. Boundary-triggered instability at specific recovery transitions
6. Storage-path-dependent spike expression during RECOVERY_R2
7. Return toward stable baseline behavior after the instability window decays

The current model is no longer simply “load causes latency.”

The stronger model is:

- sustained load does not directly produce the main spike class
- instability is triggered at the RECOVERY_R2 boundary
- spike expression requires a disk-backed storage interaction path
- buffered write behavior strongly amplifies or enables the observed spike clusters
- bounded observation can expose storage/filesystem blocking patterns without destroying the experiment

Collapse therefore appears to be a **timing and recovery-path failure**, expressed through a storage interaction mechanism rather than simple CPU saturation or steady-state load.

---

# Observed Latency Phenomena

Three latency patterns have emerged during the study.

## 1. Plateau Spike Cluster (~200–250 ms)

Observed across multiple experimental days.

Characteristics:

- appears repeatedly during persistence-related activity
- strongly correlated with fsync or disk-backed write behavior
- suppressed or eliminated under tmpfs
- reduced under direct I/O compared with buffered I/O
- concentrated during RECOVERY_R2 rather than sustained load

Current interpretation:

Interaction with the buffered disk-backed storage path, likely involving writeback, journaling, queueing, or scheduler interaction with blocked I/O.

## 2. Rare Extreme Outliers (~700 ms to ~1.3 s+)

Observed infrequently across several runs.

Characteristics:

- significantly longer than plateau spikes
- not consistently reproduced across cycles
- may appear near recovery phase boundaries
- not yet tied to a single isolated mechanism

Current interpretation:

Possible deeper storage-stack or delayed service event. Further investigation is required.

## 3. Recovery-Phase Spike Clusters

Observed repeatedly after transition into RECOVERY_R2.

Characteristics:

- phase-local rather than globally distributed
- appear after load removal rather than during active intervention
- can persist for tens of seconds within the recovery phase
- self-decay within the phase

Current interpretation:

A boundary-triggered instability regime modulated by the pre-transition state and expressed through the storage/writeback path.

---

# Open Investigation Threads

The following questions remain open in the study.

## Buffered Writeback Attribution

Determine whether the plateau spikes originate from page cache writeback, journal commit activity, dirty page flushing, or interaction between writeback and retry timing.

## Block Layer and Queueing Attribution

Determine whether the latency cluster originates below the filesystem in the block layer, device queueing, microSD service latency, or I/O scheduler behavior.

## Scheduler and I/O Interaction

Investigate whether user-space write blocking, `jbd2` activity, and `kworker` execution are causal participants or only correlated signals during spike windows.

## Recovery Phase Geometry

Map the conditions that make RECOVERY_R2 unstable and determine why R1 and R2 exhibit different latency profiles.

## Observation Regime Design

Continue using bounded observation regimes that preserve spike visibility without amplifying the phenomenon.

## Rare Outlier Mechanism

Investigate rare high-magnitude latency events separately from the repeatable ~200–300 ms plateau cluster.

---

# Study Status

The Collapse Lab study is ongoing.

Current experiments have moved the project from broad behavioral observation into mechanism narrowing.

The current best-supported interpretation is that the dominant RECOVERY_R2 spike cluster is not caused by CPU saturation, steady-state load, generic retry timing, or filesystem path/layout alone.

The strongest current candidate is buffered disk-backed write behavior, with likely involvement of writeback, journaling, or block-layer scheduling during recovery.

Future work should focus on decomposing the buffered storage path into smaller mechanisms:

- buffered vs direct write behavior
- page cache and dirty page pressure
- journal commit timing
- block-layer queueing
- microSD service latency
- scheduler interaction with blocked I/O

The objective of the next stage is to move from “buffered storage path required” to identifying the specific subsystem interaction responsible for the RECOVERY_R2 latency spike regime.
