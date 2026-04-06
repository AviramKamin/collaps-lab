Day17 – High-Resolution Timing Around Phase Transitions
--------------------------------------------------------
Introduction
--------------
Previous stages of the Collapse Lab investigation have progressively reduced the set of plausible mechanisms responsible for the observed latency spike behavior.
Day12 demonstrated that CPU scheduling placement does not eliminate the spike class, 
even under controlled execution conditions.
Day14 showed that while block-device persistence may correlate with spike events, 
it is not required for their occurrence, as spikes persist under tmpfs configurations.
Day15 introduced scheduler tracing, 
which provided visibility into kernel activity but also introduced measurement disturbance, 
limiting the ability to distinguish between system behavior and observer effect.
Day16 replaced high-volume tracing with low-intrusion sampling of system state via /proc interfaces.
Latency spikes exceeding 200 ms were observed under these conditions, including a maximum event of approximately 800 ms.
However, sampled system metrics, including CPU state, interrupt activity, and softirq counters, 
did not exhibit abrupt or anomalous changes in the time windows surrounding spike events.

In addition, spike occurrences were not concentrated within the intervention phase.
Instead, spikes were observed at multiple points across the cycle structure, including baseline and recovery phases, 
with several events aligned with phase transition boundaries.

These observations suggest that the remaining spike mechanism is not reflected in coarse-grained, 
system-wide metrics at the sampling resolution used in previous experiments.
They also indicate that spike occurrence may not be directly coupled to sustained load conditions, 
but instead may be associated with transient system states occurring at or near phase transitions.

Given these results, the next stage focuses on improving temporal resolution around the latency event itself.
Rather than expanding system-wide observability, 
this stage narrows the scope of observation to the timing structure of the spike and its relation to phase transitions within the execution cycle.

The absence of observable anomalies in sampled system-wide metrics, 
combined with the distribution of spike events across multiple phases, raises a more focused question regarding the nature of the remaining latency mechanism.
If spike events are not accompanied by detectable changes in aggregate system state, 
then the mechanism responsible may operate on a narrower temporal or structural scale than previously observed.
In particular, the alignment of several spike events with phase transition boundaries suggests that the relevant behavior may be associated 
with short-lived timing effects occurring during state changes rather than during steady-state execution.

Day17 - Hypothesis
-------------------
The residual latency spike class observed under tmpfs configuration is not accompanied by detectable changes in coarse-grained 
system-wide metrics and is not directly coupled to sustained load conditions.
This suggests that the mechanism responsible for spike events operates on a temporal and structural scale 
that is not captured by aggregate system sampling, and is instead expressed as a short-lived timing disturbance localized to a narrow execution window.
If this is the case, then increasing the temporal resolution of the heartbeat measurement and aligning observations precisely with phase transition boundaries 
will reveal that:

	-	spike onset occurs within a bounded temporal region relative to phase transition points, 
		rather than being uniformly distributed across steady-state execution
	-	spike events exhibit asymmetric temporal structure, 
		with a distinguishable onset and recovery profile that is not visible at lower sampling frequencies
	-	the duration and shape of spike events are inconsistent with broad system-wide degradation and 
		instead reflect a localized delay affecting a limited portion of the execution path

Under this hypothesis, higher-resolution timing will not only increase visibility of spike structure, 
but will also demonstrate that spike events are temporally concentrated around 
state transitions and structurally inconsistent with coarse-grained system load or aggregate kernel activity.

Methods
--------
Day17 preserves the same experimental structure used in previous stages 
in order to maintain comparability with earlier results and avoid introducing new behavioral variables.

The experiment continues to use the known reproducer:

	- PROBE_B
	- B_variant=fsync
	- OFF=3
	- N_CYCLES=3

The same cycle structure is preserved:

	* baseline
	* intervention
	* recovery R1
	* recovery R2
	* post-baseline

This preserves the phase framework established in earlier days and allows direct comparison of spike timing across runs.

Control configuration
----------------------
Day17 continues to use the tmpfs probe configuration employed in Day15 and Day16:

	- PROBE_ROOT=/dev/shm/day17_probes
	- PROBE_B_VARIANT=fsync
	- normal scheduling priority

This configuration is retained to preserve the residual spike class observed in previous experiments 
while avoiding persistence-related amplification from the block device.

Measurement strategy
----------------------
The primary change in Day17 is a shift from coarse system-wide sampling toward higher-resolution timing observation of the spike event itself.
Rather than expanding broad observability, 
Day17 narrows the scope of measurement to improve temporal characterization of heartbeat behavior and its relationship to phase transition boundaries.

Signals collected
-------------------
Day17 retains the core timing signals used in previous days:

	* Heartbeat timing
	  File: heartbeat.log
	* Heartbeat phase markers
	  File: heartbeat_marks.log
	* Probe timing
	  File: probes.log

In contrast to Day16, Day17 prioritizes higher temporal resolution in heartbeat measurement over broad sampled system-state collection.

Heartbeat resolution
---------------------
The heartbeat signal is sampled at a higher frequency than in Day16 in order to improve visibility into spike onset, duration, and recovery structure.
The purpose of this change is to determine whether spike events contain temporal substructure that was not visible at the lower heartbeat frequency 
used previously.

Transition-focused alignment
-----------------------------
Day17 places explicit emphasis on timing alignment around phase transition boundaries, including:

	* baseline to intervention
	* intervention to recovery R1
	* recovery R1 to recovery R2
	* recovery R2 to post-baseline

These boundaries are treated as primary analysis landmarks because Day16 showed that large spike events 
can occur near transition regions rather than within sustained intervention intervals.

