Day 16 – Low-Intrusion Sampling of Residual Latency Spikes
------------------------------------------------------------
Introduction
-------------

Previous stages of the Collapse Lab investigation progressively narrowed the set of plausible mechanisms responsible for the recurring ~200–250 ms latency spikes.
Day12 demonstrated that CPU scheduling placement does not eliminate the spike class. 
Even when probe execution was isolated from competing workloads, the characteristic latency behavior remained observable, weakening CPU contention as a primary explanation.
Day14 provided evidence that block-device activity is correlated with spike events under ext4 configurations backed by the microSD device. 
However, when the probe path was moved to tmpfs, thereby removing block-device persistence from the execution path, 
the spikes did not disappear. 
This indicates that while persistence-related mechanisms can amplify or correlate with spike events, they are not sufficient to fully explain the phenomenon.

Day15 introduced kernel scheduler tracing in order to observe kernel activity during spike windows. 
While scheduler events were successfully captured and aligned with spike timestamps, 
the use of continuous trace instrumentation introduced additional system disturbance, 
making it difficult to determine whether the observed behavior reflected the underlying mechanism or the effect of the tracing itself.

Taken together, these results indicate that the remaining spike class persists under conditions where CPU placement is controlled, 
block-device persistence is removed, and system pressure remains negligible. 
At the same time, heavy instrumentation has been shown to influence observability.

The goal of Day16 is therefore to reduce observer effect by replacing high-volume tracing with low-rate sampled system counters. 
Rather than attempting to capture detailed execution paths, 
this stage focuses on identifying whether the residual spike mechanism produces repeatable, observable changes in sampled system state.

Hypothesis
-----------
The residual ~200–250 ms latency spike class observed under the tmpfs configuration is not explained solely by CPU scheduling placement or block-device persistence mechanisms.
If the underlying mechanism produces measurable system-side effects, 
then low-rate sampled system counters should reveal consistent temporal patterns aligned with spike timestamps, 
even in the absence of high-volume tracing.
Specifically, the experiment tests whether spike events coincide with observable changes in one or more of the following sampled domains:

	- interrupt activity or softirq execution
	- scheduler-related aggregate counters
	- process-level activity patterns
	- system-level state indicators exposed via lightweight sampling interfaces

Under this hypothesis, spike windows should exhibit detectable deviations in sampled system metrics relative to surrounding baseline intervals.
If no consistent sampled signature is observed,
this would suggest that the underlying mechanism either operates below the resolution of the chosen sampling methods or does not manifest as a broad system-level state change.

Methods
-------

Day16 maintains the same workload structure used in Day14 and Day15 in order to avoid introducing new behavioral variables.

The experiment continues to use the known reproducer:
	- PROBE_B
	- B_variant=fsync
	- OFF=3
	- N_CYCLES=3

The same cycle structure is preserved:
	- baseline
	- intervention
	- recovery R1
	- recovery R2
	- post-baseline

This ensures that any observed differences can be attributed to the change in instrumentation method rather than changes in workload behavior.

Control configuration
----------------------

Day16 continues to use the tmpfs probe configuration established in Day14 and Day15:

- PROBE_ROOT=/dev/shm/day16_probes
- PROBE_B_VARIANT=fsync
- normal scheduling priority
- full Day14 telemetry retained

This configuration removes block-device persistence effects from the probe path while preserving the residual spike class observed in previous experiments.

Signals collected
------------------

Day16 retains all signals collected in Day14 and Day15:

1. Heartbeat timing
File: heartbeat.log

2. Probe timing
File: probes.log

3. Telemetry
File: telemetry.log

4. Disk activity
File: diskstats.log

In addition, Day16 introduces three low-intrusion sampled kernel-side signal classes:

5. Sampled system state (10 Hz)

- /proc/stat
- /proc/interrupts
- /proc/softirqs

These sampled signals provide coarse visibility into CPU state, interrupt activity, and deferred kernel execution behavior.

Sampling strategy
------------------

All three sampled sources are collected at a fixed rate of 10 Hz throughout the duration of each cycle.

This sampling rate represents a compromise between temporal resolution and observer effect.
Given the characteristic spike duration of approximately 200–250 ms, 
a 10 Hz sampling interval provides multiple samples within a spike window while maintaining low measurement overhead.

The objective is not to capture exact execution paths, but to detect repeatable changes in sampled system state aligned with spike timestamps.

Rationale for signal selection
------------------------------

The selected sampled signals are chosen to provide complementary low-intrusion visibility into kernel-adjacent activity:

- /proc/stat provides aggregate CPU state, context-switch activity, and interrupt counters
- /proc/interrupts provides per-CPU interrupt distribution and activity levels
- /proc/softirqs provides visibility into deferred interrupt-related kernel work

Together, these signals allow observation of system-side activity that may correlate with residual spike events
 without introducing the disturbance associated with continuous tracing.

Data alignment method
-----------------------

After the run completes, analysis correlates:

- heartbeat spike timestamps
- nearest probe events
- nearest telemetry samples
- nearest diskstats samples
- nearest sampled system-state records

The purpose of this alignment is to identify whether spike windows coincide with consistent deviations in sampled system metrics.

