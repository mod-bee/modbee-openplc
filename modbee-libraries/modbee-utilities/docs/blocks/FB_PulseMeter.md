# FB_PulseMeter — Pulse meter

A pulse flow meter or a hardware pulse counter, as a total and a rate, with unit conversion and a batch target.

Offers `I_Meter`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bPulse` | `BOOL` |  | each rising edge is one pulse (at most one pulse per two scans) |
| in | `nHardwareCount` | `UDINT` |  | a hardware counter (e.g. node-uio FB_PulseCounter): each count is one pulse |
| in | `bInputGood` | `BOOL` | `TRUE` | the input can be trusted |
| in | `bPumpRunning` | `BOOL` | `FALSE` | optional: the pump runs; its fall keeps the totals |
| in | `bResetBatch` | `BOOL R_EDGE` |  | the batch back to 0 |
| in | `refData` | `REFERENCE TO ST_PulseMeterData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bBatchDone` | `BOOL` |  | the batch has reached set.fBatchSetpoint |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_PulseMeterData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetTotals` | `BOOL` |  | the total back to 0 (rising edge, cleared) |
| `bCmdResetBatch` | `BOOL` |  | the batch back to 0 (cleared) |
| `bCmdConfirmReset` | `BOOL` |  | confirms bCmdResetTotals (set.bResetNeedsConfirm); cleared by the block |
| `bCmdPresetTotal` | `BOOL` |  | the total to fPresetTotal (cleared by the block) |
| `fPresetTotal` | `LREAL` |  | the total bCmdPresetTotal writes, in the meter's unit |

**Settings `set`** (`ST_PulseMeterSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eCountFrom` | `E_PulseSource` |  | what is counted: Pulse (bPulse edges) or Count (a hardware counter) |
| `fVolumePerPulse` | `REAL` | `1.0` | volume per pulse, in the total's unit |
| `nCounterWrapsAt` | `UDINT` |  | a counter that wraps here (0 = at 2^32) |
| `tRateWindow` | `TIME` | `T#10s` | the rate is worked out over this window |
| `fBatchSetpoint` | `LREAL` |  | bBatchDone when the batch reaches it (0 = off) |
| `eMeterUnit` | `E_Unit` |  | the volume unit of fVolumePerPulse (None = no conversion) |
| `eTotalUnit` | `E_Unit` |  | the volume unit of the total and the rate (None = no conversion) |
| `stMeterBadFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#5s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#5s, nMaxRetriesBeforeLockout := 0)` | the meter's input is bad (default a warning); a protection's settings ([protections](../conventions.md#protections)) |
| `bResetNeedsConfirm` | `BOOL` |  | a total reset needs the record's bCmdConfirmReset in the same write |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_PulseMeterSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bGood` | `BOOL` |  | counting: the meter can be trusted |
| `fFlowPerHour` | `REAL` |  | per hour |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stMeterBadFault` | `ST_ProtectionSts` |  | the meter's input is bad (default a warning); a protection's status ([protections](../conventions.md#protections)) |
| `nPulseCount` | `UDINT` |  | pulses counted since power-up |
| `bPulsesTooFast` | `BOOL` |  | pulses at the scan-rate limit (a pulse every second scan; held 5 s) |

**Totals `tot`** (`ST_PulseMeterTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTotal` | `LREAL` |  | the total (kept) |
| `fBatchTotal` | `LREAL` |  | counted like fTotal until bCmdResetBatch |

## Lists

- `E_PulseSource`: `Pulse`, `Count` (default `Pulse`)

## How it works

A pulse flow meter or a hardware pulse counter.

Units: `set.eMeterUnit` (the unit of `fVolumePerPulse`) and `set.eTotalUnit` (the unit of the total and the rate), `E_Unit` volume units (litre, m3, megalitre, gallon): both set convert each addition; both None = no conversion. One set, or a unit that is not a volume, is a bad setting (put back).

Batch: `tot.fBatchTotal` counts like `tot.fTotal` until `bResetBatch` (rising edge) / `bCmdResetBatch`; `bBatchDone` is TRUE once it has reached `set.fBatchSetpoint` (0 = off), until the batch is reset.

Offers `I_Meter` (an `I_Measurement` too: its rate): the total and the rate (per hour, over `set.tRateWindow`). The total and the batch are kept hourly, when `bPumpRunning` falls (the pump stops; optional) and on a reset. `sts.nPulseCount` counts pulses since power-up; pulses at the input's limit (a pulse every second scan) warn (PulsesTooFast, `sts.bPulsesTooFast`, held 5 s).

Total commands: `bCmdResetTotals` (with `set.bResetNeedsConfirm`, only together with `bCmdConfirmReset` in the same write) and `bCmdPresetTotal` (the total to `fPresetTotal`, 0 .. 1E12).

## Example

A pulse water meter on a digital input, 10 L per pulse.

| Pin | Wire |
| --- | --- |
| `bPulse` | `DI_FlowPulse` |
| `refData` | `stMeter` |

Set `stMeter.set.fVolumePerPulse := 10.0`. Wire `fbMeter` to the blocks that need a meter.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):
**Back to** [the index](../README.md).

- property `fActTotal : LREAL`: the lifetime total in its unit
- property `fActFlowPerHour : REAL`: the rate, per hour
- property `bIsGood : BOOL`: the value can be trusted now
- property `fActValue : REAL`: I_Measurement: the rate (per hour), in set.eTotalUnit per hour, no bands
- property `bHasValue : BOOL`: a value is available (fitted and read at least once)
- property `bIsFitted : BOOL`: fitted on this site
- property `eUnit : E_Unit`: the unit of the value
- method `Band(eBand) : BOOL`
