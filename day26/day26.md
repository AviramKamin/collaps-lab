Day26 - Completion Blocking vs Artificial Delay

Introduction
-------------

Previous experiments established that latency spike manifestation in the system is strongly phase-dependent, 
consistently emerging during the RECOVERY_R2 interval rather than during sustained workload execution. 
Earlier stages of the investigation demonstrated that the spike regime is preserved under reduced observation intensity, 
persists across multiple workload structures, and depends on buffered disk-backed IO behavior rather than on steady-state CPU load alone.

Subsequent experiments progressively narrowed the mechanism space underlying the observed instability. 
Day24 demonstrated that modifying deferred writeback policy altered spike characteristics only modestly, 
indicating that writeback scheduling alone is insufficient to explain the observed RECOVERY_R2 behavior. 
Day25 further constrained the mechanism by showing that synchronized buffered writes produced a substantially stronger spike regime than unsynchronized buffered writes under otherwise identical conditions.
 Specifically, synchronized conditions exhibited increased spike count, earlier onset, and longer clustering duration during RECOVERY_R2.

These findings suggest that the observed instability is sensitive to write completion behavior within the buffered IO path. 
However, the mechanism responsible for this sensitivity remains unresolved. 
Two competing explanations remain possible. The first is that actual IO completion behavior, 
including synchronization and completion ordering within the storage path, directly contributes to spike manifestation. 
The second is that the introduction of blocking into the retry execution path is itself sufficient to produce the observed spike regime, independent of actual completion behavior.

Day26 investigates this distinction by isolating execution blocking from real IO synchronization. 
The experiment compares unsynchronized buffered writes, real synchronized completion, and artificial delay insertion while holding workload structure, 
retry behavior, timing, IO target, and observation methodology constant. 
The goal is to determine whether RECOVERY_R2 spike manifestation depends primarily on actual completion semantics or on blocking duration introduced into the execution path.

Hypothesis
----------

If latency spike manifestation during RECOVERY_R2 is primarily driven by blocking duration within the retry execution path, then introducing artificial delays after unsynchronized buffered writes should reproduce a spike regime similar to real synchronized completion.

Specifically, artificial blocking is expected to produce measurable similarity to the synchronized-completion condition in one or more of the following metrics:

	- spike count
	- maximum latency
	- first spike offset
	- cluster duration

If artificial blocking produces spike behavior comparable to real synchronized completion, then blocking duration is sufficient to explain the observed completion-sensitive spike regime.

If artificial blocking remains comparable to unsynchronized buffered writes and does not reproduce the synchronized-completion spike regime, 
then actual IO completion behavior is likely required for strong spike manifestation under the tested conditions.

If artificial blocking produces an intermediate or distinct spike regime, 
then spike manifestation is likely influenced by an interaction between blocking duration, retry timing, and actual IO completion behavior.

Methods
-------

The experiment was conducted on the same Raspberry Pi 5 Linux environment used throughout previous stages of the study. 
All conditions used the same retry workload structure, buffered disk-backed IO target, phase timing, retry behavior, 
observation methodology, and heartbeat instrumentation. 
The experiment preserved the standard five-phase execution structure consisting of BASELINE, INTERVENTION, RECOVERY_R1, RECOVERY_R2, and POSTBASELINE.

Heartbeat latency sampling remained fixed across all conditions using the existing high-frequency heartbeat monitor. 
Spike manifestation analysis focused specifically on the RECOVERY_R2 interval, consistent with previous experiments in the study. 
Latency spikes were identified using the established threshold of:
dt_ms > 120

Three experimental conditions were evaluated.

Condition A - Unsynchronized Buffered Writes
---------------------------------------------
Condition A served as the baseline reference condition. 
The retry workload performed buffered writes without synchronization or additional delay insertion. 
Writes were issued through the buffered IO path and execution continued immediately after write submission.

Condition B - Real Synchronized Completion
-------------------------------------------
Condition B introduced real completion blocking through synchronized buffered writes. 
After each buffered write operation, the workload enforced data synchronization using: fdatasync()

This condition preserved the same retry structure and IO workload while introducing blocking through actual IO completion behavior.

Condition C - Artificial Blocking
----------------------------------
Condition C introduced artificial execution blocking without real IO synchronization. 
Buffered writes were issued identically to Condition A, but a fixed artificial delay was inserted after each write operation using controlled sleep intervals. 
No synchronization or completion enforcement was performed in this condition.

The artificial delay duration was selected to approximate the execution blocking introduced by the synchronized completion path while avoiding direct IO completion behavior.
The delay interval was derived from preliminary measurements of synchronized completion latency obtained under the same workload conditions.

All conditions maintained identical:

	- retry counts
	- phase durations
	- workload pacing
	- observation intensity
	- IO target path
	- heartbeat configuration
	- logging structure

The primary variable modified between conditions was whether execution blocking originated from synchronized IO completion or from artificial delay insertion.

For each condition, spike manifestation within RECOVERY_R2 was evaluated using the following metrics:

	- spike count
	- maximum observed latency
	- first spike offset relative to RECOVERY_R2 start
	- spike cluster duration within RECOVERY_R2

Each condition was executed across multiple experimental cycles using the same timing structure and workload configuration.

Results
----------

