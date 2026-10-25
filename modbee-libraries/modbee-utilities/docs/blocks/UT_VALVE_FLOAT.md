# UT_VALVE_FLOAT — Floating (3-point) valve or damper

Positions an actuator that only has **raise** and **lower** contacts (no positioner),
common on HVAC mixing valves, irrigation and motorised dampers. It estimates the
position from the run time. Position feedback is used if fitted, and the estimate
re-syncs at the ends. Mode, fail action and protections work as
[UT_VALVE](UT_VALVE.md) ([UT_VALVE_CORE](UT_VALVE_CORE.md)).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `AutoSp` | REAL | 0.0 | Position request in Auto, %. NaN / infinite is ignored |
| in | `PosFb` | REAL | -1.0 | Position feedback % (exactly −1 = not fitted, estimate used) |
| in | `OpenLs` / `ClosedLs` | BOOL | FALSE | Optional end switches (exact re-sync, the move stops on them) |
| in | `Interlock` | BOOL | TRUE | FALSE → `failPosition` |
| in | `DriveFault`, `SwHand`, `SwAuto`, `Reset` | | | As UT_VALVE |
| in | `Permissive` | BOOL | TRUE | FALSE: the valve moves only toward `failPosition` (a move away from it waits; a Hand one is dropped); it never forces it |
| in | `LocalOpen` / `LocalClose` / `LocalStop` | BOOL | FALSE | Local pushbuttons (Hand, rising edge): `handSp` 100 %, 0 %, or stop where it is (held: keeps stopping) |
| out | `Raise` | BOOL | | Open/raise contact |
| out | `Lower` | BOOL | | Close/lower contact (never with `Raise`) |
| out | `Position` | REAL | | Measured or estimated %; −1 = unknown (not homed, no feedback) |
| out | `Fault` | BOOL | | A trip is holding it at the fail action |
| out | `State` | UT_STATE | | OFF closed, ON open, STARTING raising, STOPPING lowering, INVALID stopped with the position unknown |
| inout | `Data` | UT_VALVE_DATA | | Shared valve record ([UT_VALVE](UT_VALVE.md#record-ut_valve_data-shared-by-every-ut_valve-block)) |
| inout | `Floating` | UT_VALVE_FLOAT_DATA | | The floating settings, protections, command and status (below) |

## Record `UT_VALVE_FLOAT_DATA` (pin `Floating`)
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `strokeTime` | TIME | T#60s | Full stroke time (from the actuator data plate) |
| `minPulse` | TIME | T#500ms | Shortest move: a smaller correction is not made, and a move lasts at least this (except Off, an interlock or a trip: a move away from the fail position stops at once) |
| `deadband` | REAL | 1.0 | % error ignored (never less than the travel in one scan, so it can't hunt) |
| `overTravel` | TIME | T#5s | Extra drive at 0 %/100 % to re-sync the estimate |
| `homeOnStart` | BOOL | TRUE | Drive closed at power-up (a full stroke and the over-travel) to sync, in Off and Auto. In Hand it stays put (position unknown) until Auto or `cmdHome` |
| `failPosition` | REAL | 0.0 | Position on interlock / fault / Off (−1, any value below 0 or not a number = stay where it is) |
| `openThreshold` / `closedThreshold` | REAL | 98.0 / 2.0 | `isOpen` / `isClosed`, OFF state; with feedback, the end of an end move |
| `handSp` | REAL | 0.0 | Hand position; tracks the Auto request. Hand `cmdOpen` / `cmdClose` (in `Data`) set it to 100 / 0 %, `cmdStop` to the position now |
| `deviation` | UT_LEVEL | WARN · 10 s · AUTO · sp 5 | With feedback: stopped more than `sp` % from the request (`faultCode` bit 6) |
| `posFeedback` | UT_PROTECTION | TRIP · 500 ms · AUTO | Feedback NaN, infinite or outside −5…105 % (falls back to the estimate; `faultCode` bit 7) |
| `cmdHome` | BOOL | FALSE | HMI: home now (any mode but OOS; not with good feedback). Cleared by the block |
| `notHomed` | BOOL | | Status: not homed and no feedback: the position is unknown (`Position` −1) |
| `demand` | REAL | | Status: the position asked for, % |

In the valve record `Data`: `reversalDelay` (T#500ms, the pause before changing
direction), `position`, the modes, the other protections, the HMI commands and the
status.

## How it works
- The estimate adds or takes away 100 % × run time / `strokeTime` while `Raise` /
  `Lower` are on. Good feedback replaces it; an end switch sets it to 0 / 100 %.
- A request of 0 % (or 100 %) drives to the end and on for `overTravel`, then
  stops and doesn't drive again until the request leaves the end.
- A move never lasts longer than `strokeTime` + `overTravel`. If it runs out of
  time (stuck, or a move to 0 % / 100 % whose end never comes, e.g. frozen
  feedback), it isn't repeated until the request changes; with feedback the
  deviation warning shows it.
- Power-up: with `homeOnStart` it homes first in Off and Auto. In Hand it does
  not move: `Position` is −1, `notHomed` TRUE, State INVALID, and a new `handSp` is
  not acted on, until it goes to Auto (it homes, then follows `AutoSp`), Off or an
  interlock (it homes on the way to the fail position), or the operator sends
  `cmdHome` (it homes and stays closed, `handSp` 0). With feedback it starts where
  the feedback says (in Hand it stays there). Without either, in Hand it does not
  move until the operator changes `handSp`.
- `cmdHome` at any time re-homes it (a full stroke and the over-travel, then on to
  the request), with the reversal pause if it was raising.
- `travelElapsed` is how long the move under way has driven; `timeLeft` its time
  left at the stroke speed (a homing move: the full stroke and over-travel left).
- `cmdHome` acts once, on its rising edge: one held TRUE homes once.
- OOS and a drive trip: both contacts off.

## Status
`statusCode`, `faultId` and `statusText` say the **one main thing** the valve is
doing, or what holds it back, so a technician can see on the HMI why it is not where
it was asked to be. The most important reason wins: configuration > fault > held /
waiting > warning > position > Off. The words hold no numbers: the target is in `demand` and the position in `position`. The time left
(travel, a pause, a fault's recover / retry wait) is in `timeLeft`. The text is
rebuilt only when the status or the fault changes. Where the valve is (the rows
marked *(this block)*) comes from the block's last scan, so it shows one scan after
it changes. The numbers are in [conventions](../conventions.md#the-numbers).

| `statusCode` | Words | When |
| --- | --- | --- |
| `UT_ST_OFF` | `Off` | Mode Off (it goes to its safe position) |
| `UT_ST_OPEN` | `Open` | *(this block)* At or above `openThreshold` |
| `UT_ST_CLOSED` | `Closed` | *(this block)* At or below `closedThreshold` |
| `UT_ST_MOVING` | `Moving` | *(this block)* Going to `demand`; `timeLeft` is the move's time left at the stroke speed |
| `UT_ST_HOMING` | `Homing` | *(this block)* Driving closed for a full stroke and the over-travel to find its position |
| `UT_ST_AT_POSITION` | `At position` | *(this block)* Between the thresholds, at `demand` |
| `UT_ST_POS_UNKNOWN` | `Position unknown` | *(this block)* Not homed and no feedback |
| `UT_ST_INTERLOCK` | `Blocked: interlock` | `Interlock` FALSE: at its safe position (every mode but OOS) |
| `UT_ST_OOS` | `Out of service` |  |
| `UT_ST_NOT_PERMITTED` | `Not permitted` | *(this block)* `Permissive` FALSE holds back a move away from the safe position |
| `UT_ST_DEAD_TIME` | `Waiting: dead time` | *(this block)* The pause before driving the other way (`timeLeft`) |
| `UT_ST_NOT_HOMED` | `Hand: not homed` | *(this block)* Hand and the position is unknown (not homed, no feedback): it stays put until `cmdHome` or Auto |
| `UT_ST_MOVE_TIMEOUT` | `Waiting: new request` | *(this block)* A move ran for a full stroke and the over-travel without getting there (stuck, or frozen feedback): it waits for a new request |
| `UT_ST_WARNING` | `Warning: <fault>` | A protection set to WARN is raised |
| `UT_ST_WARN_SETTING` | `Setting: <setting>` | An invalid setting, a safe value in use (settings below) |
| `UT_ST_FAULT` | `Fault: <fault>` | Tripped, AUTO: clears by itself once the cause has gone for `recover` (`timeLeft` while it counts) |
| `UT_ST_FAULT_RETRY` | `Retrying: <fault>` | Tripped, RETRY: the protection's `retries` of `maxRetries` (`timeLeft` while it counts) |
| `UT_ST_FAULT_RESET` | `Latched: <fault>` | Tripped, MANUAL: a reset (pin, `cmdReset`, Off) once the cause has gone |
| `UT_ST_FAULT_LOCKED` | `Locked: <fault>` | RETRY used up: now as MANUAL |
| `UT_ST_CONFIG` | `Config: <setting>` | An invalid setting: every output off until it is fixed |

`<fault>` is `faultId`, one of: `UT_F_BOTH_LIMITS` (both limits) · `UT_F_ACTUATOR` (actuator fault) · `UT_F_POS_DEVIATION` (pos. deviation) · `UT_F_POS_FEEDBACK` (position signal).
`<setting>` with `UT_ST_WARN_SETTING` is one of: `UT_F_SAVE_EVERY` (save every) · `UT_F_RETRY_WINDOW` (retry window) · `UT_F_MODE_SOURCE` (mode source) · `UT_F_DEADBAND` (deadband) · `UT_F_FAIL_POSITION` (fail position) · `UT_F_OPEN_THRESHOLD` (open/closed limit); with `UT_ST_CONFIG` one of: `UT_F_STROKE_TIME` (stroke time, must be above 0) · `UT_F_MIN_PULSE` (min pulse/overtravel) · `UT_F_REVERSAL_DELAY` (reversal delay).

## Bad settings
A setting that is not a number, negative or unknown never drives the valve somewhere
it could do damage. `configBad` is set and `faultCode` bit 8, and `faultId` names the
setting (the lowest priority). A negative `saveEvery` keeps nothing; a negative `retryWindow`
uses the default 1 h; an unknown `modeSource` uses the HMI (warnings).
- **Refused (a fault, both contacts off):** `strokeTime` 0 or less; a negative `minPulse`,
  `overTravel` or `reversalDelay`.
- **Warning:** `deadband` negative or not a number (the one-scan travel is used);
  `failPosition` not a number (stay) or above 100; thresholds not a number (98 / 2).
