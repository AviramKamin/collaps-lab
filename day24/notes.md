
Introduction
-------------
Day23 established that strong latency spike expression during the RECOVERY_R2 phase depends on buffered disk-backed IO.

Under identical workload and timing parameters, buffered IO configurations consistently produced dense spike clusters, while direct IO significantly suppressed both spike frequency and amplitude.
This behavior persisted across different filesystem targets and mount configurations, indicating that filesystem structure itself is not the controlling factor in spike formation.

These results isolate the buffered IO path as a necessary condition for spike manifestation under the current experimental structure.
At the same time, spike activity remains consistently confined to the RECOVERY_R2 phase, which serves as a stable manifestation window rather than a standalone causal source.

Within the buffered IO path, multiple interacting components within the buffered IO path remain potential contributors to the observed behavior, 
including page cache accumulation, dirty page thresholds, writeback scheduling, and block-layer submission.

The specific contribution of writeback behavior to spike emergence remains unresolved.

Therefore, the objective of Day24 is to isolate the role of writeback dynamics within the buffered IO path.
By modifying writeback-related system parameters while keeping workload, timing, IO mode, 
and observation regime constant, this experiment aims to determine whether latency spike manifestation is temporally coupled to writeback activity or persists independently of it.

Hypothesis
-----------
If latency spikes observed during the RECOVERY_R2 phase are associated with writeback dynamics within the buffered IO path,
then modifying writeback-related system parameters while maintaining identical workload, timing, and IO mode will produce measurable changes in spike behavior.

Specifically:

	- configurations that promote earlier and more continuous writeback are expected to reduce spike density, clustering, or peak latency during RECOVERY_R2
	- configurations that delay writeback and allow accumulation of dirty pages are expected to increase spike density, clustering, or peak latency, and potentially shift spike onset timing within RECOVERY_R2

Conversely, if spike behavior remains consistent across configurations with materially different writeback policies,
then writeback dynamics are unlikely to be the primary driver of spike manifestation, and the underlying mechanism is more likely to originate from deeper layers of the disk-backed IO path.
The hypothesis assumes that opposing writeback policies will produce opposing effects on spike behavior.

Methods
-------
Experimental Structure
----------------------
All experiments followed the same phase-based execution model established in prior experiments:

	BASELINE (B)
	INTERVENTION (I)
	RECOVERY_R1 (R1)
	RECOVERY_R2 (R2)

Latency was measured continuously using the existing heartbeat mechanism,
with timestamps and dt_ms values recorded in run.log.

Phase transitions were explicitly marked (e.g., C3_RECOVERY_R2_START, C3_RECOVERY_R2_END)
to enable precise extraction and analysis of the RECOVERY_R2 interval.

Each condition was executed across multiple cycles (3) under identical workload, timing, and retry parameters.

Control Variables
------------------
The following parameters were held constant across all conditions:

	- workload script and retry behavior
	- IO mode (buffered IO)
	- filesystem target and mount configuration
	- execution timing and phase durations
	- observation method (heartbeat logging without tracing)
	- hardware and system environment

No additional background workload or tracing instrumentation was introduced.

Variable Under Test
--------------------
The only variable modified between conditions was the system writeback policy,
controlled via kernel parameters affecting dirty page accumulation and flush behavior.

Writeback behavior was adjusted using sysctl parameters governing:

	- dirty page thresholds
	- background writeback initiation
	- writeback timing cadence

Changes in writeback state are defined as observable variation in Dirty, Writeback, nr_dirty, or nr_writeback values relative to preceding samples.

Writeback State Measurement
--------------------------------
To correlate spike behavior with buffered IO state, system-level writeback and dirty memory metrics were recorded continuously throughout each run.

Dirty and Writeback Memory State

Snapshot sampling was performed using:
	grep -E "Dirty|Writeback" /proc/meminfo
	
This captures:

	- Dirty memory (pages pending writeback)
	- Writeback memory (pages actively being flushed)
	
Writeback Activity Counters
-----------------------------
Additional writeback-related counters were collected using:

grep -E "nr_dirty|nr_writeback" /proc/vmstat

This provides visibility into:
-------------------------------
	- total number of dirty pages
	- active writeback activity over time
	
Sampling Strategy
------------------
	- Sampling interval: 50 ms
	- Sampling executed continuously across all phases
	- Output appended to a dedicated log file per run (e.g., writeback.log)

All sampling timestamps were aligned with system time to allow correlation with heartbeat events and phase markers.

Latency Measurement
--------------------
Latency spikes were defined as events where: dt_ms > 120

For each run:

	analysis was restricted to the RECOVERY_R2 phase using marker-based segmentation
	spike count, maximum latency, and temporal clustering were extracted from run.log
	
