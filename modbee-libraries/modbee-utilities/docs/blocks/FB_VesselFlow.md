# FB_VesselFlow — A vessel's inflow estimate

What flows into a vessel: its volume's rise per hour plus the metered outflow (a sump's inflow while its pump empties it), in the vessel's volume unit per hour.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipVessel` | `I_Vessel` |  | required. An instance of a block that offers I_Vessel (FB_Vessel) |
| in | `ipOutflowMeter` | `I_Meter` |  | optional. An instance of a block that offers I_Meter (FB_FlowTotal, FB_LevelMeter, FB_MeterSelect, FB_PulseMeter, FB_RegisterMeter) |
| in | `refData` | `REFERENCE TO ST_VesselFlowData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_VesselFlowData` (pin `refData`)

**Settings `set`** (`ST_VesselFlowSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tRateWindow` | `TIME` | `T#1m` | the window the rise per hour is worked out over |

**Status `sts`** (`ST_VesselFlowSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bGood` | `BOOL` |  | the flows can be trusted |
| `fInflowPerHour` | `REAL` |  | per hour: fRisePerHour + fOutflowPerHour |
| `fRisePerHour` | `REAL` |  | the volume's change per hour |
| `fOutflowPerHour` | `REAL` |  | the outflow meter's rate per hour |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## How it works

What flows into a vessel: the volume's rise per hour plus the metered outflow (a sump's inflow while its pump empties it, a tank's net fill). An observer: it reads the vessel and the meter, changes nothing.

Every `set.tRateWindow`: `sts.fRisePerHour` = the volume's change per hour (negative while it falls), `sts.fOutflowPerHour` = the meter's rate (0 without one, or while it is bad), `sts.fInflowPerHour` = `fRisePerHour` + `fOutflowPerHour`, all in the vessel's volume unit per hour. `sts.bGood`: a whole window of good volume readings (a bad vessel restarts the window; the values hold at their last good ones). A bad `tRateWindow` is put back (settings kept over a power cut).

## Example

The inflow into a sump, for the panel and SCADA.

| Pin | Wire |
| --- | --- |
| `ipVessel` | `fbSump` (an FB_Vessel) |
| `ipOutflowMeter` | `fbPumpMeter` |
| `refData` | `stSumpFlow` |

Show `stSumpFlow.sts.fInflowPerHour`.

**Back to** [the index](../README.md).
