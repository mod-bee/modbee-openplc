# UT_MOTOR_CORE — What every motor block shares

The record, run request, interlock and permissive, every protection, the restart
rules, state, fault codes and status of the motor blocks. UT_MOTOR is this core
and one contactor; the reversing, star-delta, two-speed and VSD blocks are this
core and their own output sequence. Use it directly only to build a new kind of
motor block.

The core is two functions, not a function block:
- `UT_MOTOR_RESET`: the reset request of this scan. Call it first.
- `UT_MOTOR_CORE`: everything else.

A function keeps no instance of its own, so the motor record is never copied. The
motor block keeps the core's working state in one `UT_MOTOR_ST` and passes it, with
the record, to both functions every scan. The motor block also runs its own
[UT_MODE_SELECT](UT_MODE_SELECT.md) and passes the mode in.

## Pins

**UT_MOTOR_RESET**
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Reset` | BOOL | FALSE | The motor block's `Reset` pin |
| in | `EnteredOff` | BOOL | FALSE | `UT_MODE_SELECT.EnteredOff` (for `resetByOff`) |
| inout | `Data` | UT_MOTOR_DATA | | The motor record ([UT_MOTOR](UT_MOTOR.md#record-ut_motor_data-shared-by-every-ut_motor-block)). `cmdReset` is read and cleared |
| inout | `St` | UT_MOTOR_ST | | The core's state |
| returns | | BOOL | | The reset request: a rising edge of `Reset` or `cmdReset`, or switching to Off with `resetByOff`. Also in `St.resetReq`, for the variant's own protections |

**UT_MOTOR_CORE**
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Mode` | UT_MODE | UT_MODE_OFF | `UT_MODE_SELECT.Mode` |
| in | `ModeChanged` | BOOL | FALSE | `UT_MODE_SELECT.Changed` |
| in | `AutoCmd`, `Overload`, `Thermistor`, `DriveFault`, `Current`, `Interlock`, `Permissive`, `LocalStart`, `LocalStop` | | | As [UT_MOTOR](UT_MOTOR.md) (TRUE = active; NC contacts through NOT at the pin). `Interlock` and `Permissive` default to TRUE, the others to FALSE / 0.0 |
| in | `Feedback` | BOOL | FALSE | The motor is running (whichever contactor is on) |
| in | `StartBlock` | BOOL | FALSE | The variant cannot start now (drive not ready, a dead time) |
| in | `CfgWarn` | BOOL | FALSE | The variant has an invalid setting and uses a safe fallback: a warning (`wrnConfig`) |
| in | `CfgFault` | BOOL | FALSE | The variant has an invalid setting that makes running unsafe: kept off with a fault (`wrnConfig`) |
| in | `CfgId` | UT_FAULT | UT_F_NONE | Which setting `CfgWarn` / `CfgFault` is about (the `UT_F_` setting names) |
| in | `VarStatus` | UT_STATUS | UT_ST_IDLE | What the variant's sequence is doing or waiting for (`UT_ST_IDLE` = nothing; list below) |
| in | `VarTime` | TIME | T#0s | Time left for `VarStatus` (shown in `Data.timeLeft`) |
| in | `ExtTrip` | DWORD | 0 | The variant's own protections: the `faultCode` bits of those tripping now |
| in | `ExtWarn` | DWORD | 0 | The bits of those warning now |
| in | `ExtTripped` | DWORD | 0 | The bits of those latched (their `tripped`) |
| in | `ExtCfgId` | UT_FAULT | UT_F_NONE | The first of them with a bad setting (`UT_F_NONE` = none) |
| in | `ExtResetDone` | BOOL | FALSE | One of them was reset this scan |
| in | `ExtRst` | UT_RESET_MODE | UT_RST_AUTO | The first one tripping: its `reset` mode |
| in | `ExtRetries` | INT | 0 | Its `retries` |
| in | `ExtMaxRetries` | INT | 0 | Its `maxRetries` |
| in | `ExtTimeLeft` | TIME | T#0s | Its `timeLeft` |
| inout | `Data` | UT_MOTOR_DATA | | The motor record |
| inout | `St` | UT_MOTOR_ST | | The core's state |
| returns | | BOOL | | The motor should run (`St.runReq`); the variant turns this into contactors |

The core's results are in `St` after the call, for the variant to read:

