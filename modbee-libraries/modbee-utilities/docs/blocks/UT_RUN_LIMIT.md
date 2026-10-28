# UT_RUN_LIMIT — A run limited by time or volume, or held by a remote signal

Runs a piece of equipment for a set time, until a set volume has gone through, or
for as long as a remote signal is held, and says why the run ended. Typical uses: an
effluent or irrigation run ("50 m³ or 2 h, whichever first"), filling a trough,
flushing a line, running a generator for a set time, a SCADA schedule that holds a
run signal.

`RunCmd` asks the equipment to run: wire it to a [UT_PUMP](UT_PUMP.md)'s `Demand` (or a
motor's `AutoCmd`). The pump block still decides whether it is safe to run; this block
only decides how long.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Start` | BOOL | FALSE | Rising edge: start a run (a local button, a SCADA start pulse). Wire `FALSE` if only `RunHeld` starts it |
| in | `Stop` | BOOL | FALSE | Rising edge: end the run |
| in | `RunHeld` | BOOL | FALSE | A remote run signal: its rising edge starts a run, dropping it ends the run |
| in | `Permit` | BOOL | TRUE | FALSE ends the run (`Stopped: not permitted`) and refuses a start |
| in | `Abort` | BOOL | FALSE | Ends the run and refuses a start, e.g. the sump low level or a pump fault |
| in | `AbortCode` | UT_STOP | UT_STOP_NONE | The `endReason` an `Abort` gives, e.g. `UT_STOP_LOW_LEVEL` (`UT_STOP_NONE` = `UT_STOP_ABORTED`, `Stopped: aborted`) |
| in | `Running` | BOOL | TRUE | The equipment really runs (the pump's `Running`): time only counts while TRUE, so a trip or a restart delay pauses the run. Unwired: always counts |
| in | `Volume` | REAL | 0.0 | A running total, e.g. [UT_TOTALISER](UT_TOTALISER.md)`.Total`: the run's volume is how much it rises |
| in | `CommsOk` | BOOL | TRUE | The remote link is up (e.g. `NOT` [UT_WATCHDOG](UT_WATCHDOG.md)`.CommsFail`) |
| out | `RunCmd` | BOOL | | Run the equipment |
| out | `Active` | BOOL | | A run is in progress |
| out | `Done` | BOOL | | One scan: a run has ended (`endReason` says why) |
| out | `Elapsed` | TIME | | Running time counted in this run (kept after it ends) |
| out | `TimeLeft` | TIME | | byTime: running time still to go |
| out | `Delivered` | REAL | | Volume in this run (kept after it ends) |
| out | `VolumeLeft` | REAL | | byVolume: volume still to go |
| inout | `Data` | UT_RUN_LIMIT_DATA | | The run's settings and status (below) |

## Record `UT_RUN_LIMIT_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `byTime` | BOOL | FALSE | End the run when `Elapsed` reaches `runTime` |
| `byVolume` | BOOL | FALSE | End the run when `Delivered` reaches `targetVolume`. Both: whichever comes first. Neither: it runs until stopped (a remote run) |
| `runTime` | TIME | T#1h | byTime: the running time of a run |
| `targetVolume` | REAL | 0.0 | byVolume: the volume of a run, in the unit of `Volume` |
| `maxPause` | TIME | T#0s | End the run when `Running` stays FALSE this long (`Stopped: paused too long`). 0 = no limit |
| `commsLostStops` | BOOL | TRUE | `CommsOk` FALSE ends a run that needs the remote to end it (`RunHeld`, or no limit), and a `RunHeld` rising edge while the link is down is ignored. A timed or metered run carries on |
| `cmdStart` / `cmdStop` | BOOL | | HMI / SCADA: start / end a run (each acts once, on its rising edge, and is set back to FALSE) |
| `active` | BOOL | | Status: a run is in progress |
| `paused` | BOOL | | Status: active, `Running` FALSE: time is not counting |
| `elapsed` | TIME | | Status: as `Elapsed` |
| `timeLeft` | TIME | | Status: as `TimeLeft` |
| `phaseTime` | TIME | | Status: time since the run started, pauses included (0 when idle) |
| `pauseTime` | TIME | | Status: time in the current pause |
| `delivered` / `volumeLeft` | REAL | | Status: as the pins |
| `remoteHeld` | BOOL | | Status: the run needs the remote to end it (`RunHeld`, or no limit) |
| `endReason` | UT_STOP | | Status: why the last run ended (below; `UT_STOP_NONE` = none since power-up). How far it got is in `elapsed` and `delivered` |
| `lastVolume`, `lastDuration`, `lastEndReason` | REAL, TIME, UT_STOP | | Status: the last run's summary (volume, running time, why it ended), **kept over a power cut** |
| `runs` | UDINT | | Status: runs ended since power-up |
| `configBad` | BOOL | | Status: byTime with `runTime` not above 0, or byVolume with `targetVolume` not above 0 (or not a number): no start, a run in progress ends |
| `statusCode` | UT_STATUS | | Status: what it is doing (below) |
| `faultId` | UT_FAULT | | Status: the setting that is invalid (`configBad`): `UT_F_RUN_TIME` or `UT_F_TARGET_VOLUME`; else `UT_F_NONE` |
| `statusText` | STRING(30) | | Status: the two in words |
| `powerUp` | UT_RUN_POWERUP | UT_RPU_RESUME | What a run does after a power cut: `UT_RPU_RESUME` (0, the default: it carries on with what it had left) · `UT_RPU_RESTART` (a held run starts again from the beginning) · `UT_RPU_NONE` (nothing starts). See [After a power cut](#after-a-power-cut). An unknown value acts as NONE |
| `progressSave` | TIME | T#1m | RESUME: while a run is active its running time and volume are saved at most this often (and at its start and end). At most this much running is done again after a power cut. 0 = saved only at the start and end (a resumed run starts its count again) |

### End reasons
The shared reasons of [conventions](../conventions.md#why-it-stopped). The words carry
no numbers: how far the run got is in `elapsed` and `delivered` (`lastDuration` and
`lastVolume` for the last run), and the limits in `runTime` and `targetVolume`.

| `endReason` | Words ([UT_STOP_TEXT](UT_STOP_TEXT.md)) | Why |
| --- | --- | --- |
| `UT_STOP_OPERATOR` | `Stopped: operator` | `Stop` or `cmdStop` |
| `UT_STOP_DONE` | `Done` | The time or the volume was reached |
| `UT_STOP_ABORTED` | `Stopped: aborted` | `Abort` with `AbortCode` `UT_STOP_NONE` |
| `UT_STOP_COMMS_LOST` | `Stopped: comms lost` | `CommsOk` FALSE on a run the remote must end |
| `UT_STOP_REMOTE_OFF` | `Stopped: remote off` | `RunHeld` dropped |
| `UT_STOP_NOT_PERMITTED` | `Stopped: not permitted` | `Permit` went FALSE |
| `UT_STOP_PAUSED_LONG` | `Stopped: paused too long` | `maxPause` |
| `UT_STOP_SETTING` | `Stopped: setting invalid` | A limit made invalid while running |
| `UT_STOP_POWER_CUT` | `Stopped: power cut` | A run in progress at a power cut that does not carry on (RESTART, NONE). Reported at power-up |
| any | its words | `Abort` with your `AbortCode`, e.g. `UT_STOP_LOW_LEVEL` (`Stopped: low level`) |

### Status
| `statusCode` | Words | When |
| --- | --- | --- |
| `UT_ST_IDLE` | `Idle` | No run; `endReason` says how the last one ended |
| `UT_ST_RUN_TIME` | `Running: by time` | A timed run (`timeLeft`) |
| `UT_ST_RUN_VOLUME` | `Running: by volume` | A metered run, or one with both limits (`delivered`, `volumeLeft`) |
| `UT_ST_RUN_REMOTE` | `Running: remote held` | A run held by `RunHeld` (no limit) |
| `UT_ST_RUN_UNTIL_STOP` | `Running: until stopped` | A run with no limit |
| `UT_ST_RESUMED` | `Running: resumed` | The run carried on after a power cut (RESUME), in place of the statuses above |
| `UT_ST_RESTARTED` | `Running: restarted` | The run started again after a power cut (RESTART), in place of the statuses above |
| `UT_ST_NOT_PERMITTED` | `Not permitted` | `RunHeld` on, `Permit` FALSE |
| `UT_ST_ABORT` | `Blocked: abort` | `RunHeld` on, `Abort` on |
| `UT_ST_WAIT_POWERUP` | `Waiting: start again` | NONE: a `RunHeld` that would have run is on at power-up; it must go off and on again |
| `UT_ST_PAUSED` | `Paused: not running` | Active, `Running` FALSE (`pauseTime`) |
| `UT_ST_CONFIG` | `Config: run time` · `Config: target volume` | byTime with `runTime` not above 0, or byVolume with `targetVolume` not above 0: no run until fixed |

## How it works
- A run starts on a rising edge of `Start`, `cmdStart` or `RunHeld`, if `Permit` is
  TRUE, `Abort` is FALSE and the settings are valid. A start while a run is active is
  ignored; `Stop` wins over a start in the same scan. A held `Start` acts once.
- Time counts only while `Running` is TRUE: a pump trip or restart delay pauses the
  run, and it carries on when the pump runs again (`maxPause` can end it).
- The volume is the rise of `Volume` since the start. A total that goes down (reset)
  or reads not-a-number is handled: the run carries on from the new value, never
  counting backwards. A total that is not a number when the run starts is not
  counted from 0: the run counts from the first valid reading.
- The first reason found ends the run: Stop, Abort, Permit, RunHeld dropping, lost
  comms, an invalid setting, the limit, `maxPause`.

## After a power cut
An irrigation run on a sports field or a property often has no operator: when the
power comes back (or the PLC is stopped and started) the run should carry on, as a
commercial irrigation controller does. `powerUp` chooses:

| `powerUp` | A run in progress at the cut | `RunHeld` on at power-up, no run in progress |
| --- | --- | --- |
| `UT_RPU_RESUME` (default) | **Carries on** with the time and volume it had left (`UT_ST_RESUMED`). A run whose `RunHeld` was on at the cut and is off now ends: `UT_STOP_REMOTE_OFF`. A run started by `Start` / `cmdStart` just carries on | Starts a fresh run |
| `UT_RPU_RESTART` | Nothing is kept. A run started by `RunHeld`, with `RunHeld` still on, starts again from the beginning (`UT_ST_RESTARTED`); the run cut off is reported as `UT_STOP_POWER_CUT`. A run started by `Start` / `cmdStart` ends (`UT_STOP_POWER_CUT`) | Starts a fresh run |
| `UT_RPU_NONE` | Ends (`UT_STOP_POWER_CUT`) | Nothing starts: `UT_ST_WAIT_POWERUP` until `RunHeld` goes off and on again |

- A `RunHeld` that was **already on at the cut and had been dealt with** (its run
  done, or the start refused) does not start another run after the power cut, in any
  mode: as without a power cut, it must go off and on again. Only a `RunHeld` that
  came on while the power was off counts as a new request.
- A run that carries on keeps its running time and volume: time spent before the cut
  is not counted again, and the run never goes past `runTime` or `targetVolume` (a
  run already at its limit ends at once, `Done`). The volume carries on from where
  the `Volume` total reads at power-up, so a total that came back lower (a totaliser
  saved every 12 h) is not counted backwards. A `Volume` meter that runs later in
  the scan (in a later program) has no total yet on the first scan: the run waits
  for its first good total and counts from there, never the meter's whole total.
- The resumed run starts from its **last save**: the progress is saved when the run
  starts and ends, and every `progressSave` (default 1 min) while it is active, never
  every scan (flash wear: a few hundred saves on a day of irrigation, none when idle).
  So up to `progressSave` of running can be given again after a cut.
- A run ended at power-up (`UT_STOP_REMOTE_OFF`, `UT_STOP_POWER_CUT`) is a run end:
  `Done` is on for that scan, `runs` counts it, and it becomes the last-run summary.
- `Permit`, `Abort`, `CommsOk` and the limits are checked from the first scan: a run
  that carries on with `Permit` FALSE ends at once, as it would without a power cut.
- **Kept over a power cut** (inside the block): the last run's summary, saved once
  at each run end; and the progress of a run in progress (whether one is, whether
  `RunHeld` started it, whether `RunHeld` is on, its running time and volume), saved
  as above and when `RunHeld` changes.

## Using it
```iecst
IrrRun(Start := StartPB, Stop := StopPB, RunHeld := ScadaRun, Abort := SumpLow,
       AbortCode := UT_STOP_LOW_LEVEL, Running := P1.Running, Volume := FlowTot.Total, CommsOk := NOT ScadaWd.CommsFail,
       Data := IrrRunCfg);
P1(Demand := IrrRun.RunCmd, Running := M1.Running, MotorReady := M1.Ready, MotorAuto := M1.Auto,
   Data := P1Data);
```
With `IrrRunCfg.byTime := TRUE`, `byVolume := TRUE`, `runTime := T#2h`,
`targetVolume := 50.0`, the run ends at 50 m³ or 2 h of pumping, whichever comes
first (`endReason` `UT_STOP_DONE`), or when the sump runs low (`UT_STOP_LOW_LEVEL`,
with `delivered` showing how much went, e.g. 32.4 m³).
