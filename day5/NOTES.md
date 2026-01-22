$notes = @'
# Collapse Lab - Day 5 NOTES
Date: 2026-01-22
Author: Aviram kamin

## Hypothesis
Once the system enters a collapse regime, its internal state no longer resets fully between interventions.
Queue depth, retry feedback, and scheduler deformation accumulate, producing memory effects that alter system response even under identical external load.

Observable signals:
- Divergent responses to identical interventions based on prior collapse exposure
- Degradation or elongation of recovery dynamics
- Baseline heartbeat drift after collapse exposure
- Reduced collapse threshold after prior collapse events

## Methods
### Experimental idea
Day 5 intentionally operates inside the collapse region discovered in Day 4.
Instead of sweeping OFF windows, OFF is fixed in a known unstable range and the system is observed over repeated cycles.
Day 5 treats collapse not as a boundary event, but as a persistent dynamical regime.

Conceptually:
- Hold OFF at a collapse prone value
- Apply repeated collapse cycles
- Measure whether recovery worsens, baseline shifts, collapse triggers become more frequent, and tail latencies accumulate

You are no longer searching for the knee.
You are walking inside the avalanche.

### Core dimensions to explore
1. Collapse memory
2. Collapse hysteresis
3. Collapse layering
4. Collapse reversibility
   Is there a point where recovery never truly completes?

### Metrics focus
Memory indicators

Heartbeat:
- baseline drift
- p99 inflation persistence
- recovery decay time

Retry storm:
- event clustering
- persistence after intervention ends
- growth rate

IO:
- tail thickening across time
- variance explosion

### Experimental structure
Day 5 is a repeated cycle experiment. The external load pattern is held constant across cycles.
Only the system internal state is allowed to evolve.
Each cycle is evaluated against Baseline0, not against the previous cycle.
This makes memory measurable as drift away from the original healthy state.

One collapse cycle consists of ordered stages:
- Baseline probe (B): heartbeat only
- Collapse entry (K): burst plus retry interference using fixed OFF
- Intervention hold (I): hold interference to stabilize collapse dynamics
- Recovery (R): stop interference, heartbeat only
- Post recovery baseline probe (B2): heartbeat only

Cycle notation:
B -> K -> I -> R -> B2

### Fixed parameters
Held constant during all cycles:
- OFF value
- burst ON duration
- burst count per intervention window
- retry storm parameters (BUDGET_MS, RETRIES)
- heartbeat interval

Only N and the internal state evolve.

### Operational definitions
Memory:
Any persistent change in baseline metrics after recovery relative to Baseline0.

Memory is present if one or more trends occur across cycles:
- Baseline p99 increases monotonic or stepwise
- Recovery time increases across cycles
- p99 inflation persists into recovery or B2
- collapse becomes easier to trigger

Hysteresis:
Delayed restoration of stability when returning to a safe regime.

Layering:
Discrete collapse depths, for example stable p95 with violent p99 or max jumps.

Reversibility:
System returns within a tolerance band around Baseline0.
If it fails, collapse is partially irreversible.

### Termination conditions
Stop if:
- baseline p99 remains above Baseline0 by tolerance for full recovery window
- retry events continue during recovery or baseline stages
- sustained baseline drift over cycles with no stabilization
- system becomes unusable

### Notes on parameter safety
Avoid instant hard collapse.
If collapse occurs immediately in cycle 1, reduce aggressiveness before continuing.

## Evidence on disk
All runs are preserved, including partial and exploratory ones, to avoid survivorship bias.

Windows path:
C:\Users\אבירם\Desktop\raspberry_pi_project\day5\runs

Run inventory (heartbeat_lines, marks_lines):
OFF3:
- 2026-01-18_141333_day5_off3_n3  heartbeat=196   marks=1   (partial)
- 2026-01-18_141622_day5_off3_n1  heartbeat=138   marks=8   (single cycle)
- 2026-01-18_151048_day5_off3_n3  heartbeat=12170 marks=24
- 2026-01-22_141442_day5_off3_n3  heartbeat=12194 marks=24

OFF2:
- 2026-01-18_163053_day5_off2_n3  heartbeat=12141 marks=24

OFF1:
- 2026-01-18_174408_day5_off1_n1  heartbeat=1740  marks=8
- 2026-01-18_175017_day5_off1_n3  heartbeat=12049 marks=24
- 2026-01-18_190035_day5_off1_n1  heartbeat=1323  marks=8
- 2026-01-18_194652_day5_off1_n1  heartbeat=1357  marks=8
- 2026-01-18_204133_day5_off1_n1  heartbeat=285   marks=8
- 2026-01-18_210141_day5_off1_n1  heartbeat=288   marks=8
- 2026-01-18_213407_day5_off1_n1  heartbeat=283   marks=8

