# UT_VALVE — Two-position valve, cylinder or damper

Opens and closes any two-position actuator and supervises its limit switches:
- solenoid valves and cylinders with spring return (one coil),
- double-solenoid valves held in position (two coils),
- bistable / latching solenoids that need only a pulse (two coils),
- motorised on/off valves and dampers (drive to the limit, then stop).

Hand/Off/Auto/OOS is built in, like the motors. The shared logic (mode, safe
position, protections, stroke count) is [UT_VALVE_CORE](UT_VALVE_CORE.md).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `AutoOpen` | BOOL | FALSE | Auto command: TRUE = open, FALSE = close |
| in | `OpenLs` | BOOL | FALSE | Open limit switch |
| in | `ClosedLs` | BOOL | FALSE | Closed limit switch |
| in | `Interlock` | BOOL | TRUE | FALSE drives to `safePosition` in every mode |
| in | `DriveFault` | BOOL | FALSE | Actuator thermal / fault relay |
| in | `SwHand`, `SwAuto` | BOOL | FALSE | Selector switch (if `modeSource` uses it) |
| in | `Reset` | BOOL | FALSE | Fault reset (rising edge) |
| in | `Permissive` | BOOL | TRUE | FALSE: no move away from the safe position starts; it never forces safe |
| in | `LocalOpen` / `LocalClose` | BOOL | FALSE | Local pushbuttons (Hand), each on its rising edge |
| in | `LocalStop` | BOOL | FALSE | Local stop pushbutton (Hand; held: stops and keeps stopping). Motorised: stops where it is |
| out | `OpenOut` | BOOL | | Open coil / the single solenoid / motor open |
| out | `CloseOut` | BOOL | | Close coil / motor close (unused for spring return) |
| out | `IsOpen` | BOOL | | Confirmed open |
| out | `IsClosed` | BOOL | | Confirmed closed |
| out | `Fault` | BOOL | | A trip is holding it in the safe position |
| out | `State` | UT_STATE | | OFF = closed, ON = open, STARTING = opening, STOPPING = closing |
| inout | `Data` | UT_VALVE_DATA | | The valve's record |

## Record `UT_VALVE_DATA` (shared by every UT_VALVE* block)

