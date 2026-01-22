DAY 3 NOTES – Burst Alignment and Retry Amplification

hypothesis
----------
Increasing IO burst alignment and introducing retry feedback will amplify scheduler drift beyond the baseline jitter envelope, 
producing measurable tail latency expansion and collapse-adjacent behavior even if the system remains recoverable.

experimental structure
---------------------
Day 3 was executed in three attempts:

Attempt 1 – orchestration failure  
Attempt 2 – retry-only execution  
Attempt 3 – first valid combined run (fio bursts + retry storm)

Only Attempt 3 is considered valid for collapse analysis.


attempt 1 summary – invalid
---------------------------
Cause:
Scripts contained CRLF line endings, causing Linux to interpret the shebang as `bash\r`.

Effect:
- IO bursts did not execute
- Retry storm did not execute
- Heartbeat ran without interference
- No collapse mechanisms were active

Conclusion:
Attempt 1 is invalid for collapse analysis and is classified as an orchestration failure.

attempt 2 summary – partial execution
------------------------------------
Cause:
`run_bursts.sh` assumed execution from the scripts directory, but was launched from the run directory.
Relative path to `burst_io.fio` failed.

Effect:
- Retry storm executed successfully
- IO bursts failed to execute
- Intervention was retry-only

Conclusion:
Attempt 2 exercised only retry amplification and is not considered a valid combined collapse experiment.

attempt 3 – combined collapse experiment
---------------------------------------

configuration
-------------
Heartbeat interval: 0.1 seconds  
Baseline: 60 seconds  
Intervention: 180 seconds  
Recovery: 120 seconds  

Interference mechanisms:
1. IO bursts via fio:
   - randwrite, 4K blocks
   - iodepth = 16
   - direct IO enabled
   - target file on SD-backed root filesystem (/dev/mmcblk0p2)

2. Retry storm:
   - continuous file creation and retry amplification
   - target directory:
     /home/observer/project/day3/workdir/retry_test

storage layer behavior
----------------------
During intervention:

- SD card utilization (mmcblk0):
  92–96%

- IO tail latency:
  p99 ≈ 97–121 ms  
  max latency up to ≈ 286 ms  

This indicates strong IO queue saturation and heavy tail amplification, consistent with local collapse behavior in the storage layer.

scheduler behavior (heartbeat)
------------------------------
Heartbeat was segmented according to experiment phases:

Baseline:
p95 = 101.519 ms  
p99 = 101.584 ms  

Intervention:
p95 = 101.761 ms  
p99 = 101.934 ms  

Recovery:
p95 = 101.515 ms  
p99 = 101.561 ms  

Delta (Baseline → Intervention):
- p95: +0.242 ms
- p99: +0.350 ms

Delta (Intervention → Recovery):
- p95: −0.246 ms
- p99: −0.373 ms

Recovery returned almost exactly to baseline values.

interpretation
--------------
The IO subsystem entered a collapse-like regime characterized by:

- Near-saturation utilization
- Heavy tail latency amplification
- Increased service time variability

This pressure propagated upward into scheduler timing:

- Heartbeat tail latency increased measurably
- Scheduler timing deformed under load
- The deformation was reversible

This behavior represents a pre-collapse elastic regime:
the system absorbs pressure, idle windows shrink, timing stability degrades, but recovery remains possible.

conclusion
-----------
Under combined IO bursts and retry storm amplification, 
scheduler heartbeat tail latency increased measurably during intervention (p99 +0.35 ms) and returned to baseline during recovery, 
demonstrating reversible pre-collapse deformation of system timing.

research significance
---------------------
This experiment demonstrates that collapse behavior emerges gradually 
through elastic deformation of system timing before any visible service failure occurs. 
Scheduler heartbeat measurements provide an early and sensitive indicator of systemic stress propagation across layers.
