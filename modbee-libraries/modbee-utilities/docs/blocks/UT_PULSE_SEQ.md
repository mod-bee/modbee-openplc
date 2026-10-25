# UT_PULSE_SEQ — Sequential pulsing (jet-pulse filters, flushing, staged outputs)

Pulses a row of outputs one after another: dust-collector cleaning valves,
irrigation flush valves, staged heaters. It can run continuously or on demand
(e.g. while the filter differential pressure is high), with post-clean cycles after
stopping. Any number of channels. Never more than one output is on.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Enable` | BOOL | FALSE | Allow operation (e.g. fan running) |
| in | `Demand` | BOOL | TRUE | On-demand cleaning (e.g. DP high from `UT_TWO_POINT`). Leave TRUE for continuous |
| in | `Hold` | BOOL | FALSE | Pause where it is |
| out | `Busy` | BOOL | | A cleaning run is in progress (pulses, gaps and pauses) |
| out | `Channel` | INT | | Channel pulsing, or between its pulses (0 = none, and during channel gaps and cycle pauses) |
| out | `CycleDone` | BOOL | | One scan at the end of each full cycle |
| inout | `Outputs` | ARRAY[*] OF BOOL | | One element per valve. Wire each with a contact → coil, or declare the array on located outputs |
| inout | `Data` | UT_PULSE_SEQ_DATA | | |

Channels count from 1 = the first element, whatever the array's lower bound.

## Record `UT_PULSE_SEQ_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `pulsesPerChannel` | INT | 1 | Pulses per channel (below 1 counts as 1) |
| `pulseOn` | TIME | T#100ms | Valve open time (at least one scan) |
| `pulseOff` | TIME | T#1s | Gap between pulses on the same channel |
| `channelGap` | TIME | T#10s | Gap between channels (lets the compressed-air tank recover) |
| `cyclePause` | TIME | T#60s | Pause after a full cycle |
| `startDelay` | TIME | T#0s | After `Enable` and `Demand` come on |
| `postCycles` | INT | 0 | Full cycles after `Demand` or `Enable` drops (post-clean) |
| `skip` | DWORD | 0 | Bit n = skip channel n+1 (faulty valve). Channels above 32 can't be skipped |
| `cmdStart` | BOOL | | HMI: one full cleaning cycle now (manual clean, needs neither Enable nor Demand) |
| `cmdStop` | BOOL | | HMI: stop now; demand cleaning waits until `Demand` or `Enable` drops and comes back |
| `channel` | INT | | Status: as `Channel`; in the gap before a channel, that channel (with `pulse` 0) |
| `pulse` | INT | | Status: pulse number on that channel |
| `cycles` | UDINT | | Status: full cycles done since the PLC started |
| `busy` | BOOL | | Status |
| `postLeft` | INT | | Status: post-clean cycles still to start |
| `configBad` | BOOL | | Status: a setting is invalid (a warning, see Bad settings) |
| `statusCode` | UT_STATUS | | Status: what it is doing, or what holds it back (see [Status codes](#status-codes)) |
| `faultId` | UT_FAULT | | Status: the setting the status is about (`UT_F_NONE` when none) |
| `statusText` | STRING(30) | | Status: `statusCode` and `faultId` in words, e.g. `Cleaning`. Where it is: `channel`, `pulse`, `timeLeft` |
| `timeLeft` | TIME | | Status: time left in the current phase (start delay, pulse, gap between pulses, channel gap, cycle pause); 0 when idle |

## How it works
- Each channel gets `pulsesPerChannel` pulses of `pulseOn` with `pulseOff` between
  them, then `channelGap` before the next channel. After the last channel `CycleDone`
  pulses and, while cleaning is still wanted, `cyclePause` passes before the next cycle.
- Cleaning is wanted while `Enable` AND `Demand`, after `startDelay`. When that ends:
  `postCycles` = 0 stops at once (an output that is on goes off); `postCycles` > 0
  finishes the cycle and runs that many more full cycles, even with `Enable` off
  (off-line cleaning after the fan stops). Demand coming back during the post-clean
  simply carries on cleaning.
- `Hold` turns the output off; on release the interrupted pulse is given again in full
  on the same channel. Gaps and pauses keep their remaining time.
- With every channel skipped nothing runs (no `CycleDone`).
- Each phase lasts at least one scan, so a pulse shorter than the scan lasts one scan.
- Nothing is kept over a power cut: every output is off, and cleaning starts again
  from channel 1 when wanted.

## Status codes
`statusCode` is a `UT_STATUS` and `faultId` a `UT_FAULT` (an HMI reads their numbers);
`statusText` is the two in words, changed only when one of them changes. The one main
thing, in the order config, held, warning, normal, idle. `channel`, `pulse` and
`timeLeft` (the phase's time left) say where it is.

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_OFF` | | `Off` | `Enable` off |
| `UT_ST_IDLE_NO_DEMAND` | | `Idle: no demand` | `Enable` on and no `Demand` |
| `UT_ST_CLEANING` | | `Cleaning` | Pulsing a channel, between its pulses, or in the gap before the next channel |
| `UT_ST_CLEAN_NEXT` | | `Cleaning: waiting next cycle` | The pause after a full cycle |
| `UT_ST_START_DELAY` | | `Waiting: start delay` | `startDelay` after Enable and Demand |
| `UT_ST_PAUSED_HOLD` | | `Paused: Hold input` | `Hold` during a run or the start delay |
| `UT_ST_WAIT_DEMAND_DROP` | | `Waiting: demand to drop` | After `cmdStop`, while Enable and Demand stay on |
| `UT_ST_WARN_SETTING` | `UT_F_SETTING` | `Setting: a setting` | See Bad settings: a safe value is used |
| `UT_ST_CONFIG` | `UT_F_ALL_SKIPPED` | `Config: all channels skipped` | Nothing can ever run |
| `UT_ST_CONFIG` | `UT_F_NO_OUTPUTS` | `Config: no outputs` | An empty `Outputs` array |

## Bad settings
Invalid settings warn (`configBad`) and use safe values: a negative time acts as 0
(`pulseOn` one scan), `pulsesPerChannel` below 1 as 1, `postCycles` below 0 as 0.
