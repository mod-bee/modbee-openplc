# FB_RunStyle — Run signal style

The way a run takes its signal: held, toggle (push-on / push-off), keep-alive pulses or a single pulse. Put it in front of FB_Run.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRunSignal` | `BOOL` |  | the run signal (held, toggled, pulsed, kept alive) |
| in | `bStop` | `BOOL` |  | rising edge: ends a latched run |
| in | `refData` | `REFERENCE TO ST_RunStyleData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bRunHeld` | `BOOL` |  | -> FB_Run.bRun (held) |
| out | `bStart` | `BOOL` |  | one scan -> FB_Run.bStart (Pulse with the run's own target) |
| out | `bKeepAliveLost` | `BOOL` |  | one scan: KeepAlive pulses stopped |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunStyleData` (pin `refData`)

**Settings `set`** (`ST_RunStyleSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eRunStyle` | `E_RunStyle` |  | Held, Toggle (push-on / push-off), KeepAlive or Pulse |
| `tKeepAliveTimeout` | `TIME` | `T#30s` | KeepAlive: the run ends this long after the last change |
| `tPulseRunTime` | `TIME` |  | Pulse: 0 = a start pulse for the run's own target |

**Status `sts`** (`ST_RunStyleSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bRunHeld` | `BOOL` |  | the held run signal it gives now |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Lists

- `E_RunStyle`: `Held`, `Toggle`, `KeepAlive`, `Pulse` (default `Held`)

## How it works

How a run takes its signal: a front end for [`FB_Run`](FB_Run.md) (or any block with a held run pin), in the style the installer picks (`set.eRunStyle`):

```
  Held       bRunHeld follows bRunSignal
  Toggle     each rising edge of bRunSignal flips bRunHeld (a push-on / push-off button)
  KeepAlive  bRunHeld while bRunSignal keeps changing (pulses from a remote unit); off set.tKeepAliveTimeout after the last change
             (bKeepAliveLost for one scan)
  Pulse      a rising edge of bRunSignal: with set.tPulseRunTime = 0 a one-scan bStart (the run's own target ends it: wire bStart
             to FB_Run.bStart); with set.tPulseRunTime > 0, bRunHeld for tPulseRunTime
```

`bStop` (rising edge) ends a Toggle / Pulse run and forgets it. Edges in the first scan are ignored: nothing starts at power-up. Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A push-on / push-off button for a run.

| Pin | Wire |
| --- | --- |
| `bRunSignal` | `DI_RunPB` |
| `bStop` | `DI_StopPB` |
| `refData` | `stStyle` |
| `bRunHeld` | `fbRun.bRun` |
| `bStart` | `fbRun.bStart` |

Set `stStyle.set.eRunStyle := E_RunStyle.Toggle`.

**Back to** [the index](../README.md).
