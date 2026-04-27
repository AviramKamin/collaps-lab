Day20 - Storage Path Participation vs Retry Dynamics in RECOVERY_R2

Introduction
------------
Day19 demonstrated that latency spikes in RECOVERY_R2 do not emerge uniformly across conditions, 
and that retry intensity influences the timing of spike onset without proportionally scaling spike count. 
Conditions A and B showed no spike expression within RECOVERY_R2 in Cycle 3, 
while Conditions C and D exhibited sustained spike activity within the same phase. 
This separation indicates that phase entry alone is insufficient to trigger instability.

The observed behavior raises a critical question regarding the underlying mechanism of spike formation. Specifically, 
whether retry dynamics alone are sufficient to generate latency instability, 
or whether participation of the storage path is required for instability to manifest.

Day20 isolates this question by preserving retry activity while altering the nature of the storage path. 
By comparing disk-backed retry execution with retry execution on tmpfs, 
the experiment tests whether removal of real storage contention suppresses spike formation in RECOVERY_R2.

The goal is to determine whether latency instability is a product of retry timing alone, or whether it requires interaction with the block and filesystem layers.

Hypothesis
----------
Latency instability in RECOVERY_R2 requires participation of the storage path.
If retry dynamics alone are sufficient to generate instability, 
then preserving retry activity while executing on tmpfs should still produce spike clusters within RECOVERY_R2.

If, however, interaction with the block and filesystem layers is required,
then removing real storage contention by using tmpfs will suppress or eliminate spike expression within RECOVERY_R2, even when retry pressure is preserved.

Accordingly, spike presence, onset timing, 
and cluster structure within RECOVERY_R2 are expected to differ between disk-backed and tmpfs conditions 
if storage-path participation is a necessary component of the mechanism.

Methods
-------
Day20 preserves the experimental structure and measurement framework established in Day19, 
while isolating storage-path participation as the primary independent variable.

All conditions follow an identical phase sequence:

BASELINE → INTERVENTION → RECOVERY_R1 → RECOVERY_R2 → POSTBASELINE

Each run consists of N = 3 cycles. Phase durations are fixed across all conditions:

	- BASELINE: 60 seconds  
	- INTERVENTION: 10 seconds  
	- RECOVERY_R1: 60 seconds  
	- RECOVERY_R2: 60 seconds  
	- POSTBASELINE: 60 seconds  

No modifications are made to phase timing or cycle structure relative to Day19.

Retry logic is active in all conditions and is held constant unless explicitly varied. 
The retry mechanism and its execution pattern remain unchanged from previous experiments.

The primary manipulation in Day20 is the location of the retry target:

	- Disk-backed execution: retry operations interact with the standard filesystem and underlying block device  
	- tmpfs execution: retry operations are redirected to a memory-backed filesystem, 
	  removing block-layer participation while preserving retry timing and execution flow  

No scheduler competitor or additional load beyond the preserved experimental phase structure is introduced.
This ensures that any observed differences arise from storage-path participation rather than scheduling interference.

All runs are executed without intrusive tracing tools. 
Measurement relies on the existing instrumentation framework:

	- heartbeat logging for latency measurement (dt_ms)  
	- phase markers recorded in heartbeat_marks.log  
	- retry activity recorded in run.log  
	- auxiliary probe signals recorded in probes.log  

Data extraction focuses on RECOVERY_R2 in Cycle 3, using phase markers to define the analysis window.

Primary metrics:

	- spike count above threshold (dt_ms > 120 ms)  
	- maximum observed latency  
	- time-to-first-spike relative to RECOVERY_R2_START  
	- spike cluster duration within RECOVERY_R2  

These metrics are computed using the same extraction and filtering procedures established in Day19 to ensure direct comparability between experiments.

Experimental conditions
------------------------
Day20 uses two primary conditions and one optional escalation condition.

Condition A - Disk-backed retry reference
------------------------------------------
This condition preserves the standard retry target on the project filesystem.

Implementation:

	* retry target remains on the standard disk-backed filesystem
	* retry intensity is fixed at the reference level (RETRIES=5)
	* no scheduler competitor is introduced
	* phase structure and timing remain unchanged

Purpose:

	provide the active reference condition for RECOVERY_R2 spike expression under normal storage-path participation

Condition B - tmpfs retry condition
------------------------------------
This condition redirects the retry target to tmpfs while preserving retry behavior.

Implementation:

	* retry target is redirected to a tmpfs path
	* retry intensity remains fixed at the reference level (RETRIES=5)
	* no scheduler competitor is introduced
	* phase structure and timing remain unchanged

Purpose:

	test whether RECOVERY_R2 spike expression persists when block-layer participation is removed

Condition C - tmpfs elevated retry condition (optional)
--------------------------------------------------------
This condition increases retry intensity while preserving tmpfs execution.

Implementation:

	* retry target remains on tmpfs
	* retry intensity is increased above the reference level (recommended: RETRIES=10)
	* no scheduler competitor is introduced
	* phase structure and timing remain unchanged

Purpose:

	test whether stronger retry pressure can restore spike expression in the absence of real storage-path participation

This condition is executed only if Conditions A and B do not provide a sufficiently clear discriminator.

Analysis window
----------------
Primary analysis is restricted to the RECOVERY_R2 phase of Cycle 3.
Only events occurring between the RECOVERY_R2 start and end markers of Cycle 3 are included in the primary comparison table.
Spike activity observed in other phases or cycles may be examined separately, but is not used as the primary discriminator in Day20.

Spike definition
-----------------
A latency spike is defined as any event with dt_ms > 120 ms.
This threshold is held constant from Day19 in order to preserve direct comparability between experiments.