Correlation Analysis
--------------------
Spike events observed during RECOVERY_R2 were analyzed in relation to:

	- dirty memory levels
	- writeback activity levels
	- timing of writeback fluctuations relative to spike onset

This enables evaluation of whether spike emergence aligns with changes in buffered writeback state.

Temporal precedence is evaluated such that changes in writeback or dirty memory state
must occur prior to or at spike onset in order to be considered a contributing factor.

Post-spike changes are not considered causal.

Experimental Conditions
--------------------------
All conditions were executed under identical workload, timing, and system configuration,
with buffered IO maintained across all runs.

The only variable modified between conditions was the writeback policy,
controlled via sysctl parameters governing dirty page accumulation and flush behavior.

Condition A – Default writeback policy (reference)
The system operated under default kernel writeback settings.
This condition serves as the reference for spike-producing behavior under buffered IO.

Condition B – Early and continuous writeback

Writeback behavior was configured to initiate earlier and occur more continuously,
reducing the accumulation of dirty pages before flush.

This was achieved by lowering dirty thresholds and increasing writeback frequency:

	vm.dirty_background_ratio = 2
	vm.dirty_ratio = 5
	vm.dirty_writeback_centisecs = 100
	vm.dirty_expire_centisecs = 500
	
This configuration is expected to promote gradual flushing and reduce burst writeback activity.
	
Condition C – Delayed and burst writeback

Writeback behavior was configured to allow greater accumulation of dirty pages
before initiating flush operations.

This was achieved by increasing dirty thresholds and reducing writeback frequency:

	vm.dirty_background_ratio = 20
	vm.dirty_ratio = 40
	vm.dirty_writeback_centisecs = 500
	vm.dirty_expire_centisecs = 3000
	
This configuration is expected to promote bursty writeback behavior following accumulation.

Control Considerations
---------------------
	- All conditions were executed on the same hardware and operating environment
	- No tracing was enabled during primary runs to minimize observation bias
	- Writeback state sampling was performed identically across all conditions
	- No additional background IO or system load was introduced
	- All sysctl values were applied prior to run start and recorded in meta.env
	
Measurement
------------
Latency spikes were defined as events where dt_ms > 120.

For each run, analysis was restricted to the RECOVERY_R2 phase using marker-based segmentation of run.log.
Spike counts were computed as the number of events exceeding the defined threshold within the R2 interval.

In addition to spike count, maximum observed dt_ms and temporal clustering of spikes within R2 were examined directly from the logs.

Writeback State Analysis
-------------------------
To evaluate the relationship between latency spikes and buffered IO state,
writeback-related system metrics were analyzed in parallel with latency data.

For each run:

	- Dirty memory levels were extracted from writeback.log
	- Writeback activity levels were extracted from vmstat sampling logs

These values were examined in relation to:

	- timing of RECOVERY_R2 phase
	- timing of spike onset
	- temporal alignment between changes in writeback state and spike events
	
Comparative Analysis Across Conditions
----------------------------------------
For each condition (A, B, C), the following were compared within the RECOVERY_R2 phase:

	- total number of spikes exceeding threshold
	- maximum observed latency values
	- temporal distribution and clustering of spike events
	- qualitative relationship between writeback state changes and spike timing
	
Interpretation framework
-------------------------

Day24 does not evaluate writeback behavior by simple co-occurrence alone.
Interpretation is based on whether changes in writeback policy produce consistent changes in spike behavior within RECOVERY_R2, 
and whether writeback-state changes occur prior to or at spike onset.

The following outcomes define the interpretation space.

Outcome 1 - Strong writeback support
-------------------------------------
Conditions B and C produce clear and directional differences relative to Condition A:

	- earlier and more continuous writeback reduces spike density, clustering, peak latency, or delays spike onset
	- delayed and burst writeback increases spike density, clustering, peak latency, or advances spike onset into an earlier portion of RECOVERY_R2
	- observed changes in dirty or writeback state occur prior to or at spike onset

Interpretation:

Writeback dynamics are supported as a necessary contributing component of spike manifestation under the current experimental structure.
This outcome would indicate that the instability is not merely associated with buffered IO in general, 
but is sensitive to the timing and structure of writeback behavior within that path.

Outcome 2 - Partial writeback support
--------------------------------------
Conditions B and C differ from Condition A, but the effect is incomplete or asymmetric.

Examples include:

	- only one manipulated condition differs materially from the reference
	- spike count remains similar, but onset timing or clustering changes
	- peak latency changes without a corresponding change in spike density
	- writeback-state changes are visible near spike onset, but temporal ordering is inconsistent across cycles

