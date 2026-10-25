# UT_VALVE_MOD — Modulating valve or damper (analog positioner)

Drives a valve or damper that has a positioner (4–20 mA / 0–10 V demand), with
optional position feedback. Typically sits after OpenPLC's `PID`. Mode, fail
action and protections work as [UT_VALVE](UT_VALVE.md) ([UT_VALVE_CORE](UT_VALVE_CORE.md)).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `AutoSp` | REAL | 0.0 | Position request in Auto, % (e.g. `PID` output). NaN / infinite is ignored (the last good value stands) |
| in | `PosFb` | REAL | -1.0 | Position feedback % (exactly −1 = not fitted) |
| in | `OpenLs` / `ClosedLs` | BOOL | FALSE | Optional end switches |
| in | `Interlock` | BOOL | TRUE | FALSE → `failPosition` |
| in | `DriveFault`, `SwHand`, `SwAuto`, `Reset` | | | As UT_VALVE |
| in | `Permissive` | BOOL | TRUE | FALSE: the valve moves only toward `failPosition` (an Auto request away from it waits where the valve is; a Hand one is dropped); it never forces it |
| in | `LocalOpen` / `LocalClose` / `LocalStop` | BOOL | FALSE | Local pushbuttons (Hand, rising edge): `handSp` 100 %, 0 %, or stop where it is (held: keeps stopping) |
| out | `Out` | REAL | | Demand to the positioner, % (100 − demand when `reverseActing`) |
| out | `OutRaw` | UINT | | `Out` scaled to `rawMin..rawMax`, clipped to 0–65535, for `%QW` |
| out | `IsOpen` / `IsClosed` | BOOL | | Feedback (or the demand) against the thresholds, or the end switch |
| out | `Fault` | BOOL | | A trip is holding it at the fail action |
| out | `State` | UT_STATE | | OFF closed, ON open, STARTING / STOPPING while ramping or the feedback catches up |
| inout | `Data` | UT_VALVE_DATA | | Shared valve record ([UT_VALVE](UT_VALVE.md#record-ut_valve_data-shared-by-every-ut_valve-block)) |
| inout | `Modul` | UT_VALVE_MOD_DATA | | The modulating settings, protections and status (below) |

## Record `UT_VALVE_MOD_DATA` (pin `Modul`)
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `outMin` / `outMax` | REAL | 0.0 / 100.0 | Clamp (min above max gives max, as IEC `LIMIT`) |
| `rampRate` | REAL | 0.0 | Rate limit in Hand and Auto, in % per `rateUnit` (0 = off). The fail action is immediate |
| `rateUnit` | UT_RATE_UNIT | UT_PER_SEC | Time unit of `rampRate`: `UT_PER_SEC` (0, % per second) or `UT_PER_MIN` (% per minute); `UT_PER_HOUR` and `UT_PER_DAY` work too |
| `tightShutoff` | REAL | 0.0 | Demand below this → 0 % (seat it properly), even below `outMin`. 0 = off |
| `fullOpenAbove` | REAL | 100.0 | Demand above this → 100 %, even above `outMax`. 100 = off |
| `reverseActing` | BOOL | FALSE | Air-to-close: output inverted |
| `failPosition` | REAL | 0.0 | Demand on interlock / fault / Off (below 0, or not a number = stay where it is) |
| `holdOnFault` | BOOL | FALSE | A trip holds the last demand instead of `failPosition` |
| `openThreshold` / `closedThreshold` | REAL | 98.0 / 2.0 | `IsOpen` at or above, `IsClosed` at or below, % |
| `rawMin` / `rawMax` | REAL | 0.0 / 65535.0 | `OutRaw` at 0 % and 100 % |
| `handSp` | REAL | 0.0 | Hand position (HMI); tracks the demand in Auto. Hand `cmdOpen` / `cmdClose` (in `Data`) set it to 100 / 0 %, `cmdStop` to the demand now (a ramp stops where it is) |
| `deadband` | REAL | 1.0 | Feedback within this of the demand counts as there (State) |
| `deviation` | UT_LEVEL | WARN · 10 s · AUTO · sp 5 | Feedback vs demand: `sp` is the limit in %, `delay` the time (`faultCode` bit 6) |
| `posFeedback` | UT_PROTECTION | TRIP · 500 ms · AUTO | Feedback NaN, infinite or outside −5…105 % (`faultCode` bit 7) |
| `demand` | REAL | | Status: the position asked for, % |

In the valve record `Data`: `position` (the feedback, or the demand without one), the
modes, the other protections, the HMI commands and the status.

## How it works
- Request → tight shutoff / full open → clamp → ramp → `Out` (inverted if
  reverse acting) → `OutRaw`.
- The ramp is in % of the stroke per second, or per minute with
  `rateUnit := UT_PER_MIN`. For a slow damper that should take 5 minutes from
  closed to open: `rampRate := 20.0, rateUnit := UT_PER_MIN` (the same as
  `rampRate := 0.3333` per second).
- Bumpless: `handSp` follows the demand in Auto, so Auto → Hand doesn't move
  the valve. In Hand an interlock sets `handSp` to `failPosition`, so it does not
  move by itself when the interlock returns.
- Deviation is checked only with good feedback, after its delay. Bad feedback
  trips `posFeedback` and applies the fail action; the demand is then used as
  the position.
- `travelElapsed` is how long the ramp under way has run (a reversal starts a new
  one) and `timeLeft` the ramp's time left, with no ramp both 0.
- OOS: `Out` = 0, faults hidden.
- Power-up: with feedback, the demand and `handSp` start at the feedback, so in
  Hand the valve stays where it is. Without feedback the demand starts at 0 %
  (declare the record `RETAIN` to keep `handSp`).

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
| `UT_ST_MOVING` | `Moving` | *(this block)* Going to `demand`; `timeLeft` is the ramp's time left when a ramp is set |
| `UT_ST_AT_POSITION` | `At position` | *(this block)* Between the thresholds, at `demand` |
| `UT_ST_INTERLOCK` | `Blocked: interlock` | `Interlock` FALSE: at its safe position (every mode but OOS) |
| `UT_ST_OOS` | `Out of service` |  |
| `UT_ST_NOT_PERMITTED` | `Not permitted` | *(this block)* `Permissive` FALSE holds back a move away from the safe position |
| `UT_ST_WARNING` | `Warning: <fault>` | A protection set to WARN is raised |
| `UT_ST_WARN_SETTING` | `Setting: <setting>` | An invalid setting, a safe value in use (settings below) |
| `UT_ST_FAULT` | `Fault: <fault>` | Tripped, AUTO: clears by itself once the cause has gone for `recover` (`timeLeft` while it counts) |
| `UT_ST_FAULT_RETRY` | `Retrying: <fault>` | Tripped, RETRY: the protection's `retries` of `maxRetries` (`timeLeft` while it counts) |
| `UT_ST_FAULT_RESET` | `Latched: <fault>` | Tripped, MANUAL: a reset (pin, `cmdReset`, Off) once the cause has gone |
| `UT_ST_FAULT_LOCKED` | `Locked: <fault>` | RETRY used up: now as MANUAL |

`<fault>` is `faultId`, one of: `UT_F_BOTH_LIMITS` (both limits) · `UT_F_ACTUATOR` (actuator fault) · `UT_F_POS_DEVIATION` (pos. deviation) · `UT_F_POS_FEEDBACK` (position signal).
`<setting>` with `UT_ST_WARN_SETTING` is one of: `UT_F_SAVE_EVERY` (save every) · `UT_F_RETRY_WINDOW` (retry window) · `UT_F_MODE_SOURCE` (mode source) · `UT_F_OUTPUT_MIN_MAX` (output min / max) · `UT_F_RAMP_RATE` (ramp rate) · `UT_F_RATE_UNIT` (rate unit) · `UT_F_SHUTOFF` (shutoff / full open) · `UT_F_FAIL_POSITION` (fail position) · `UT_F_OPEN_THRESHOLD` (open/closed limit) · `UT_F_RAW_MIN_MAX` (raw min / max) · `UT_F_DEADBAND` (deadband).

## Bad settings
A setting that is not a number, negative or unknown never drives the valve somewhere
it could do damage. `configBad` is set and `faultCode` bit 8, and `faultId` names the
setting (the lowest priority). A negative `saveEvery` keeps nothing; a negative `retryWindow`
uses the default 1 h; an unknown `modeSource` uses the HMI (warnings).
- **Warning only (a safe value is used):** `outMin` / `outMax` not a number, outside
  0..100 or min above max (the 0..100 clamp holds); `rampRate` negative or not a number,
  or an unknown `rateUnit` (no ramp, as 0); `tightShutoff` / `fullOpenAbove` not a number (off); `failPosition`
  not a number (stay) or above 100 (100); `openThreshold` / `closedThreshold` not a
  number (98 / 2); `rawMin` / `rawMax` not a number or equal (`OutRaw` 0 or fixed);
  `deadband` negative or not a number.
