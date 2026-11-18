# FB_FlowTotal — Flow total

A total from a flow rate, from running time at a nominal rate, or from samples of a slow reading, with unit conversion and a batch target.

Offers `I_Meter`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipFlow` | `I_Measurement` |  | I_Measurement, the flow in its unit per set.eRateUnit. A measurement block's instance (FB_AnalogIn, FB_SwitchSet, FB_Vessel, ...) |
| in | `bActive` | `BOOL` |  | Runtime: counting while TRUE; Rate / Sample: optional, counting only while TRUE when set.bOnlyActive |
| in | `bResetBatch` | `BOOL R_EDGE` |  | the batch back to 0 Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_FlowTotalData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bBatchDone` | `BOOL` |  | the batch has reached set.fBatchTarget |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_FlowTotalData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetTotal` | `BOOL` |  | the totals back to 0 (cleared by the block) |
| `bCmdResetBatch` | `BOOL` |  | the batch back to 0 (cleared by the block) |
| `bCmdConfirm` | `BOOL` |  | confirms bCmdResetTotal (set.bConfirmReset); cleared by the block |
| `bCmdPreset` | `BOOL` |  | the total to fPresetTotal (cleared by the block) |
| `fPresetTotal` | `LREAL` |  |  |

**Settings `set`** (`ST_FlowTotalSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eSource` | `E_FlowSource` |  |  |
| `eRateUnit` | `E_RateUnit` | `E_RateUnit.PerHour` | the flow's time base (Rate) and fNominalRate's |
| `fLowCutoff` | `REAL` |  | \|flow\| below this counts as 0 |
| `bCountReverse` | `BOOL` |  | negative flow into tot.fTotalOut |
| `bOnlyActive` | `BOOL` |  | Rate: count only while bActive |
| `fNominalRate` | `REAL` |  | Runtime, and the estimate while the meter is bad |
| `bBadEstimate` | `BOOL` |  | count fNominalRate while bActive and the meter is bad |
| `tRateWindow` | `TIME` | `T#10s` | The rate is worked out over this window |
| `tSampleTime` | `TIME` | `T#1m` | Sample: the value is read every this long |
| `bSampleAsQuantity` | `BOOL` |  | Sample: each sample is a quantity (the value), not a rate |
| `fBatchTarget` | `LREAL` |  | bBatchDone when the batch reaches it (0 = off) |
| `eInUnit` | `E_Unit` |  | the volume unit of the flow (None = no conversion) |
| `eOutUnit` | `E_Unit` |  | the volume unit of every total and of the rate (None = no conversion) |
| `stInputBad` | `ST_ProtectionSet` | `(eResponse := E_Response.Warn, tDelay := T#5s, eReset := E_ResetMode.Auto, tRecover := T#5s, nMaxRetries := 0)` | a protection's settings ([protections](../conventions.md#protections)) |
| `bConfirmReset` | `BOOL` |  | a total reset needs the record's bCmdConfirm in the same write |

**Status `sts`** (`ST_FlowTotalSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bGood` | `BOOL` |  | The value can be trusted |
| `bEstimating` | `BOOL` |  |  |
| `fRate` | `REAL` |  | per hour |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |
| `stInputBad` | `ST_ProtectionSts` |  | a protection's status ([protections](../conventions.md#protections)) |

**Totals `tot`** (`ST_FlowTotalTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTotal` | `LREAL` |  | forward flow, estimates included |
| `fTotalOut` | `LREAL` |  | reverse flow |
| `fEstimated` | `LREAL` |  | the part of fTotal that was estimated |
| `fBatch` | `LREAL` |  | counted like fTotal (forward only) until bCmdResetBatch |

## Lists

- `E_FlowSource`: `Rate`, `Runtime`, `Sample` (default `Rate`)

## How it works

Totals from a flow rate, or from running time at a nominal rate. Offers `I_Meter` (the total, the rate per hour; an `I_Measurement` too: its rate).

Rate / Sample: optional, counting only while TRUE when `set.bOnlyActive`), `bResetBatch` (rising edge: the batch to 0), `refData` -> `bBatchDone`. `set.eSource`:

```
  Rate     integrates ipFlow; below set.fLowCutoff counts as 0; with set.bCountReverse a negative flow beyond the
           cut-off counts into tot.fTotalOut (reverse), not into tot.fTotal
  Runtime  adds set.fNominalRate while bActive (an estimate of what a pump moved; not a measured flow)
  Sample   every set.tSampleTime reads ipFlow once and adds it x tSampleTime (a rate, set.eRateUnit) or, with
           set.bSampleAsQuantity, the value itself (a quantity per sample); the same cut-off, reverse and bad
           meter rules as Rate. A slow reading, a meter that only updates now and then.
```

Units: `set.eInUnit` and `set.eOutUnit` (`E_Unit`, volume units: litre, m3, megalitre, gallon) both set convert every addition from the flow's volume unit to the total's (and so the rate); both None = no conversion. One set, or a unit that is not a volume, is a bad setting (put back).

Batch: `tot.fBatch` counts like `tot.fTotal` (forward flow, estimates included) until `bResetBatch` / `bCmdResetBatch`; `bBatchDone` is TRUE once it has reached `set.fBatchTarget` (0 = off), until the batch is reset.

A failed meter (`ipFlow` not good or not wired) does not count; with `set.bBadEstimate` the nominal rate is counted instead while `bActive`, into `tot.fEstimated` too (a warning). Bad past `set.stInputBad`'s delay: `bIsGood` FALSE and a warning (SensorBad). Totals and batch are LREAL, kept hourly, when `bActive` falls (the pump stops) and on a reset (`bCmdResetTotal`, `bCmdResetBatch`).

Total commands: `bCmdResetTotal` (with `set.bConfirmReset`, only together with `bCmdConfirm` in the same write) and `bCmdPreset` (the total to `fPresetTotal`, 0 .. 1E12).

## Example

A total from a flow transmitter.

| Pin | Wire |
| --- | --- |
| `ipFlow` | `fbFlow` |
| `refData` | `stFlowTotal` |

## Read from ST (methods and properties)

Ladder uses the pins above. These are for ST code and for other blocks (through the interface pins):

- property `fActTotal : LREAL`
- property `fActRate : REAL`
- property `bIsGood : BOOL`
- property `fActValue : REAL`: I_Measurement: the rate (per hour), in set.eOutUnit per hour, no bands
- property `bHasValue : BOOL`
- property `bIsFitted : BOOL`
- property `eUnit : E_Unit`
- method `Band(eBand) : BOOL`

**Back to** [the index](../README.md).