Interpretation:

Writeback dynamics likely contribute to spike manifestation, but do not fully explain the mechanism on their own.
This outcome supports a mixed-mechanism model in which writeback behavior influences spike expression while deeper layers of the disk-backed buffered path remain involved.

Outcome 3 - No writeback effect
--------------------------------
Conditions B and C remain comparable to Condition A in:

	- spike count
	- clustering structure
	- peak latency
	- onset timing

and no consistent temporal coupling is observed between writeback-state changes and spike onset.

Interpretation:

Writeback dynamics are unlikely to be a necessary component of spike manifestation under the tested conditions.
This outcome would weaken a writeback-centered explanation and shift attention toward deeper components of the buffered disk-backed path, 
including block-layer submission, completion behavior, or lower-level IO scheduling effects.

Outcome 4 - Ambiguous result due to weak policy separation
--------------------------------------------------------------
Conditions B and C do not separate cleanly from A, but sampled writeback-state behavior also fails to separate meaningfully across conditions.

Examples include:

	- Dirty and Writeback levels remain similar across all three conditions
	- no substantial difference in nr_dirty or nr_writeback behavior is observed
	- spike behavior remains similar, but kernel writeback state also remains similar

Interpretation:

The experiment does not provide a valid discriminator between writeback regimes.
Under this outcome, absence of a spike difference cannot be interpreted as evidence against writeback involvement, 
because the manipulated conditions failed to produce materially different writeback behavior.

Outcome 5 - Ambiguous result due to inverted ordering
------------------------------------------------------
Changes in writeback or dirty state are observed only after spike onset.

Interpretation:

Observed writeback-state changes are more likely to be downstream effects of the latency event than causal contributors.
This outcome does not support a writeback-driven explanation, even if writeback activity appears near the spike window.
Temporal precedence is required for causal support.

Results
---------
The experiment was conducted under three conditions:

	- Condition A: default writeback policy
	- Condition B: early and continuous writeback
	- Condition C: delayed and burst writeback

All conditions used buffered disk-backed IO and identical workload structure across three cycles.

Cycle 3 RECOVERY_R2 spike behavior
-----------------------------------
Latency events (dt_ms) were extracted within the RECOVERY_R2 window for Cycle 3 and filtered using the threshold dt_ms > 120 ms.

Condition A
	- Spike count: 6
	- Maximum latency: 340 ms
	- First spike offset from RECOVERY_R2 start: 6593.120 ms
	- Cluster duration: 47229.862 ms

Spike values:
181, 180, 324, 340, 250, 209

Condition B
	- Spike count: 7
	- Maximum latency: 287 ms
	- First spike offset from RECOVERY_R2 start: 4894.418 ms
	- Cluster duration: 48201.360 ms

Spike values:
198, 141, 287, 179, 146, 191, 143

Condition C
	- Spike count: 7
	- Maximum latency: 304 ms
	- First spike offset from RECOVERY_R2 start: 5031.624 ms
	- Cluster duration: 48213.709 ms

Spike values:
146, 182, 195, 304, 141, 230, 140

Writeback-state observations around first spike (Cycle 3 RECOVERY_R2)
----------------------------------------------------------------------
Writeback-related state was sampled continuously using:

	/proc/meminfo (Dirty, Writeback)
	/proc/vmstat (nr_dirty, nr_writeback)

A window of 5 seconds prior to first spike and 1 second after was examined.

Condition A
-------------
	- Dirty memory remained stable in the range of approximately 240–256 kB prior to spike onset
	- Writeback activity appeared intermittently before spike onset, with short bursts (e.g., Writeback_kB up to ~1616)
	- vmstat showed corresponding nr_writeback activity preceding the spike

Representative behavior:

	- steady dirty state
	- intermittent writeback bursts before spike onset
	
Condition B
-------------
	- Dirty memory ranged approximately between 128–256 kB prior to spike onset
	- Writeback activity appeared prior to spike onset, including sustained small bursts (e.g., Writeback_kB ~112, occasional peaks ~1872)
	- vmstat showed non-zero nr_writeback activity in the pre-spike window

Representative behavior:

	- lower baseline dirty state compared to A
	- visible writeback activity preceding spike onset
	
Condition C
-------------
	- Dirty memory increased from approximately 144 kB to ~272–288 kB prior to spike onset
	- Writeback activity appeared prior to spike onset, including both short bursts and larger sustained activity (e.g., Writeback_kB up to ~1520)
	- vmstat showed corresponding increases in nr_writeback in the pre-spike window

Representative behavior:

	- higher dirty accumulation compared to B
	- writeback bursts occurring before spike onset
	
