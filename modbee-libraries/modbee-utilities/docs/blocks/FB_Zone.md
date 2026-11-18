# FB_Zone — One irrigation zone

One zone of an irrigation or wash-down program: its valve, its water time or volume, cycles and soak, a flow check and its pressure setpoint. Used by FB_ZoneSeq.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipValve` | `I_Equipment` |  | its valve: any I_Equipment, an FB_Valve; unwired = no valve: bValveOut drives a plain output. The instance it drives (a motor, pump, valve or FB_Group) |
| in | `refData` | `REFERENCE TO ST_ZoneData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bValveOut` | `BOOL` |  | A plain valve output, with no `ipValve` |
| out | `bOpen` | `BOOL` |  | its valve is proven open: the valve's state, or, with no valve, after set.tOpenTime |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ZoneData` (pin `refData`)

**Settings `set`** (`ST_ZoneSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bEnable` | `BOOL` | `TRUE` | in the program |
| `tRunTime` | `TIME` | `T#10m` | water time |
| `fVolume` | `LREAL` |  | water to apply (meter units); > 0: by volume (with tRunTime as its cap) |
| `tOpenTime` | `TIME` | `T#5s` | no valve: the time a plain output takes to open |
| `nCycles` | `INT` | `1` | the water is given in this many cycles (1..100) |
| `tSoakTime` | `TIME` |  | between cycles the zone soaks this long (0 = the next cycle at once) |
| `fMinFlow` | `REAL` |  | the flow band while watering, per hour in the meter's unit (0 = not checked) |
| `fMaxFlow` | `REAL` |  | 0 = not checked; in the meter's unit, per hour |
| `stFlowCheck` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#60s, eReset := E_ResetMode.Auto, tRecover := T#10s, nMaxRetries := 3)` | a protection's settings ([protections](../conventions.md#protections)) |
| `bDose` | `BOOL` | `TRUE` | this zone may be dosed |
| `fPressure` | `REAL` |  | its pressure setpoint (0 = the program's set.fDefaultSp) |
| `eEndBy` | `E_ZoneEnd` |  | what ends a cycle: Auto volume if set and metered, else time |

**Status `sts`** (`ST_ZoneSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bWatering` | `BOOL` |  |  |
| `bOpen` | `BOOL` |  | its valve is proven open: the valve's state, or, with no valve, after set.tOpenTime |
| `bDone` | `BOOL` |  |  |
| `tWatered` | `TIME` |  |  |
| `fWatered` | `LREAL` |  |  |
| `tTimeLeft` | `TIME` |  | Time left in the delay or phase running now |
| `nCycle` | `INT` |  | cycles finished |
| `bSoaking` | `BOOL` |  |  |
| `tSoakLeft` | `TIME` |  |  |
| `bFlowTrip` | `BOOL` |  | the flow check has taken the zone out |
| `bCapped` | `BOOL` |  | the last cycle ended on its time cap |
| `stFlowCheck` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |
| `bSkipped` | `BOOL` |  | skipped in this program (a skip, the rain, its valve, the pump wait) |
| `eResult` | `E_StopReason` |  | how it ended in this program (None: not yet) |

## Lists

- `E_ZoneEnd`: `Auto`, `ByTime`, `UntilStop`, `ByVolume`, `First` (default `Auto`)

## How it works

One zone of a zone program: its valve, its water time or volume, its progress. The project declares `aZones : ARRAY [1..n] OF FB_Zone` with their records, calls each zone once per scan before the program, and passes the array to `FB_ZoneSeq.aZones`.

The program opens and closes it through Open (every scan) and tells it how much it watered through AddWatered. Its progress (`bDone`, cycles done, watered time and volume) is kept hourly and at each change of zone, for a resume.

Cycles and soak: `set.nCycles` splits the water (time and volume) into that many equal cycles; after each cycle but the last the zone soaks for `set.tSoakTime` (the program waters the next zones meanwhile; Open is not asked of a soaking zone). EndCycle ends a cycle; `bIsReady` is TRUE for an enabled zone with water left that is not soaking.

Flow check: while the program waters it, it tells the zone the meter's flow (Flow, every scan). Flow below `set.fMinFlow` or above `set.fMaxFlow` (0 = not checked; in the meter's unit, per hour) for `set.stFlowCheck`'s delay acts per its response: Warn = a warning (`sts.stFlowCheck`, ZoneFlow), Trip = the zone is out (`bFlowTrip`, an error ZoneFlow; the program ends that zone) until the check resets (Auto / Retry after the recover time, or a reset).

Pressure: `set.fPressure` is the zone's pressure setpoint (0 = the program's default); the program passes the watering zone's on as `fZoneSp` (wire it to [`FB_SpeedLoop`](FB_SpeedLoop.md)'s `fSp` pin, with its `set.eSpSource` Pin).