Observability constraints
--------------------------
To minimize observer effect, Day17 avoids continuous tracing and avoids reintroducing broad high-volume system instrumentation.
The experiment is designed to preserve the low-disturbance conditions of Day16 while improving temporal resolution around the latency event.

Data alignment method
----------------------
After the run completes, analysis will correlate:

	* heartbeat spike timestamps
	* heartbeat phase markers
	* probe start and end timestamps
	* temporal distance between spike events and nearby phase transitions

The objective is to determine whether higher-resolution heartbeat timing reveals repeatable temporal 
structure in spike events and whether those events cluster near state-transition boundaries.

Expected limitations
---------------------
Several limitations are acknowledged:

	* higher-resolution heartbeat measurement improves visibility of timing structure but does not directly identify kernel execution paths
	* phase alignment can reveal temporal association without establishing direct causality
	* if the responsible mechanism remains shorter-lived than the chosen measurement interval, some structure may still be aliased or partially obscured.
	
Results
-------
The Day17 experiment was executed with three full cycles, each consisting of baseline, 
intervention, recovery R1, recovery R2, and post-baseline phases. 
Heartbeat sampling was performed at ~50 Hz, yielding a total of 34,601 samples.

General Heartbeat Behavior
---------------------------
Across the run, the steady-state heartbeat interval remained stable at approximately 21–22 ms, 
consistent with the configured sampling rate. No drift or degradation in baseline cadence was observed across cycles.

Spike Occurrence
------------------
A total of:
spikes >200 ms = 1
was detected across the entire experiment.

The maximum observed latency was:
707.296 ms
Phase Distribution of High Latency Events
---------------------------------------------
The single spike exceeding 200 ms occurred during:

C2_RECOVERY_R1_START

No spikes above 200 ms were observed during:

	Baseline phases
	Intervention phases
	Recovery R2 phases
	Post-baseline phases
	
Top Latency and Deviations Events
-----------------------------------
While only a single event exceeded the 200 ms threshold, 
additional high-latency deviations below this threshold are included to characterize the upper tail of the distribution.

The ten highest latency events observed in the run were:

707.296 ms → C2_RECOVERY_R1_START
158.047 ms → C2_RECOVERY_R2_START
147.969 ms → C3_RECOVERY_R2_START
146.639 ms → C1_RECOVERY_R2_START
133.780 ms → C1_RECOVERY_R1_START
84.931 ms  → C2_RECOVERY_R2_START
79.849 ms  → C1_RECOVERY_R2_START
68.243 ms  → C1_RECOVERY_R2_START
66.981 ms  → C2_RECOVERY_R2_START
62.250 ms  → C1_RECOVERY_R2_START


Phase-Level Observations
-------------------------
The highest latency event (707 ms) occurred at the start of recovery R1 in cycle 2.
Additional elevated latency events (>130 ms) were observed at:
	- Recovery R2 across multiple cycles
	- Recovery R1 in cycle 1
*Intervention phases did not produce any high-latency events in the top percentile range.
*Baseline and post-baseline phases did not exhibit elevated latency events.

Cycle Consistency
------------------
All three cycles executed successfully with consistent phase durations and correct probe alignment:

Intervention windows were correctly marked and executed
Recovery phases followed expected timing boundaries
No missing or truncated phases were observed

Conclusions
--------------
The Day17 experiment reveals a clear separation between phases in terms of latency behavior, 
with distinct characteristics observed across intervention, recovery R1, and recovery R2.
First, the intervention phase did not produce high-latency events. Across all three cycles, 
no spikes above 200 ms were observed during active load. 
This indicates that the applied stress alone does not directly manifest as extreme latency in the measured signal.

Second, a single extreme latency event (707 ms) was observed, 
and it occurred at the start of recovery R1 in cycle 2. No other phase produced a comparable magnitude event. 
This establishes that extreme latency can emerge outside of the active intervention window.

Third, sub-threshold high-latency deviations (approximately 60–160 ms) were consistently observed, 
primarily during recovery R2, and to a lesser extent at recovery R1. 
These deviations appeared across multiple cycles and were absent from baseline, intervention, and post-baseline phases.

Taken together, the results demonstrate that latency behavior is strongly phase-dependent and not directly expressed during sustained load conditions. 
The absence of spikes during intervention, combined with the presence of both extreme and sub-threshold latency events during recovery phases, 
indicates that system instability is expressed after the removal of load rather than during its application.

Additionally, the results show that recovery is not uniform. The data distinguishes between:

	* Recovery R1, where rare but high-magnitude latency events may occur
	* Recovery R2, where more frequent but lower-magnitude deviations are observed

This differentiation suggests that recovery consists of multiple regimes with distinct latency characteristics.

Finally, the use of higher-resolution heartbeat sampling (~50 Hz) preserved the observed behavior 
and did not eliminate the phase-dependent pattern. Instead, 
it provided clearer visibility into the distribution and magnitude of latency deviations across phases.

Despite the clear phase-dependent structure observed, 
the mechanism underlying the emergence of extreme latency events remains unresolved. 
In particular, the occurrence of a single high-magnitude event during recovery R1 in cycle 2, 
without recurrence in subsequent cycles, indicates that the phenomenon is not strictly deterministic under the current configuration.

This raises a critical question: whether the observed latency behavior is driven by the timing of phase transitions themselves, 
or by accumulated system state that is only intermittently released at specific transition boundaries. 
The distinction between these possibilities is not resolved by the present experiment and requires further isolation of transition conditions 
and timing sensitivity.