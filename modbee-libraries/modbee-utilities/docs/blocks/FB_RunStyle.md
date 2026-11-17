# FB_RunStyle — Run signal style

The way a run takes its signal: held, toggle (push-on / push-off), keep-alive pulses or a single pulse. Put it in front of FB_Run.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bIn` | `BOOL` |  | the run signal (held, toggled, pulsed, kept alive) |
| in | `bStop` | `BOOL` |  | rising edge: ends a latched run |
| in | `refData` | `REFERENCE TO ST_RunStyleData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bRun` | `BOOL` |  | -> FB_Run.bRun (held) |
| out | `bStart` | `BOOL` |  | one scan -> FB_Run.bStart (Pulse with the run's own target) |
| out | `bLost` | `BOOL` |  | one scan: KeepAlive pulses stopped |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunStyleData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bRun` | `BOOL` |  | status |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**Settings `set`** (`ST_RunStyleSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eStyle` | `E_RunStyle` |  |  |
| `tKeepAlive` | `TIME` | `T#30s` |  |
| `tPulse` | `TIME` |  | Pulse: 0 = a start pulse for the run's own target |

## Lists

- `E_RunStyle`: `Held`, `Toggle`, `KeepAlive`, `Pulse` (default `Held`)

## How it works

How a run takes its signal: a front end for [`FB_Run`](FB_Run.md) (or any block with a held run pin), in the style the installer picks (`set.eStyle`):

```
  Held       bRun follows bIn
  Toggle     each rising edge of bIn flips bRun (a push-on / push-off button)
  KeepAlive  bRun while bIn keeps changing (pulses from a remote unit); off set.tKeepAlive after the last change
             (bLost for one scan)
  Pulse      a rising edge of bIn: with set.tPulse = 0 a one-scan bStart (the run's own target ends it: wire bStart
             to FB_Run.bStart); with set.tPulse > 0, bRun for tPulse
```

`bStop` (rising edge) ends a Toggle / Pulse run and forgets it. Edges in the first scan are ignored: nothing starts at power-up. Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.

## Example

A push-on / push-off button for a run.

| Pin | Wire |
| --- | --- |
| `bIn` | `DI_RunPB` |
| `bStop` | `DI_StopPB` |
| `refData` | `stStyle` |
| `bRun` | `fbRun.bRun` |
| `bStart` | `fbRun.bStart` |

Set `stStyle.set.eStyle := E_RunStyle.Toggle`.

**Back to** [the index](../README.md).
