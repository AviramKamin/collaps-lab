Day21 - Buffered Writeback vs Direct I/O in RECOVERY_R2
--------------------------------------------------------

Introduction
------------
Day20 demonstrated that latency spike expression during RECOVERY_R2 depends on the retry storage path. 
Spike clusters were observed only when retry execution used a disk-backed target, 
and disappeared when the retry target was redirected to tmpfs. This pattern held regardless of whether intervention I/O was present earlier in the cycle.

These results isolate disk-backed retry execution as the trigger surface for spike formation under the current design, 
but they do not identify which component of the storage path is responsible. In particular, 
the results do not distinguish between instability associated with buffered filesystem behavior and instability associated with the disk path more generally.

Day21 addresses this gap by comparing buffered disk-backed retry execution with direct I/O retry execution 
while preserving the same phase structure and retry timing. 
The goal is to determine whether spike expression depends on buffering and writeback behavior, or whether it persists when the buffered path is minimized.

Hypothesis
-----------
Latency spike expression during RECOVERY_R2 depends on buffered disk-backed I/O behavior rather than on disk access in the most general sense.
If buffered writeback behavior is required for spike formation, 
then redirecting retry execution to direct I/O on a disk-backed target should suppress or substantially reduce spike expression during RECOVERY_R2.
If spike expression persists under direct I/O with comparable structure, 
then the mechanism is not limited to buffered writeback behavior and likely arises from a deeper component of the disk-backed execution path.

Methods
-------
Day21 preserves the experimental phase structure and analysis framework established in Day20 
while isolating buffered versus direct disk-backed retry behavior as the primary independent variable.

All conditions follow the same phase sequence:

	BASELINE → INTERVENTION → RECOVERY_R1 → RECOVERY_R2 → POSTBASELINE

Each run consists of N = 3 cycles. Phase durations remain fixed:

	- BASELINE: 60 seconds
	- INTERVENTION: 10 seconds
	- RECOVERY_R1: 60 seconds
	- RECOVERY_R2: 60 seconds
	- POSTBASELINE: 60 seconds

Primary analysis is restricted to RECOVERY_R2 in Cycle 3.

No scheduler competitor is introduced. 
Intervention I/O is disabled for the primary comparison conditions in order to preserve direct continuity with the no-intervention branch established in Day20.

Retry intensity remains fixed at the reference level used in Day20. The primary manipulation is the I/O mode used by the retry path:

	- buffered disk-backed execution
	- direct I/O disk-backed execution
	- optional tmpfs execution as a negative control

Measurement relies on the existing instrumentation framework:

	- heartbeat logging for latency measurement (dt_ms)
	- heartbeat_marks.log for phase boundaries
	- run.log for retry activity
	- probes.log for auxiliary markers
	- meta.env for exact execution parameters

A latency spike is defined as any event with dt_ms > 120 ms, unchanged from Day19 and Day20.

Experimental conditions
------------------------

Condition A - Buffered disk retry reference
-------------------------------------------
This condition preserves disk-backed retry execution using the standard buffered path.

Implementation:

	- retry target remains on the standard disk-backed filesystem
	- retry intensity remains fixed at the reference level
	- intervention I/O is disabled
	- phase structure and timing remain unchanged

Purpose:

	provide the active reference condition for RECOVERY_R2 spike expression under buffered disk-backed execution

Condition B - Direct I/O disk retry
-----------------------------------
This condition preserves the disk-backed retry target while minimizing buffered writeback behavior.

Implementation:

	- retry target remains on the standard disk-backed filesystem
	- retry operations are executed using direct I/O
	- retry intensity remains fixed at the reference level
	- intervention I/O is disabled
	- phase structure and timing remain unchanged

Purpose:

	determine whether spike expression persists when buffered filesystem behavior is bypassed

Condition C - tmpfs negative control (optional)
-----------------------------------------------
This condition preserves retry timing while removing disk-backed execution entirely.

Implementation:

	- retry target is redirected to tmpfs
	- retry intensity remains fixed at the reference level
	- intervention I/O is disabled
	- phase structure and timing remain unchanged

Purpose:

	confirm the negative-control behavior under the Day21 execution model
	

Analysis plan
-----------------
Analysis follows the same extraction procedure used in Day19 and Day20 in order to preserve direct comparability.

For each run, RECOVERY_R2 in Cycle 3 is isolated using phase markers from heartbeat_marks.log. 
Latency values (dt_ms) are extracted from run.log within this window.

The following metrics are computed for each condition:

	- spike count (dt_ms > 120 ms)
	- maximum observed latency within RECOVERY_R2
	- time-to-first-spike relative to RECOVERY_R2_START
	- spike cluster duration within RECOVERY_R2

Comparison focuses on whether direct I/O suppresses, preserves, or reshapes spike expression relative to buffered disk-backed execution.

Interpretation guidelines:

	- if direct I/O removes or sharply reduces spike expression, this supports buffered writeback behavior as a necessary component of the mechanism
	- if direct I/O preserves spike expression with comparable structure, buffered writeback is not required
	- if direct I/O reduces severity without eliminating spikes, buffered behavior acts as an amplifier rather than a sole requirement
	
	
	
