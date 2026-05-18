Day 1 – Controlled Drift Without Collapse

Objective
---------
The objective of Day 1 was to validate that the system observation lab can detect
subtle, reversible behavioral drift under controlled load, without triggering
thermal throttling, power events, or system instability.

This day intentionally avoids collapse or failure. The goal is observability,
not stress.

Environment
-----------
Platform: Raspberry Pi 5
OS: Linux (headless, SSH only)
Cooling: Active fan, auto mode enabled
Power: Stable supply, no undervoltage events observed

All tools used are open source and Linux native. No containers, no orchestration
layers, and no external monitoring frameworks were used.

Methodology
-----------
Baseline Reference:
A clean baseline was established prior to Day 1, defining the system’s idle
scheduling rhythm using a heartbeat logger (periodic wakeups at ~100 ms
intervals).

Baseline characteristics:
- Stable fan behavior in auto mode
- No throttling events
- Consistent scheduler wake intervals

Day 1 measurements are interpreted strictly relative to this baseline.

Drift Injection:
A controlled IO workload was introduced using fio with deliberately conservative
parameters:

- IO pattern: random write
- Block size: small (4K)
- Concurrency: single job
- Queue depth: 1
- Duration: 600 seconds

This configuration was chosen to introduce persistent but non-catastrophic
contention, primarily affecting scheduler timing rather than CPU saturation or
thermal runaway.

Measurement
-----------
Two independent signals were recorded throughout the experiment:

1. Thermal and fan telemetry
   - Temperature
   - Throttling state
   - Fan mode (pwm_en)
   - Fan RPM

2. Scheduler heartbeat
   - Periodic wakeup intervals (dt_ns)
   - Captured continuously before, during, and after drift

The run was divided into three windows:
- Pre-drift: 120 seconds
- Drift: 600 seconds
- Post-drift: 120 seconds

Results
-------
Thermal and Power Behavior:
- Fan remained in auto mode for the entire run (pwm_en=2)
- No throttling events detected (throttled=0x0 throughout)
- Temperature range: 45.0°C to 60.9°C
- Average temperature: 54.7°C
- Fan RPM responded smoothly to temperature changes

Conclusion:
Thermal and power subsystems did not constrain system behavior. Observed drift is
not attributable to throttling or cooling artifacts.

Scheduler Heartbeat Analysis:
Average wake interval:
- Pre-drift: 101.558 ms
- Drift: 102.057 ms
- Post-drift: 101.536 ms

This represents an average increase of approximately 0.5 ms (~0.49%) during
drift, followed by recovery after load removal.

Distribution behavior:
Higher percentile analysis revealed additional structure:

- During drift:
  - Increased p95 and p99 latency
  - Wider distribution spread
  - Higher maximum wake intervals

- Post-drift:
  - Variance collapsed back toward baseline
  - Average and percentiles returned to pre-drift values

This indicates reversible timing degradation rather than permanent system impact.

Interpretation
--------------
Day 1 demonstrates that:
- The system observation pipeline is sensitive enough to detect sub-millisecond
  behavioral changes
- Controlled IO pressure alone can measurably affect scheduler timing
- The system recovers promptly once pressure is removed
- Drift can be induced without crossing into thermal or power-induced collapse

This validates both the measurement methodology and the experimental discipline
of the lab.

Limitations
-----------
- Drift magnitude is intentionally modest
- Only a single pressure source (IO contention) was introduced
- Results are specific to this hardware and configuration

These limitations are deliberate and will be addressed incrementally in
subsequent days.

Next Step
---------
Day 2 will increase drift strength slightly by modifying one load parameter only,
while preserving all other conditions. The objective is to amplify observable
drift without introducing throttling or instability.

Day 1 Status
------------
Completed successfully.
