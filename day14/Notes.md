|Day 14 – Block Layer Visibility and Writeback Interaction|
----------------------------------------------------------

Introduction
------------
Previous experiments established that the recurring ~200–250 ms latency
cluster is strongly associated with persistence-related filesystem
operations, particularly fsync interactions on ext4.

Day 11 isolated persistence boundaries as a likely trigger by showing that
tmpfs operations do not produce spikes while ext4 persistence operations
do. Day 12 further demonstrated that CPU scheduling placement does not
explain the phenomenon, suggesting that the source lies within the shared
storage path rather than compute contention.

Day 13 compared root ext4 behavior with loop-mounted ext4 on the same
device. The results showed that the spike cluster largely disappears
under loop-mounted ext4 configurations, while it remains present when
operating directly on the root filesystem. Rare long outliers (~1.2–1.3 s)
were also observed during root baseline measurements.

These observations suggest that the phenomenon may depend not only on
filesystem semantics but also on the broader storage environment in which
persistence operations occur.

The objective of Day 14 is therefore to introduce direct visibility into
block-device activity during experimental runs. Specifically, this day
aims to determine whether the recurring latency plateau correlates with
block layer write activity, device service time, or kernel writeback
behavior.

This experiment does not attempt to modify the workload or eliminate the
phenomenon. Instead, it introduces additional instrumentation in order to
observe the storage stack during spike events.


 Hypothesis
------------
If the ~200–250 ms latency plateau originates from storage stack
interactions below the filesystem layer, then spike events should coincide
with observable changes in block device activity.

Possible sources include:

- kernel writeback activity
- block queue service latency
- device flush operations
- delayed writeback bursts

If no correlation is observed, the mechanism may reside within filesystem
synchronization boundaries rather than deeper storage layers.



 Methods
------------
 Experimental Environment
---------------------------
Platform: Raspberry Pi 5  
Operating System: Linux (headless)  
Filesystem: ext4 (root filesystem)  
Storage Device: microSD (mmcblk0)

The experiment continues to use the Collapse Lab framework developed in
earlier days of the study.

All experiments are executed under stable thermal conditions with active
cooling enabled.


Workload
---------
The workload remains intentionally identical to the baseline persistence
tests used in previous days.

The probe action under investigation remains **PROBE_B**, which performs
persistence-sensitive operations that previously produced the observed
latency plateau.

Cycle structure:

- N_CYCLES: 3
- OFF window: 3 seconds
- probe program: low
- filesystem target: root ext4

This ensures that any observed differences are attributable to added
instrumentation rather than workload changes.

---

 Block Device Observation
-------------------------
To observe storage behavior during the experiment, block device statistics
are recorded continuously during the run.

Sampling source:
/proc/diskstats


Device monitored:
mmcblk0

Sampling frequency:
~100 ms interval


Each sample records:
- timestamp
- device read counters
- device write counters
- IO service time
- IO queue statistics

The sampling process runs concurrently with the experiment in order to
capture device behavior during latency spike windows.



 Data Collection
------------------
The following signals are collected during each run:
Heartbeat log:
heartbeat.log
This records scheduler wake intervals used to detect spike events.

Probe logs:
probes.log
These logs record the timing of probe actions during the experiment.

Block device statistics:
diskstats.log


These logs capture device-level activity during the experiment.

By aligning timestamps across these three signals, it becomes possible to
identify whether spike events correspond with bursts of storage activity.



 Expected Observations
-------------------------
Three broad outcomes are possible.

1. Spike events correlate with bursts of block-device activity

This would suggest that the plateau originates from device-level service
latency or writeback bursts.

2. Spike events correlate with flush or barrier operations

This would indicate that persistence boundaries interact with block-layer
synchronization points.

3. Spike events occur without noticeable block-device anomalies

In this case the mechanism may be internal to filesystem synchronization
logic rather than device-level behavior.