Results
-------

Experimental Scope
-------------------
Heartbeat latency (dt_ms) measurements were extracted from the R2 phase for three conditions:

	Condition A — Buffered disk-backed execution
	Condition B — Direct I/O disk-backed execution
	Condition C — tmpfs execution (negative control)

Extraction criteria:

	- Only entries within R2 timestamp bounds were included
	- Each record: <timestamp_ns> <dt_ms>
	- Spike threshold: dt_ms > 120 ms
	
Condition A
------------
Run: 2026-04-12_122205_day21_A_buffered_vs_direct

Sample Overview
	Total R2 samples: 16
full dt_ms Sequence (R2)

Format: <offset_ms_from_R2_start> → dt_ms

	0.000      → ~baseline
	~100 ms    → ~baseline
	~200 ms    → ~baseline
	491.356    → 250
	...
	(remaining samples include both baseline-range values and spikes)

(Note: Only spike values explicitly extracted from analysis output are reported. 
Non-spike values are present in the dataset but are not enumerated individually in this section.)

Spike Events

Spike threshold: >120 ms

Observed spikes:

Spike#		Offset(ms)		dt_ms
1			491.356		   	250
2–8			within R2	    >120

Total spikes: 8

Inter-Spike Gaps

Defined as time difference between consecutive spike offsets.

	- First spike offset: 491.356 ms
	- Subsequent spike offsets occur within same R2 window
	- Inter-spike gaps are sub-second scale (bounded by total R2 duration and sample count)
	
Summary Metrics
-----------------
Max latency: 250 ms
Spike count: 8 / 16 samples
First spike offset: 491.356 ms


Condition B
------------
Run: 2026-04-12_131905_day21_B_buffered_vs_direct

Sample Overview
	Total R2 samples: 2

Full dt_ms Sequence (R2)

~0 ms        → <120 ms (non-spike)
28496.8 ms   → 153 ms (spike)

Spike Events

Spike#		Offset(ms)		dt_ms
1			 28496.8		 153

Total spikes: 1
The spike occurs near the latter portion of the R2 window based on its offset from R2_START.
Inter-Spike Gaps
	Only one spike observed
	Inter-spike gap: not applicable
	
	
Summary Metrics
Max latency: 153 ms
Spike count: 1 / 2 samples
First spike offset: 28496.8 ms


Condition C
------------
Run: 2026-04-12_133149_day21_C_buffered_vs_direct

Sample Overview
Total R2 samples: 0

Full dt_ms Sequence (R2)
No samples recorded

Spike Events
No spikes observed

Inter-Spike Gaps
Not applicable

Summary Metrics
	Max latency: 0 ms
	Spike count: 0
	First spike offset: not observed
	
Cross-Condition Data Summary

Sample Counts

Condition	Samples
A			  16
B			   2
C			   0


Spike Counts

Condition	Spikes (>120 ms)
A			  8
B			  1
C			  0


Maximum Latency

Condition	Max(ms)
A			250
B			153
C			 0


First Spike Offset

Condition	Offset (ms)
A			  491.356
B			  28496.8
C			Not observed

Data Characteristics
--------------------
	- R2 data volume varies across conditions (16 → 2 → 0 samples)
	- Spike presence varies across conditions
	- Spike timing varies in absolute offset within R2
	- Only Condition A contains multiple spike events within a single R2 window
	- Condition B contains a single spike event
	- Condition C contains no recorded events
	
Conclusions
------------
The experiment does not provide consistent evidence that the tested condition produces a stable or repeatable spike pattern during the R2 phase.
While Condition A exhibits multiple latency excursions above the defined threshold,
this behavior is not reproduced in Condition B and is not observable in Condition C within the recorded data.
The presence of spikes in one condition and their absence or sparsity in others indicates that the observed behavior is not consistently expressed across runs.

As a result, the hypothesis that the tested mechanism deterministically drives spike formation
during R2 is not supported by the current data.
The observed spike events are condition-dependent and not reproducible across all experimental configurations executed in this run set.

The mechanism responsible for the latency excursions is not isolated by this experiment.
Although spike events are observed in specific cases,
their inconsistent appearance and the lack of measurable data in one of the conditions prevent attribution to a single controlled factor within the experiment.

The experiment establishes that spike behavior,
when present, can occur within the R2 phase and can reach latency values above 120 ms.
However, it does not establish a consistent trigger, nor does it demonstrate that the buffered versus direct IO
distinction alone is sufficient to explain the presence or absence of these events.

Therefore, within the scope of this experiment, the relationship between the tested IO mode and spike formation remains unresolved.

This lack of resolution is accompanied by uneven observability across conditions, 
including minimal sampling in one case and the absence of measurable R2 data in another. 
As a result, the current configuration does not provide a uniform basis for comparison between conditions, 
and limits the ability to isolate the factors influencing spike formation. 
The next step will therefore focus on enforcing consistent R2 visibility across all runs, 
while maintaining strict separation between IO modes and controlling for measurement continuity. 
Day22 will be designed to ensure comparable data density and stable observation windows, 
allowing direct evaluation of spike behavior under fully observable conditions.