Canonical runs locked for analysis:
- OFF3: 2026-01-22_141442_day5_off3_n3
- OFF2: 2026-01-18_163053_day5_off2_n3
- OFF1: 2026-01-18_175017_day5_off1_n3

## Results
canonical runs used

The following canonical runs were used for comparison across OFF values:

OFF=3 canonical: 2026-01-22_141442_day5_off3_n3

OFF=2 canonical: 2026-01-18_163053_day5_off2_n3

OFF=1 canonical: 2026-01-18_175017_day5_off1_n3

Each run contains 3 cycles with the standard phase markers:
C1 C2 C3 baseline intervention recovery postbaseline.

retry storm results

Retry storm activity was observed only in the OFF=3 canonical run. OFF=1 and OFF=2 canonical runs produced zero recorded retry events in all cycles.

OFF=3 canonical retry storm percentiles by cycle:

cycle 1: dt_ms samples=98 p95=431 p99=2314 max=2314

cycle 2: dt_ms samples=96 p95=388 p99=2598 max=2598

cycle 3: dt_ms samples=93 p95=436 p99=1257 max=1257

Retry budget was configured as BUDGET_MS=120 and RETRIES=3. The OFF=3 run consistently exceeded budget with multi hundred millisecond p95 and multi second p99 max events. Retry severity varied by cycle and did not increase monotonically across cycles.

heartbeat results

Heartbeat p95 and p99 remained stable across cycles for all OFF values. Postbaseline phases returned to baseline range, with no monotonic drift or stepwise increase across cycles.

OFF=3 canonical heartbeat:

C1 baseline: samples=590 p95=101678757 p99=101755318 max=101911824
C1 postbaseline: samples=591 p95=101666891 p99=101714978 max=101934610

C2 baseline: samples=591 p95=101659900 p99=101707159 max=101745848
C2 postbaseline: samples=586 p95=101667713 p99=101836668 max=507773308

C3 baseline: samples=591 p95=101678394 p99=101725441 max=102657384
C3 postbaseline: samples=591 p95=101634452 p99=101732170 max=101915040

One extreme outlier was observed in OFF=3 cycle 2 postbaseline max value of 507773308 ns. This was not accompanied by sustained p95 or p99 inflation.

OFF=2 canonical heartbeat:

C1 baseline p95=101653378 p99=101718842 and postbaseline p95=101658285 p99=101686249

C2 baseline p95=101667125 p99=101701557 and postbaseline p95=101647371 p99=101675552

C3 baseline p95=101669445 p99=101750094 and postbaseline p95=101643964 p99=101680131

OFF=1 canonical heartbeat:

C1 baseline p95=101663245 p99=101722522 and postbaseline p95=101655169 p99=101693725

C2 baseline p95=101665539 p99=101721946 and postbaseline p95=101668001 p99=101713964

C3 baseline p95=101668093 p99=101696705 and postbaseline p95=101663057 p99=101708890

Across OFF values, baseline and postbaseline p95 and p99 remained within a narrow band without a rising trend across cycles.

## Conclusions
main question answer

Day 5 does not show evidence of persistent baseline deformation in heartbeat timing under the tested conditions. Baseline and postbaseline heartbeat percentiles remained stable across cycles for OFF=1 OFF=2 and OFF=3.

collapse regime characterization

A collapse prone regime was observed in the retry subsystem at OFF=3. Under OFF=3, retry storm events repeatedly exceeded the configured budget BUDGET_MS=120 with p95 dt_ms approximately 388 to 436 ms and p99 reaching 1257 to 2598 ms. This behavior was not observed in OFF=1 or OFF=2 canonical runs, where retries logs were empty.

memory assessment

The hypothesis predicted that collapse exposure would accumulate and degrade recovery. The data shows repeated vulnerability at OFF=3 but does not show accumulation across cycles in heartbeat metrics. Retry severity varies across cycles but does not increase monotonically, and heartbeat postbaseline returns near baseline in all cycles.

interpretation boundary

These results support a constrained conclusion: collapse can be repeatable and severe within a specific subsystem without producing persistent global timing drift. Under the current forcing intensity and durations, recovery remains effective and no irreversible degradation is detected.