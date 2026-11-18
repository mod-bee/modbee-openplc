# FB_PulseSeq — Sequential pulsing

Sequential pulsing (jet-pulse filter cleaning, flush valves): one output at a time, in order, with gaps and pauses, on demand or continuously.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` |  | allow operation (e.g. the fan running) |
| in | `bDemand` | `BOOL` | `TRUE` | on-demand cleaning (e.g. DP high); TRUE for continuous |
| in | `bHold` | `BOOL` |  | pause where it is |
| in | `bStart` | `BOOL R_EDGE` |  | one full cleaning cycle now Acts on its rising edge. |
| in | `bStop` | `BOOL R_EDGE` |  | stop now Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_PulseSeqData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aOutputs` | `ARRAY[*] OF BOOL` |  | the project's row of valves, one element per channel |
| out | `bBusy` | `BOOL` |  | Running a dose, run or sequence |
| out | `nChannel` | `INT` |  | the channel pulsing (0 = none) |
| out | `bCycleDone` | `BOOL` |  | one scan at the end of each full cycle |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_PulseSeqData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdStart` | `BOOL` |  | one full cleaning cycle now (cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop now (cleared by the block) |

**Settings `set`** (`ST_PulseSeqSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nPulsesPerChannel` | `INT` | `1` |  |
| `tPulseOn` | `TIME` | `T#100ms` | valve open time (at least one scan) |
| `tPulseOff` | `TIME` | `T#1s` | gap between pulses on the same channel |
| `tChannelGap` | `TIME` | `T#10s` | gap between channels (the air tank recovers) |
| `tCyclePause` | `TIME` | `T#60s` | pause after a full cycle |
| `tStartDelay` | `TIME` |  | after bEnable and bDemand come on |
| `nPostCycles` | `INT` |  | full cycles after bDemand or bEnable drops (post-clean) |
| `nSkip` | `DWORD` |  | bit n = skip channel n+1 (a faulty valve) |

**Status `sts`** (`ST_PulseSeqSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `ePhase` | `E_PulsePhase` |  | The phase now (status) |
| `nChannel` | `INT` |  | pulsing, or next after its channel gap (0 = none) |
| `nPulse` | `INT` |  |  |
| `nCycles` | `UDINT` |  | Cycles completed since power-up |
| `nPostLeft` | `INT` |  |  |
| `bWaitDemandDrop` | `BOOL` |  | stopped: demand cleaning waits for bDemand / bEnable to drop |
| `tTimeLeft` | `TIME` |  | in the phase |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

## Lists

- `E_PulsePhase`: `Idle`, `StartDelay`, `PulseOn`, `PulseGap`, `ChannelGap`, `CyclePause` (default `Idle`)

## How it works

Sequential pulsing: jet-pulse filter cleaning, flush valves, staged outputs. `aOutputs` (the project's row of valves, one element per channel) is pulsed one at a time in order: each channel gets `set.nPulsesPerChannel` pulses of `tPulseOn` with `tPulseOff` between them, then `tChannelGap` before the next channel.

After the last channel the cycle is done (`bCycleDone` for one scan) and, while cleaning is still wanted, `tCyclePause` passes before the next cycle. Never more than one output is on.

Cleaning is wanted while `bEnable` AND `bDemand` (`bDemand` defaults TRUE, so `bEnable` alone runs it continuously), after `tStartDelay`. When that ends: `nPostCycles` = 0 stops at once (an output that is on goes off); `nPostCycles` > 0 finishes the cycle and runs that many more full cycles (post-clean, also after the fan stops). `bStart` / `bCmdStart` runs one full cycle now (a manual clean); `bStop` / `bCmdStop` stops at once, and demand cleaning waits until `bDemand` or `bEnable` has dropped and come back. `bHold` pauses where it is: the output goes off, the interrupted pulse is given again in full on release; gaps and pauses keep their remaining time.

Channels count from 1 = the first element, whatever the array's lower bound; `set.nSkip` bit n skips channel n+1 (channels above 32 cannot be skipped). Every channel skipped (or no outputs): `bError` NoChannels, nothing runs.

Nothing is kept over a power cut but the settings (a retained last-good copy, a bad write put back); `sts.nCycles` counts from power-up. A command the HMI keeps writing TRUE acts once.

## Example

Six jet-pulse valves on a dust filter, cleaning while the fan runs.

| Pin | Wire |
| --- | --- |
| `bEnable` | `DI_FanRunning` |
| `bDemand` | `DI_DpHigh` |
| `aOutputs` | `aPulseValves` |
| `refData` | `stPulse` |

**Back to** [the index](../README.md).
