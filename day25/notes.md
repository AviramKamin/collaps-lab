Day25 - Synchronized vs Unsynchronized Buffered Writes

Introduction
-------------
Previous experiments established that latency spikes are consistently localized to the RECOVERY_R2 phase and require disk-backed buffered IO for strong expression. 
Filesystem target and mount configuration were shown not to control spike manifestation under the tested conditions.

Day24 investigated the role of writeback dynamics within the buffered IO path by modifying writeback policy parameters. 
While these manipulations produced distinct buffered-state regimes, they did not result in directional divergence in spike behavior. 
Spike count, peak latency, and cluster duration remained comparable across conditions, 
indicating that writeback policy does not exert first-order control over spike manifestation.

Notably, both early and delayed writeback configurations produced earlier spike onset relative to the default condition, 
despite opposing policy directions. This suggests that spike behavior may be sensitive to changes in buffered IO execution dynamics, 
rather than to the direction of writeback scheduling itself.

Based on these findings, the next step is to investigate whether latency spike manifestation is governed by write completion behavior within the buffered IO path, 
specifically the distinction between asynchronous buffered writes and enforced synchronous completion.

Hypothesis
-----------

If latency spike manifestation during RECOVERY_R2 is governed by write completion behavior within the buffered IO path, 
then changing write completion semantics while holding workload, timing, retry behavior, IO target, 
and observation method constant will produce a measurable change in the spike regime.

Specifically, enforcing synchronous completion after each write is expected to alter one or more of the following:

	- spike count
	- maximum latency
	- first spike offset
	- cluster duration

If synchronous completion does not materially change these metrics relative to unsynchronized buffered writes, 
then write completion semantics are unlikely to be the primary control mechanism for spike manifestation under the tested conditions.

Methods
--------

Experimental Design
---------------------
Day25 uses a three-condition comparison designed to isolate write completion semantics within the buffered disk-backed IO path.
All conditions preserve identical workload structure, retry behavior, timing parameters, IO target, and observation method.
The only variable modified between conditions is the level of synchronization enforced after each write operation.

Experimental Conditions
--------------------------
Condition A – Unsynchronized buffered writes

Write operations are performed using the default buffered IO path without explicit synchronization.

This condition does not use:

	fsync
	fdatasync
	O_SYNC
	O_DSYNC
	conv=fsync

Condition A serves as the reference condition for buffered disk-backed writes without enforced completion.

Condition B – Fully synchronized buffered writes
----------------------------------------------------
Write operations are performed using the same buffered disk-backed path, but each write is followed by enforced full synchronization.
This condition ensures that both file data and associated metadata are flushed to storage before execution continues.

Synchronization is implemented using fsync-equivalent behavior.

Condition C – Data-synchronized buffered writes
------------------------------------------------
Write operations are performed using the same buffered disk-backed path, 
but each write is followed by data synchronization without full metadata synchronization.
This condition ensures that file data is flushed while minimizing metadata-related synchronization.

Synchronization is implemented using fdatasync-equivalent behavior.

Execution Model
-------------------
All runs follow the established phase sequence:

	- BASELINE
	- INTERVENTION
	- RECOVERY_R1
	- RECOVERY_R2
	- POSTBASELINE

Each condition is executed across three cycles using identical timing parameters:

	- BASELINE: 60 seconds
	- INTERVENTION: 10 seconds
	- RECOVERY_R1: 60 seconds
	- RECOVERY_R2: 60 seconds
	- POSTBASELINE: 60 seconds

Primary analysis is restricted to RECOVERY_R2 in Cycle 3.

Workload

The retry workload performs repeated write operations to a disk-backed target path.

The retry mechanism remains unchanged across all conditions:

	- identical retry count
	- identical budget threshold
	- identical target path
	- identical write size
	- identical loop structure
	- identical phase activation window

Retry activity is confined to RECOVERY_R2.

No additional IO workload is introduced.

Control Variables
-------------------
The following parameters are held constant across all conditions:

	- hardware and operating environment
	- filesystem target
	- IO target path
	- retry script structure
	- write size
	- retry count
	- budget threshold
	- phase timing
	- number of cycles
	- observation method
	- writeback policy
	- logging format

No tracing instrumentation, background IO, scheduler competition, filesystem changes, or sysctl modifications are introduced.

Variable Under Test

The only variable under test is write completion semantics:

	- Condition A allows writes to return through the default buffered path
	- Condition B enforces full synchronization after each write
	- Condition C enforces data-only synchronization after each write

This isolates whether spike manifestation is sensitive to completion behavior and whether metadata-related synchronization contributes to the observed instability.

Measurement
------------
Latency is measured using the existing heartbeat and retry timing framework.

A latency spike is defined as:

dt_ms > 120

For each condition, RECOVERY_R2 is extracted using marker-based segmentation from heartbeat_marks.log.

Metrics
--------
The following metrics are computed within Cycle 3 RECOVERY_R2:

	- spike count (dt_ms > 120)
	- maximum latency (max dt_ms)
	- first spike offset from RECOVERY_R2 start
	- cluster duration (time between first and last spike)

Cluster duration is defined as the elapsed time between the first and last spike within the RECOVERY_R2 window.

Interpretation
---------------
If synchronization level produces a material change in spike count, 
maximum latency, onset timing, or cluster duration, then spike manifestation is sensitive to write completion semantics.