All three conditions completed successfully across three experimental cycles using identical workload structure, retry behavior, 
timing configuration, buffered disk-backed IO target, and observation methodology. 
Analysis focused on latency spike manifestation during the RECOVERY_R2 interval of cycle C3.

Condition A, which used unsynchronized buffered writes without additional delay insertion, 
produced a limited spike regime during RECOVERY_R2. Two latency spikes exceeded the established threshold of dt_ms > 120
The maximum observed latency was 148 ms. 
The first spike appeared 25861.041 ms after the start of RECOVERY_R2, and the observed spike cluster duration was 10257.644 ms.

Condition B, which enforced synchronized buffered completion using fdatasync(), 
produced a substantially stronger spike regime during RECOVERY_R2. 
Seven latency spikes exceeded the spike threshold, with a maximum observed latency of 296 ms. 
The first spike appeared 2351.409 ms after the start of RECOVERY_R2, 
and spike manifestation remained active across a cluster duration of 47564.234 ms. 
Multiple high-amplitude latency events above 180 ms were observed throughout the RECOVERY_R2 interval.

Condition C introduced artificial execution blocking through a fixed 10 ms delay after unsynchronized buffered writes while preserving the same retry workload structure and IO target. 
No latency spikes exceeding the threshold were observed during RECOVERY_R2 in cycle C3. 
No spike cluster formation was detected within the analyzed interval.

Comparison Table

| Condition | Completion Behavior                         | Spike Count (>120 ms) | Max dt_ms | First Spike Offset (ms) | Cluster Duration (ms) |
| --------- | ------------------------------------------- | --------------------: | --------: | ----------------------: | --------------------: |
| A         | Unsynchronized buffered writes              |                     2 |       148 |               25861.041 |             10257.644 |
| B         | Buffered writes with `fdatasync()`          |                     7 |       296 |                2351.409 |             47564.234 |
| C         | Buffered writes with artificial 10 ms delay |                     0 |         0 |                      NA |                     0 |
--------------------------------------------------------------------------------------------------------------------------------------------------

The strongest spike regime was observed under synchronized buffered completion in Condition B. 
Condition A exhibited limited late-stage spike manifestation, 
while Condition C produced no threshold-exceeding latency spikes during the analyzed RECOVERY_R2 interval.

Conclusions
------------
The results demonstrate that execution blocking alone is insufficient to reproduce the synchronized-completion spike regime observed during RECOVERY_R2. 
Although Condition B and Condition C both introduced additional delay into the retry execution path relative to unsynchronized buffered writes, 
only synchronized buffered completion produced strong and sustained latency spike manifestation.

Condition B, which enforced synchronized completion using fdatasync(), 
produced the strongest instability profile observed in the experiment. 
Spike manifestation appeared early in RECOVERY_R2, persisted across a large portion of the recovery interval, 
and reached substantially higher latency amplitudes than the unsynchronized reference condition. 
In contrast, Condition C, which introduced deterministic artificial blocking without synchronized completion behavior, 
produced no threshold-exceeding spikes during the analyzed RECOVERY_R2 interval.

These findings directly address the experimental hypothesis. 
The hypothesis predicted that if blocking duration within the retry execution path were sufficient to produce the synchronized-completion spike regime, 
then artificial delay insertion should reproduce behavior comparable to synchronized completion. 
This prediction was not supported by the observed results. 
Artificial blocking at the tested delay interval did not reproduce the spike count, onset timing, cluster duration, or latency amplitude observed under synchronized buffered completion.

The results therefore suggest that the RECOVERY_R2 spike regime depends on properties specific to synchronized IO completion behavior rather than on execution slowdown alone. 
The mechanism underlying the instability appears to involve interaction with the real completion path of buffered disk-backed IO rather than deterministic delay insertion in userspace execution.

When considered together with previous experiments in the study, 
the emerging structure of spike manifestation becomes increasingly constrained. 
Earlier stages established that the instability is phase-dependent rather than steady-state load dependent, 
that it persists under reduced observation intensity, and that it is strongly associated with buffered disk-backed IO behavior. 
Day24 demonstrated that writeback timing policy alone was insufficient to fully explain spike manifestation, 
while Day25 demonstrated strong sensitivity to synchronized completion semantics. 
Day26 further narrows the mechanism space by showing that synchronized completion behavior cannot be reproduced through artificial execution delay alone.

Taken together, the accumulated results suggest that the observed instability is likely generated through interaction between recovery-phase retry activity and the real buffered IO completion path, 
potentially involving filesystem synchronization behavior, block-layer completion ordering, deferred writeback state, 
or scheduler interaction around completion wakeups. 
The spike regime no longer appears consistent with a simple interpretation based solely on CPU saturation, retry pressure, or generic execution slowdown.

The next stage of the investigation should therefore focus on identifying the specific subsystem boundary responsible for the synchronized-completion spike regime
rather than introducing additional synthetic workload variation. 
Future experiments should compare the strongest known synchronized-completion condition across different 
storage backends in order to determine whether the instability originates primarily from the physical storage completion path or from higher-level filesystem and kernel completion behavior. 
Additional low-intrusion timing instrumentation may later be incorporated to correlate latency spikes with synchronized completion intervals while minimizing observer-induced distortion. 
The study remains open until the spike regime can be reduced, eliminated, or predictably reshaped through direct modification of the identified bottleneck path.