# Collapse Lab – Study Inventory

This document summarizes the progression of the Collapse Lab study.
Each experimental day contributed a specific observation that shaped the
current understanding of system collapse behavior.

The study investigates how systems transition from stable operation
into timing instability and how they recover from such states.

This document serves as a **research map** of the project.


---

# Study Timeline

## Day 1 – Measurement Validation

Objective:
Validate the heartbeat measurement method and establish baseline scheduler jitter.

Observation:
Small timing drift was measurable under light IO pressure, and the system
returned cleanly to baseline once load stopped.

Contribution:
Established the **elastic deformation regime** of the system and confirmed
the sensitivity of the measurement instrumentation.


---

## Day 2 – Concurrency Paradox

Objective:
Increase IO concurrency to amplify scheduling contention.

Observation:
Despite higher IO activity, drift magnitude decreased and remained close
to baseline scheduler jitter.

Contribution:
Revealed that **contention structure matters more than load magnitude**.
Higher concurrency smoothed burstiness instead of amplifying instability.


---

## Day 3 – Elastic Deformation

Objective:
Apply heavier IO and retry pressure while maintaining recovery windows.

Observation:
Tail latency increased but the system fully recovered after load removal.

Contribution:
Confirmed the existence of a **stable elastic region** where timing
distortion occurs without collapse.


---

## Day 4 – Collapse Boundary Discovery

Objective:
Reduce recovery windows to test system resilience under repeated load cycles.

Observation:
When OFF windows became too short, the system began exhibiting collapse-like
behavior with visible latency spikes.

Contribution:
Identified the central principle of the study:

Collapse occurs when **recovery opportunity disappears**.


---

## Day 5 – Collapse Regime Exploration

Objective:
Observe behavior while operating near the collapse boundary.

Observation:
Retry subsystems exhibited severe instability while heartbeat latency
metrics remained mostly stable.

Contribution:
Showed that collapse can be **subsystem-local**, not necessarily visible
in global performance metrics.


---

## Day 6 – Recovery Fingerprint

Objective:
Examine the structure of the recovery phase.

Observation:
Recovery contained rare extreme latency outliers while baseline percentiles
remained stable.

Contribution:
Collapse memory appears in **recovery behavior**, not permanent baseline drift.


---

## Day 7 – Recovery Metastability

Objective:
Test the sensitivity of recovery using benign probes.

Observation:
Operations harmless during baseline produced large spikes during recovery.

Contribution:
Revealed that recovery is a **metastable phase** with elevated sensitivity
to perturbations.


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
Combine probe operations with background maintenance IO.

Observation:
Low-rate background IO did not significantly amplify recovery instability.

Contribution:
Demonstrated that collapse requires **specific stress structures**, not
simply overlapping workloads.


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
Spikes appeared when fsync interacted with ext4 persistence boundaries.
Tmpfs operations produced no spikes.

Contribution:
Identified filesystem persistence boundaries as a likely source of the
~200–250 ms latency cluster.


---

## Day 12 – Scheduling Mediation Test

Objective:
Determine whether CPU scheduling causes the spikes.

Observation:
CPU affinity changes did not remove spikes, while moving operations to
tmpfs eliminated them.

Contribution:
Confirmed the phenomenon is tied to **shared storage interaction**, not CPU scheduling.


---

## Day 13 – Root Filesystem Interaction

Objective:
Compare root ext4 behavior with loop-mounted ext4.

Observation:
Root ext4 produced recurring ~200–250 ms spike clusters and rare ~1.3 s
outliers, while loop-mounted ext4 largely eliminated them.

Contribution:
Suggested that the phenomenon depends on **filesystem topology and
storage path interaction**, not simply journaling mode.


---

# Current Collapse Model

Based on observations from Day 1–13, the system appears to exhibit
several behavioral phases:

1. Elastic deformation under load  
2. Collapse boundary when recovery time is insufficient  
3. Collapse regime where subsystems destabilize  
4. Metastable recovery with heightened sensitivity  
5. Return to stable baseline behavior  

Collapse therefore appears to be primarily a **timing failure**
caused by insufficient recovery opportunity between stress cycles.


---

# Observed Latency Phenomena

Two distinct latency patterns have emerged during the study.

### 1. Plateau Spike Cluster (~200–250 ms)

Observed across multiple experimental days.

Characteristics:

- appears repeatedly during persistence-related activity
- strongly correlated with fsync operations
- disappears under tmpfs or isolated loop configurations

Possible interpretation:

Interaction with filesystem persistence boundaries.


### 2. Rare Extreme Outliers (~1.2–2.5 s)

Observed infrequently across several runs.

Characteristics:

- significantly longer than plateau spikes
- not consistently tied to the same probe conditions
- may reflect delayed writeback or device service stalls

Further investigation is required.


---

# Open Investigation Threads

The following questions remain open in the study.

### Block Layer Attribution

Determine whether the plateau spikes originate in the
block layer, device queueing behavior, or filesystem
persistence mechanisms.

### Root Filesystem Interaction

Investigate why root ext4 exhibits spikes while loop-mounted
ext4 often eliminates them.

### Latency Oscillation Structure

Analyze the temporal spacing of spikes to determine whether
they align with kernel writeback or journaling cycles.

### Recovery Phase Geometry

Map the boundaries of the metastable recovery phase and
identify conditions that trigger recovery instability.

### Rare Outlier Mechanism

Investigate the recurring ~1.2–1.3 s latency spikes observed
in several experiments.

---

# Study Status

The Collapse Lab study is ongoing.

Current experiments have established multiple behavioral
patterns and candidate mechanisms, but further investigation
is required to determine the precise origin of the observed
latency phenomena.

Future work will focus on storage stack instrumentation,
block layer analysis, and deeper characterization of recovery dynamics.