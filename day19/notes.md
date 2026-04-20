Day19 – Introduction
---------------------
Previous stages of the Collapse Lab investigation have established that the observed latency spike phenomenon is neither load-driven nor randomly distributed across execution time.

Day18 demonstrated that latency spikes are consistently initiated at the transition into RECOVERY_R2, independent of absolute timing or sustained workload intensity.
Manipulation of phase structure confirmed that the transition boundary acts as a triggering event, while the system state prior to the transition modulates the density and duration of the resulting instability.

These results define a constrained behavioral model:

instability is boundary-triggered
spike intensity is state-dependent
the phenomenon is transient and self-decaying within the recovery phase

However, the underlying mechanism responsible for spike generation remains unresolved.

The current model describes when instability is released and how it behaves, but does not identify which subsystem produces the observed latency amplification.

Multiple candidate mechanisms remain consistent with the observed behavior:

scheduler-level execution delays resulting from runnable task backlog or wakeup latency
block-layer or filesystem stalls caused by deferred IO completion or writeback activity
retry or feedback-driven amplification arising from delayed operation resolution

All three mechanisms can produce transient latency spikes aligned with a phase boundary, and all remain compatible with the results obtained in Day18.

A key limitation of previous stages is that they relied on phase timing manipulation and high-resolution heartbeat observation.
While sufficient to establish boundary-triggered behavior, these methods do not provide direct visibility into kernel-level execution paths or resource contention dynamics.

As a result, the current evidence cannot distinguish whether spikes originate from CPU scheduling, IO completion behavior, or internal feedback interactions.

This defines the central problem addressed in Day19:

If latency spikes are consistently released at the RECOVERY_R2 boundary,
which subsystem is responsible for expressing this instability when the transition occurs?

Day19 shifts the investigation from behavioral characterization to mechanism isolation.

Rather than varying phase timing or accumulated activity, the experiment introduces controlled modifications that selectively suppress or amplify individual subsystems while preserving the overall phase structure.

By holding the transition framework constant and altering only one mechanism axis at a time,
the experiment aims to identify which subsystem produces a measurable change in spike behavior.

Under this approach, the causal mechanism is not inferred from correlation with phase timing,
but from the system’s response to targeted isolation of scheduler behavior, IO activity, and retry interaction.

The outcome of Day19 is expected to reduce the set of viable explanations from multiple compatible mechanisms
to a narrower class of subsystem-level causes responsible for the transient instability regime.

Methods
--------
Day19 preserves the established phase-based experimental framework in order to maintain direct comparability with previous stages while introducing targeted mechanism isolation.
The experiment uses the same cycle structure and measurement approach as Day18, with controlled modifications applied to isolate individual subsystem contributions to the latency spike phenomenon.

Experimental objective
------------------------
Identify the subsystem responsible for releasing latency spikes at the RECOVERY_R2 transition by selectively modifying scheduler behavior, IO activity, and retry interaction while holding all other factors constant.
The experiment is designed such that each condition alters only a single mechanism axis.

Cycle definition
------------------
The experiment uses the standard cycle structure:

B → I → R1 → R2 → B2

Each run consists of:

N = 3 cycles

Phase durations remain identical across all conditions and match the Day18 reference configuration.

No variation in phase timing is introduced in Day19.

Measurement signals
-----------------------
The experiment retains the minimal signal set used in previous stages:

1. Heartbeat timing
	 File: heartbeat.log
2. Phase markers
	 File: heartbeat_marks.log
3. Probe timing
	 File: probes.log

No continuous tracing or high-volume system instrumentation is used in default runs.

Primary metrics
-----------------
Analysis focuses on the following metrics within RECOVERY_R2:

	- spike count above threshold (dt_ms > 120 ms)
	- maximum observed latency
	- p99 latency
	- spike cluster duration within R2


Additional discriminators:
-----------------------------
- time-to-first-spike after RECOVERY_R2_START marker
- early R2 spike concentration

Time-to-first-spike is defined as:

the elapsed time between the R2_START marker and the first dt_ms value exceeding 120 ms

This is used to distinguish immediate boundary-triggered release from delayed backlog-driven release.

Early R2 spike concentration is defined as:

	the percentage of spikes (dt_ms > 120 ms) occurring within the first T seconds after RECOVERY_R2_START

Where T is fixed across all runs (recommended: T = 2 seconds)

This metric quantifies whether spike activity is concentrated near the phase boundary.

Controlled parameters
-----------------------
The following parameters are held constant across all conditions:

	* phase structure and durations
	* number of cycles
	* probe type and execution path
	* heartbeat sampling interval
	* logging format and resolution
	* system environment and startup procedure
	* CPU affinity configuration is fixed and documented where applicable
No changes are made to intervention workload or probe configuration.

Experimental conditions
------------------------
Day19 introduces mechanism-isolation conditions.
Each condition modifies a single subsystem while preserving all other aspects of execution.

Condition A – Reference control
---------------------------------
This condition reproduces the Day18 baseline behavior without modification.

