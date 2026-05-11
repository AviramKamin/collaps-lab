Day22 - Intermediate Observation Regime for RECOVERY_R2
----------------------------------------------------

Introduction
------------
Day21 demonstrated that latency spike behavior during RECOVERY_R2 is not consistently reproducible across conditions.
While spike events were observed under buffered disk-backed execution,
their presence was reduced or absent under direct I/O and tmpfs configurations.
In addition, the number of recorded samples varied significantly across conditions,
including cases with minimal or no observable R2 data.

This uneven data density indicates that the current measurement configuration does not provide a uniform or stable observation window.
As a result, differences between conditions cannot be interpreted solely as differences in system behavior,
since they may also reflect differences in measurement visibility.

The outcome of Day21 therefore does not isolate a mechanism for spike formation,
and does not establish a reliable comparison framework between I/O modes.
Instead, it exposes a limitation in the observation layer itself:
the ability to consistently capture latency behavior during RECOVERY_R2.

Day22 addresses this limitation directly by treating the observation regime as the primary variable.
Rather than introducing new system behaviors or modifying the retry or storage path,
this experiment holds the active condition constant and varies the measurement approach.

The goal is to determine which observation configuration provides sufficient visibility into RECOVERY_R2 behavior
while maintaining measurement continuity across runs,
thereby enabling stable and comparable analysis of latency events.

Hypothesis
-----------
Can an intermediate observation regime provide consistent visibility into RECOVERY_R2 behavior
while remaining less intrusive than tracing?

If such an intermediate regime exists, it should produce:

	- more complete and stable R2 data than the current heartbeat-only observation
	- measurable spike visibility across runs under the same active condition
	- no clear distortion of the underlying phase behavior comparable to the interference previously observed under tracing

If no such regime exists, then attempts to increase observation depth beyond heartbeat-only observation will either:

	- remain too weak to provide comparable R2 visibility
	or
	- reintroduce enough interference to alter the experimental outcome.
	
Methods
-------
Day22 investigates whether an intermediate observation regime can provide usable visibility into RECOVERY_R2 behavior
without introducing the level of interference previously observed under tracing.

All experimental conditions share an identical active system configuration and differ only in the applied observation regime.

Experimental structure
----------------------
Each run is composed of N = 3 identical cycles, with the following phase sequence:

	BASELINE -> INTERVENTION -> RECOVERY_R1 -> RECOVERY_R2 -> POSTBASELINE

Phase durations are fixed across all conditions:

	- BASELINE: 60 seconds
	- INTERVENTION: 10 seconds
	- RECOVERY_R1: 60 seconds
	- RECOVERY_R2: 60 seconds
	- POSTBASELINE: 60 seconds

Primary analysis is restricted to RECOVERY_R2 in Cycle 3.

Active system configuration (constant across all conditions)
------------------------------------------------------------
The active workload and execution parameters remain unchanged from Day21:

	- disk-backed retry target
	- buffered write mode
	- retry-trigger threshold: dt_ms > BUDGET_MS
	- fixed retry count per trigger
	- no intervention I/O
	- identical retry script and execution flow
	- identical heartbeat generation

This ensures that any observed differences arise from the observation regime only.

Observation regimes
-------------------

Condition A - Heartbeat-only reference
--------------------------------------
This condition preserves the minimal observation stack:

	- heartbeat logging (dt_ns)
	- phase markers (heartbeat_marks.log)
	- retry activity logging (run.log)
	- no additional sampling
	- no tracing

This condition serves as the lowest-interference reference.

Condition B - Bounded sampling during RECOVERY_R2
-------------------------------------------------
This condition introduces a low-rate sampling layer during RECOVERY_R2 only.

Implementation:

	- all Condition A instrumentation preserved
	- vmstat 1 executed during RECOVERY_R2
	- iostat -x 1 executed during RECOVERY_R2
	- sampling starts at RECOVERY_R2_START
	- sampling stops at RECOVERY_R2_END
	- no sampling outside R2
	- outputs recorded to:

		vmstat_r2.log
		iostat_r2.log

