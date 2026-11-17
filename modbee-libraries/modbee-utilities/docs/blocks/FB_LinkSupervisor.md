# FB_LinkSupervisor — Comms link recovery

Escalating recovery of a remote site's comms link: restart the modem, power cycle it, and at most a few controlled reboots a day.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bLinkOk` | `BOOL` |  | the link works (heartbeat seen, modem connected) |
| in | `bEnable` | `BOOL` | `TRUE` | the link is in use |
| in | `bRebootAllowed` | `BOOL` |  | "nothing running, no lock-out": a reboot may happen |
| in | `dtClock` | `DT` |  | local time, for the reboots-per-day count (unset: no date change) |
| in | `bResetReboots` | `BOOL R_EDGE` |  | the reboot count to 0 Acts on its rising edge. |
| in | `refData` | `REFERENCE TO ST_LinkSupervisorData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bRestartModem` | `BOOL` |  | TRUE for tPulse: restart the modem |
| out | `bPowerCycle` | `BOOL` |  | TRUE for tPowerOff: switch the modem's power off |
| out | `bRebootReq` | `BOOL` |  | reboot the controller (held until it does) |
| out | `bLinkDown` | `BOOL` |  | The link is down |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LinkSupervisorData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetReboots` | `BOOL` |  | cleared by the block |

**Settings `set`** (`ST_LinkSupervisorSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tRestartAfter` | `TIME` | `T#30s` | link down this long: restart the modem (0 = step off) |
| `tPowerCycleAfter` | `TIME` | `T#5m` | ... power cycle the modem (0 = step off) |
| `tRebootAfter` | `TIME` |  | ... reboot the controller once (0 = off, the default) |
| `tPulse` | `TIME` | `T#1s` | bRestartModem pulse length |
| `tPowerOff` | `TIME` | `T#10s` | bPowerCycle: how long the modem stays off |
| `tMaxBackoff` | `TIME` | `T#10m` | the longest wait between retries |
| `nMaxRebootsPerDay` | `INT` | `3` | 0 = never reboot |
| `tRebootSaveWait` | `TIME` | `T#3s` | the count is kept this long before bRebootReq |
| `tCountWindow` | `TIME` | `T#24h` | no clock: the count starts again this long after the first counted reboot |

**Status `sts`** (`ST_LinkSupervisorSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bLinkOk` | `BOOL` |  |  |
| `nNextStep` | `INT` |  | 1 modem restart, 2 power cycle, 3 reboot, 0 none |
| `bRebootPending` | `BOOL` |  | the reboot is due but bRebootAllowed is FALSE |
| `nRebootsToday` | `INT` |  | kept over a reboot |
| `nRestarts` | `UDINT` |  |  |
| `nPowerCycles` | `UDINT` |  |  |
| `nOutages` | `UDINT` |  |  |
| `tLastDownFor` | `TIME` |  |  |
| `tDownFor` | `TIME` |  |  |
| `tTimeLeft` | `TIME` |  | Time left in the delay or phase running now |
| `tCountResetIn` | `TIME` |  |  |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

## How it works

Escalating recovery of a remote site's comms link. `bLinkOk` comes from whatever checks the link (an [`FB_Watchdog`](FB_Watchdog.md) on the SCADA heartbeat, the modem's connected flag).

While it is FALSE the supervisor steps up, each step optional (its time 0 = off), timed from when the link went down (or from power-up, if it is down then):

```
  tRestartAfter     (30 s)  bRestartModem for tPulse
  tPowerCycleAfter  (5 min) bPowerCycle for tPowerOff
  tRebootAfter      (off)   ONE controlled reboot of the controller: bRebootReq until it reboots
```

After those the modem is tried again with a back-off: the first retry `tRestartAfter` after the last step (`tPowerCycleAfter` if the restart step is off), each wait twice the one before, up to `tMaxBackoff` (10 min). A retry power cycles the modem (or restarts it, if the power cycle step is off). The back-off starts again once the link has stayed up for `tMaxBackoff`.

The reboot happens only while `bRebootAllowed` (the program vetoes it while equipment runs; it waits and reboots once allowed, in the same outage), and at most `nMaxRebootsPerDay` times a day. The count is kept over the reboot itself (and any power cut), so a dead link can never make the controller reboot in a loop: it is counted and kept first; `bRebootReq` follows `tRebootSaveWait` later. With a set `dtClock` (local time, 2000 or later) the count starts again at each date change; without one it starts again `tCountWindow` (24 h) of running time after the first counted reboot (a rolling window, kept over reboots, saved in 24 steps; time switched off does not count). `bResetReboots` / `bCmdResetReboots` sets the count to 0. Not in use (`bEnable` FALSE): nothing is done.

Outputs: wire `bRestartModem` to the modem block's restart, `bPowerCycle` to the relay or HAT power feeding the modem (TRUE = off), `bRebootReq` to the controller's reboot. Settings are kept (a retained last-good copy, a bad write put back).

## Example

A cellular remote site.

| Pin | Wire |
| --- | --- |
| `bLinkOk` | `fbWatchdog.bOk` |
| `bRebootAllowed` | `NOT DI_P1_Running` (nothing running) |
| `dtClock` | the local time |
| `refData` | `stLink` |
| `bRestartModem` | the modem block's restart |
| `bPowerCycle` | the modem power relay |
| `bRebootReq` | the controller's reboot |

**Back to** [the index](../README.md).