Comparative interpretation:

	- If Condition B differs significantly from Condition A, completion enforcement is implicated
	- If Condition B differs from Condition C, metadata-related synchronization contributes to spike behavior
	- If Conditions B and C behave similarly and differ from A, completion semantics (not metadata) are implicated
	- If all conditions remain comparable, write completion semantics are unlikely to be the primary control mechanism, and the source likely resides deeper within the buffered IO execution path
	
Results
--------

Overview

Three experimental conditions were evaluated under identical workload, timing, and observation constraints, differing only in write completion behavior:

	Condition A – unsynchronized buffered writes
	Condition B – buffered writes with full synchronization (fsync)
	Condition C – buffered writes with data-only synchronization (fdatasync)

Analysis was restricted to RECOVERY_R2 in Cycle 3.

Condition A – Unsynchronized Buffered Writes
----------------------------------------------
Within RECOVERY_R2, latency events above the defined spike threshold (dt_ms > 120) were sparse.

Observed values:

	- Spike count: 2
	- Maximum latency: 124 ms
	- First spike offset from RECOVERY_R2 start: 20417.823 ms
	- Cluster duration: 17404.055 ms

The detected spikes were limited in number and occurred later within the RECOVERY_R2 phase. No high-magnitude outliers beyond 124 ms were observed.

Condition B – Fully Synchronized Buffered Writes
--------------------------------------------------
Within RECOVERY_R2, latency spikes were more frequent and appeared earlier relative to phase start.

Observed values:

	- Spike count: 5
	- Maximum latency: 183 ms
	- First spike offset from RECOVERY_R2 start: 6114.481 ms
	- Cluster duration: 37348.936 ms

Multiple spike events exceeding 120 ms were distributed throughout the RECOVERY_R2 window. Peak latency increased relative to Condition A.

Condition C – Data-Synchronized Buffered Writes
------------------------------------------------
Within RECOVERY_R2, latency spikes were consistently present, with early onset and extended persistence.

Observed values:

	- Spike count: 6
	- Maximum latency: 182 ms
	- First spike offset from RECOVERY_R2 start: 4371.280 ms
	- Cluster duration: 49958.228 ms

Spike events above 120 ms occurred throughout the majority of the RECOVERY_R2 interval. 
The earliest spike onset and longest cluster duration among all conditions were observed in this condition.

Comparative Summary
Condition	Sync Mode	Spike Count (>120 ms)	Max dt_ms	First Spike Offset (ms)	Cluster Duration (ms)
A			 none			2					124				20417.823				17404.055
B			 fsync			5					183				6114.481				37348.936
C			fdatasync		6					182				4371.280				49958.228


Observed Patterns
------------------
Across conditions, measurable differences were observed in:

	- spike frequency
	- peak latency values
	- temporal position of first spike within RECOVERY_R2
	- duration of spike clustering

Condition A exhibited the lowest spike count and latest onset.
Conditions B and C exhibited increased spike counts, earlier onset, and extended clustering within RECOVERY_R2.
No deviations were observed in phase structure, workload execution, or logging consistency across conditions.


Conclusions
------------
The results demonstrate that modifying write completion semantics within the buffered IO path produces a measurable change in the latency spike regime during RECOVERY_R2.

Condition A, which employed unsynchronized buffered writes, exhibited a reduced spike profile characterized by lower spike count, 
lower peak latency, delayed spike onset, and shorter clustering duration. In contrast, 
both synchronized conditions (B and C) showed consistent increases across all measured metrics, including higher spike counts, 
increased maximum latency, earlier spike onset, and longer clustering duration.

These differences directly address the stated hypothesis. 
The transition from unsynchronized to synchronized write behavior resulted in observable and systematic changes in:

spike count
maximum latency
first spike offset
cluster duration

Because all other variables - workload, timing, retry behavior, 
IO target, and observation method - were held constant, the observed changes can be attributed to differences in write completion behavior.

Therefore, the results support the hypothesis that latency spike manifestation during RECOVERY_R2 is sensitive to write completion semantics within the buffered IO path.
The null condition defined in the hypothesis, in which synchronization does not materially alter spike behavior, is not supported by the observed results.

A further comparison between Conditions B and C shows that data-only synchronization produces a spike regime comparable to, 
and in some metrics stronger than, full synchronization. 
Both conditions exhibit similar maximum latency values, while Condition C shows slightly higher spike count, earlier onset, and longer clustering duration. 
This indicates that the observed effect does not require full metadata synchronization and can be reproduced through data-level completion alone.

These findings constrain the possible mechanisms underlying the observed instability. 
Explanations that rely solely on deferred writeback scheduling without accounting for completion behavior are not sufficient to explain the differences observed between conditions. 
Instead, the results indicate that the enforcement of write completion within the buffered IO path is associated with the timing and persistence characteristics of latency spikes.

Further investigation is required to determine whether the observed effect arises from the completion operation itself or from the introduction of blocking within the execution path. 
A subsequent experiment should isolate execution blocking duration from IO completion by comparing enforced synchronization with controlled artificial delays of equivalent duration. 
This will allow differentiation between spike behavior driven by completion semantics and spike behavior driven by execution blocking, 
thereby narrowing the underlying mechanism responsible for latency spike manifestation.