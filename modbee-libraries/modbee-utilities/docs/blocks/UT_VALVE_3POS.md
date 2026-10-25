# UT_VALVE_3POS — Three-position valve (diverter or open/mid/closed)

For actuators with three positions:
- 3-way diverters: **A / closed / B**,
- spring-centred double-solenoid valves and cylinders (centre = both coils off),
- three-coil valves (one coil per position),
- motorised valves with a mid position (mid limit switch or timed).

Mode, safe position, protections and stroke count work exactly as
[UT_VALVE](UT_VALVE.md) ([UT_VALVE_CORE](UT_VALVE_CORE.md)).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `AutoPos` | INT | 2 | Auto position request: 1, 2 or 3 (anything else is ignored) |
| in | `Ls1` / `Ls2` / `Ls3` | BOOL | FALSE | Position limit switches |
| in | `Interlock` | BOOL | TRUE | FALSE → `safePos3` position |
| in | `DriveFault`, `SwHand`, `SwAuto`, `Reset` | | | As [UT_VALVE](UT_VALVE.md) |
| in | `Permissive` | BOOL | TRUE | FALSE: no move away from `safePos3` starts (a move to it is allowed; it never forces it) |
| in | `Local1` / `Local2` / `Local3` | BOOL | FALSE | Local pushbuttons (Hand), each on its rising edge: go to position 1, 2, 3 |
| in | `LocalStop` | BOOL | FALSE | Local stop pushbutton (Hand; held: keeps stopping). Motorised: stops where it is |
| out | `Out1` / `Out2` / `Out3` | BOOL | | Coils, see the type table |
| out | `Position` | INT | | Confirmed position 1–3 (0 = moving/unknown) |
| out | `Fault` | BOOL | | A trip is holding it at the safe position |
| out | `State` | UT_STATE | | OFF at `safePos3`, ON at another position, STARTING moving away from `safePos3`, STOPPING moving to it |
| inout | `Data` | UT_VALVE_DATA | | Shared valve record ([UT_VALVE](UT_VALVE.md#record-ut_valve_data-shared-by-every-ut_valve-block)) |
| inout | `Pos3` | UT_VALVE3_DATA | | The three-position settings, command and status (below) |

## Record `UT_VALVE3_DATA` (pin `Pos3`)
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `type3` | UT_VALVE3_TYPE | UT_V3_SPRING_CENTRE | `UT_V3_SPRING_CENTRE` (pos1 = Out1, pos2 = none, pos3 = Out3) · `UT_V3_THREE_COIL` (one output per position) · `UT_V3_MOTOR` (Out1 drives toward 1, Out3 toward 3, stops at the target; mid by `Ls2` or `midTime`) |
| `useLs1` / `useLs2` / `useLs3` | BOOL | TRUE | Which limits are fitted |
| `travelTime` | TIME | T#10s | Timeout per move (end to end for a motor). Without that limit, the position is taken as reached after this |
| `midTime` | TIME | T#0s | Motor without `Ls2`: timed run from an end to mid (0 = half of `travelTime`) |
| `safePos3` | INT | 2 | Position on interlock / Off / a trip (outside 1–3 = 2) |
| `cmdPos` | INT | −1 | HMI position request 1–3 (Hand). A one-shot request like `cmdMode`: it acts when a new value arrives and is set back to −1; invalid values are ignored |
| `targetPos` / `actualPos` | INT | | Status: where it is going (0 = hold) / confirmed position (0 = moving or unknown) |

In the valve record `Data`: `reversalDelay` (T#500ms, motor: pause before driving the
other way), the modes, protections, `cmdOpen` / `cmdClose` / `cmdStop` / `cmdReset`
and the status.

`cmdStop` stops a motorised valve where it is (Hand). Faults use the shared bits:
a move toward a higher position that times out is `openTimeout` (bit 0), toward a
lower one `closeTimeout` (bit 1); two limits on → bit 2; position lost → bit 3.
`lastOpenStroke` / `lastCloseStroke` are the last measured moves up / down
(on a limit). `position` is 0 / 50 / 100 at positions 1 / 2 / 3.

## How it works
- A motor going 1 ↔ 3 passes 2 without stopping.
- Motor to 2 with `Ls2`: from 1 it drives up, from 3 down, from an unknown
  position down; if it reaches end 1 first it turns round (reversal pause) and
  drives up to `Ls2`.
- Motor to 2 without `Ls2`: from a known end it runs `midTime` toward the
  middle; from an unknown position it first goes to end 1 (re-sync), then runs
  `midTime` up.
- A limit that drops again within the travel time is a flicker: the valve
  carries on. At most two legs per move, then a timeout.
- Power-up: the position comes from the limits, no false fault. Hand stays put;
  Off goes to `safePos3`; Auto goes to `AutoPos`.

## Status
`statusCode`, `faultId` and `statusText` say the **one main thing** the valve is
doing, or what holds it back, so a technician can see on the HMI why it is not where
it was asked to be. The most important reason wins: configuration > fault > held /
waiting > warning > position > Off. The words hold no numbers: the target and the position are in `targetPos` and `actualPos`. The time left
(travel, a pause, a fault's recover / retry wait) is in `timeLeft`. The text is
rebuilt only when the status or the fault changes. Where the valve is (the rows
marked *(this block)*) comes from the block's last scan, so it shows one scan after
it changes. The numbers are in [conventions](../conventions.md#the-numbers).

| `statusCode` | Words | When |
| --- | --- | --- |
| `UT_ST_OFF` | `Off` | Mode Off (it goes to its safe position) |
| `UT_ST_MOVING` | `Moving` | *(this block)* Going to `targetPos`; `timeLeft` is the travel time left when one applies |
| `UT_ST_AT_POSITION` | `At position` | *(this block)* At `actualPos` |
| `UT_ST_BETWEEN` | `Stopped between positions` | *(this block)* Held where it is (a Hand stop on a motorised valve) |
| `UT_ST_POS_UNKNOWN` | `Position unknown` | *(this block)* Not moving and no limit or travel time says where it is |
| `UT_ST_INTERLOCK` | `Blocked: interlock` | `Interlock` FALSE: at its safe position (every mode but OOS) |
| `UT_ST_MUST_CYCLE` | `Waiting: command must cycle` | After a MANUAL reset in Auto: it stays safe until the Auto request changes (unless `restartAfterReset`) |
| `UT_ST_OOS` | `Out of service` |  |
| `UT_ST_NOT_PERMITTED` | `Not permitted` | *(this block)* `Permissive` FALSE holds back a move away from the safe position |
| `UT_ST_DEAD_TIME` | `Waiting: dead time` | *(this block)* Motorised: the pause before driving the other way (`timeLeft`) |
| `UT_ST_WARNING` | `Warning: <fault>` | A protection set to WARN is raised |
| `UT_ST_WARN_SETTING` | `Setting: <setting>` | An invalid setting, a safe value in use (settings below) |
| `UT_ST_FAULT` | `Fault: <fault>` | Tripped, AUTO: clears by itself once the cause has gone for `recover` (`timeLeft` while it counts) |
| `UT_ST_FAULT_RETRY` | `Retrying: <fault>` | Tripped, RETRY: the protection's `retries` of `maxRetries` (`timeLeft` while it counts) |
| `UT_ST_FAULT_RESET` | `Latched: <fault>` | Tripped, MANUAL: a reset (pin, `cmdReset`, Off) once the cause has gone |
| `UT_ST_FAULT_LOCKED` | `Locked: <fault>` | RETRY used up: now as MANUAL |
| `UT_ST_CONFIG` | `Config: <setting>` | An invalid setting: every output off until it is fixed |

`<fault>` is `faultId`, one of: `UT_F_OPEN_TIMEOUT` (open timeout) · `UT_F_CLOSE_TIMEOUT` (close timeout) · `UT_F_BOTH_LIMITS` (both limits) · `UT_F_POS_LOST` (position lost) · `UT_F_NO_MOVEMENT` (did not move) · `UT_F_ACTUATOR` (actuator fault).
`<setting>` with `UT_ST_WARN_SETTING` is one of: `UT_F_SAVE_EVERY` (save every) · `UT_F_RETRY_WINDOW` (retry window) · `UT_F_MODE_SOURCE` (mode source) · `UT_F_SAFE_POSITION` (safe position, must be 1..3); with `UT_ST_CONFIG` one of: `UT_F_THREE_POS_TYPE` (three-position type) · `UT_F_MID_TIME` (travel / mid time) · `UT_F_REVERSAL_DELAY` (reversal delay).

## Bad settings
A setting that is not a number, negative or unknown never drives the valve somewhere
it could do damage. `configBad` is set and `faultCode` bit 8, and `faultId` names the
setting (the lowest priority). A negative `saveEvery` keeps nothing; a negative `retryWindow`
uses the default 1 h; an unknown `modeSource` uses the HMI (warnings).
- **Refused (a fault, every output off):** an unknown `type3`; a negative `travelTime`,
  `midTime` or `reversalDelay`.
- **Warning:** `safePos3` outside 1..3 (2 is used).
