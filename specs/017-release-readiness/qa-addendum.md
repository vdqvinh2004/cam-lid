# QA addendum: release readiness (spec 017)

## Measurement gate (User Story 2, T002)

Measured 2026-11-05 on Mac17,3 (10 cores), recorded 2026-11-06.

Method: `SensorTimingGateTests.lidReadsUnderFullLoad` (set `CAMLID_SENSOR_GATE_OUT` to a CSV path). One CPU-bound
process per core runs for 180 seconds while the lid is sampled on two queues, utility and userInitiated. For each sample:
(a) the time of the sensor call alone, (b) the time from sample start to finish.

| Queue | Samples | Lid state | (a) max | (a) p99 | (a) median | Calls at or over 0.2 s | (b) max |
|---|---|---|---|---|---|---|---|
| utility | 175 | open (all) | 0.0304 s | 0.0112 s | 0.00046 s | 0 | 0.0304 s |
| userInitiated | 175 | open (all) | 0.0004 s | 0.0001 s | 0.000028 s | 0 | 0.0004 s |

**Decision (spec rule):** every call stayed under 0.2 s, so the cause is scheduling delay. The fix is to time only the
call and sample on a higher quality-of-service queue, with **no tolerance window**. The code follows that: sampling runs on
the userInitiated queue, and `LiveSensors.swift` has no window.

**Not part of this gate:** acceptance 1 (three minutes at 100 % CPU with a session running, no `lidUnknown` stop) is task
T024, a live run of 190 seconds with no stop. Acceptance 2 (a stalled source stops the session within the limit) is
covered by `SensorStallBudgetTests` and was not re-run here.
