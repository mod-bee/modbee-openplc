# Conventions — how every block behaves

> Read this once and every block will feel familiar.

## Names
- Every block, record type and enum value starts with `UT_`.
- **Pins** are PascalCase plain English: `Feedback`, `Overload`, `Interlock`.
- **Record fields** are camelCase: `feedbackDelay`, `overload.reset`.
  - `cmdXxx`: an HMI command. The block acts on it once and clears it (see
    [HMI commands](#hmi-commands)).
  - `grpXxx`: written by a group block (station, duty). Don't write these yourself.
- Reserved words that can't be used as names: `step`, `now`, `time`, `action`, `method`, `min`, `max`, `set`.

## Zero is off
**The first value of every enum (0) is the off / none / safest choice**, and every
mode starts at 0 = Off. A freshly loaded program does nothing until someone
chooses otherwise, and an enum left at its default never surprises anyone.

There are two exceptions, both about what happens after a power cut, where the
unattended plant carrying on is the safe default:
- `UT_POWERUP`, whose first value `UT_PU_LAST` keeps a device's mode over a power
  cut (see [Power-up](#power-up)): a freshly loaded program still starts Off, and an
  unattended pump left in Auto carries on after a power cut.
- `UT_RUN_POWERUP` ([UT_RUN_LIMIT](blocks/UT_RUN_LIMIT.md), [UT_ZONE_SEQ](blocks/UT_ZONE_SEQ.md)),
  whose first value `UT_RPU_RESUME` lets a run or zone program that was going at a
  power cut carry on with what it had left, as a commercial irrigation controller
  does (`UT_RPU_RESTART` and `UT_RPU_NONE` are the other choices). A freshly loaded
  program still starts nothing.

## Pin order
1. The **first input** is the main signal and should always be wired.
2. The **first output** is the main result.
3. The record (`Data`, or an array such as `Pumps`) comes last.

## Ladder / FBD rule (important)
Library blocks run on **EN**. If the rung feeding EN is false, the block **doesn't
run** and its outputs freeze. Give every library block its own **unconditional
rung** and wire commands into **named pins**. See [ladder-rules.md](ladder-rules.md).

## Defaults
- Unwired permissives/interlocks default to **TRUE** (OK). Unwired fault inputs default to **FALSE** (healthy).
- Optional sensors are **not installed** until you say so (`installed := FALSE`).
- Every setting has a working default.

## Inputs are TRUE = active
**Inputs are TRUE = active; wire NC contacts through NOT at the pin.** A fault
input is TRUE when tripped, a button TRUE when pressed, a switch TRUE when it
signals. The device blocks have no "NC" setting: a normally-closed contact (an overload
aux, a thermistor relay, a stop button, a flow switch) is inverted with `NOT` at
the pin or in the I/O mapping, e.g. `Overload := NOT M1_OL_NC`. A broken wire then
reads as tripped / pressed, the safe side.

## Invalid settings
**An invalid or out-of-range setting never runs anything that could damage
equipment.** A setting that is not a number, infinite, negative where it can't be,
or out of range either falls back to a safe value and raises a warning
(`wrnConfig`, `Warning`), or, where no fallback is safe, keeps the device off with
a fault until it is fixed. Each block's doc lists its checks.

## Interlock vs permissive
| | Stops a running device | Blocks a start | Applies in Hand |
| --- | --- | --- | --- |
| **Interlock** | yes | yes | **yes** |
| **Permissive** | no | yes | yes |

Neither is a fault. The device shows `UT_STATE_INTERLOCKED`.

---

## Protections — every fault works the same way

Every protection in every block (overload, dry run, high pressure, travel
timeout…) is a `UT_PROTECTION`. Its **response** and **how it resets** are separate
choices, so latching is always optional:

### `UT_PROTECTION` (settings + status in one)
| Field | Type | Meaning |
| --- | --- | --- |
| `response` | UT_RESPONSE | `UT_RESP_OFF` (0, ignored) · `UT_RESP_WARN` (alarm only, the device keeps running) · `UT_RESP_TRIP` (stop the device) |
| `delay` | TIME | The condition must last this long |
| `reset` | UT_RESET_MODE | `UT_RST_AUTO` (0) · `UT_RST_RETRY` · `UT_RST_MANUAL`, see below |
| `recover` | TIME | AUTO/RETRY: the cause must be gone this long before the device runs again (also the retry wait). A reset with the cause gone skips it |
| `maxRetries` | INT | RETRY: attempts allowed within the device's `retryWindow`, then it becomes MANUAL |
| `active` | BOOL | *status*: the condition is present now (after the delay) |
| `tripped` | BOOL | *status*: the protection is holding the device off, or warning |
| `retries` | INT | *status*: attempts used in the current window |
| `count` | UDINT | *status*: total events (not kept over a power cut) |
| `timeLeft` | TIME | *status*: the countdown in progress: the `delay` still to run while the condition is present, or the `recover` / retry wait still to go while an AUTO or RETRY trip holds and its cause has gone. `T#0s` when nothing counts |

### Reset modes
| Mode | Cause can be observed (overload, high pressure, limit switch…) | One-off event (failed to start, travel timeout, max run…) |
| --- | --- | --- |
| `UT_RST_AUTO` | Clears by itself once the cause has gone for `recover`, or at once on a reset | Clears after `recover` (or at once on a reset), and the device tries again (unlimited) |
| `UT_RST_RETRY` | As AUTO, but only `maxRetries` times in `retryWindow`; after that MANUAL. A reset clears it at once and starts a fresh count. `retryWindow` `T#0s` = no window: the count is cleared only by a reset or a power cycle | As AUTO, limited to `maxRetries` |
| `UT_RST_MANUAL` | Stays until a reset **and** the cause has gone | Stays until a reset |

**Example: a sump pump overload.** Overload uses `UT_RST_AUTO`. The maintenance
person resets the overload relay in the panel, the cause goes, and the pump goes
straight back into service. Nobody needs to touch an HMI.

### Ways to reset a MANUAL fault (any one of these)
1. the block's `Reset` pin (a panel pushbutton);
2. the HMI command `cmdReset`;
3. **switching the device to Off and back** (`resetByOff := TRUE`, the default),
   so a selector switch is a reset.

### Restart after a fault clears
- After an **AUTO/RETRY** recovery, the device resumes if it's still asked to run.
  That's the point of choosing auto recovery. A motor in **Hand** is not "still
  asked": a trip drops its hand start (as the interlock does), so the operator
  presses start again.
- After a **MANUAL** reset, a maintained run command must cycle (go FALSE and back to
  TRUE) before the device restarts, unless `restartAfterReset := TRUE`.

The status of a tripped device says how the trip will clear, by its prefix (see
[Status](#status-every-critical-block-says-what-it-is-doing-and-why)): `Fault:
overload` clears by itself, `Retrying: no run feedback` retries, `Latched:
overload` needs a reset, `Locked: no run feedback` has used up its retries. The
wait still to run is in the record's `timeLeft` (and `faultClearIn` on the motors),
and in the protection's own `timeLeft` and `retries`.

Each block's record also has `fault` (any trip), `warning` (any warning),
`faultCode : DWORD` (one bit per protection), and `faultId : UT_FAULT` (the
highest-priority active one, by name). **`faultCode` and `faultId` cover warnings
too**: a protection set to WARN sets its bit and `faultId` while it is raised, as a
TRIP does.

### `UT_LEVEL` — a protection with a setpoint
Used for analog alarm levels (HH/H/L/LL), current limits and so on: every
`UT_PROTECTION` field plus
| Field | Type | Meaning |
| --- | --- | --- |
| `sp` | REAL | Setpoint |
| `deadband` | REAL | Must come back past `sp ∓ deadband` to clear (stops chatter) |

### `UT_MEAS` — a measurement that might be a switch, a transmitter, both, or nothing
Pumps and controllers watch measurements (pressure, flow, suction level) that
vary from site to site. Each one is a `UT_MEAS`:
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `installed` | BOOL | FALSE | Is anything fitted at all? |
| `sensor` | UT_SENSOR | UT_SENSOR_SWITCH | `UT_SENSOR_SWITCH` · `UT_SENSOR_ANALOG` (transducer/meter) · `UT_SENSOR_BOTH`. More types can be added later without breaking projects. |
| `highSwitch` | UT_LEVEL_ID | per block | Which level the **high switch** triggers: `UT_LVL_NONE` (0, no high switch fitted), `UT_LVL_HIHI`, `UT_LVL_HI` |
| `lowSwitch` | UT_LEVEL_ID | per block | Which level the **low switch** triggers: `UT_LVL_NONE`, `UT_LVL_LO`, `UT_LVL_LOLO` |
| `hiHi`, `hi`, `lo`, `loLo` | UT_LEVEL | per block | Setpoints (analog) and response/reset for each level |
| `onlyWhenRunning` | BOOL | per block | Only check while the equipment runs (e.g. discharge pressure) |
| `maskAtStart` | BOOL | per block | Ignore the low levels during the start mask / prime |
| `value` | REAL | | *status*: live analog value |

So a site with just a high-pressure switch sets `installed := TRUE`,
`sensor := UT_SENSOR_SWITCH`, `highSwitch := UT_LVL_HIHI`, `lowSwitch := UT_LVL_NONE`.
A site with a transducer sets `sensor := UT_SENSOR_ANALOG` and the four setpoints.
H and L are warnings by default, so abnormal conditions can be dealt with
before they become trips.

---

## Device modes — `UT_MODE`
| Value | Code | Meaning |
| --- | --- | --- |
| `UT_MODE_OFF` | **0** | Off / safe position. **The default.** |
| `UT_MODE_HAND` | 1 | Operator control (HMI buttons, local pushbuttons). Interlocks still apply. |
| `UT_MODE_AUTO` | 2 | Program control (`AutoCmd` pin or a group block) |
| `UT_MODE_OOS` | 3 | Out of service (maintenance): outputs off, faults and alarms suppressed |

- The mode starts at **Off**. Whatever the operator selects is **retained inside the
  block**. After a power cut it comes back as the device's `powerUp` says (see
  [Power-up](#power-up)): by default in the mode it was left in.
- An HMI changes the mode by writing `cmdMode` (an INT): `0` Off, `1` Hand, `2` Auto,
  `3` OOS. The block applies it once and sets `cmdMode` back to `-1` ("no request");
  see [HMI commands](#hmi-commands).
  The actual mode is in `mode`.

**Where the mode comes from** — `modeSource : UT_MODE_SOURCE`
| Value | Meaning |
| --- | --- |
| `UT_SRC_HMI` (0) | HMI `cmdMode`, retained |
| `UT_SRC_SWITCH` | Physical selector pins `SwHand` / `SwAuto` (neither = Off) |
| `UT_SRC_REMOTE` | Selector Off/Hand act locally; selector Auto hands control to the HMI mode (local/remote) |

### Power-up
**What a device's mode does after a power cut is a per-device setting**,
`powerUp : UT_POWERUP` in its record (a PLC stop / start counts as a power-up too):

| Value | After a power cut | For example |
| --- | --- | --- |
| `UT_PU_LAST` (default) | The mode comes back as it was, from the first scan | An unattended effluent pump stays in Auto and carries on |
| `UT_PU_OFF` | The mode comes back **Off**; the operator selects it again. A selector found in Hand or Auto is held at Off until it is moved | A quarry conveyor someone must restart on purpose |

- **A motor in Hand always needs a fresh start after a power cut** (EN 60204-1),
  whatever `powerUp` says: the motor blocks never keep a Hand start.
- `UT_HOA`, whose Hand switches an output straight on, has `handPowerUp :
  UT_HAND_POWERUP`: `UT_HPU_OFF` (default) a Hand comes back Off; `UT_HPU_KEEP`
  Hand and its output come back.
- `ForceOff` on [UT_MODE_SELECT](blocks/UT_MODE_SELECT.md) holds a mode at Off
  without losing the choice (a plant-wide off, an isolator's auxiliary contact).
- Plant-level Off / Manual / Auto is [UT_SYSTEM_MODE](blocks/UT_SYSTEM_MODE.md).

## Device state — `UT_STATE` (one colour map for every device)
`UT_STATE_OFF` (0) · `UT_STATE_STARTING` · `UT_STATE_ON` · `UT_STATE_STOPPING` ·
`UT_STATE_INTERLOCKED` · `UT_STATE_WARNING` (running with a warning) · `UT_STATE_FAULT` ·
`UT_STATE_INVALID` · `UT_STATE_OOS`. For valves: OFF = closed, ON = open, STARTING/STOPPING = moving.

## Status: every critical block says what it is doing and why

Any block that can stop equipment (motors, pumps, pump stations, duty and cascade
groups, speed control, valves, dosing, run limits, sequencers, interlocks, vessels)
has these status fields in its record, updated every scan:

| Field | Type | What it is |
| --- | --- | --- |
| `statusCode` | UT_STATUS | The one main thing happening, or holding it back, right now |
| `faultId` | UT_FAULT | Which fault, warning or setting the status is about. `UT_F_NONE` when none. Blocks that have no faults or settings to name leave it out |
| `statusText` | STRING(30) | The two in words ([UT_STATUS_TEXT](blocks/UT_STATUS_TEXT.md)), for a person looking at the PLC online. Written only when the code or the fault changes |

The text never holds a number. The numbers that go with a status are in their own
fields: `timeLeft` for the countdown, `statusUnit` on the group blocks for the pump
or unit (its array index) the status is about, and counts such as `runningCount`.

**HMIs and SCADA read the codes.** `UT_STATUS`, `UT_FAULT` and `UT_STOP` are
enumerations. An HMI, Modbus or SCADA sees an enumeration as a number: the
member's position in its list, counting from 0, as in the tables below. The
debugger shows the name. Keep the words, alarm texts, colours and history in the
HMI or SCADA, keyed on the numbers. Each device has its own fields in its own
record: read them directly (`Pump1.statusCode`, `Pump1.faultId`).

The block always shows the **most important** reason, in this order (top first).
[UT_STATUS_KIND](blocks/UT_STATUS_TEXT.md) gives the kind of any status:

| Order | Kind (`UT_KIND`) | What it means | Example `statusText` |
| --- | --- | --- | --- |
| 1 | `UT_KIND_CONFIG` | A setting keeps it off until it is fixed | `Config: valve type` |
| 2 | `UT_KIND_FAULT` | A trip holds it off, or it runs in a fallback | `Latched: overload` · `Fault: dry run` |
| 3 | `UT_KIND_HELD` | Held or waiting (not a fault): why it isn't running when asked | `Waiting: restart delay` · `Blocked: interlock` · `Not permitted` · `Hand: press start` · `Waiting: turn in group` |
| 4 | `UT_KIND_WARNING` | It runs, but something needs looking at: shown over "Running" | `Warning: current signal` · `Setting: full load current` |
| 5 | `UT_KIND_NORMAL` | Normal operation | `Running: Auto` · `Starting` · `Stopping` · `Running: group` |
| 6 | `UT_KIND_NORMAL` | Idle, nothing wanted | `Off` · `Idle` |

Rules:
- The words start with their kind (`Config:`, `Fault:`, `Retrying:`, `Latched:`,
  `Locked:`, `Warning:`, `Setting:`, `Waiting:`, `Blocked:`, `Not permitted`,
  `Hand:`, `Running`, `Starting`, `Stopping`, `Off`, `Idle`; mode blocks show their
  mode: `Auto`, `Manual: running (local)`), then the detail.
- A device that is asked to run but is not running always says why.
- A status means the same in every block: `UT_ST_RESTART_DELAY` is a restart delay,
  `UT_ST_INTERLOCK` an interlock, wherever it appears. Each block's doc lists the
  statuses it uses.
- Show the status on the HMI next to the device; for a whole-site text line feed the
  statuses into [UT_MSG_QUEUE](blocks/UT_MSG_QUEUE.md).

### Fault prefixes
A warning, fault or configuration status is a prefix followed by the words of the
fault or setting in `faultId`. The prefix tells you how the problem behaves:

| Status | Prefix | Meaning |
| --- | --- | --- |
| `UT_ST_FAULT` | `Fault: ` | A trip that resets by itself once the cause has gone (AUTO) |
| `UT_ST_FAULT_RETRY` | `Retrying: ` | A trip that retries (RETRY), with retries still left |
| `UT_ST_FAULT_RESET` | `Latched: ` | A trip that needs a reset (MANUAL) |
| `UT_ST_FAULT_LOCKED` | `Locked: ` | A RETRY trip whose retries are used up: it needs a reset |
| `UT_ST_WARNING` | `Warning: ` | It runs, but something needs looking at |
| `UT_ST_WARN_SETTING` | `Setting: ` | A setting is not valid; a safe value is used instead |
| `UT_ST_CONFIG` | `Config: ` | A setting is not valid and keeps the device off until it is fixed |

For example `Retrying: no run feedback`, `Latched: overload`, `Setting: full load
current`, `Config: valve type`. A setting with no words of its own reads `a setting`.

### The numbers
The tables below give every member with its number, in list order from 0. These
numbers are fixed: a member added to the library later goes at the very end of its
list, so no number ever moves and an HMI's lists stay right after a library update.
The statuses up to `UT_ST_CONFIG` are grouped by kind; the ones after it (from
`UT_ST_FIXED_SPEED`) are not, so take a status's kind from the Kind column or from
[UT_STATUS_KIND](blocks/UT_STATUS_TEXT.md), never from its position.

UT_STATUS, UT_FAULT, UT_STOP and UT_KIND have the base type USINT (IEC 61131-3 Ed. 3,
`UT_STATUS : USINT (UT_ST_IDLE, ...)`): one byte each, and an HMI or SCADA reads them as
a USINT (0..255).

#### UT_STATUS: what the block is doing (`statusCode`)

| No. | Name | Words (`UT_STATUS_TEXT`) | Kind |
| --- | --- | --- | --- |
| 0 | `UT_ST_IDLE` | `Idle` | normal |
| 1 | `UT_ST_OFF` | `Off` | normal |
| 2 | `UT_ST_OFF_NOT_AUTO` | `Off: motor not in Auto` | normal |
| 3 | `UT_ST_RUN_AUTO` | `Running: Auto` | normal |
| 4 | `UT_ST_RUN_HAND` | `Running: Hand` | normal |
| 5 | `UT_ST_STARTING` | `Starting` | normal |
| 6 | `UT_ST_STOPPING` | `Stopping` | normal |
| 7 | `UT_ST_RUN_GROUP` | `Running: group` | normal |
| 8 | `UT_ST_IDLE_GROUP` | `Idle: in group` | normal |
| 9 | `UT_ST_EXERCISING` | `Exercising` | normal |
| 10 | `UT_ST_PRIMING` | `Priming` | normal |
| 11 | `UT_ST_HIGH_FLOAT` | `Running: high float` | normal |
| 12 | `UT_ST_MIN_RUN` | `Running: min run time` | normal |
| 13 | `UT_ST_STOP_DELAY` | `Running: stop delay` | normal |
| 14 | `UT_ST_RUN_TIMED` | `Running: timed` | normal |
| 15 | `UT_ST_RUN_DEMAND` | `Running: demand` | normal |
| 16 | `UT_ST_RUN_TIME` | `Running: by time` | normal |
| 17 | `UT_ST_RUN_VOLUME` | `Running: by volume` | normal |
| 18 | `UT_ST_RUN_REMOTE` | `Running: remote held` | normal |
| 19 | `UT_ST_RUN_UNTIL_STOP` | `Running: until stopped` | normal |
| 20 | `UT_ST_RESUMED` | `Running: resumed` | normal |
| 21 | `UT_ST_RESTARTED` | `Running: restarted` | normal |
| 22 | `UT_ST_OPENING` | `Opening` | normal |
| 23 | `UT_ST_CLOSING` | `Closing` | normal |
| 24 | `UT_ST_OPEN` | `Open` | normal |
| 25 | `UT_ST_CLOSED` | `Closed` | normal |
| 26 | `UT_ST_MOVING` | `Moving` | normal |
| 27 | `UT_ST_HOMING` | `Homing` | normal |
| 28 | `UT_ST_AT_POSITION` | `At position` | normal |
| 29 | `UT_ST_BETWEEN` | `Stopped between positions` | normal |
| 30 | `UT_ST_POS_UNKNOWN` | `Position unknown` | normal |
| 31 | `UT_ST_STAR` | `Starting: star` | normal |
| 32 | `UT_ST_LOW_FIRST` | `Starting: low speed first` | normal |
| 33 | `UT_ST_SKIP_EDGE` | `Running: at skip band edge` | normal |
| 34 | `UT_ST_OK` | `OK` | normal |
| 35 | `UT_ST_BYPASSED` | `Bypassed` | normal |
| 36 | `UT_ST_RUNNING` | `Running` | normal |
| 37 | `UT_ST_STOPPED` | `Stopped` | normal |
| 38 | `UT_ST_STILL_TURNING` | `Stopped: still turning` | normal |
| 39 | `UT_ST_CHECKS_DELAY` | `Starting: checks delayed` | normal |
| 40 | `UT_ST_IDLE_NO_DEMAND` | `Idle: no demand` | normal |
| 41 | `UT_ST_IDLE_LEVEL_REACHED` | `Idle: demand level reached` | normal |
| 42 | `UT_ST_IDLE_HAND` | `Idle: Hand, command off` | normal |
| 43 | `UT_ST_AUTO` | `Auto` | normal |
| 44 | `UT_ST_MANUAL_LOCAL` | `Manual: running (local)` | normal |
| 45 | `UT_ST_MANUAL_REMOTE` | `Manual: running (remote)` | normal |
| 46 | `UT_ST_IDLE_MANUAL` | `Idle: Manual, no run request` | normal |
| 47 | `UT_ST_LOCAL` | `Local control` | normal |
| 48 | `UT_ST_LOCAL_REMOTE` | `Local and remote` | normal |
| 49 | `UT_ST_RUN_ALL` | `Running: all steps` | normal |
| 50 | `UT_ST_RUN_PART` | `Running: part` | normal |
| 51 | `UT_ST_OFF_ABORTED` | `Off: aborted` | normal |
| 52 | `UT_ST_RUN_STEP` | `Running: step` | normal |
| 53 | `UT_ST_CLEANING` | `Cleaning` | normal |
| 54 | `UT_ST_CLEAN_NEXT` | `Cleaning: waiting next cycle` | normal |
| 55 | `UT_ST_RUN_ZONE` | `Running: zone` | normal |
| 56 | `UT_ST_DOSE_FAST` | `Dosing fast` | normal |
| 57 | `UT_ST_DOSE_SLOW` | `Dosing slow` | normal |
| 58 | `UT_ST_SETTLING` | `Settling` | normal |
| 59 | `UT_ST_DOSE_FLOW` | `Dosing: flow-paced` | normal |
| 60 | `UT_ST_DOSE_TIMED` | `Dosing: timed` | normal |
| 61 | `UT_ST_DOSE_NEXT` | `Timed: waiting next dose` | normal |
| 62 | `UT_ST_DONE` | `Idle: done` | normal |
| 63 | `UT_ST_ABORTED` | `Idle: aborted` | normal |
| 64 | `UT_ST_IDLE_NOT_ENABLED` | `Idle: not enabled` | normal |
| 65 | `UT_ST_HOLDING` | `Running: holding setpoint` | normal |
| 66 | `UT_ST_PIPE_FILL` | `Pipe fill` | normal |
| 67 | `UT_ST_BOOST` | `Boost before sleep` | normal |
| 68 | `UT_ST_MAX_SPEED` | `Max speed, below setpoint` | normal |
| 69 | `UT_ST_FLOW_LIMIT` | `Running: flow limit` | normal |
| 70 | `UT_ST_FALLBACK` | `Running: fallback speed` | normal |
| 71 | `UT_ST_MANUAL_SPEED` | `Running: manual speed` | normal |
| 72 | `UT_ST_SLEEPING` | `Sleeping` | normal |
| 73 | `UT_ST_ADDING` | `Adding a pump` | normal |
| 74 | `UT_ST_DROPPING` | `Dropping a pump` | normal |
| 75 | `UT_ST_JOCKEY` | `Jockey running` | normal |
| 76 | `UT_ST_SWAPPING` | `Swapping pumps (rotation)` | normal |
| 77 | `UT_ST_LINK_OK` | `Link OK` | normal |
| 78 | `UT_ST_PRE_RUN` | `Running: pre-run` | normal |
| 79 | `UT_ST_POST_RUN` | `Running: post-run` | normal |
| 80 | `UT_ST_RUN_WITH_PUMP` | `Running: with pump` | normal |
| 81 | `UT_ST_RESTART_DELAY` | `Waiting: restart delay` | held |
| 82 | `UT_ST_INTERLOCK` | `Blocked: interlock` | held |
| 83 | `UT_ST_NOT_PERMITTED` | `Not permitted` | held |
| 84 | `UT_ST_HAND_PRESS_START` | `Hand: press start` | held |
| 85 | `UT_ST_START_BLOCKED` | `Blocked: start block` | held |
| 86 | `UT_ST_WAIT_GROUP` | `Waiting: turn in group` | held |
| 87 | `UT_ST_HAND_MAX_RUN` | `Hand: max run, press start` | held |
| 88 | `UT_ST_MUST_CYCLE` | `Waiting: command must cycle` | held |
| 89 | `UT_ST_OOS` | `Out of service` | held |
| 90 | `UT_ST_DEAD_TIME` | `Waiting: dead time` | held |
| 91 | `UT_ST_START_DELAY` | `Waiting: start delay` | held |
| 92 | `UT_ST_MIN_OFF` | `Waiting: min off time` | held |
| 93 | `UT_ST_INHIBITED` | `Blocked: inhibit` | held |
| 94 | `UT_ST_MOTOR_NOT_AUTO` | `Blocked: motor not in Auto` | held |
| 95 | `UT_ST_MOTOR_NOT_READY` | `Blocked: motor not ready` | held |
| 96 | `UT_ST_FULL` | `Blocked: high float (full)` | held |
| 97 | `UT_ST_TIMED_REST` | `Waiting: timed rest` | held |
| 98 | `UT_ST_STOPPED_LOW` | `Stopped: low level` | held |
| 99 | `UT_ST_STOPPED_FULL` | `Stopped: full` | held |
| 100 | `UT_ST_PAUSED` | `Paused: not running` | held |
| 101 | `UT_ST_ABORT` | `Blocked: abort` | held |
| 102 | `UT_ST_WAIT_POWERUP` | `Waiting: start again` | held |
| 103 | `UT_ST_NOT_HOMED` | `Hand: not homed` | held |
| 104 | `UT_ST_MOVE_TIMEOUT` | `Waiting: new request` | held |
| 105 | `UT_ST_WAIT_MAIN_FB` | `Waiting: main contactor` | held |
| 106 | `UT_ST_WAIT_OPEN` | `Waiting: contactor to open` | held |
| 107 | `UT_ST_REFUSED_LOCAL` | `Refused: local control` | held |
| 108 | `UT_ST_REFUSED_LOCAL_ONLY` | `Refused: local only` | held |
| 109 | `UT_ST_FORCED_OFF` | `Blocked: forced off` | held |
| 110 | `UT_ST_SELECT_MODE` | `Waiting: select a mode` | held |
| 111 | `UT_ST_SELECTOR_HAND` | `Waiting: selector out of Hand` | held |
| 112 | `UT_ST_MANUAL_MAX_RUN` | `Manual: max run, release run` | held |
| 113 | `UT_ST_REMOTE_REFUSED` | `Blocked: remote run refused` | held |
| 114 | `UT_ST_COMMS_LOST` | `Blocked: comms lost` | held |
| 115 | `UT_ST_RESET_NEEDED` | `Waiting: reset` | held |
| 116 | `UT_ST_AUTO_RESTART` | `Waiting: auto restart` | held |
| 117 | `UT_ST_HELD` | `Held` | held |
| 118 | `UT_ST_PAUSED_HOLD` | `Paused: Hold input` | held |
| 119 | `UT_ST_PAUSED_START` | `Paused: press Start` | held |
| 120 | `UT_ST_WAIT_CONDITION` | `Waiting: step condition` | held |
| 121 | `UT_ST_WAIT_DEMAND_DROP` | `Waiting: demand to drop` | held |
| 122 | `UT_ST_PAUSED_RAIN` | `Paused: rain` | held |
| 123 | `UT_ST_PAUSED_INPUT` | `Paused: Pause input` | held |
| 124 | `UT_ST_PUMP_FAULT_HOLD` | `Blocked: pump fault` | held |
| 125 | `UT_ST_WAIT_PUMP` | `Waiting: pump not running` | held |
| 126 | `UT_ST_SOAK` | `Waiting: soak` | held |
| 127 | `UT_ST_LOW_CARRIER` | `Waiting: carrier flow low` | held |
| 128 | `UT_ST_ENABLE_CYCLE` | `Waiting: Enable must cycle` | held |
| 129 | `UT_ST_DRIVE_NOT_RUNNING` | `Waiting: drive not running` | held |
| 130 | `UT_ST_STAGE_DELAY` | `Waiting: stage delay` | held |
| 131 | `UT_ST_PUMP_DELAY` | `Waiting: pump own delay` | held |
| 132 | `UT_ST_MAX_RUNNING` | `Waiting: max running reached` | held |
| 133 | `UT_ST_LOW_FLOAT` | `Blocked: low float (dry)` | held |
| 134 | `UT_ST_FAILOVER` | `Waiting: start failed, next` | held |
| 135 | `UT_ST_SHORTFALL` | `Shortfall: too few available` | held |
| 136 | `UT_ST_DRIVE_NOT_READY` | `Blocked: drive not ready` | held |
| 137 | `UT_ST_DEFER_MANUAL` | `Deferred: manual` | held |
| 138 | `UT_ST_DEFER_REMOTE` | `Deferred: remote` | held |
| 139 | `UT_ST_DEFER_RAIN` | `Deferred: rain` | held |
| 140 | `UT_ST_DEFER_SOIL` | `Deferred: soil wet` | held |
| 141 | `UT_ST_DEFER_SENSOR` | `Deferred: sensor lost` | held |
| 142 | `UT_ST_DEFER_CLEARING` | `Deferred: clearing` | held |
| 143 | `UT_ST_WARNING` | `Warning: ` + the fault's words | warning |
| 144 | `UT_ST_WARN_SETTING` | `Setting: ` + the fault's words | warning |
| 145 | `UT_ST_LINK_RESTART` | `Link down: modem restart` | warning |
| 146 | `UT_ST_LINK_POWER_CYCLE` | `Link down: power cycle` | warning |
| 147 | `UT_ST_LINK_REBOOT` | `Link down: reboot` | warning |
| 148 | `UT_ST_LINK_REBOOT_WAITS` | `Link down: reboot not allowed` | warning |
| 149 | `UT_ST_LINK_NO_STEPS` | `Link down: no more steps` | warning |
| 150 | `UT_ST_LINK_RETRY` | `Link down: retry` | warning |
| 151 | `UT_ST_LINK_REBOOTING` | `Link down: rebooting` | warning |
| 152 | `UT_ST_FAULT` | `Fault: ` + the fault's words | fault |
| 153 | `UT_ST_FAULT_RETRY` | `Retrying: ` + the fault's words | fault |
| 154 | `UT_ST_FAULT_RESET` | `Latched: ` + the fault's words | fault |
| 155 | `UT_ST_FAULT_LOCKED` | `Locked: ` + the fault's words | fault |
| 156 | `UT_ST_FLOAT_CONTROL` | `Float control` | fault |
| 157 | `UT_ST_FLOAT_LOCKOUT` | `Float lockout` | fault |
| 158 | `UT_ST_CONFIG` | `Config: ` + the setting's words | config |
| 159 | `UT_ST_FIXED_SPEED` | `Running: fixed speed` | normal |
| 160 | `UT_ST_START_HOLD` | `Waiting: start hold` | held |
| 161 | `UT_ST_WAIT_PROVEN` | `Waiting: valve proven` | held |
| 162 | `UT_ST_FLOAT_RUN` | `Running: on floats` | normal |

#### UT_FAULT: which fault, warning or setting (`faultId`)

| No. | Name | Words | Kind |
| --- | --- | --- | --- |
| 0 | `UT_F_NONE` | (none) | none |
| 1 | `UT_F_OVERLOAD` | `overload` | fault / warning |
| 2 | `UT_F_MOTOR_HOT` | `motor too hot` | fault / warning |
| 3 | `UT_F_NO_FEEDBACK` | `no run feedback` | fault / warning |
| 4 | `UT_F_FEEDBACK_LOST` | `feedback lost` | fault / warning |
| 5 | `UT_F_WELDED` | `contactor welded` | fault / warning |
| 6 | `UT_F_CURRENT_HIGH` | `current high` | fault / warning |
| 7 | `UT_F_CURRENT_LOW` | `current low` | fault / warning |
| 8 | `UT_F_DRIVE` | `drive fault` | fault / warning |
| 9 | `UT_F_CURRENT_BAD` | `current signal` | fault / warning |
| 10 | `UT_F_SPEED_DEV` | `speed deviation` | fault / warning |
| 11 | `UT_F_CHANGEOVER` | `changeover` | fault / warning |
| 12 | `UT_F_DRIVE_NOT_READY` | `drive not ready` | fault / warning |
| 13 | `UT_F_DRY_RUN` | `dry run` | fault / warning |
| 14 | `UT_F_PRESSURE_HH` | `pressure HH` | fault / warning |
| 15 | `UT_F_PRESSURE_LL` | `pressure LL` | fault / warning |
| 16 | `UT_F_NO_FLOW` | `no flow` | fault / warning |
| 17 | `UT_F_FLOW_HH` | `flow HH` | fault / warning |
| 18 | `UT_F_SUCTION_HH` | `suction HH` | fault / warning |
| 19 | `UT_F_PRIME` | `failed to prime` | fault / warning |
| 20 | `UT_F_EXTERNAL` | `external fault` | fault / warning |
| 21 | `UT_F_MAX_RUN` | `ran too long` | fault / warning |
| 22 | `UT_F_SEAL_LEAK` | `seal leak` | fault / warning |
| 23 | `UT_F_PRESSURE_H` | `pressure high` | fault / warning |
| 24 | `UT_F_PRESSURE_L` | `pressure low` | fault / warning |
| 25 | `UT_F_FLOW_H` | `flow high` | fault / warning |
| 26 | `UT_F_FLOW_L` | `flow low` | fault / warning |
| 27 | `UT_F_SUCTION_H` | `suction high` | fault / warning |
| 28 | `UT_F_SUCTION_L` | `suction low` | fault / warning |
| 29 | `UT_F_POINTS` | `start/stop points` | fault / warning |
| 30 | `UT_F_PV_BAD` | `Pv not a number` | fault / warning |
| 31 | `UT_F_SENSOR_BAD` | `sensor bad` | fault / warning |
| 32 | `UT_F_OPEN_TIMEOUT` | `open timeout` | fault / warning |
| 33 | `UT_F_CLOSE_TIMEOUT` | `close timeout` | fault / warning |
| 34 | `UT_F_BOTH_LIMITS` | `both limits` | fault / warning |
| 35 | `UT_F_POS_LOST` | `position lost` | fault / warning |
| 36 | `UT_F_NO_MOVEMENT` | `did not move` | fault / warning |
| 37 | `UT_F_ACTUATOR` | `actuator fault` | fault / warning |
| 38 | `UT_F_POS_DEVIATION` | `pos. deviation` | fault / warning |
| 39 | `UT_F_POS_FEEDBACK` | `position signal` | fault / warning |
| 40 | `UT_F_TRANSDUCER` | `transducer` | fault / warning |
| 41 | `UT_F_LEVEL_BAD` | `level signal bad` | fault / warning |
| 42 | `UT_F_NO_PUMP` | `no pump ready` | fault / warning |
| 43 | `UT_F_FLOAT_DISAGREE` | `level vs high float` | fault / warning |
| 44 | `UT_F_CLEAN_TIME` | `cleaning too long` | fault / warning |
| 45 | `UT_F_FLOW_BAD` | `flow signal bad` | fault / warning |
| 46 | `UT_F_FLOW_SHORT` | `flow staging short` | fault / warning |
| 47 | `UT_F_HIGH_FLOW` | `high flow` | fault / warning |
| 48 | `UT_F_OVERPRESSURE` | `overpressure` | fault / warning |
| 49 | `UT_F_LOW_AT_MAX` | `low at max speed` | fault / warning |
| 50 | `UT_F_PIPE_FILL` | `pipe fill time` | fault / warning |
| 51 | `UT_F_NOT_REACHING` | `below setpoint` | fault / warning |
| 52 | `UT_F_HUNTING` | `loop hunting` | fault / warning |
| 53 | `UT_F_START_FAILED` | `failed to start` | fault / warning |
| 54 | `UT_F_DOSE_NO_FLOW` | `no dose flow` | fault / warning |
| 55 | `UT_F_DOSE_TOO_LONG` | `dose too long` | fault / warning |
| 56 | `UT_F_PUMP_TOO_SMALL` | `pump too small` | fault / warning |
| 57 | `UT_F_TOLERANCE` | `out of tolerance` | fault / warning |
| 58 | `UT_F_FLOW_NAN` | `Flow not a number` | fault / warning |
| 59 | `UT_F_ACTUAL_NAN` | `Actual not a number` | fault / warning |
| 60 | `UT_F_STALLED` | `stalled` | fault / warning |
| 61 | `UT_F_UNDERSPEED` | `underspeed` | fault / warning |
| 62 | `UT_F_OVERSPEED` | `overspeed` | fault / warning |
| 63 | `UT_F_PULSES_STOPPED` | `turning when off` | fault / warning |
| 64 | `UT_F_PULSES_FAST` | `pulses too fast` | fault / warning |
| 65 | `UT_F_HIGH_HIGH` | `high-high` | fault / warning |
| 66 | `UT_F_HIGH` | `high` | fault / warning |
| 67 | `UT_F_LOW` | `low` | fault / warning |
| 68 | `UT_F_LOW_LOW` | `low-low` | fault / warning |
| 69 | `UT_F_VALUE_BAD` | `value not a number` | fault / warning |
| 70 | `UT_F_STEP_NO_STOP` | `step not stopped` | fault / warning |
| 71 | `UT_F_STEP_NO_FB` | `step no feedback` | fault / warning |
| 72 | `UT_F_STEP_FB_LOST` | `step fb lost` | fault / warning |
| 73 | `UT_F_STEP_TIMEOUT` | `step timed out` | fault / warning |
| 74 | `UT_F_NO_STEPS` | `no steps to run` | fault / warning |
| 75 | `UT_F_ZONE_FLOW` | `zone flow` | fault / warning |
| 76 | `UT_F_PUMP_FAULT` | `pump fault` | fault / warning |
| 77 | `UT_F_LEVEL_ABOVE_FULL` | `level above full` | fault / warning |
| 78 | `UT_F_CONDITION` | `condition` | fault / warning |
| 79 | `UT_F_IO_MISSING` | `IO module missing` | fault / warning |
| 80 | `UT_F_IO_BAD` | `IO channel bad` | fault / warning |
| 81 | `UT_F_IO_FORCED` | `IO forced` | fault / warning |
| 82 | `UT_F_NO_PRE_RUN` | `no pre-run` | fault / warning |
| 83 | `UT_F_BELOW_MIN` | `below minimum` | fault / warning |
| 84 | `UT_F_ABOVE_MAX` | `above maximum` | fault / warning |
| 85 | `UT_F_NOT_ABOVE` | `not above related` | fault / warning |
| 86 | `UT_F_NOT_BELOW` | `not below related` | fault / warning |
| 87 | `UT_F_LIMITS` | `limits not valid` | fault / warning |
| 88 | `UT_F_SETTING` | `a setting` | setting |
| 89 | `UT_F_FLC` | `full load current` | setting |
| 90 | `UT_F_CURRENT_NEEDS_FLC` | `current needs FLC` | setting |
| 91 | `UT_F_START_MASK` | `start mask` | setting |
| 92 | `UT_F_RESTART_DELAY` | `restart delay` | setting |
| 93 | `UT_F_HAND_MAX_RUN` | `hand max run` | setting |
| 94 | `UT_F_REVERSAL_DELAY` | `reversal delay` | setting |
| 95 | `UT_F_TRANSITION_TIME` | `transition time` | setting |
| 96 | `UT_F_STAR_CURRENT` | `star current %` | setting |
| 97 | `UT_F_STAR_NEEDS_FLC` | `star % needs FLC` | setting |
| 98 | `UT_F_STAR_TIME` | `star time` | setting |
| 99 | `UT_F_SPEED_CHANGE` | `speed change delay` | setting |
| 100 | `UT_F_LOW_START_TIME` | `low start time` | setting |
| 101 | `UT_F_MIN_MAX_SPEED` | `min / max speed` | setting |
| 102 | `UT_F_RAW_MIN_MAX` | `raw min / max` | setting |
| 103 | `UT_F_ACCEL_RATE` | `accel / decel rate` | setting |
| 104 | `UT_F_SKIP_BAND` | `skip band` | setting |
| 105 | `UT_F_HAND_SPEED` | `hand speed` | setting |
| 106 | `UT_F_RESET_PULSE` | `reset pulse` | setting |
| 107 | `UT_F_RATE_UNIT` | `rate unit` | setting |
| 108 | `UT_F_RATED_HZ_RPM` | `rated Hz / rpm` | setting |
| 109 | `UT_F_PUMP_MODE` | `pump mode` | setting |
| 110 | `UT_F_PRIME_DONEBY` | `prime doneBy` | setting |
| 111 | `UT_F_PRESSURE_SENSOR` | `pressure sensor` | setting |
| 112 | `UT_F_FLOW_SENSOR` | `flow sensor` | setting |
| 113 | `UT_F_SUCTION_SENSOR` | `suction sensor` | setting |
| 114 | `UT_F_RESPONSE` | `response unknown` | setting |
| 115 | `UT_F_PRIME_NEEDS_PRES` | `prime: no pressure` | setting |
| 116 | `UT_F_PRIME_NEEDS_FLOW` | `prime: no flow` | setting |
| 117 | `UT_F_RUN_TIME` | `run time` | setting |
| 118 | `UT_F_TARGET_VOLUME` | `target volume` | setting |
| 119 | `UT_F_SAVE_EVERY` | `save every` | setting |
| 120 | `UT_F_RETRY_WINDOW` | `retry window` | setting |
| 121 | `UT_F_MODE_SOURCE` | `mode source` | setting |
| 122 | `UT_F_VALVE_TYPE` | `valve type` | setting |
| 123 | `UT_F_TRAVEL_TIME` | `open / close time` | setting |
| 124 | `UT_F_PULSE_TIME` | `pulse time` | setting |
| 125 | `UT_F_SAFE_POSITION` | `safe position` | setting |
| 126 | `UT_F_THREE_POS_TYPE` | `three-position type` | setting |
| 127 | `UT_F_MID_TIME` | `travel / mid time` | setting |
| 128 | `UT_F_OUTPUT_MIN_MAX` | `output min / max` | setting |
| 129 | `UT_F_RAMP_RATE` | `ramp rate` | setting |
| 130 | `UT_F_SHUTOFF` | `shutoff / full open` | setting |
| 131 | `UT_F_FAIL_POSITION` | `fail position` | setting |
| 132 | `UT_F_OPEN_THRESHOLD` | `open/closed limit` | setting |
| 133 | `UT_F_DEADBAND` | `deadband` | setting |
| 134 | `UT_F_STROKE_TIME` | `stroke time` | setting |
| 135 | `UT_F_MIN_PULSE` | `min pulse/overtravel` | setting |
| 136 | `UT_F_STATION_MODE` | `station mode` | setting |
| 137 | `UT_F_STAGE1` | `stage 1 start / stop` | setting |
| 138 | `UT_F_SETPOINT` | `setpoint` | setting |
| 139 | `UT_F_KP` | `kp` | setting |
| 140 | `UT_F_RATE_LIMIT` | `rate limit` | setting |
| 141 | `UT_F_START_SPEED` | `start/fallback speed` | setting |
| 142 | `UT_F_DOSE_MODE` | `dose mode` | setting |
| 143 | `UT_F_TIMED_ON_OFF` | `timed on / off time` | setting |
| 144 | `UT_F_NO_TARGET` | `no target set` | setting |
| 145 | `UT_F_NO_CAPACITY` | `no capacity / ratio` | setting |
| 146 | `UT_F_DIAMETER` | `diameter` | setting |
| 147 | `UT_F_TANK_HEIGHT` | `tank height` | setting |
| 148 | `UT_F_LENGTH_WIDTH` | `length / width` | setting |
| 149 | `UT_F_CONE` | `cone / outlet` | setting |
| 150 | `UT_F_FRACTION` | `fraction` | setting |
| 151 | `UT_F_DENSITY` | `density` | setting |
| 152 | `UT_F_DEAD_VOLUME` | `dead volume` | setting |
| 153 | `UT_F_LEVEL_OFFSET` | `level offset` | setting |
| 154 | `UT_F_LEVEL_RANGE` | `level % range` | setting |
| 155 | `UT_F_UNIT` | `unit unknown` | setting |
| 156 | `UT_F_DIST_PER_PULSE` | `distance per pulse` | setting |
| 157 | `UT_F_SPEED_UNIT` | `speed unit` | setting |
| 158 | `UT_F_MANUAL_MAX_RUN` | `manual max run` | setting |
| 159 | `UT_F_NO_OUTPUTS` | `no outputs` | setting |
| 160 | `UT_F_ALL_SKIPPED` | `all channels skipped` | setting |
| 161 | `UT_F_DEFAULT_SP` | `default setpoint` | setting |
| 162 | `UT_F_VALVE_PUMP_TIME` | `valve / pump time` | setting |
| 163 | `UT_F_SP_ORDER` | `setpoint order` | setting |
| 164 | `UT_F_LEVEL_SETTING` | `a level` | setting |
| 165 | `UT_F_NO_CONDITIONS` | `no conditions` | setting |
| 166 | `UT_F_BYPASS_TIMEOUT` | `bypass timeout` | setting |
| 167 | `UT_F_BAD_NEXT` | `next outside recipe` | setting |
| 168 | `UT_F_ENDLESS_LOOP` | `endless loop` | setting |
| 169 | `UT_F_STOP_STEP` | `stop step` | setting |
| 170 | `UT_F_CHAIN` | `chain setting` | setting |
| 171 | `UT_F_STEP_SETTING` | `step setting` | setting |
| 172 | `UT_F_GROUP_SETTING` | `group setting` | setting |
| 173 | `UT_F_NO_UNITS` | `no units in array` | setting |
| 174 | `UT_F_IO_ADDRESS` | `IO address` | setting |
| 175 | `UT_F_IO_NOT_FITTED` | `IO not fitted` | setting |
| 176 | `UT_F_IO_SHARED` | `output used twice` | setting |
| 177 | `UT_F_FORCE_TIME` | `force time` | setting |
| 178 | `UT_F_PRE_POST_RUN` | `pre/post-run time` | setting |
| 179 | `UT_F_DEFER_DELAY` | `defer delay` | setting |
| 180 | `UT_F_NOT_PROVEN` | `valve not proven` | fault |
| 181 | `UT_F_PUMPS_USED` | `pumps used` | setting |
| 182 | `UT_F_VALVE_DRIVE` | `valve drive` | setting |

#### UT_STOP: why the last run ended (`stopReason`)

| No. | Name | Words (`UT_STOP_TEXT`) |
| --- | --- | --- |
| 0 | `UT_STOP_NONE` | (empty) |
| 1 | `UT_STOP_DEMAND_ENDED` | `Auto: demand ended` |
| 2 | `UT_STOP_OPERATOR` | `Stopped: operator` |
| 3 | `UT_STOP_SWITCHED_OFF` | `Stopped: switched off` |
| 4 | `UT_STOP_INTERLOCK` | `Stopped: interlock` |
| 5 | `UT_STOP_FAULT` | `Stopped: fault` |
| 6 | `UT_STOP_MAX_RUN` | `Stopped: max run time` |
| 7 | `UT_STOP_DONE` | `Done` |
| 8 | `UT_STOP_ABORTED` | `Stopped: aborted` |
| 9 | `UT_STOP_INHIBITED` | `Stopped: inhibited` |
| 10 | `UT_STOP_COMMS_LOST` | `Stopped: comms lost` |
| 11 | `UT_STOP_GROUP` | `Stopped: group` |
| 12 | `UT_STOP_LOW_LEVEL` | `Stopped: low level` |
| 13 | `UT_STOP_FULL` | `Stopped: full` |
| 14 | `UT_STOP_EXERCISE_DONE` | `Done: exercise` |
| 15 | `UT_STOP_BY_MOTOR` | `Stopped: by the motor` |
| 16 | `UT_STOP_REMOTE_OFF` | `Stopped: remote off` |
| 17 | `UT_STOP_NOT_PERMITTED` | `Stopped: not permitted` |
| 18 | `UT_STOP_PAUSED_LONG` | `Stopped: paused too long` |
| 19 | `UT_STOP_SETTING` | `Stopped: setting invalid` |
| 20 | `UT_STOP_POWER_CUT` | `Stopped: power cut` |
| 21 | `UT_STOP_RAIN` | `Stopped: rain` |
| 22 | `UT_STOP_PUMP_FAULT` | `Stopped: pump fault` |
| 23 | `UT_STOP_STEP_TIMEOUT` | `Stopped: step timeout` |
| 24 | `UT_STOP_REFUSED` | `Stopped: recipe refused` |
| 25 | `UT_STOP_ABORT_CMD` | `Stopped: aborted (HMI)` |
| 26 | `UT_STOP_ASLEEP` | `Asleep: demand met` |
| 27 | `UT_STOP_LEVEL_BAD` | `Stopped: level signal bad` |
| 28 | `UT_STOP_CLEAN_TIMEOUT` | `Stopped: cleaning too long` |

## Time visibility
**Every block that times something shows the time**, so an HMI or SCADA can show a
countdown without parsing text:

| Field | Type | What it is |
| --- | --- | --- |
| `timeLeft` | TIME | The countdown its status is showing (delay, wait, run time left …). `T#0s` when nothing counts |
| `phaseTime` | TIME | Where useful: time spent in the current phase or step so far |

They are in the block's record, or are outputs on blocks without one. Every
protection has its own `timeLeft` ([`UT_PROTECTION`](#ut_protection-settings--status-in-one)).
The status text holds no numbers: show `timeLeft` beside it.
[UT_TIME_TEXT](blocks/UT_TIME_TEXT.md) turns it into short text (`1 h 20 m`) for a
simple display.

## Why it stopped
The motor, valve, pump, pump station, pump cascade, speed-control and dose records
keep why the last run ended and the last trip, so "what happened overnight" can be
read after the fact:

| Field | Type | What it is |
| --- | --- | --- |
| `stopReason` | UT_STOP | Why the last run ended. Set when a run ends, kept until the next run ends. `UT_STOP_NONE` (0) = none since power-up |
| `lastFaultCode` | DWORD | The `faultCode` bits of the last trip, kept after it clears, until the next trip |
| `lastFault` | UT_FAULT | The last trip by name, kept the same way |
| `trips` | UDINT | Trips since power-up (not kept over a power cut) |

UT_RUN_LIMIT and UT_ZONE_SEQ keep `endReason`, and UT_STEP_SEQ `lastResult`, of the
same type. The numbers are in the [UT_STOP table](#ut_stop-why-the-last-run-ended-stopreason)
above; [UT_STOP_TEXT](blocks/UT_STOP_TEXT.md) gives the words. The common ones:

| Name | Words | Meaning |
| --- | --- | --- |
| `UT_STOP_NONE` | (empty) | No run has ended since power-up |
| `UT_STOP_DEMAND_ENDED` | `Auto: demand ended` | The Auto command or demand dropped: a normal stop |
| `UT_STOP_OPERATOR` | `Stopped: operator` | A stop in Hand: `cmdStop`, a stop button, `HandCmd` dropped |
| `UT_STOP_SWITCHED_OFF` | `Stopped: switched off` | The mode changed to Off or OOS |
| `UT_STOP_INTERLOCK` | `Stopped: interlock` | The interlock dropped |
| `UT_STOP_FAULT` | `Stopped: fault` | A protection tripped (`lastFault` says which) |
| `UT_STOP_MAX_RUN` | `Stopped: max run time` | A run-time limit ran out |
| `UT_STOP_DONE` | `Done` | A timed or metered run finished |
| `UT_STOP_ABORTED` | `Stopped: aborted` | `Abort`, `cmdAbort` |
| `UT_STOP_INHIBITED` | `Stopped: inhibited` | An inhibit or a plant-level off (`ForceOff`, system Off) |
| `UT_STOP_COMMS_LOST` | `Stopped: comms lost` | A remote run request was dropped on lost comms |
| `UT_STOP_GROUP` | `Stopped: group` | A group block (duty, station, cascade) stopped it |

The other members are used by the blocks named in their docs.

## Signal quality — `UT_QUALITY`
`UT_Q_BAD` (0) · `UT_Q_UNCERTAIN` · `UT_Q_GOOD` · `UT_Q_SIM`. A block that isn't
running reports BAD, never a stale GOOD. This matches the BeeBus topic quality.

## Other shared enums
| Enum | Values (first = 0) |
| --- | --- |
| `UT_PRIORITY` | `UT_PRIO_LOW`, `UT_PRIO_MEDIUM`, `UT_PRIO_HIGH`, `UT_PRIO_CRITICAL` |
| `UT_RATE_UNIT` | `UT_PER_SEC`, `UT_PER_MIN`, `UT_PER_HOUR`, `UT_PER_DAY` |
| `UT_VOL_UNIT` | `UT_VOL_NONE` (no conversion: the block's own unit), `UT_VOL_L`, `UT_VOL_M3`, `UT_VOL_ML` (megalitre) |
| `UT_ROTATE_MODE` | `UT_ROT_FIXED`, `UT_ROT_EACH_START`, `UT_ROT_HOURS`, `UT_ROT_INTERVAL` |
| `UT_POWERUP` | `UT_PU_LAST` (default: the mode comes back), `UT_PU_OFF` |
| `UT_HAND_POWERUP` | `UT_HPU_OFF` (default: a Hand comes back Off), `UT_HPU_KEEP` |
| `UT_RUN_POWERUP` | `UT_RPU_RESUME` (default: a run carries on), `UT_RPU_RESTART`, `UT_RPU_NONE` (declared with UT_RUN_LIMIT) |
| `UT_CMD_FROM` | `UT_FROM_NONE`, `UT_FROM_LOCAL`, `UT_FROM_REMOTE` |
| `UT_UNIT` | `UT_UNIT_NONE`, then pressure, flow, volume, temperature and length units (see [UT_UNIT_CONV](blocks/UT_UNIT_CONV.md)) |

## Simulation
Device and signal blocks have `simulate : BOOL`. Feedbacks follow commands after a
realistic delay, signal blocks use `simValue`, and quality shows `UT_Q_SIM`. Use it
for commissioning and FAT. In the motor blocks simulation fakes **only the run
feedback**: the feedback checks (`noFeedback`, `feedbackLost`, `stuck`) see the
simulated one, and every other protection (overload, thermistor, drive fault,
`driveNotReady`, the current levels) still acts.

## Retained data
Retain is kept to a minimum. Over a power cut the library keeps **only**, inside
the block:

1. **The device's HMI mode** (`UT_MODE_SELECT`: every motor and valve block, and
   `UT_HOA`; a pump's mode is its motor block's), and the plant mode and auto type
   of `UT_SYSTEM_MODE`. Whether the mode is used after a power cut is the device's
   `powerUp` setting.
2. **Run hours, starts and valve strokes**: `UT_RUN_HOURS` (total, service, today,
   yesterday), `UT_STARTS` (lifetime, today, yesterday) and the valves' stroke count.
3. **Flow / volume totals and dose totals**: `UT_TOTALISER` (every total, with what
   it needs to stay correct and never count twice) and `UT_DOSE` (`doses`,
   `dosedTotal`).
4. **The progress of a run or zone program in progress**, for its `powerUp`
   (`UT_RPU_RESUME` carries it on): [UT_RUN_LIMIT](blocks/UT_RUN_LIMIT.md) (whether
   a run is active, how it started, whether `RunHeld` is on, its running time and
   volume) and [UT_ZONE_SEQ](blocks/UT_ZONE_SEQ.md) (whether a program is running, how
   it started, the zone watering with its water time, volume and cycles, the pass,
   the HMI pause). Also `UT_RUN_LIMIT`'s last-run summary, saved once per run end.

**Nothing else is kept.** Protection trips are not kept: a latched or MANUAL trip
is forgotten at power-up, and if the fault is still there it trips again. Inhibits,
retries, a dose in progress, a learned preact, alarm
states, leads, statistics, diagnostic counters and toggles all start fresh. (`UT_TONR`, like Siemens TONR and
Rockwell RTO, keeps its time only while the PLC is powered.) This needs only
Persistent Storage switched on in the project. To keep **your settings** across
power loss, declare your record variable `RETAIN`.

**How often values reach storage.** The controller saves all retained values
together, and only when something changed: a change after a quiet spell at once,
then at most once per period (default 10 s runtime, 1 min ESP32, 10 min other
boards). So what a block retains decides how hard it works the flash or EEPROM:

| What | Saved | Why |
| --- | --- | --- |
| The HMI mode, and presets, resets, service resets and rollovers of the counts below | At once | Rare, and must never come back after a power cut |
| Values that count up: starts, run hours, strokes, totals | Every `saveEvery` (default **T#12h**) | They change all the time; a PLC runs 24/7, so a power cut costs at most 12 h of counting |
| A run's or zone program's progress | At its start and end, on a zone, pass or cycle change, and otherwise at most every `progressSave` (default **T#1m**) **while it runs**; nothing while idle | A resume repeats at most `progressSave` of running; a day of irrigation is a few hundred saves |

Blocks that count keep the live value in normal memory and copy it to their
retained snapshot every `saveEvery`. `saveEvery = T#0s` means the count is not
kept over a power cycle at all. At one save per 12 h even an STM32's 10,000-erase flash lasts about
13 years.

Totals and hours are accumulated as 64-bit integers with a fractional remainder,
not as REAL, so they stay exact on every target. On an AVR board LREAL is only 32-bit.

## Timing
All timing uses real elapsed time (`TIME()`, 64-bit, constant within a scan), so
behaviour is identical at any task interval. Pulse inputs are limited by the scan rate (each doc states the limit).

## No blocking code
**No WHILE or REPEAT: every loop has a fixed bound.** A loop is a `FOR` over an
array's bounds or over a small fixed count (leaving early with `EXIT`), or the
work is done with arithmetic. A scan can never hang, and its longest time is known.

## HMI commands
- **A BOOL `cmdXxx` acts once, on its rising edge.** The block keeps the value it
  read the scan before, acts when it goes from FALSE to TRUE, and clears it to
  FALSE. A command that is held or forced TRUE (a Modbus coil left on, a debugger
  force) acts once, not every scan, and acts again only after it has been FALSE.
- **An INT request (`cmdMode`, …) acts when a valid value arrives** (a value that
  differs from the one read the scan before) and is set back to `-1`. An invalid
  value is ignored and also set back to `-1`.
- **Stop / Off always wins** over a start in the same scan.
- **A master that rewrites a value every poll** (a SCADA writing its whole register
  block each cycle), or **two masters** (a panel HMI and SCADA) commanding the same
  device, must not write the record's `cmdXxx` directly: put
  [UT_CMD](blocks/UT_CMD.md) in front. Each master then writes its own variables,
  which nobody clears; UT_CMD reacts only to changes, applies local / remote
  (`RemoteEnabled`), lets stop win and passes one-scan requests into the record.
- Settings written by an HMI or SCADA can be checked before use with
  [UT_SETTING_CHECK](blocks/UT_SETTING_CHECK.md).

## Names
IEC names are case-insensitive: `Count` and `count` in one block clash.
`tools/check-names.py` checks this, the reserved words and the names of every
installed library block.

## Groups
A group block takes an **array of member records**, and each member block uses one
element. See [UT_PUMP_STATION](blocks/UT_PUMP_STATION.md) and [UT_DUTY](blocks/UT_DUTY.md).
