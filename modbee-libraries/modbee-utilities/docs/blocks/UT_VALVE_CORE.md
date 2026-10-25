# UT_VALVE_CORE — What every valve block shares

The record, safe-position decision, every protection, fault codes, the status and
the retained stroke count of the valve blocks. Each valve block is this core plus
its own way of moving the valve: the core decides **whether** the valve follows
its request or goes to the safe position; the valve block decides **how** (which
outputs, for how long) and reports the fault conditions it sees through the
cause pins. Use it directly only to build a new kind of valve block.

The core is two functions, not a function block:
- `UT_VALVE_RESET`: the reset request and the retry window of this scan. Call it first.
- `UT_VALVE_CORE`: everything else.

A function keeps no instance of its own, so the valve record is never copied. The
valve block keeps the core's working state in one `UT_VALVE_ST` and passes it, with
the record, to both functions every scan. The valve block also runs its own
[UT_MODE_SELECT](UT_MODE_SELECT.md) and passes the mode in, and keeps the retained
stroke count (`Saved`).

## Pins

**UT_VALVE_RESET**
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Reset` | BOOL | FALSE | The valve block's `Reset` pin |
| in | `EnteredOff` | BOOL | FALSE | `UT_MODE_SELECT.EnteredOff` (for `resetByOff`) |
| inout | `Data` | UT_VALVE_DATA | | The valve record ([UT_VALVE](UT_VALVE.md#record-ut_valve_data-shared-by-every-ut_valve-block)). `cmdReset` is read and cleared |
| inout | `St` | UT_VALVE_ST | | The core's state |
| returns | | BOOL | | The reset request: a rising edge of `Reset` or `cmdReset`, or switching to Off with `resetByOff`. Also in `St.resetReq`; the retry window in use is in `St.rw` (`retryWindow`, or T#1h when it is negative), for the valve block's own protections |

**UT_VALVE_CORE**
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Mode` | UT_MODE | UT_MODE_OFF | `UT_MODE_SELECT.Mode` |
| in | `ModeChanged` | BOOL | FALSE | `UT_MODE_SELECT.Changed` |
| in | `AutoChanged` | BOOL | FALSE | The Auto request changed this scan (ends the wait for a new command after a MANUAL reset). TRUE for analog requests |
| in | `Interlock` | BOOL | TRUE | As [UT_VALVE](UT_VALVE.md): FALSE sends the valve to its safe position in every mode |
| in | `DriveFault` | BOOL | FALSE | As [UT_VALVE](UT_VALVE.md): the actuator's fault relay |
| in | `OpenTimeout`, `CloseTimeout`, `BothLimits`, `PositionLost`, `NoMovement` | BOOL | FALSE | The fault conditions, worked out by the valve block |
| in | `StrokeDone` | BOOL | FALSE | One scan: a move has completed (counted) |
| in | `VarStatus` | UT_STATUS | UT_ST_IDLE | Where the valve is or what it waits for (`UT_ST_IDLE` = nothing; list below) |
| in | `VarTime` | TIME | T#0s | Time left for `VarStatus` (shown in `Data.timeLeft`) |
| in | `Permissive` | BOOL | TRUE | As [UT_VALVE](UT_VALVE.md) (`Data.notPermitted`; the valve block holds back a move away from safe) |
| in | `LocalOpen`, `LocalClose`, `LocalStop` | BOOL | FALSE | Local pushbuttons (Hand), turned into the `req…` results |
| in | `Away` | BOOL | FALSE | The valve block: at the end of its last scan the valve was asked away from its safe position (for `stopReason`) |
| in | `CfgFault` | UT_FAULT | UT_F_NONE | The valve block's setting that keeps the valve still (`UT_F_NONE` = none): every output off, a fault, `faultCode` bit 8 |
| in | `CfgWarn` | UT_FAULT | UT_F_NONE | The valve block's setting replaced by a safe value (`UT_F_NONE` = none): a warning, bit 8 |
| in | `ExtTrip` | DWORD | 0 | The valve block's own protections (position deviation, position feedback): the `faultCode` bits of those tripping now |
| in | `ExtWarn` | DWORD | 0 | The bits of those warning now |
| in | `ExtTripped` | DWORD | 0 | The bits of those latched (their `tripped`) |
| in | `ExtResetDone` | BOOL | FALSE | One of them was reset this scan |
| in | `ExtRst` | UT_RESET_MODE | UT_RST_AUTO | The first one tripping: its `reset` mode |
| in | `ExtRetries` | INT | 0 | Its `retries` |
| in | `ExtMaxRetries` | INT | 0 | Its `maxRetries` |
| in | `ExtTimeLeft` | TIME | T#0s | Its `timeLeft` |
| inout | `Data` | UT_VALVE_DATA | | The valve record |
| inout | `St` | UT_VALVE_ST | | The core's state |
| inout | `Saved` | UDINT | | The valve block's retained stroke count (copied every `saveEvery`) |
| returns | | BOOL | | Go to the safe position (`St.goSafe`) |

