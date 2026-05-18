DAY 2 NOTES – Increased IO Concurrency

Hypothesis
----------
Day 2 aimed to amplify scheduler drift by increasing IO concurrency
(numjobs = 2, iodepth = 1), while keeping all other variables constant
(block size, IO pattern, duration, logging).

The expectation was that higher concurrency would increase contention
and result in a larger sub-collapse drift compared to Day 1, without
causing thermal or power-induced collapse.

Observation
-----------
A measurable drift did occur, but its magnitude was small and close to
noise levels.
Baseline idle variance measurements suggest this drift is near the lower bound of observable scheduler jitter,
though further isolation is required to fully separate noise from signal.
Day 1 baseline heartbeat measurements showed scheduler jitter on the order of ~0.10 ms, 
with p99 excursions occasionally reaching similar magnitudes under idle conditions.

The Day 2 p99 drift increase of ~0.07 ms falls entirely within this baseline envelope.
As a result, the observed drift remains near the lower bound of detectability and 
cannot be cleanly separated from natural scheduler noise.

Observed metrics:
- Average drift increase: ~0.09 ms
- Tail behavior:
  - p95 increased by ~0.11 ms
  - p99 increased by ~0.07 ms
  
 

The heartbeat distribution did shift during the drift window, and the
system returned to baseline behavior in the post-drift window.
This confirms that the system did experience load, but only lightly.

Importantly, the magnitude of drift in Day 2 was smaller than Day 1,
despite higher overall IO activity.

Interpretation
--------------
Increasing IO concurrency appears to have reduced contention burstiness under these conditions relative to Day 1.

Although total IO load increased, timing variability decreased,
indicating that concurrency smoothed contention rather than amplifying it.

This behavior suggests that, under these conditions, concurrency acts
as a stabilizing factor for scheduler timing rather than a destabilizing one.

This experiment highlights that increasing load does not necessarily
increase instability, and that system behavior depends strongly on the
shape of contention, not only its magnitude.
