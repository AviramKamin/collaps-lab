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

Additional discriminator:

	- time-to-first-spike after RECOVERY_R2_START marker

This metric is defined as:

the elapsed time between the R2_START marker and the first dt_ms value exceeding 120 ms
This is used to distinguish immediate boundary-triggered release from delayed backlog-driven release.

Controlled parameters
-----------------------
The following parameters are held constant across all conditions:

	* phase structure and durations
	* number of cycles
	* probe type and execution path
	* heartbeat sampling interval
	* logging format and resolution
	* system environment and startup procedure

No changes are made to intervention workload or probe configuration.

Experimental conditions
------------------------
Day19 introduces mechanism-isolation conditions.
Each condition modifies a single subsystem while preserving all other aspects of executio

Condition A – Reference control
---------------------------------
This condition reproduces the Day18 baseline behavior without modification.

Purpose:

	- establish reproducibility of R2 spike behavior
	- provide a reference distribution for comparison

No subsystem behavior is altered.

Condition B – IO-suppressed condition
-----------------------------------------
This condition minimizes block-layer and filesystem involvement during execution.

Implementation:

	* experimental write paths are redirected to in-memory storage (tmpfs)
	* no background IO is introduced during any phase
	* no additional write activity is allowed during R2

Purpose:

	determine whether latency spikes depend on delayed IO completion or filesystem-level behavior

Interpretation:

	* reduction or disappearance of spikes supports IO-dominant mechanism
	* persistence of spikes weakens IO as primary source

Condition C – Scheduler-sensitive condition
--------------------------------------------
This condition introduces controlled CPU scheduling competition during RECOVERY_R2.

Implementation:

	- a low-intensity CPU-bound task is activated only during R2
	- the task runs concurrently with the main loop
	- the task is terminated at R2 end

The intensity is kept minimal to avoid introducing sustained load effects.

Purpose:

determine whether spike behavior is sensitive to scheduling contention

Interpretation:

	* increased spike density or duration supports scheduler involvement.
	* no measurable change weakens scheduler-dominant explanation.

Condition D – Retry-suppressed condition
-----------------------------------------
This condition reduces or disables retry behavior within the experimental path.

Implementation:

	- retry count is minimized or disabled where applicable
	- retry events are logged with timestamps for correlation

Purpose:

determine whether spike amplification depends on retry-driven feedback

Interpretation:

	* reduction in spike frequency or magnitude supports retry interaction mechanism
	* no change suggests retries are not a primary driver

This condition is included only if retry behavior is present and controllable.

Boundary integrity constraints
-------------------------------
Strict separation between phases is enforced.

The following constraints apply:

	no IO activity from previous phases may extend into R2
	scheduler competitor must begin at R2_START and terminate at R2_END
	no probe or intervention activity may overlap into R2
	logging must remain continuous and synchronized across phase markers

Violation of these constraints invalidates the run.

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
Evidence for IO-dominant mechanism:
	spikes are significantly reduced or eliminated under IO suppression

Evidence for scheduler-dominant mechanism:
	spike behavior increases under scheduler competition
	IO suppression does not significantly alter spike structure

Evidence for retry-driven mechanism:
	spike behavior decreases when retry logic is suppressed
	spike timing correlates with retry events

Mixed behavior:
	multiple conditions alter spike characteristics
	indicates combined subsystem interaction

Expected limitations
suppression of IO may not fully eliminate kernel-level storage effects.
scheduler perturbation is limited to user-space competition and may not expose all scheduling dynamics.
retry mechanisms may not be fully observable or controllable within current framework.
absence of change in a given condition does not conclusively eliminate that subsystem.

Day19 is designed as a mechanism isolation step rather than a complete causal resolution.
