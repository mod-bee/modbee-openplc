# FB_PulseSeq — Sequential pulsing

Sequential pulsing (jet-pulse filter cleaning, flush valves): one output at a time, in order, with gaps and pauses, on demand or continuously.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bEnable` | `BOOL` |  | allow operation (e.g. the fan running) |
| in | `bCleaningDemand` | `BOOL` | `TRUE` | on-demand cleaning (e.g. DP high); TRUE for continuous |
| in | `bPause` | `BOOL` |  | pause where it is |
| in | `bCleanCycleNow` | `BOOL R_EDGE` |  | one full cleaning cycle now |
| in | `bStop` | `BOOL R_EDGE` |  | stop now |
| in | `refData` | `REFERENCE TO ST_PulseSeqData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aOutputs` | `ARRAY[*] OF BOOL` |  | the project's row of valves, one element per channel |
| out | `bBusy` | `BOOL` |  | cleaning is running |
| out | `nChannelNow` | `INT` |  | the channel pulsing (0 = none) |
| out | `bCycleDone` | `BOOL` |  | one scan at the end of each full cycle |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_PulseSeqData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdCleanCycleNow` | `BOOL` |  | one full cleaning cycle now (cleared by the block) |
| `bCmdStop` | `BOOL` |  | stop now (cleared by the block) |

**Settings `set`** (`ST_PulseSeqSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nPulsesPerChannel` | `INT` | `1` | pulses on each channel per cycle |
| `tPulseOnTime` | `TIME` | `T#100ms` | valve open time (at least one scan) |
| `tGapBetweenPulses` | `TIME` | `T#1s` | gap between pulses on the same channel |
| `tGapBetweenChannels` | `TIME` | `T#10s` | gap between channels (the air tank recovers) |
| `tPauseAfterCycle` | `TIME` | `T#60s` | pause after a full cycle |
| `tStartDelay` | `TIME` |  | after bEnable and bCleaningDemand come on |
| `nPostCleanCycles` | `INT` |  | full cycles after bCleaningDemand or bEnable drops (post-clean) |
| `nSkipChannelBits` | `DWORD` |  | bit n = skip channel n+1 (a faulty valve) |

**Status `sts`** (`ST_PulseSeqSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `ePulsePhase` | `E_PulsePhase` |  | Idle, StartDelay, PulseOn, PulseGap, ChannelGap or CyclePause |
| `nChannelNow` | `INT` |  | pulsing, or next after its channel gap (0 = none) |
| `nPulseOnChannel` | `INT` |  | the pulse number on this channel |
| `nCycleCount` | `UDINT` |  | cycles completed since power-up |
| `nPostCleanCyclesLeft` | `INT` |  | post-clean cycles still to run |
| `bWaitDemandDrop` | `BOOL` |  | stopped: demand cleaning waits for bCleaningDemand / bEnable to drop |
| `tTimeLeft` | `TIME` |  | in the phase |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Lists

- `E_PulsePhase`: `Idle`, `StartDelay`, `PulseOn`, `PulseGap`, `ChannelGap`, `CyclePause` (default `Idle`)

## How it works

Sequential pulsing: jet-pulse filter cleaning, flush valves, staged outputs. `aOutputs` (the project's row of valves, one element per channel) is pulsed one at a time in order: each channel gets `set.nPulsesPerChannel` pulses of `tPulseOnTime` with `tGapBetweenPulses` between them, then `tGapBetweenChannels` before the next channel.

After the last channel the cycle is done (`bCycleDone` for one scan) and, while cleaning is still wanted, `tPauseAfterCycle` passes before the next cycle. Never more than one output is on.

Cleaning is wanted while `bEnable` AND `bCleaningDemand` (`bCleaningDemand` defaults TRUE, so `bEnable` alone runs it continuously), after `tStartDelay`. When that ends: `nPostCleanCycles` = 0 stops at once (an output that is on goes off); `nPostCleanCycles` > 0 finishes the cycle and runs that many more full cycles (post-clean, also after the fan stops). `bCleanCycleNow` / `bCmdCleanCycleNow` runs one full cycle now (a manual clean); `bStop` / `bCmdStop` stops at once, and demand cleaning waits until `bCleaningDemand` or `bEnable` has dropped and come back. `bPause` pauses where it is: the output goes off, the interrupted pulse is given again in full on release; gaps and pauses keep their remaining time.

Channels count from 1 = the first element, whatever the array's lower bound; `set.nSkipChannelBits` bit n skips channel n+1 (channels above 32 cannot be skipped). Every channel skipped (or no outputs): `bError` NoChannels, nothing runs.

Nothing is kept over a power cut but the settings (a retained last-good copy, a bad write put back); `sts.nCycleCount` counts from power-up. A command the HMI keeps writing TRUE acts once.

## Example

Six jet-pulse valves on a dust filter, cleaning while the fan runs.

| Pin | Wire |
| --- | --- |
| `bEnable` | `DI_FanRunning` |
| `bCleaningDemand` | `DI_DpHigh` |
| `aOutputs` | `aPulseValves` |
| `refData` | `stPulse` |

**Back to** [the index](../README.md).
