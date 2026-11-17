# FB_PulseMeter — Pulse meter

A pulse flow meter or a hardware pulse counter, as a total and a rate, with unit conversion and a batch target.

Offers `I_Meter`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bPulse` | `BOOL` |  | each rising edge is one pulse: at most one pulse per two scans |
| in | `nCount` | `UDINT` |  | a hardware counter, e.g. node-uio PULSE_COUNT: each count is one pulse; a wrap past 2^32 or set.nRolloverAt is counted, a drop of more than half the range is a counter restart |
| in | `bInGood` | `BOOL` | `TRUE` | the input can be trusted |
| in | `bRunning` | `BOOL` | `FALSE` | optional: the pump runs; its fall keeps the totals |
| in | `bResetBatch` | `BOOL R_EDGE` |  | the batch back to 0 Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_PulseMeterData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bBatchDone` | `BOOL` |  | the batch has reached set.fBatchTarget |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_PulseMeterData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetTotal` | `BOOL` |  | the total back to 0 (rising edge, cleared) |
| `bCmdResetBatch` | `BOOL` |  | the batch back to 0 (cleared) |

**Settings `set`** (`ST_PulseMeterSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSource` | `E_PulseSource` |  |  |
| `fPerPulse` | `REAL` | `1.0` | volume per pulse, in the total's unit |
| `nRolloverAt` | `UDINT` |  | a counter that wraps here (0 = at 2^32) |
| `tRateWindow` | `TIME` | `T#10s` | The rate is worked out over this window |
| `fBatchTarget` | `LREAL` |  | bBatchDone when the batch reaches it (0 = off) |
| `eInUnit` | `E_Unit` |  | the volume unit of fPerPulse (None = no conversion) |
| `eOutUnit` | `E_Unit` |  | the volume unit of the total and the rate (None = no conversion) |
| `stInputBad` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#5s, eReset := E_ResetMode.Auto, tRecover := T#5s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |

**Status `sts`** (`ST_PulseMeterSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bGood` | `BOOL` |  | The value can be trusted |
| `fRate` | `REAL` |  | per hour |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `stInputBad` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |

**Totals `tot`** (`ST_PulseMeterTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTotal` | `LREAL` |  | The total (kept) |
| `fBatch` | `LREAL` |  | counted like fTotal until bCmdResetBatch |

## Lists

- `E_PulseSource`: `Pulse`, `Count` (default `Pulse`)

## How it works

A pulse flow meter or a hardware pulse counter.

Units: `set.eInUnit` (the unit of `fPerPulse`) and `set.eOutUnit` (the unit of the total and the rate), `E_Unit` volume units (litre, m3, megalitre, gallon): both set convert each addition; both None = no conversion. One set, or a unit that is not a volume, is a bad setting (put back).

Batch: `tot.fBatch` counts like `tot.fTotal` until `bResetBatch` (rising edge) / `bCmdResetBatch`; `bBatchDone` is TRUE once it has reached `set.fBatchTarget` (0 = off), until the batch is reset.

Offers `I_Meter`: the total and the rate (per hour, over `set.tRateWindow`). The total and the batch are kept hourly, when `bRunning` falls (the pump stops; optional) and on a reset.

## Example

A pulse water meter on a digital input, 10 L per pulse.

| Pin | Wire |
| --- | --- |
| `bPulse` | `DI_FlowPulse` |
| `refData` | `stMeter` |

Set `stMeter.set.fPerPulse := 10.0`. Wire `fbMeter` to the blocks that need a meter.

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActTotal : LREAL`
- property `fActRate : REAL`
- property `bIsGood : BOOL`

**Back to** [the index](../README.md).