### Settings
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `valveType` | UT_VALVE_TYPE | UT_VT_SPRING | See types |
| `modeSource` | UT_MODE_SOURCE | UT_SRC_HMI | As motors. The mode starts at Off and is retained |
| `resetByOff` | BOOL | TRUE | Switching to Off resets MANUAL faults |
| `restartAfterReset` | BOOL | FALSE | After a **MANUAL** reset, move again without a new command |
| `retryWindow` | TIME | T#1h | Window for RETRY counts |
| `useOpenLs` / `useClosedLs` | BOOL | TRUE / TRUE | Which limits are fitted |
| `openTime` / `closeTime` | TIME | T#10s / T#10s | Travel timeout. Without that limit, the travel is taken as complete after this |
| `pulseTime` | TIME | T#500ms | Coil pulse length for bistable valves |
| `reversalDelay` | TIME | T#500ms | Motorised: pause with both outputs off before driving the other way |
| `safePosition` | UT_SAFE_POS | UT_SAFE_CLOSED | On interlock, Off mode or a trip: `UT_SAFE_CLOSED`, `UT_SAFE_OPEN`, `UT_SAFE_HOLD` |
| `saveEvery` | TIME | T#12h | How often the stroke count is saved for a power cut (T#0s = not kept) |
| `simulate` | BOOL | FALSE | Positions follow the commands after the travel time, protections suppressed |
| `powerUp` | UT_POWERUP | UT_PU_LAST | After a power cut: `UT_PU_LAST` the mode comes back; `UT_PU_OFF` back to Off (and its safe position) until the operator selects it again. See [conventions](../conventions.md#power-up) |

The three-position, modulating and floating blocks keep their own settings, commands
and status in a second record of their own (`Pos3`, `Modul`, `Floating`), so a
two-position valve carries none of them. See [3POS](UT_VALVE_3POS.md),
[MOD](UT_VALVE_MOD.md) and [FLOAT](UT_VALVE_FLOAT.md). `reversalDelay` is in this
record and is used by every motorised or floating valve.

`UT_VALVE_TYPE`:
| Value | Outputs |
| --- | --- |
| `UT_VT_SPRING` | `OpenOut` held while open, off = close (spring) |
| `UT_VT_DOUBLE_HELD` | `OpenOut` held while open, `CloseOut` held while closed |
| `UT_VT_DOUBLE_PULSE` | `OpenOut` / `CloseOut` pulsed for `pulseTime`, once per move (bistable) |
| `UT_VT_MOTOR` | `OpenOut` / `CloseOut` on until the limit (or the travel time), then off. Hand can stop mid-travel. |

`UT_SAFE_HOLD` stops a motorised valve where it is; the coil types keep their
coils as they were.

### Protections (each a [`UT_PROTECTION`](../conventions.md#protections--every-fault-works-the-same-way); response and reset set per protection)
| Field | Bit | Default response · delay · reset | Raised when |
| --- | --- | --- | --- |
| `openTimeout` | 0 | TRIP · 0 · RETRY (2, recover 1 min) | Didn't reach open within `openTime` (only with the open limit fitted) |
| `closeTimeout` | 1 | TRIP · 0 · RETRY (2, recover 1 min) | Didn't reach closed within `closeTime` |
| `bothLimits` | 2 | TRIP · 0 · AUTO | Both limits on (switch fault). Clears when one drops |
| `positionLost` | 3 | TRIP · 1 s · AUTO | Left an end position with no command, for the delay |
| `noMovement` | 4 | OFF · 2 s · RETRY | Still on the end limit it should have left, for the delay (set `response` to use it) |
| `drive` | 5 | TRIP · 0 · AUTO | `DriveFault` input. A motorised valve also stops driving |
| *(position deviation)* | 6 | MOD / FLOAT only | Their `deviation` ([MOD](UT_VALVE_MOD.md), [FLOAT](UT_VALVE_FLOAT.md)) |
| *(position feedback)* | 7 | MOD / FLOAT only | Their `posFeedback` |
| (`configBad`) | 8 | fault or warning | A setting is invalid (see Bad settings) |

`faultId` names the lowest-numbered protection tripped. A RETRY on a travel
timeout repeats the move, which often frees a sticky valve. A timeout set to
WARN keeps the valve where it was sent and warns until it arrives.

### HMI commands
| Field | Type | Meaning |
| --- | --- | --- |
| `cmdMode` | INT | 0 Off · 1 Hand · 2 Auto · 3 OOS (acts when a new value arrives; the block sets it back to −1) |
| `cmdOpen` / `cmdClose` | BOOL | Hand open / close (close wins when both arrive). MOD / FLOAT: `handSp` to 100 / 0 % |
| `cmdStop` | BOOL | Hand stop (stop wins): motorised UT_VALVE / 3POS stop driving; MOD / FLOAT stay where they are (`handSp` = the position now). A stop read TRUE blocks every Hand move in that scan, so one held TRUE keeps the valve stopped |
| `cmdReset` | BOOL | Reset MANUAL protections |

The three-position Hand position `cmdPos` is in UT_VALVE_3POS's record (`Pos3`), and
the floating valve's `cmdHome` in UT_VALVE_FLOAT's (`Floating`).

Every BOOL command acts once, **on its rising edge**, and is cleared by the block, also by
the valve blocks that don't use it: one held TRUE (a Modbus coil left on, a debugger
force) acts once, and a Hand valve closed by the interlock does not re-open when the
interlock returns with `cmdOpen` still held.
A command left in the record at power-up does not act. Commands outside Hand (and
Hand commands while interlocked, or not permitted away from safe) are ignored. A master
that rewrites a command every poll goes through [UT_CMD](UT_CMD.md).