A program can give the zone another water time for one run (its `tRunTime` pin, 0 = `set.tRunTime`).

What ends a cycle (`set.eEndBy`; the cycle's targets are the zone's `tRunTime` and `fVolume` divided by `set.nCycles`; a volume target needs the program to have a meter, else it counts as 0 = no target):

```
  ByTime      the cycle's time; a volume is ignored
  ByVolume    the cycle's volume; the time is no target
  First       the time or the volume, whichever comes first
  Auto        the volume if set.fVolume > 0, else the time
  UntilStop   no target: it waters until a skip or a stop
```

A mode with no target left (a volume mode with no volume or no meter, a time of 0) has none: it waters until a skip or stop. A cycle whose only target is a volume has a time cap on its counted time, so a dry meter cannot water for ever: the program's `set.tMaxTime` (divided by the cycles) if set, else the volume at `set.fMinFlow` (per hour), else the program's `set.tDefaultCap`. When the cap ends the cycle `sts.bCapped` is TRUE and the program warns RunCapped.

In a program: `sts.eResult` (how it ended: Done, or the stop reason; None = not yet) and `sts.bSkipped` (skipped: a skip, the rain, its valve not opening, the pump wait), set by the sequence; both clear when a program starts.

## Example

Zone 1 of a program, on its own valve. Declare `aZones : ARRAY[1..4] OF FB_Zone` and one record per zone.

| Pin | Wire |
| --- | --- |
| `ipValve` | `fbValve1` |
| `refData` | `stZone1` |

Call each `aZones[i]` on its own rung before the FB_ZoneSeq rung.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- method `Open(bOpen)`: the program: open (TRUE) or close the valve; every scan
- method `AddWatered(tWatered, fWatered)`: the program: water given this scan
- method `Flow(fRate, bGood)`: the program: the flow of the meter this scan, while it waters this zone
- method `SetDone(bDone)`: the program: this zone is done (TRUE) or starts afresh (FALSE)
- method `SetRunTime(tRunTime)`: the program, at its start: this run's water time (0 = the zone's own set.tRunTime)
- property `tRunTimeNow : TIME`: the water time in use: this run's (SetRunTime) or set.tRunTime
- method `SetResult(eResult, bSkipped)`: the program: how the zone ended in this program (sts.eResult, sts.bSkipped)
- method `SaveProgress()`: the program: keep the progress now (its set.tProgressSave)
- method `EndCycle() : BOOL`: the program: the cycle's water is given. TRUE: that was the last cycle; FALSE: the zone soaks (set.tSoakTime) or is ready for its next cycle at once
- method `Reached(bByVolume, tMaxTime, tDefaultCap) : BOOL`: this cycle's water is given, per set.eEndBy (see the header); the program's cap values are passed in
- property `bIsEnabled : BOOL`
- property `bIsWaterable : BOOL`: water left, not soaking, usable: it may water now (a one-zone run need not have it enabled)
- property `bIsReady : BOOL`: in the program as well: the program's next zone
- property `bIsPending : BOOL`: water left (soaking too) and usable: the program is not over while it is TRUE
- property `bIsSoaking : BOOL`
- property `bIsUsable : BOOL`: it may water (a one-zone run need not have it in the program): called, valid, not out on its flow check
- property `bIsFlowTrip : BOOL`
- property `bIsDone : BOOL`
- property `bIsCapped : BOOL`
- property `bUntilStop : BOOL`
- property `fActPressure : REAL`
- property `bDoseAllowed : BOOL`
- property `tActTimeLeft : TIME`: the time this cycle's water has left (as of the last Reached)
- property `tActRemaining : TIME`: the time this zone still has to water in this program (its cycles left x the cycle's share of the water time in use, less the running cycle's watered time); 0 for a zone done, not enabled, or watered by volume only

**Back to** [the index](../README.md).
