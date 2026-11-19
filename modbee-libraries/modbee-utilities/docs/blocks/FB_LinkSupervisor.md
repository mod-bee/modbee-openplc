# FB_LinkSupervisor — Comms link recovery

Escalating recovery of a remote site's comms link: restart the modem, power cycle it, and at most a few controlled reboots a day.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bLinkGood` | `BOOL` |  | the link works (heartbeat seen, modem connected) |
| in | `bEnable` | `BOOL` | `TRUE` | the link is in use |
| in | `bRebootAllowed` | `BOOL` |  | "nothing running, no lock-out": a reboot may happen |
| in | `dtLocalTime` | `DT` |  | local time, for the reboots-per-day count (unset: no date change) |
| in | `bResetReboots` | `BOOL R_EDGE` |  | the reboot count to 0 |
| in | `refData` | `REFERENCE TO ST_LinkSupervisorData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bRestartModem` | `BOOL` |  | TRUE for tModemRestartPulseLength: restart the modem |
| out | `bPowerCycleModem` | `BOOL` |  | TRUE for tModemPowerOffTime: switch the modem's power off |
| out | `bRebootRequest` | `BOOL` |  | reboot the controller (held until it does) |
| out | `bLinkDown` | `BOOL` |  | the link is down |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_LinkSupervisorData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetReboots` | `BOOL` |  | cleared by the block |

**Settings `set`** (`ST_LinkSupervisorSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tModemRestartAfter` | `TIME` | `T#30s` | link down this long: restart the modem (0 = step off) |
| `tModemPowerCycleAfter` | `TIME` | `T#5m` | ... power cycle the modem (0 = step off) |
| `tControllerRebootAfter` | `TIME` |  | ... reboot the controller once (0 = off, the default) |
| `tModemRestartPulseLength` | `TIME` | `T#1s` | bRestartModem pulse length |
| `tModemPowerOffTime` | `TIME` | `T#10s` | bPowerCycleModem: how long the modem stays off |
| `tMaxWaitBetweenRetries` | `TIME` | `T#10m` | the longest wait between retries |
| `nMaxRebootsPerDay` | `INT` | `3` | 0 = never reboot |
| `tSaveBeforeReboot` | `TIME` | `T#3s` | the count is kept this long before bRebootRequest |
| `tRebootCountWindow` | `TIME` | `T#24h` | no clock: the count starts again this long after the first counted reboot |

**Status `sts`** (`ST_LinkSupervisorSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bLinkGood` | `BOOL` |  | the link works now |
| `nNextRecoveryStep` | `INT` |  | 1 modem restart, 2 power cycle, 3 reboot, 0 none |
| `bRebootPending` | `BOOL` |  | the reboot is due but bRebootAllowed is FALSE |
| `nRebootCountToday` | `INT` |  | kept over a reboot |
| `nModemRestartCount` | `UDINT` |  | modem restarts since power-up |
| `nModemPowerCycleCount` | `UDINT` |  | modem power cycles since power-up |
| `nOutageCount` | `UDINT` |  | link outages since power-up |
| `tLastOutageTime` | `TIME` |  | how long the last outage lasted |
| `tCurrentOutageTime` | `TIME` |  | how long the link has been down now |
| `tTimeLeft` | `TIME` |  | time left to the next recovery step |
| `tRebootCountResetTimeLeft` | `TIME` |  | time until the reboot count starts again |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## How it works

Escalating recovery of a remote site's comms link. `bLinkGood` comes from whatever checks the link (an [`FB_Watchdog`](FB_Watchdog.md) on the SCADA heartbeat, the modem's connected flag).

While it is FALSE the supervisor steps up, each step optional (its time 0 = off), timed from when the link went down (or from power-up, if it is down then):

```
  tModemRestartAfter     (30 s)  bRestartModem for tModemRestartPulseLength
  tModemPowerCycleAfter  (5 min) bPowerCycleModem for tModemPowerOffTime
  tControllerRebootAfter      (off)   ONE controlled reboot of the controller: bRebootRequest until it reboots
```

After those the modem is tried again with a back-off: the first retry `tModemRestartAfter` after the last step (`tModemPowerCycleAfter` if the restart step is off), each wait twice the one before, up to `tMaxWaitBetweenRetries` (10 min). A retry power cycles the modem (or restarts it, if the power cycle step is off). The back-off starts again once the link has stayed up for `tMaxWaitBetweenRetries`.

The reboot happens only while `bRebootAllowed` (the program vetoes it while equipment runs; it waits and reboots once allowed, in the same outage), and at most `nMaxRebootsPerDay` times a day. The count is kept over the reboot itself (and any power cut), so a dead link can never make the controller reboot in a loop: it is counted and kept first; `bRebootRequest` follows `tSaveBeforeReboot` later. With a set `dtLocalTime` (local time, 2000 or later) the count starts again at each date change; without one it starts again `tRebootCountWindow` (24 h) of running time after the first counted reboot (a rolling window, kept over reboots, saved in 24 steps; time switched off does not count). `bResetReboots` / `bCmdResetReboots` sets the count to 0. Not in use (`bEnable` FALSE): nothing is done.

Outputs: wire `bRestartModem` to the modem block's restart, `bPowerCycleModem` to the relay or HAT power feeding the modem (TRUE = off), `bRebootRequest` to the controller's reboot. Settings are kept (a retained last-good copy, a bad write put back).

## Example

A cellular remote site.

| Pin | Wire |
| --- | --- |
| `bLinkGood` | `fbWatchdog.bOk` |
| `bRebootAllowed` | `NOT DI_P1_Running` (nothing running) |
| `dtLocalTime` | the local time |
| `refData` | `stLink` |
| `bRestartModem` | the modem block's restart |
| `bPowerCycleModem` | the modem power relay |
| `bRebootRequest` | the controller's reboot |

**Back to** [the index](../README.md).