### Status fields
`mode`, `state`, `isOpen`, `isClosed`, `moving`, `interlocked`, `position : REAL`
(100 open, 0 closed, 50 between; measured / estimated for MOD and FLOAT; −1 = unknown,
FLOAT not homed),
`lastOpenStroke` / `lastCloseStroke : TIME` (measured limit-to-limit travel times,
a wear indicator; only with the limit fitted), `strokes : UDINT` (completed moves,
kept over a power cut as of the last `saveEvery`), `fault`, `warning`, `configBad` (a setting is
invalid, bit 8: see Bad settings),
`faultCode : DWORD`, `faultId : UT_FAULT`, `statusCode : UT_STATUS` and
`statusText : STRING(30)` (what it is doing or what holds it back, see
[Status](#status); every valve block has its own list). The variants keep their own
status in their own record: `targetPos` / `actualPos` (3POS), `demand` (MOD / FLOAT),
`notHomed` (FLOAT).

Added for time visibility and "why it stopped" (at the end of the record):
| Field | Type | Meaning |
| --- | --- | --- |
| `notPermitted` | BOOL | `Permissive` is FALSE: no move away from the safe position starts |
| `travelElapsed` | TIME | How long the move under way has been driving (0 when not moving). MOD: the ramp under way (a reversal starts a new one) |
| `timeLeft` | TIME | The countdown the status shows: travel left, the reversing pause, a fault's recover / retry wait |
| `stopReason` | UT_STOP | Why the valve last went back to its safe position (below; `UT_STOP_NONE` = none since power-up), kept until the next time |
| `lastFaultCode` | DWORD | The `faultCode` bits of the last trip, kept after it clears, until the next trip |
| `lastFault` | UT_FAULT | Its name (the lowest bit), e.g. `UT_F_CLOSE_TIMEOUT`, kept the same way |
| `trips` | UDINT | Trips since power-up (not kept over a power cut) |

**Why it went back to safe** (`stopReason`, the common
[stop reasons](../conventions.md#why-it-stopped)): it is set when the valve stops
being asked away from its safe position, from what held it in that scan, so the
record shows one scan after the move back starts.
| `stopReason` | Words ([UT_STOP_TEXT](UT_STOP_TEXT.md)) | When |
| --- | --- | --- |
| `UT_STOP_DEMAND_ENDED` | `Auto: demand ended` | Auto: `AutoOpen` (`AutoPos`, `AutoSp`) went back to the safe position |
| `UT_STOP_OPERATOR` | `Stopped: operator` | Hand: a close, stop or a move to the safe position |
| `UT_STOP_SWITCHED_OFF` | `Stopped: switched off` | The mode changed to Off or OOS |
| `UT_STOP_INTERLOCK` | `Stopped: interlock` | `Interlock` dropped |
| `UT_STOP_FAULT` | `Stopped: fault` | A trip (or a bad setting); `lastFault` says which |

## How it works
- **Mode** ([UT_MODE_SELECT](UT_MODE_SELECT.md)): Off → `safePosition`. Hand → `cmdOpen` /
  `cmdClose` / `cmdStop` and the `LocalOpen` / `LocalClose` / `LocalStop` buttons.
  Auto → follows `AutoOpen`. OOS → every output off,
  protections suppressed, no fault or warning reported; the position is found again afterwards.
- **Safe position** on Off, interlock, or any trip. In Hand an interlock also
  puts the Hand request back to the safe position, so the valve does not move
  by itself when the interlock returns. In Auto it follows `AutoOpen` again.
- **Permissive** FALSE: no move away from the safe position starts (Auto waits, a
  Hand request away from safe is dropped, status `UT_ST_NOT_PERMITTED`, `Not permitted`); a move toward
  the safe position is always allowed, and a valve already away stays where it is
  (unlike the interlock, it never forces safe). When it returns, Auto follows
  `AutoOpen` again; Hand needs a new command.
- After a **MANUAL** reset the valve stays in the safe position until it gets a
  new command (`AutoOpen` changes, or a new Hand command), unless `restartAfterReset`.
  AUTO / RETRY recovery puts it back where it is asked to be.
- **Moves**: a move ends on its limit, or after the travel time when that limit
  isn't fitted. A limit that makes and drops again within the travel time is
  treated as a flicker: the valve carries on (a motorised one keeps driving)
  and only the real arrival counts as one stroke.
- **Motorised**: a reversal waits `reversalDelay` with both outputs off. Hand
  `cmdStop` stops it mid-travel (State ON, `position` 50).
- **Power-up**: the position comes from the limit switches, no false fault.
  In Hand the valve stays where it is (a spring valve is closed); in Off it goes
  to `safePosition`; in Auto it follows `AutoOpen`. With `powerUp` = `UT_PU_OFF`
  the mode comes back Off, so the valve goes to its safe position until the
  operator selects a mode again.
- `OpenOut` and `CloseOut` are never on together.

## Status
`statusCode`, `faultId` and `statusText` say the **one main thing** the valve is
doing, or what holds it back, so a technician can see on the HMI why it is not where
it was asked to be. The most important reason wins: configuration > fault > held /
waiting > warning > position > Off. The words hold no numbers: the position is in `position`. The time left
(travel, a pause, a fault's recover / retry wait) is in `timeLeft`. The text is
rebuilt only when the status or the fault changes. Where the valve is (the rows
marked *(this block)*) comes from the block's last scan, so it shows one scan after
it changes. The numbers are in [conventions](../conventions.md#the-numbers).

| `statusCode` | Words | When |
| --- | --- | --- |
| `UT_ST_OFF` | `Off` | Mode Off (it goes to its safe position) |
| `UT_ST_OPENING` | `Opening` | *(this block)* `timeLeft` is the travel time left when a travel time applies |
| `UT_ST_CLOSING` | `Closing` | *(this block)* As opening |
| `UT_ST_OPEN` | `Open` | *(this block)* Confirmed open (limit, or the travel time without one) |
| `UT_ST_CLOSED` | `Closed` | *(this block)* Confirmed closed |
| `UT_ST_BETWEEN` | `Stopped between positions` | *(this block)* Held where it is (a Hand stop on a motorised valve, or `safePosition` HOLD) |
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
`<setting>` with `UT_ST_WARN_SETTING` is one of: `UT_F_SAVE_EVERY` (save every) · `UT_F_RETRY_WINDOW` (retry window) · `UT_F_MODE_SOURCE` (mode source) · `UT_F_SAFE_POSITION` (safe position); with `UT_ST_CONFIG` one of: `UT_F_VALVE_TYPE` (valve type) · `UT_F_TRAVEL_TIME` (open / close time) · `UT_F_REVERSAL_DELAY` (reversal delay) · `UT_F_PULSE_TIME` (pulse time, must be above 0).

## Using it
```iecst
V1(AutoOpen := FillValveCmd, OpenLs := V1_Open, ClosedLs := V1_Closed,
   Interlock := NOT TankHigh, Data := Valve1);
V1_Solenoid := V1.OpenOut;
```

## Bad settings
A setting that is not a number, negative or unknown never drives the valve somewhere
it could do damage. `configBad` is set and `faultCode` bit 8, and `faultId` names the
setting (the lowest priority). A negative `saveEvery` keeps nothing; a negative `retryWindow`
uses the default 1 h; an unknown `modeSource` uses the HMI (warnings).
- **Refused (a fault, every output off):** an unknown `valveType`; a negative `openTime`,
  `closeTime` or `reversalDelay`; a bistable `pulseTime` of 0 or less. It drives again
  once the setting is valid.
- **Warning (a safe value is used):** an unknown `safePosition` (closed).
- An unknown enum value can only come from a raw HMI write.