Analysis plan
-----------------
Analysis follows the same extraction and computation procedure established in Day19 in order to ensure direct comparability across experiments.
For each run, RECOVERY_R2 in Cycle 3 is isolated using phase markers from heartbeat_marks.log. 
Latency values (dt_ms) are extracted from run.log within this window.

The following metrics are computed for each condition:

	* spike count (dt_ms > 120 ms)
	* maximum observed latency within R2
	* time-to-first-spike relative to RECOVERY_R2_START
	* spike cluster duration within R2

Time-to-first-spike is defined as:
	the elapsed time between RECOVERY_R2_START and the first dt_ms value exceeding 120 ms

Spike cluster duration is defined as:
	the elapsed time between the first and last spike (dt_ms > 120 ms) within the R2 window

All metrics are computed using the same command-line extraction and filtering approach used in Day19.

Comparison strategy
-------------------
Results are compared across conditions using a structured comparison table.
Interpretation focuses on the presence, timing, and structure of spike activity within RECOVERY_R2.
The primary discriminator is whether spike expression persists when transitioning from disk-backed execution to tmpfs execution.

Interpretation guidelines:

	* If spike count collapses or becomes zero in tmpfs conditions, this supports the requirement of storage-path participation
	* If spike activity remains comparable in tmpfs conditions, this supports a retry-driven mechanism independent of storage-path cost
	* If spike activity is reduced but not eliminated, this suggests a combined mechanism in which storage-path participation amplifies or stabilizes instability rather than generating it alone

No conclusions are drawn from activity outside RECOVERY_R2 unless explicitly stated.

Results
---------
Latency behavior was evaluated across four conditions during the RECOVERY_R2 phase using a threshold of dt_ms > 120 ms.
All measurements were extracted from the same temporal window defined by phase markers.

In Condition A, latency spikes were observed during RECOVERY_R2, forming a continuous cluster over an extended portion of the phase.
Multiple events exceeded the threshold, with peak values reaching 312 ms.
The first spike appeared several seconds after the start of RECOVERY_R2, 
followed by repeated spike occurrences distributed across the remainder of the phase window.

In Condition B, no latency spikes were observed.
All recorded dt_ms values remained below the defined threshold throughout RECOVERY_R2.
No clustering behavior or elevated latency events were detected at any point within the phase.

In Condition C, latency spikes were again observed during RECOVERY_R2.
The spike pattern was similar in structure to Condition A, consisting of multiple events above the threshold and forming a sustained cluster.
The maximum observed latency reached 261 ms.
Spike onset occurred several seconds into the phase, 
followed by continued spike activity over a prolonged interval.

In Condition D, no latency spikes were observed.
All dt_ms values remained below the threshold, and no clustering behavior was present during RECOVERY_R2.
The phase remained stable for its entire duration.

Across all conditions, spike activity, when present, was confined to the RECOVERY_R2 phase.
No comparable spike patterns were observed during BASELINE, INTERVENTION, or RECOVERY_R1 in any of the runs.

The quantitative measurements for each condition are summarized below:

Condition | Retry Target | Intervention IO | Spike Count | Max dt (ms) | First Spike (ms) | Cluster Duration (ms)
----------|--------------|-----------------|-------------|-------------|------------------|----------------------
A         | Disk         | Yes             | 6           | 312         | 7946.77          | 46347.4				|
B         | tmpfs        | Yes             | 0           | 0           | N/A              | 0					|
C         | Disk         | No              | 7           | 261         | 6407.21          | 47818.6				|
D         | tmpfs        | No              | 0           | 0           | N/A              | 0					|
-----------------------------------------------------------------------------------------------------------------


Conclusions
-----------
The results establish a consistent relationship between latency spike expression in RECOVERY_R2 and the storage path used during retry execution.

Across all conditions, spike activity was observed exclusively when the retry mechanism operated on a disk-backed target (Conditions A and C).
In both cases, spike clusters emerged several seconds after the onset of RECOVERY_R2 and persisted over extended intervals, 
with comparable magnitude and temporal structure.

In contrast, no spike activity was observed when the retry mechanism was redirected to tmpfs (Conditions B and D).
This absence was consistent across all measurements, including spike count, maximum latency, and cluster duration.
The elimination of spike expression under tmpfs conditions was observed regardless of the presence or absence of prior intervention I/O.

The comparison between Conditions A and C shows that prior intervention I/O is not required for spike formation.
Spike clusters appeared in both conditions despite the removal of intervention activity in Condition C.
Similarly, the comparison between Conditions B and D shows that the absence of spikes under tmpfs conditions is not dependent on prior system state.

Taken together, these results isolate the retry storage path as the defining factor associated with spike expression under the current design.
The symmetry of the outcomes across all four conditions demonstrates 
that neither retry timing alone nor prior intervention activity is sufficient to produce spikes in the absence of disk-backed execution.

At the same time, the results do not identify the underlying mechanism within the storage path that gives rise to these latency events.
The observed behavior indicates that interaction with the disk-backed path introduces a source of instability during RECOVERY_R2, 
but does not distinguish whether this originates from block layer activity, scheduling effects, writeback behavior, or another component of the I/O stack.

This leaves a clear and bounded next step.
Having isolated the storage path as the trigger surface, 
the next phase of investigation must focus on decomposing this path into its contributing mechanisms.

A subsequent experiment (Day21) should therefore aim to differentiate between competing explanations within the disk-backed path by selectively isolating:

	- scheduler involvement versus direct I/O effects
	- buffered versus direct write behavior
	- and the role of background writeback or queueing dynamics

The objective of this next stage is not to re-establish the presence of spikes, 
but to determine which component within the storage interaction is responsible for their emergence.