Summary of observed behavior

Across all three conditions:
----------------------------
	- Latency spikes (dt_ms > 120 ms) were observed within RECOVERY_R2 in Cycle 3
	- Spike counts ranged between 6 and 7
	- Maximum latency values ranged between 287 ms and 340 ms
	- First spike onset occurred between ~4.9 seconds and ~6.6 seconds after RECOVERY_R2 start
	- Cluster durations were approximately 47–48 seconds

Writeback-state sampling showed:

	- Non-zero writeback activity in the pre-spike window in all conditions
	- Dirty memory accumulation prior to spike onset
	- Variation in dirty-state magnitude across conditions confirms that writeback-policy manipulations produced distinct buffered-state regimes
	This confirms that the experimental conditions produced materially distinct writeback regimes, and therefore Outcome 4 does not apply.
	
		Comparison Table
		-----------------
The following table summarizes Cycle 3 RECOVERY_R2 metrics across all three conditions.

Condition	Writeback Policy	Spike Count (>120 ms)	Max dt_ms	First Spike Offset (ms)	Cluster Duration (ms)
	A			Default		  		6						340				6593.120			47229.862
	B		Early / Continuous		7						287				4894.418			48201.360
	C		Delayed / Burst			7						304				5031.624			48213.709
	
	
Additional writeback-state summary (Cycle 3 R2, pre-spike window)
------------------------------------------------------------------
Condition	Dirty_kB Range	Writeback Activity					nr_dirty Range	nr_writeback Activity
	A			~240–256	Intermittent bursts (up to ~1616 kB)	~15–17		Present before spike
	B			~128–256	Small sustained bursts, 
							occasional peaks (up to ~1872 kB)		~8–16		Present before spike
	C			~144–288	Larger bursts and sustained activity 
							(up to ~1520 kB)						~9–18		Present before spike
							
							
							
Conclusions
------------
The observed variation in dirty-state behavior across conditions confirms that the applied writeback-policy configurations produced materially distinct system states.
The results demonstrate that latency spikes remain present within RECOVERY_R2 across all tested writeback-policy conditions. 
Cycle 3 analysis shows comparable spike counts, peak latencies, and cluster durations between the default, 
early-writeback, and delayed-writeback configurations. 
The instability regime persists regardless of whether writeback is triggered earlier and more continuously or allowed to accumulate and flush in larger bursts.
These results do not support the strong form of the hypothesis, which predicted directional divergence in spike behavior between early and delayed writeback regimes.

Variation was observed in the timing of initial spike onset. 
Both modified conditions (B and C) exhibited earlier first-spike occurrence relative to the default condition. 
However, this shift did not differentiate the early and delayed writeback regimes from each other in a consistent or opposing manner. 
Notably, both modified conditions produced earlier spike onset relative to the default condition, 
but in the same direction despite opposing writeback policies. 
This indicates that writeback policy changes influence onset timing, but not in a manner consistent with a directional or policy-specific control mechanism.

Writeback-state observations show that writeback activity occurs prior to or near spike onset in all conditions. 
Dirty memory accumulates before the first spike, and writeback activity is present in the pre-spike window, as reflected in both memory and vmstat metrics. 
This establishes consistent temporal proximity between buffered writeback activity and the spike window.

Despite this association, modifying writeback policy does not produce a corresponding structural change in the spike regime. 
Spike density, peak magnitude, and cluster duration remain within a similar range across all conditions. 
The persistence of the instability pattern under materially different writeback configurations indicates that 
writeback policy manipulation does not produce first-order control over spike manifestation within the buffered IO path.

Within the predefined interpretation framework, the observed results do not satisfy Outcome 1, 
as no directional divergence in spike behavior was observed between Conditions B and C. 
The similarity in spike count, peak latency, and cluster duration across all conditions aligns most closely with Outcome 3. 
However, the presence of writeback activity prior to spike onset in all conditions provides limited support for Outcome 2, indicating partial temporal coupling without structural control.

These findings indicate that while writeback activity is present during the spike window, it does not act as the primary driver of the observed instability. 
The mechanism responsible for spike expression appears to reside beyond policy-level writeback tuning, within deeper components of the buffered disk-backed execution path.
The absence of directional divergence under conditions that materially altered writeback behavior indicates that the observed instability is not governed by high-level writeback scheduling parameters.

The next step is to investigate lower-level behavior, 
focusing on mechanisms not governed by policy-level writeback scheduling. 
Future experiments will aim to isolate whether spike manifestation is driven by block-layer submission and completion behavior, 
filesystem commit interactions, or blocking dynamics that emerge during retry-driven write activity.