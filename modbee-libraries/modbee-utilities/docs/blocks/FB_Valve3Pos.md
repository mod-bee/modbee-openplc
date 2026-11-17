# FB_Valve3Pos — Three-position valve

A three-position valve: a 3-way diverter, a spring-centred double solenoid, a three-coil valve or a motorised valve with a mid position.

It is **equipment** (it extends `FB_Equipment`): Off / Hand / Auto, an owner that drives it in Auto, interlock and permissive, the restart delay and the part list work as described in [equipment](../conventions.md#equipment-with-an-owner).

Offers `I_LocalChoice`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bLs1` | `BOOL` | `FALSE` | Position 1 switch (with `set.bUseLs1`) |
| in | `bLs2` | `BOOL` |  | Position 2 switch (with `set.bUseLs2`) |
| in | `bLs3` | `BOOL` |  | Position 3 switch (with `set.bUseLs3`) |
| in | `refData` | `REFERENCE TO ST_Valve3PosData` |  | Its record (a variable of this type) |
| in | `bInterlock` | `BOOL` | `TRUE` | FALSE stops it in every mode *(from FB_Equipment)* |
| in | `bPermissive` | `BOOL` | `TRUE` | FALSE blocks a start *(from FB_Equipment)* |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bOut1` | `BOOL` |  | Coil 1 / drive toward 1 |
| out | `bOut2` | `BOOL` |  | Coil 2 (ThreeCoil only) |
| out | `bOut3` | `BOOL` |  | Coil 3 / drive toward 3 |
| out | `nPosition` | `INT` |  | 1..3 reached, -1 moving / not known |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_Valve3PosData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCmdMode` | `INT` | `-1` | 0 Off, 1 Hand, 2 Auto, 3 OutOfService: once, then -1 (cleared; SMS, SCADA) |
| `bCmdStart` | `BOOL` |  | Hand start (rising edge, cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop in Hand and Auto (rising edge, cleared) |
| `bCmdReset` | `BOOL` |  | reset trips whose cause has gone (rising edge, cleared) |
| `nCmdPos` | `INT` | `-1` | Hand position 1..3 (set back to -1) |

**Settings `set`** (`ST_Valve3PosSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_Mode` |  | the operator's choice, kept over a power cut |
| `ePowerUp` | `E_PowerUp` |  | `Last`: back in the mode it had; `Off`: Off after every power-up |
| `tRetryWindow` | `TIME` | `T#1h` | RETRY protections count trips within this window |
| `bResetByOff` | `BOOL` | `TRUE` | switching to Off resets trips whose cause has gone |
| `tHandMax` | `TIME` |  | longest Hand run (0 = no limit) |
| `bRestartAfterReset` | `BOOL` | `TRUE` | After a reset clears a trip, run again at once while the owner still asks (default); FALSE: the owner's request must drop and come back first |
| `bWarnNotAuto` | `BOOL` |  | the owner's request must drop and come back first warn NotAuto while not in Auto and the plant is in Auto |
| `eKind` | `E_Valve3Kind` |  | The kind |
| `bUseLs1` | `BOOL` |  |  |
| `bUseLs2` | `BOOL` |  |  |
| `bUseLs3` | `BOOL` |  |  |
| `tTravel` | `TIME` | `T#10s` | per move: arrival without a switch; the timeout base with one |
| `tMid` | `TIME` |  | motor without bLs2: end -> mid (0 = half tTravel) |
| `tReversal` | `TIME` | `T#500ms` | motor: pause between the two directions |
| `nSafePos` | `INT` | `2` |  |
| `nRestPos` | `INT` | `2` | when nothing is asked |
| `nHandPos` | `INT` | `2` | Hand position (kept) |
| `stTravel` | `ST_ProtectionSet` | `(eResponse := E_Response.Trip, tDelay := T#0s, eReset := E_ResetMode.Retry, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `nAutoPos` | `INT` | `3` | the position asked with no number |
| `bPosLatch` | `BOOL` |  | the last position asked stays when the request ends |

**Status `sts`** (`ST_Valve3PosSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | What it is doing now (status) |
| `eErrorId` | `E_UtError` |  | first-out: the first error since the last reset |
| `eStopReason` | `E_StopReason` |  | Why it last stopped |
| `bRunning` | `BOOL` |  | It runs (status) |
| `bReady` | `BOOL` |  | could start now if asked |
| `bAvailable` | `BOOL` |  | in Auto, not tripped, not interlocked |
| `bLinked` | `BOOL` |  | an owner is driving it |
| `bInterlocked` | `BOOL` |  | The interlock is holding it off |
| `bRefused` | `BOOL` |  | a setting write was refused and put back |
| `bJogging` | `BOOL` |  | jogging (FB_MotorJog, Hand only) |
| `bMustCycle` | `BOOL` |  | a reset cleared a trip: waiting for the request to drop (bRestartAfterReset) |
| `nTargetPos` | `INT` |  | going to (0 = hold) |
| `nActualPos` | `INT` |  | reached (-1 not known) |
| `stTravel` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |

**Totals `tot`** (`ST_ValveTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nStrokes` | `UDINT` |  | Strokes, lifetime (kept hourly) |

## Lists

- `E_Valve3Kind`: `SpringCentre`, `ThreeCoil`, `Motor` (default `SpringCentre`)

## How it works

A three-position valve: a 3-way diverter (A / closed / B), a spring-centred double solenoid, a three-coil valve, or a motorised valve with a mid position. Positions 1, 2, 3.

On `FB_Equipment`: an owner (a route, a zone) drives it through `I_Equipment.Request`: `bRun` = go, `fSpeed` = the position 1..3 (none: `set.nAutoPos`, default 3); its request off = `set.nRestPos`, or with `set.bPosLatch` the last position asked (it stays there until another is asked). Hand: `set.nHandPos` (kept; `nCmdPos` 1..3, or [`FB_LocalControl`](FB_LocalControl.md)'s `bPos1`..bPos3, writes it and starts in Hand); a motorised valve: [`FB_LocalControl`](FB_LocalControl.md)'s `bHalt` stops it where it is until the next position or command. Off, the interlock or a trip: `set.nSafePos`. "Running" is away from the rest position. An [`FB_Exercise`](FB_Exercise.md) part on it moves an idle valve (in Auto) to `nAutoPos` for its run time.

Kinds (`set.eKind`): SpringCentre (`bOut1` / `bOut3` held, none for 2: the springs centre it), ThreeCoil (`bOut1`..3 held), Motor (`bOut1` drives toward 1, `bOut3` toward 3, `set.tReversal` between; the mid by `bLs2`, or timed `set.tMid` from a known end (0 = half `tTravel`); a position not known goes to 1 first). Arrival: the position's switch when used, else `set.tTravel` after the move started. A switch that does not come within `tTravel` + 50 %: the travel protection (TravelTimeout). Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back; a bad setting with no good copy is a trip (BadSetting) with every output off (a spring-centred valve centres). Moves counted (`tot.nStrokes`: each new target 1..3), kept hourly.

## Example

A spring-centred 3-way diverter with end switches.

| Pin | Wire |
| --- | --- |
| `bLs1` | `DI_Pos1` |
| `bLs3` | `DI_Pos3` |
| `refData` | `stDiverter` |
| `bOut1` | `DO_CoilA` |
| `bOut3` | `DO_CoilB` |

Its owner asks for a position through `Request` (`fSpeed` = 1, 2 or 3).

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- method `Choose(eChoice) : BOOL`: a panel choice (FB_LocalControl bPos1..bPos3, bHalt): in Hand
- method `Request(bRun, bHold, fSpeed, bUrgent) : E_UtError`
- method `Command(eCmd)`
- property `eActMode : E_Mode`
- property `bIsRunning : BOOL`
- property `bIsReady : BOOL`
- property `bIsAvailable : BOOL`
- property `bIsAuto : BOOL`
- property `bIsFaulted : BOOL`
- property `eActError : E_UtError`
- property `eActStopReason : E_StopReason`
- property `fActRunHours : REAL`

**Back to** [the index](../README.md).