The core's results are in `St` after the call, for the valve block to read:

| Field | Type | Meaning |
| --- | --- | --- |
| `goSafe` | BOOL | Go to the safe position: Off, interlock, a trip, or waiting for a new command after a reset |
| `fault`, `warning` | BOOL | As UT_VALVE (never in OOS, except a bad setting) |
| `cfgBad` | BOOL | A setting is invalid and the valve must not be driven: the valve block turns every output off |
| `hand`, `auto`, `oos` | BOOL | The mode (OOS: every output off) |
| `handSafe` | BOOL | Hand: put the Hand request back to the safe position (interlocked, or just reset) |
| `enteredHand` | BOOL | One scan: just changed to Hand (take the current request: bumpless) |
| `tripCleared` | BOOL | One scan: the last trip has just cleared (try the move again) |
| `driveTrip` | BOOL | The `drive` protection is holding the valve (motorised valves stop driving) |
| `reqOpen`, `reqClose` | BOOL | One scan: a Hand open / close (`cmdOpen` / `cmdClose` or the local button, each on its rising edge; dropped in a scan with a stop) |
| `reqStop` | BOOL | A Hand stop: `cmdStop` on its rising edge, or `LocalStop` while held |
| `resetReq`, `rw` | | `UT_VALVE_RESET`'s results (above) |

The other fields of `UT_VALVE_ST` are the core's own memory: leave them alone, and
don't show them on an HMI. The variants' own commands (`cmdPos` on UT_VALVE_3POS,
`cmdHome` on UT_VALVE_FLOAT) are read by the valve block from its own record.

## Status
The core works out `statusCode`, `faultId` and `statusText` for every valve block
(statuses in each block's doc, e.g. [UT_VALVE](UT_VALVE.md#status)): configuration,
faults, out of service, the interlock and the wait for a new Auto command are its
own; the valve block says where the valve is through `VarStatus` (worked out from
its last scan, so it shows one scan late). It also reads and clears `cmdOpen`,
`cmdClose` and `cmdStop` (each on its rising edge; a command left in the record at
power-up never acts), keeps `stopReason`, the last trip and `trips`, and sets
`timeLeft` to the time the status shows.

| `VarStatus` | Words | Kind |
| --- | --- | --- |
| `UT_ST_OPENING` | `Opening` | normal |
| `UT_ST_CLOSING` | `Closing` | normal |
| `UT_ST_OPEN` | `Open` | normal |
| `UT_ST_CLOSED` | `Closed` | normal |
| `UT_ST_MOVING` | `Moving` | normal |
| `UT_ST_HOMING` | `Homing` | normal |
| `UT_ST_AT_POSITION` | `At position` | normal |
| `UT_ST_BETWEEN` | `Stopped between positions` | normal |
| `UT_ST_POS_UNKNOWN` | `Position unknown` | normal |
| `UT_ST_DEAD_TIME` | `Waiting: dead time` | held |
| `UT_ST_NOT_HOMED` | `Hand: not homed` | held |
| `UT_ST_MOVE_TIMEOUT` | `Waiting: new request` | held |
| `UT_ST_NOT_PERMITTED` | `Not permitted` | held |

The words hold no numbers: the position or target is in the record (`position`,
and the variant's `targetPos`, `actualPos` or `demand`), and the time left of a
move or a pause in `timeLeft`.

The settings are named with `UT_FAULT` members. The core's own are
`UT_F_SAVE_EVERY`, `UT_F_RETRY_WINDOW` and `UT_F_MODE_SOURCE` (warnings). The valve
blocks' are `UT_F_VALVE_TYPE`, `UT_F_TRAVEL_TIME`, `UT_F_REVERSAL_DELAY`,
`UT_F_PULSE_TIME`, `UT_F_SAFE_POSITION`, `UT_F_THREE_POS_TYPE`, `UT_F_MID_TIME`,
`UT_F_OUTPUT_MIN_MAX`, `UT_F_RAMP_RATE`, `UT_F_SHUTOFF`, `UT_F_FAIL_POSITION`,
`UT_F_OPEN_THRESHOLD`, `UT_F_RAW_MIN_MAX`, `UT_F_DEADBAND`, `UT_F_STROKE_TIME`,
`UT_F_MIN_PULSE` and `UT_F_RATE_UNIT`. The full list is in
[conventions](../conventions.md#ut_fault-which-fault-warning-or-setting-faultid).

## Retained
The mode (in [UT_MODE_SELECT](UT_MODE_SELECT.md)) and a snapshot of `strokes`,
copied every `saveEvery` (T#0s = not kept) into the valve block's `Saved`.