Purpose:

	- establish reproducibility of R2 spike behavior
	- provide a reference distribution for comparison

No subsystem behavior is altered.

Condition B – Real-filesystem IO condition
-----------------------------------------
This condition introduces real filesystem and block-layer participation by relocating the probe path from in-memory storage to disk-backed storage.

Implementation:

	* experimental write paths are redirected from tmpfs to a real filesystem
	* the probe path itself introduces filesystem interaction
	* probe type, timing, and cycle structure remain unchanged
	* no additional background IO is introduced during any phase
	* no additional write activity is allowed during R2 beyond the probe path

Purpose:

determine whether latency spikes depend on real filesystem or block-layer behavior

Interpretation:

* increase in spike density, magnitude, or persistence supports IO involvement
* no measurable change weakens IO as a dominant mechanism

Condition C – Scheduler-sensitive condition
---------------------------------------------
This condition introduces controlled CPU scheduling competition during RECOVERY_R2 using 
CPU affinity to increase the probability of contention on a defined execution core.

Implementation:

	* a low-intensity CPU-bound task is activated only during R2
	* the task is pinned with taskset to a defined CPU core
	* the main experimental path is pinned to the same CPU core
	* the competitor is terminated at R2 end
	* probe type, timing, and cycle structure remain unchanged

The intensity is kept low enough to avoid converting the condition into a general load test.

Purpose:

	determine whether spike behavior is sensitive to controlled scheduler contention

Interpretation:

	* increased spike density, persistence, or earlier spike onset supports scheduler involvement
	* no measurable change weakens scheduler-dominant explanation

Condition D – Retry-intensity condition
------------------------------------------
This condition tests whether latency spike behavior scales with the intensity of retry-driven feedback within RECOVERY_R2.

Implementation:

	* retry activity remains confined to RECOVERY_R2
	* retry intensity is controlled by varying the RETRIES parameter
	* all other phase timings, probe behavior, and execution conditions remain unchanged
	retry target path and logging remain fixed within the condition

Recommended retry levels:

	* low retry intensity
	* reference retry intensity
	elevated retry intensity

Purpose:

	determine whether latency spike behavior is sensitive to the strength of retry-driven amplification

Interpretation:

	* increased spike density, magnitude, or persistence with increasing retry intensity supports retry involvement
	* no measurable scaling weakens retry amplification as a dominant mechanism

Boundary integrity constraints
-------------------------------
Strict separation between phases is enforced at the level of user-space activity and experiment control.

The following constraints apply:

* no intentionally scheduled IO or workload from previous phases may extend into RECOVERY_R2
* scheduler competitor must begin at R2_START and terminate at R2_END
* no probe or intervention activity may overlap into R2
* logging must remain continuous and synchronized across phase markers

Residual kernel-level effects (such as delayed IO completion or scheduler backlog) 
may persist across phase boundaries and are considered part of the system behavior under observation rather than a violation.

Violation of user-space boundary constraints invalidates the run.


Analysis plan
-------------
For each condition:

1. Extract R2 segments across all cycles
2. Compute:
	- spike count (>120 ms)
	- max latency
	- p99 latency
	- time-to-first-spike
	- cluster duration
3. Compare against Condition A

Primary comparisons:

	* Condition B vs A → IO contribution
	* Condition C vs A → scheduler contribution
	* Condition D vs A → retry contribution
	
Discriminating outcomes
------------------------
Evidence for IO involvement:
	spike density, magnitude, or duration changes under real-filesystem condition relative to control

Evidence for scheduler involvement:
	spike behavior increases or changes under scheduler competition without corresponding IO changes

Evidence for retry involvement:
	spike density, magnitude, or persistence scales with retry intensity

Mixed behavior:
	multiple conditions alter spike characteristics
	indicates that spike expression is governed by interaction between subsystems rather than a single dominant mechanism.

Expected limitations
--------------------
	* suppression of IO may not fully eliminate kernel-level storage effects
	* scheduler perturbation is limited to user-space competition
	* retry mechanisms may not be fully observable
	* absence of change does not eliminate subsystem

Day19 is designed as a mechanism isolation step rather than a complete causal resolution.

Experimental Reliability
------------------------
All experimental conditions were executed under a validated orchestration framework
ensuring deterministic phase transitions, controlled intervention timing,
and consistent retry behavior across conditions.

Control checks confirmed:
- Correct phase sequencing and boundary integrity
- Proper activation and termination of intervention mechanisms
- Isolation of condition-specific parameters (retry target, CPU affinity, retry count)
- Consistent logging and timestamp alignment across all subsystems

Results
--------

Comparison Table - Day19 (C3, R2)
Table X. Condition-wise comparison of latency spike behavior during RECOVERY_R2 (Cycle 3)
Latency spikes are defined as dt_ms > 120 ms.
All metrics reported in Table X are computed exclusively within the RECOVERY_R2 window of Cycle 3.