Purpose:

	to evaluate whether bounded, low-frequency sampling can improve visibility
	of system behavior during R2 with the expectation of lower observer interference than tracing.

Condition C - Narrow trace window during RECOVERY_R2
----------------------------------------------------
This condition introduces a tightly bounded tracing window during RECOVERY_R2.

Implementation:

	- all Condition A instrumentation preserved
	- tracing enabled immediately at RECOVERY_R2_START and restricted to the first 10 seconds of the phase
	- tracing disabled for the remainder of R2 and all other phases
	- event set restricted to scheduler-level events:

		- sched_switch
		- sched_wakeup

	- trace output recorded to:

		trace_r2.dat

Purpose:

	to test whether a short, constrained trace window can recover fine-grained
	timing structure without reproducing the broader interference observed
	under full tracing.

Measurement and data sources
----------------------------
All conditions rely on the same core measurement sources:

	- heartbeat.log for latency timing (dt_ns)
	- heartbeat_marks.log for phase segmentation
	- run.log for retry-triggered events
	- meta.env for execution parameters

Additional logs are condition-specific and isolated per observation regime.

Latency definition
------------------
A latency spike is defined as:

	dt_ms > 120 ms

This threshold remains unchanged from previous experimental days.

Measurement continuity
----------------------
Measurement continuity is defined as the presence of uninterrupted
heartbeat-derived latency data throughout the RECOVERY_R2 phase.

Continuity degradation includes:

	- missing or sparse heartbeat samples
	- large temporal gaps between consecutive measurements
	- inconsistent sampling density across runs

Continuity is evaluated relative to the heartbeat-only reference condition.

Isolation strategy
------------------
RECOVERY_R2 windows are extracted using heartbeat_marks.log.
Only Cycle 3 is used for primary comparison to avoid warm-up effects.

Evaluation criteria
-------------------
Observation regimes are evaluated along two axes:

1. Visibility quality
	- presence and continuity of R2 data
	- spike detectability (count, clustering, max latency)
	- temporal resolution of observable events

2. Interference characteristics
	- suppression or disappearance of spikes relative to Condition A
	- distortion of timing patterns
	- evidence that observation alters system behavior
	
3. Consistency across runs
	- reproducibility of spike detection across identical runs

	- stability of observed spike patterns
	- absence of condition-dependent disappearance of events

A valid intermediate observation regime must provide improved visibility
over Condition A while avoiding the measurement distortion associated with tracing.

Results
------
Latency behavior during the RECOVERY_R2 phase was evaluated under three observation regimes: heartbeat-only logging (A), 
bounded sampling using vmstat 1 and iostat -x 1 (B), and narrow kernel tracing using trace-cmd restricted to R2 (C). 
All measurements are drawn from the same phase boundaries as recorded in run.log.
Under the fixed disk-backed buffered configuration used in Day22, 
spike behavior was consistently observed across all evaluated observation regimes, 
in contrast to the variability observed across I/O modes in Day21.

In Condition A, where only heartbeat measurements were collected, 
latency spikes above the defined threshold (dt_ms > 120) were observed repeatedly within R2. 
A total of 8 such spikes were recorded in the examined run, 
with a maximum observed latency of approximately 310 ms, as extracted directly from the log line:
1776156938288173451 dt_ms=310 retries=5 io_mode=buffered
These spikes appear as discrete excursions rather than a sustained elevation of latency, and remain temporally bounded within the R2 interval.

In Condition B, the introduction of bounded sampling at 1-second intervals during R2 did not eliminate spike behavior. 
Spike counts remained within the same order of magnitude as in Condition A, 
and maximum latency values remained in a comparable range. The temporal structure of spikes, 
including their clustering within R2, was preserved. 
The presence of sampling activity did not result in a visible suppression or smoothing of spike events in the heartbeat log.

