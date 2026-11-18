# FB_VesselFlow — A vessel's inflow estimate

What flows into a vessel: its volume's rise per hour plus the metered outflow (a sump's inflow while its pump empties it), in the vessel's volume unit per hour.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipVessel` | `I_Vessel` |  | required. An FB_Vessel instance |
| in | `ipOutflow` | `I_Meter` |  | optional. A meter block's instance (FB_PulseMeter, FB_FlowTotal, FB_RegisterMeter, FB_LevelMeter) |
| in | `refData` | `REFERENCE TO ST_VesselFlowData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_VesselFlowData` (pin `refData`)

**Settings `set`** (`ST_VesselFlowSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tRateWindow` | `TIME` | `T#1m` | The rate is worked out over this window |

**Status `sts`** (`ST_VesselFlowSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bGood` | `BOOL` |  | The value can be trusted |
| `fInflow` | `REAL` |  | per hour: fRise + fOutflow |
| `fRise` | `REAL` |  | the volume's change per hour |
| `fOutflow` | `REAL` |  | the outflow meter's rate per hour |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

## How it works

What flows into a vessel: the volume's rise per hour plus the metered outflow (a sump's inflow while its pump empties it, a tank's net fill). An observer: it reads the vessel and the meter, changes nothing.

Every `set.tRateWindow`: `sts.fRise` = the volume's change per hour (negative while it falls), `sts.fOutflow` = the meter's rate (0 without one, or while it is bad), `sts.fInflow` = `fRise` + `fOutflow`, all in the vessel's volume unit per hour. `sts.bGood`: a whole window of good volume readings (a bad vessel restarts the window; the values hold at their last good ones). A bad `tRateWindow` is put back (settings kept over a power cut).

## Example

The inflow into a sump, for the panel and SCADA.

| Pin | Wire |
| --- | --- |
| `ipVessel` | `fbSump` (an FB_Vessel) |
| `ipOutflow` | `fbPumpMeter` |
| `refData` | `stSumpFlow` |

Show `stSumpFlow.sts.fInflow`.

**Back to** [the index](../README.md).
