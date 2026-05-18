Introduction
-------------
Day22 established that latency spike behavior during the R2 phase remains observable across different observation regimes, 
including minimal heartbeat logging, bounded sampling, and narrow tracing. Under a fixed disk-backed buffered configuration, 
spike events exceeding 120 ms were observed in all examined runs across all evaluated conditions, 
indicating that spike visibility is not dependent on the observation method itself.

In addition, scheduler trace analysis revealed that execution during spike windows is characterized by short running intervals followed by repeated transitions 
into blocking states. 
These transitions frequently involved disk-related processes, 
including write operations and filesystem journal activity, suggesting potential involvement of the storage path.

However, Day22 did not isolate whether spike formation depends on filesystem-level behavior, 
such as journaling and buffered writeback, or whether it originates from deeper layers of the disk-backed I/O path. 
The persistence of spikes under different observation regimes establishes their stability, but does not identify the mechanism responsible for their emergence.

Therefore, the objective of Day23 is to isolate the role of the storage path in spike formation by comparing disk-backed configurations 
with varying degrees of filesystem involvement. 
By controlling the I/O mode and reducing filesystem-related effects, 
this experiment aims to determine whether latency spikes in R2 require filesystem-level behavior or persist independently of it.

Hypothesis
-----------
If latency spikes observed during the R2 phase are dependent on filesystem-level behavior, 
then altering the storage configuration to reduce or modify filesystem and writeback involvement will result in a measurable change in spike behavior, 
including spike count, magnitude, or temporal distribution.

Conversely, if spike behavior persists across storage configurations with reduced filesystem involvement, 
then the underlying mechanism is likely not limited to filesystem-level processes and may originate from deeper layers of the disk-backed I/O path.

Methods
---------
Experimental Structure

All experiments followed the same phase-based execution model established in prior experiments, consisting of:

	BASELINE (B)
	INTERVENTION (I)
	RECOVERY_R1 (R1)
	RECOVERY_R2 (R2)

Latency was measured continuously using a heartbeat mechanism, 
with timestamps and dt_ms values recorded in run.log. 
Phase transitions were explicitly marked (e.g., C3_RECOVERY_R2_START, C3_RECOVERY_R2_END) to enable precise extraction of the R2 interval.

Each condition was executed across multiple cycles (3) under identical timing and retry parameters.

Measurement
-----------
Latency spikes were defined as events where dt_ms > 120.

For each run, analysis was restricted to the R2 phase using marker-based segmentation of run.log. 
Spike counts were computed as the number of events exceeding the defined threshold within the R2 interval.

In addition to spike count, maximum observed dt_ms and temporal clustering of spikes within R2 were examined directly from the logs.

Experimental Conditions
-------------------------
All conditions used the same retry-driven write workload, identical timing parameters, 
and the same execution environment. The only variable modified between conditions was the storage configuration used for write operations.

Condition A - Filesystem-backed buffered I/O (reference)

Write operations were performed on a standard disk-backed filesystem using buffered I/O. 
This configuration preserves normal filesystem behavior, including journaling and writeback mechanisms.

This condition serves as the reference for spike-producing behavior.

Condition B - Filesystem-backed direct I/O

Write operations were performed on the same disk-backed filesystem using direct I/O, bypassing the page cache.
This condition reduces buffered writeback effects while maintaining the same filesystem and underlying block device.

Condition C - Reduced filesystem involvement (disk-backed)

Write operations were directed to a disk-backed configuration with modified filesystem behavior, 
configured with modified mount parameters intended to reduce journaling and metadata activity relative to the reference condition.

This configuration preserves access to the underlying block device while minimizing filesystem-level involvement in the write path.

Control Considerations
-----------------------
	- All runs were executed on the same hardware and operating environment.
	- No additional tracing was enabled during primary runs.
	- Observation method was kept constant across conditions.
	- Background system activity was not intentionally introduced
	
Results
-------

The experiment evaluated three conditions with identical workload parameters, differing only in IO mode and filesystem target.

Condition A (buffered IO, default filesystem) produced consistent latency spikes during the RECOVERY_R2 phase across all cycles.
In Cycle 3, a total of 7 spikes exceeding 120 ms were observed, with a maximum latency of 318 ms.
Spike values included multiple events above 150 ms and several above 200 ms.

Condition B (direct IO, default filesystem) showed a significant reduction in spike activity.
In Cycle 3, only 1 spike exceeding 120 ms was observed, with a maximum latency of 153 ms.
No high-amplitude spike clusters comparable to Condition A were present.

Condition C (buffered IO, alternate filesystem path via loopback mount) exhibited strong spike activity similar to Condition A.
In Cycle 3, 7 spikes exceeding 120 ms were recorded, with a maximum latency of 411 ms.
Multiple spike events exceeded 200 ms, and several exceeded 300 ms.

Across all conditions, latency spikes were observed exclusively during the RECOVERY_R2 phase.
No comparable spike patterns were observed during BASELINE, INTERVENTION, or RECOVERY_R1 phases.

The retry workload was active in all conditions with identical parameters (RETRIES=5, BUDGET_MS=50), and execution timelines were consistent across cycles and conditions.

| Condition | IO Mode  | Filesystem Target      | Spike Count >120 ms | High Spikes (>200 ms) | Max dt_ms |
| --------- | -------- | ---------------------- | ------------------- | --------------------- | --------- |
| A         | buffered | default                | 7                   | multiple              | 318       |
| B         | direct   | default                | 1                   | none                  | 153       |
| C         | buffered | alternate (loop mount) | 7                   | multiple              | 411       |
-----------------------------------------------------------------------------------------------------------

Conclusions
------------

The results demonstrate a strong dependency between IO mode and the emergence of latency spikes during the RECOVERY_R2 phase.
Conditions A and C, both operating with buffered IO, consistently produced dense spike clusters with high latency values. 
In contrast, Condition B, which utilized direct IO, showed a substantial reduction in both spike frequency and spike amplitude.

The similarity in behavior between Conditions A and C, despite operating on different filesystem targets, 
indicates that the phenomenon is not driven by a specific filesystem layout or path. 
The persistence of spike activity under buffered IO across both filesystem configurations suggests that the underlying mechanism is not tied to a particular directory structure or mount location.

The results do not support the hypothesis that latency spikes depend on filesystem-level behavior.
Spike activity persisted across both filesystem configurations tested (Conditions A and C), 
indicating that modifying the filesystem path and reducing filesystem-related effects did not eliminate or substantially alter the phenomenon.

The suppression of spikes in Condition B isolates the buffered IO path as a necessary condition for the observed instability. 
Under identical workload parameters, 
removing buffered write behavior significantly altered the system’s latency profile during RECOVERY_R2, reducing both the number of spike events and their severity.
Additionally, the consistent confinement of spike activity to the RECOVERY_R2 phase across all conditions reinforces the observation that instability is not present during steady-state load 
or during initial recovery. 
Instead, it emerges at a specific phase boundary following the intervention period.
These findings suggest that the mechanism responsible for latency spikes is associated with buffered writeback behavior or related IO scheduling dynamics that become active during the recovery phase.

To further refine the understanding of this mechanism, 
the next experiment should aim to isolate the specific layer responsible for this behavior, distinguishing between page cache writeback processes and lower-level block device scheduling effects.