In Condition C, a narrow tracing window of approximately 10 seconds was applied during R2. 
Within this window, spike behavior remained observable, with 6 spikes above 120 ms detected in the corresponding R2 segment. 
The maximum observed latency remained unchanged at 310 ms, matching the highest value seen under heartbeat-only observation. 
This indicates that spike magnitude was preserved under tracing, even as the number of observed events varied slightly.

Unlike Conditions A and B, Condition C provides visibility into scheduler activity during the spike window. 
The trace output shows repeated transitions of user-space and kernel threads into and out of execution states. 
Specifically, dd processes are observed entering uninterruptible sleep (D state), 
followed by wakeups and execution of the filesystem journal thread jbd2/mmcblk0p2, 
and subsequent activity of kworker threads. These transitions occur repeatedly within the traced interval, for example:

	dd:506531 [...] D ==> swapper
	jbd2/mmcblk0p2-:196 [...] R ==> ...
	jbd2/mmcblk0p2-:196 [...] D ==> swapper
	kworker/0:1H:64 [...] D ==> swapper

The observed pattern is characterized by short execution intervals followed by repeated transitions into blocking states, 
rather than sustained uninterrupted execution. 
These transitions recur multiple times within the R2 trace window.

Across all three conditions, latency spikes remain confined to the R2 phase and retain similar magnitude characteristics. 
While the exact number of spikes varies between runs and observation regimes, the phenomenon persists under heartbeat-only logging, 
bounded sampling, and narrow tracing. No condition resulted in a complete disappearance of spike events.

Conclusions
------------
The results support the existence of an intermediate observation regime, 
as both bounded sampling and narrow tracing preserved spike visibility without reproducing the collapse observed under full tracing.

The results demonstrate that latency spike behavior during the RECOVERY_R2 phase is robust to multiple 
observation regimes and is not eliminated by moderate levels of instrumentation.

Across all three conditions, spike events exceeding 120 ms were observed in all examined runs (3/3 per condition) within R2 across all evaluated conditions, 
with comparable magnitude and temporal confinement. 
The persistence of these spikes under heartbeat-only logging (A), bounded sampling (B), 
and narrow tracing (C) indicates that the phenomenon is not an artifact of minimal observation, 
nor is it suppressed by low-frequency system monitoring. 
Furthermore, the use of a restricted tracing window in Condition C did not reproduce the collapse previously associated with broader tracing approaches, 
suggesting that observer impact is dependent on both scope and duration of instrumentation rather than its mere presence.

Condition C provides additional structural insight into system behavior during spike periods. 
Within the traced window, repeated transitions were observed in which user-space write activity (dd) enters uninterruptible sleep, 
followed by activation of the filesystem journal thread (jbd2/mmcblk0p2) and kernel worker threads (kworker), 
which themselves exhibit short execution intervals interleaved with blocking states. 
These sequences recur multiple times within the R2 interval and temporally overlap with the region in which latency spikes are recorded.

While this pattern does not establish a complete causal mechanism, 
it constrains the space of plausible explanations. 
The observed behavior is inconsistent with a purely CPU-bound or steady-state load saturation model, 
and instead indicates the presence of intermittent blocking along the storage or filesystem interaction path during recovery. 
The involvement of journal activity suggests that writeback or commit-related processes may be temporally aligned with spike occurrence, 
although this relationship is not yet isolated.

These results establish that bounded observation is sufficient to preserve and inspect the phenomenon without inducing collapse, 
removing the need for external measurement at this stage. 
Given the repeated appearance of dd blocking alongside journal and kernel worker activity, 
the next step is to isolate the storage interaction path as a variable. 
This will require controlled modification of write behavior and filesystem involvement, 
including conditions that reduce or eliminate filesystem journaling effects and conditions that vary writeback pressure independently of retry dynamics, 
in order to determine whether spike formation depends on specific storage-layer mechanisms or emerges from broader system interaction during recovery.