Expected limitations
---------------------

Several limitations are acknowledged:

- sampling provides coarse temporal resolution relative to the spike duration
- short-lived events may not be fully captured between sampling intervals
- sampled counters provide aggregate behavior rather than exact execution paths
- absence of a detectable signal does not necessarily imply absence of an underlying mechanism

For this reason, Day16 is treated as a low-intrusion observational step intended to detect indirect system-level signatures
 rather than fully attribute kernel execution paths.
 
results
---------

The Day16 experiment was executed using low-intrusion sampling, 
including heartbeat measurement, phase marking, and periodic `/proc` sampling at 10 Hz. No tracing mechanisms were active during the run.

Heartbeat Measurements
--------------------
A total of 3 latency spikes exceeding 200 ms were observed during the run.

The maximum recorded latency was:

	- 808.388 ms at timestamp 1774203107776655592

Additional spikes included:

	- 227.511 ms
	- 204.400 ms

Phase Association
-----------------
Mapping spike timestamps to phase markers shows the following distribution:

	- 808.388 ms occurred at: `C2_RECOVERY_R1_START`
	- 227.511 ms occurred at: `C3_RECOVERY_R2_START`
	- 204.400 ms occurred at: `C3_BASELINE_START`

No spikes exceeding 200 ms were observed during the INTERVENTION phase.

/proc/stat Sampling
--------------------

Sampling of `/proc/stat` in a ±0.5 second window around the maximum spike (808 ms) shows:

- Continuous increase in CPU counters across all cores
- `procs_running` remained at 1 throughout the window
- `procs_blocked` remained at 0 throughout the window
- Gradual increases in:

  - `ctxt`
  - `intr`
  - `softirq`

No abrupt discontinuities or sudden jumps were observed in the sampled values.

/proc/interrupts Sampling
--------------------------

Inspection of `/proc/interrupts` in the same window shows:

- Steady increments in the `arch_timer` interrupt across all CPUs
- No visible spike or burst in any individual interrupt line
- Storage-related interrupts (`mmc0`, `mmc1`) remained largely unchanged
- Peripheral and auxiliary interrupt lines remained inactive

Inter-processor interrupts (IPIs) show:

- Small, steady increases in:

  - Rescheduling interrupts (IPI0)
  - Function call interrupts (IPI1)

No abrupt increase or imbalance across CPUs was observed.

/proc/softirqs Sampling
------------------------

Inspection of `/proc/softirqs` in the same window shows:

- Gradual increases in:

  - `TIMER`
  - `SCHED`
  - `RCU`
- No significant changes in:

  - `NET_RX`
  - `NET_TX`
  - `BLOCK`
  - `TASKLET`
  - `HRTIMER`

Values increased smoothly across consecutive samples without visible spikes or bursts.

Summary of Observed Data
------------------------
* Heartbeat latency spikes occurred outside the INTERVENTION phase
* The largest spike (808 ms) occurred during a recovery phase transition
* System-level sampled metrics (`/proc/stat`, `/proc/interrupts`, `/proc/softirqs`) showed continuous and gradual changes during the window surrounding the spike
* No abrupt changes or localized bursts were observed in the sampled data

Conclusions
-------------
The Day16 experiment confirms that latency spikes persist under low-intrusion observation conditions, without the presence of tracing mechanisms.
Latency spikes exceeding 200 ms were observed, 
including a maximum event of approximately 808 ms. 
These spikes occurred outside the INTERVENTION phase and were observed during BASELINE and RECOVERY phases.
System-level sampling of `/proc/stat`, `/proc/interrupts`, and `/proc/softirqs` 
in the time window surrounding the largest spike did not reveal any abrupt or anomalous behavior. 
CPU activity, interrupt counts, and softirq counters exhibited continuous and gradual progression without visible bursts or discontinuities.

No evidence was observed for:

- CPU saturation or overload conditions
- Increase in runnable or blocked processes
- Interrupt storms or localized IRQ spikes
- Softirq bursts across TIMER, SCHED, BLOCK, or networking categories

The absence of observable anomalies in sampled system metrics indicates that the latency spikes 
are not associated with coarse-grained system load, interrupt activity, or softirq accumulation as captured by the current sampling resolution.
The observed behavior is consistent with a latency mechanism that is not reflected in aggregated `/proc`-level metrics
 at the sampling frequency used in this experiment.

The Day16 results indicate that latency spikes are not reflected in coarse-grained system metrics sampled via /proc at 10 Hz resolution. 
As a result, the next step is to increase temporal resolution and focus on narrower execution paths.

Day17 will focus on improving observability around the latency event itself rather than expanding system-wide sampling.

The proposed direction includes:

	-Increasing timing resolution of the heartbeat measurement to better capture sub-100 ms behavior leading into and out of spike events
	-Introducing finer-grained, low-intrusion instrumentation around the heartbeat execution path to detect local delay		
	-Maintaining minimal system perturbation to preserve the natural behavior observed in Day16
	-Avoiding broad or heavy tracing mechanisms that may alter timing characteristics

The objective of Day17 is to reduce uncertainty around the temporal structure of latency spikes and identify whether the delay 
is localized to a specific execution segment or occurs outside the observed measurement path.