# FB_FlowTotal — Flow total

A total from a flow rate, from running time at a nominal rate, or from samples of a slow reading, with unit conversion and a batch target.

Offers `I_Meter`: wire this instance to another block's `ip…` pin of that type.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipFlow` | `I_Measurement` |  | the flow measurement, in its unit per eRateUnit. An instance of a block that offers I_Measurement (FB_AnalogIn, FB_FlowTotal, FB_LevelMeter, FB_MeasFilter, FB_MeasFrozen, ...) |
| in | `bPumpRunning` | `BOOL` |  | Runtime: counting while TRUE; Rate / Sample: counting only while TRUE when bCountOnlyWhilePumpRunning |
| in | `bResetBatch` | `BOOL R_EDGE` |  | the batch back to 0 |
| in | `refData` | `REFERENCE TO ST_FlowTotalData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bBatchDone` | `BOOL` |  | the batch has reached set.fBatchSetpoint |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_FlowTotalData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetTotals` | `BOOL` |  | the totals back to 0 (cleared by the block) |
| `bCmdResetBatch` | `BOOL` |  | the batch back to 0 (cleared by the block) |
| `bCmdConfirmReset` | `BOOL` |  | confirms bCmdResetTotals (set.bResetNeedsConfirm); cleared by the block |
| `bCmdPresetTotal` | `BOOL` |  | the total to fPresetTotal (cleared by the block) |
| `fPresetTotal` | `LREAL` |  | the total bCmdPresetTotal writes, in the meter's unit |

**Settings `set`** (`ST_FlowTotalSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eCountFrom` | `E_FlowSource` |  | what is counted: Rate (a flow), Runtime (fNominalRate while active) or Sample |
| `eRateUnit` | `E_RateUnit` | `E_RateUnit.PerHour` | the flow's time base (Rate) and fNominalRate's |
| `fZeroBelow` | `REAL` |  | \|flow\| below this counts as 0 |
| `bCountReverseFlow` | `BOOL` |  | negative flow into tot.fTotalReverse |
| `bCountOnlyWhilePumpRunning` | `BOOL` |  | Rate: count only while bPumpRunning |
| `fNominalRate` | `REAL` |  | Runtime, and the estimate while the meter is bad |
| `bEstimateWhenBad` | `BOOL` |  | count fNominalRate while bPumpRunning and the meter is bad |
| `tRateWindow` | `TIME` | `T#10s` | the rate is worked out over this window |
| `tSampleInterval` | `TIME` | `T#1m` | Sample: the value is read every this long |
| `bSampleAsQuantity` | `BOOL` |  | Sample: each sample is a quantity (the value), not a rate |
| `fBatchSetpoint` | `LREAL` |  | bBatchDone when the batch reaches it (0 = off) |
| `eMeterUnit` | `E_Unit` |  | the volume unit of the flow (None = no conversion) |
| `eTotalUnit` | `E_Unit` |  | the volume unit of every total and of the rate (None = no conversion) |
| `stMeterBadFault` | `ST_ProtectionSet` | `(eActionOnFault := E_Response.Warn, tTripDelay := T#5s, eResetMode := E_ResetMode.Auto, tAutoRecoverAfter := T#5s, nMaxRetriesBeforeLockout := 0)` | the meter's input is bad (default a warning); a protection's settings ([protections](../conventions.md#protections)) |
| `bResetNeedsConfirm` | `BOOL` |  | a total reset needs the record's bCmdConfirmReset in the same write |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_FlowTotalSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bGood` | `BOOL` |  | counting: the meter can be trusted |
| `bEstimating` | `BOOL` |  | the meter is bad and fNominalRate is being counted |
| `fFlowPerHour` | `REAL` |  | per hour |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |
| `stMeterBadFault` | `ST_ProtectionSts` |  | the meter's input is bad (default a warning); a protection's status ([protections](../conventions.md#protections)) |

**Totals `tot`** (`ST_FlowTotalTot`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `fTotal` | `LREAL` |  | forward flow total, estimates included (kept) |
| `fTotalReverse` | `LREAL` |  | reverse flow |
| `fTotalEstimated` | `LREAL` |  | the part of fTotal that was estimated |
| `fBatchTotal` | `LREAL` |  | counted like fTotal (forward only) until bCmdResetBatch |

## Lists

- `E_FlowSource`: `Rate`, `Runtime`, `Sample` (default `Rate`)

## How it works

Totals from a flow rate, or from running time at a nominal rate. Offers `I_Meter` (the total, the rate per hour; an `I_Measurement` too: its rate).

Rate / Sample: optional, counting only while TRUE when `set.bCountOnlyWhilePumpRunning`), `bResetBatch` (rising edge: the batch to 0), `refData` -> `bBatchDone`. `set.eCountFrom`:

```
  Rate     integrates ipFlow; below set.fZeroBelow counts as 0; with set.bCountReverseFlow a negative flow beyond the
           cut-off counts into tot.fTotalReverse (reverse), not into tot.fTotal
  Runtime  adds set.fNominalRate while bPumpRunning (an estimate of what a pump moved; not a measured flow)
  Sample   every set.tSampleInterval reads ipFlow once and adds it x tSampleInterval (a rate, set.eRateUnit) or, with
           set.bSampleAsQuantity, the value itself (a quantity per sample); the same cut-off, reverse and bad
           meter rules as Rate. A slow reading, a meter that only updates now and then.
```

Units: `set.eMeterUnit` and `set.eTotalUnit` (`E_Unit`, volume units: litre, m3, megalitre, gallon) both set convert every addition from the flow's volume unit to the total's (and so the rate); both None = no conversion. One set, or a unit that is not a volume, is a bad setting (put back).

Batch: `tot.fBatchTotal` counts like `tot.fTotal` (forward flow, estimates included) until `bResetBatch` / `bCmdResetBatch`; `bBatchDone` is TRUE once it has reached `set.fBatchSetpoint` (0 = off), until the batch is reset.

A failed meter (`ipFlow` not good or not wired) does not count; with `set.bEstimateWhenBad` the nominal rate is counted instead while `bPumpRunning`, into `tot.fTotalEstimated` too (a warning). Bad past `set.stMeterBadFault`'s delay: `bIsGood` FALSE and a warning (SensorBad). Totals and batch are LREAL, kept hourly, when `bPumpRunning` falls (the pump stops) and on a reset (`bCmdResetTotals`, `bCmdResetBatch`).

Total commands: `bCmdResetTotals` (with `set.bResetNeedsConfirm`, only together with `bCmdConfirmReset` in the same write) and `bCmdPresetTotal` (the total to `fPresetTotal`, 0 .. 1E12).

## Example

A total from a flow transmitter.

| Pin | Wire |
| --- | --- |
| `ipFlow` | `fbFlow` |
| `refData` | `stFlowTotal` |

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