| Condition | Retry Target | Retries | Spike Count (>120ms) | Max dt (ms) | First Spike Offset (ms) | Cluster Duration (ms) |
|----------|-------------|---------|-----------------------|-------------|--------------------------|------------------------|
| A        | Disk        | 5       | 0                     | 0           | N/A                      | 0                      |
| B        | tmpfs       | 5       | 0                     | 0           | N/A                      | 0                      |
| C        | Disk        | 5       | 6                     | 194         | 4740.6                   | 49005.9                |
| D-low    | Disk        | 1       | 7                     | 303         | 7751.6                   | 46727.1                |
| D-high   | Disk        | 10      | 7                     | 200         | 746.9                    | 56550.5			 |
------------------------------------------------------------------------------------------------------------------------------
**Table X. Latency spike metrics (dt_ms > 120 ms) measured strictly within the RECOVERY_R2 phase of Cycle 3. Only events between R2 start and R2 end markers are included. Spike activity from other phases is excluded.**

Latency spike behavior during the RECOVERY_R2 phase of Cycle 3 was quantified across all experimental conditions. 
Spikes were defined as events with dt_ms greater than 120 ms. The extracted metrics for each condition are summarized in Table X.
Within the RECOVERY_R2 window of Cycle 3, Conditions A and B exhibited no latency spikes. 
Accordingly, spike count, maximum dt, and cluster duration within that phase window were zero, and no first spike offset was defined for those conditions.

Conditions C, D-low, and D-high all exhibited measurable spike activity within RECOVERY_R2. 
Spike counts were comparable across these active conditions, with 6 spikes observed in Condition C and 7 spikes observed in both D-low and D-high.

Maximum observed latency within RECOVERY_R2 varied across the active conditions. 
Condition C reached a maximum dt of 194 ms, while D-high reached 200 ms. 
Condition D-low exhibited the highest maximum dt, reaching 303 ms.

The timing of the first spike within RECOVERY_R2 differed across active conditions. 
In Condition D-high, the first spike occurred at approximately 746.9 ms after the start of RECOVERY_R2. 
In Condition C, the first spike occurred later, at approximately 4740.6 ms. 
Condition D-low showed the latest onset, with the first spike appearing at approximately 7751.6 ms.

Cluster duration, defined as the time between the first and last spike within RECOVERY_R2, 
was substantial in all active conditions. Condition C exhibited a cluster duration of approximately 49005.9 ms. 
Condition D-low showed a duration of approximately 46727.1 ms, while Condition D-high exhibited the longest duration at approximately 56550.5 ms.

Taken together, the Cycle 3 RECOVERY_R2 comparison shows a clear separation between conditions with 
no spike expression in that phase window (A and B) and conditions with sustained spike activity during the same phase window (C, D-low, and D-high).
The consistent absence of spikes in A and B within RECOVERY_R2, 
despite their presence in other phases, contrasts with the sustained spike expression 
observed in C, D-low, and D-high under the same phase window.

Conclusions
------------
The results establish that latency spike expression is phase-dependent rather than uniformly distributed across system activity. 
While spike events (dt_ms > 120 ms) were observed in multiple conditions across the full run, 
their presence within the RECOVERY_R2 phase is not universal.

Conditions A and B demonstrate that spike activity outside RECOVERY_R2 does not imply spike expression within it. 
Despite observable latency events in other phases, both conditions exhibited a complete absence of spikes during RECOVERY_R2. 
This demonstrates that entry into RECOVERY_R2 alone is not sufficient to produce instability.

In contrast, Conditions C, D-low, and D-high consistently produced spike clusters within RECOVERY_R2. 
These clusters were not isolated events but extended over substantial portions of the phase window, 
with durations on the order of tens of seconds. 
This sustained expression suggests that once instability is triggered within RECOVERY_R2, it persists as a phase-level behavior rather than a transient anomaly.

The comparison between D-low and D-high isolates the effect of retry intensity. 
Increasing retry pressure from low (RETRIES=1) to high (RETRIES=10) did not increase spike count, 
but it significantly shifted the temporal onset of instability. 
In D-high, the first spike appeared near the beginning of RECOVERY_R2, 
whereas in D-low the onset was delayed by several seconds. 
This indicates that retry pressure does not control whether instability occurs, but influences how early the system transitions into the unstable regime.
Spike count remained stable across retry intensities, indicating that retry pressure affects temporal dynamics but does not increase the frequency of spike events.

Maximum latency also varied across conditions, 
with D-low exhibiting the highest peak (303 ms), exceeding both D-high and Condition C. 
This suggests that peak severity is not strictly correlated with retry intensity and may depend on interaction effects between IO load, recovery timing, and internal system state.

Taken together, the results support a state-dependent interpretation of latency instability. 
Spike expression is gated by specific conditions that emerge during RECOVERY_R2, 
and not by load magnitude alone. 
Entry into RECOVERY_R2 creates the potential for instability, but additional factors determine whether that potential is realized.

The next experiment targets mechanism isolation by removing background IO while maintaining retry pressure during RECOVERY_R2. 
This configuration tests whether latency instability persists without storage contention, and determines whether retry dynamics alone are sufficient to produce spike formation.