| Field | Type | Meaning |
| --- | --- | --- |
| `runReq` | BOOL | The motor should run |
| `running` | BOOL | Run confirmed by feedback |
| `fault`, `warning`, `ready`, `auto`, `state` | | As UT_MOTOR's outputs |
| `hand` | BOOL | In Hand (the variant reads its Hand direction or speed commands) |
| `resetDone` | BOOL | One scan: a fault was reset (the VSD pulses `DriveReset`) |
| `resetReq` | BOOL | One scan: a reset was asked for, whether or not anything was reset (the VSD resets the drive on it) |

The other fields of `UT_MOTOR_ST` are the core's own memory: leave them alone, and
don't show them on an HMI.

## Status
The core works out `statusCode`, `faultId` and `statusText` for every motor block
([statuses](UT_MOTOR.md#status)). The variant only says what its sequence is doing
through `VarStatus` (with `VarTime`), names a bad setting through `CfgId`, and hands
its own protections over as one summary through the `Ext…` pins. The core ranks the
variant's status with its own: a normal status shows while the motor runs; a
waiting status shows while it is asked to run; "drive not ready" shows whenever it is
stopped. A `StartBlock` with no status shows `UT_ST_START_BLOCKED`, so a start held
back by a variant is never unexplained. A variant works out its status before
calling the core, from its last scan, so its sequence states show one scan late.
The core also reads and clears `cmdStart` and `cmdStop` (each on its rising edge; a
stop read TRUE blocks every start), keeps `stopReason`, the last trip and `trips`,
the Hand run limit, and sets `timeLeft` to the time the status shows.

| `VarStatus` | Words | Kind | Used by |
| --- | --- | --- | --- |
| `UT_ST_STAR` | `Starting: star` | normal | SD |
| `UT_ST_LOW_FIRST` | `Starting: low speed first` | normal | 2SPD |
| `UT_ST_SKIP_EDGE` | `Running: at skip band edge` | normal | VSD |
| `UT_ST_DEAD_TIME` | `Waiting: dead time` | held | REV (reversing), 2SPD (speed change), SD (star-delta transition) |
| `UT_ST_DRIVE_NOT_READY` | `Blocked: drive not ready` | held | VSD |
| `UT_ST_WAIT_MAIN_FB` | `Waiting: main contactor` | held | SD |
| `UT_ST_WAIT_OPEN` | `Waiting: contactor to open` | held | REV, SD, 2SPD |

`CfgId`, `ExtCfgId` and the core's own settings name the setting with a `UT_FAULT`
member: the core's are `UT_F_FLC`, `UT_F_CURRENT_NEEDS_FLC`, `UT_F_START_MASK`,
`UT_F_RESTART_DELAY`, `UT_F_HAND_MAX_RUN`, or a protection's name (`UT_F_OVERLOAD`
… `UT_F_DRIVE`) for its `delay`, `recover` or `maxRetries`. The variants' are
`UT_F_REVERSAL_DELAY`, `UT_F_TRANSITION_TIME`, `UT_F_STAR_CURRENT`,
`UT_F_STAR_NEEDS_FLC`, `UT_F_STAR_TIME`, `UT_F_SPEED_CHANGE`, `UT_F_LOW_START_TIME`,
`UT_F_MIN_MAX_SPEED`, `UT_F_RAW_MIN_MAX`, `UT_F_ACCEL_RATE`, `UT_F_SKIP_BAND`,
`UT_F_HAND_SPEED`, `UT_F_RESET_PULSE`, `UT_F_RATE_UNIT`, `UT_F_RATED_HZ_RPM`, and
`UT_F_SPEED_DEV`, `UT_F_CHANGEOVER` or `UT_F_DRIVE_NOT_READY` for their own
protections. The full list is in [conventions](../conventions.md#ut_fault-which-fault-warning-or-setting-faultid).

## Using it
The pattern every motor block follows (here a block with one contactor):

```iecst
modeSel(Source := Data.modeSource, SwHand := SwHand, SwAuto := SwAuto,
        PowerUp := Data.powerUp, CmdMode := Data.cmdMode);
x1 := UT_MOTOR_RESET(Reset := Reset, EnteredOff := modeSel.EnteredOff, Data := Data, St := cs);
(* the variant's own protections here, with UT_PROT_RUN and ResetReq := cs.resetReq *)
x2 := UT_MOTOR_CORE(Mode := modeSel.Mode, ModeChanged := modeSel.Changed, AutoCmd := AutoCmd,
                    Feedback := Feedback, Overload := Overload, Interlock := Interlock,
                    Permissive := Permissive, Data := Data, St := cs);
Run := cs.runReq;
```
