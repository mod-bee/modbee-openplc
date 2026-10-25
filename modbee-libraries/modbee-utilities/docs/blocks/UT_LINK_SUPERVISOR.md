# UT_LINK_SUPERVISOR — Escalating recovery of a remote site's comms link

Gets a remote site back online by itself when its link to SCADA or the IoT platform
dies: first a modem restart, then a modem power cycle, then **one** controlled reboot of
the controller, then modem retries further and further apart. The reboots are counted
and limited per day, and the count is kept over the reboot itself, so a dead link can
never make the controller reboot in a loop.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `LinkOk` | BOOL | FALSE | The link works: `NOT` [UT_WATCHDOG](UT_WATCHDOG.md)`.CommsFail` on the SCADA heartbeat, the modem's connected flag. Unwired: the link is down from power-up |
| in | `RebootAllowed` | BOOL | TRUE | FALSE: no reboot now (e.g. while equipment runs); the reboot waits and happens once allowed, in the same outage |
| in | `Clock` | DT | DT#1970-01-01-00:00:00 | Local time, for the reboots-per-day count. Unwired or not set: a rolling window instead (see below) |
| out | `RestartModem` | BOOL | | TRUE for `pulseTime`: restart the modem (its restart input or command) |
| out | `PowerCycle` | BOOL | | TRUE for `powerOffTime`: switch the modem's power off (a relay or HAT power, TRUE = off) |
| out | `RebootReq` | BOOL | | Reboot the controller; held until it does |
| out | `LinkDown` | BOOL | | The link is down |
| inout | `Data` | UT_LINK_SUPERVISOR_DATA | | |

## Record `UT_LINK_SUPERVISOR_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `restartAfter` | TIME | T#30s | Link down this long: restart the modem (0 = step off) |
| `powerCycleAfter` | TIME | T#5m | Link down this long: power cycle the modem (0 = step off) |
| `rebootAfter` | TIME | T#10m | Link down this long: reboot the controller once (0 = step off) |
| `pulseTime` | TIME | T#1s | `RestartModem` pulse length |
| `powerOffTime` | TIME | T#10s | How long the modem stays off |
| `maxBackoff` | TIME | T#10m | The longest wait between retries |
| `maxRebootsPerDay` | INT | 3 | Reboots allowed in one day (0 = never reboot) |
| `rebootSaveWait` | TIME | T#3s | The count is saved this long before `RebootReq` |
| `countWindow` | TIME | T#24h | No clock: the count starts again this long (running time) after the first counted reboot |
| `cmdResetReboots` | BOOL | | HMI: set the reboot count to 0 (acts once, on its rising edge, and is cleared) |
| `linkOk` | BOOL | | Status: the link is up |
| `downFor` | TIME | | Status: time the link has been down (0 while up) |
| `timeLeft` | TIME | | Status: time to the next step (0 = none) |
| `nextStep` | INT | | Status: the next step: 1 modem restart, 2 power cycle, 3 reboot, 0 none |
| `rebootPending` | BOOL | | Status: the reboot is due but `RebootAllowed` is FALSE |
| `rebootsToday` | INT | | Status: reboots counted in this day or window (**kept over a reboot or power cut**) |
| `restarts`, `powerCycles`, `outages` | UDINT | | Status: since power-up |
| `lastDownFor` | TIME | | Status: how long the last outage lasted |
| `statusCode` | UT_STATUS | | Status: what it is doing (codes below) |
| `statusText` | STRING(30) | | Status: `statusCode` in words. The times are in `downFor` and `timeLeft` |
| `countResetIn` | TIME | | Status: no clock, reboots counted: time until the count starts again (0 = none) |

### Status codes
`statusCode` is a `UT_STATUS` (an HMI reads its number); `statusText` is the same in
words. `downFor` says how long the link has been down, `timeLeft` the time to the step.

| `statusCode` | `statusText` | When |
| --- | --- | --- |
| `UT_ST_LINK_OK` | `Link OK` | The link is up |
| `UT_ST_LINK_RESTART` | `Link down: modem restart` | Waiting for the modem restart step |
| `UT_ST_LINK_POWER_CYCLE` | `Link down: power cycle` | Waiting for the power cycle step |
| `UT_ST_LINK_REBOOT` | `Link down: reboot` | Waiting for the reboot step |
| `UT_ST_LINK_REBOOT_WAITS` | `Link down: reboot not allowed` | The reboot is due, `RebootAllowed` FALSE |
| `UT_ST_LINK_NO_STEPS` | `Link down: no more steps` | Every step done or off, no retries |
| `UT_ST_LINK_RETRY` | `Link down: retry` | Modem retries with the back-off |
| `UT_ST_LINK_REBOOTING` | `Link down: rebooting` | `RebootReq` is on (or the count was saved and it follows) |

## How it works
- The steps are timed from when the link went down (or from power-up, if it is down
  then). Each is optional (its time 0 = off). The outputs are pulses of their full
  length, even if the link comes back meanwhile.
- **Retries**: once the restart and power cycle steps are past, the modem is tried
  again (a power cycle, or a restart if the power cycle step is off). The first retry
  comes `restartAfter` after the last step (`powerCycleAfter` if the restart step is
  off), each wait twice the one before, up to `maxBackoff`. The back-off starts again
  once the link has stayed up for `maxBackoff`; a short flap keeps it.
- **Reboots**: at most `maxRebootsPerDay`. The reboot is counted and saved first;
  `RebootReq` follows `rebootSaveWait` later, so the count survives the reboot. At the
  limit no reboot is asked for, however long the link stays down: the retries go on.
- **The day**: with a set `Clock` (2000 or later), the count starts again at each date
  change. Without one (unwired, or the clock not set yet), it starts again
  `countWindow` of running time after the first counted reboot: a rolling window. Its
  progress is saved in 24 steps (one an hour by default), so a reboot or a power cut
  loses at most one step and the window only gets longer; time switched off does not
  count. `countResetIn` shows when it ends.
- **Kept over a power cut**: only the reboot count, its day and the window's progress.

## Using it
```iecst
LinkSup(LinkOk := NOT ScadaWd.CommsFail, RebootAllowed := NOT P1.Running, Clock := Now,
        Data := LinkSupCfg);
ModemRestart := LinkSup.RestartModem;
ModemPowerOff := LinkSup.PowerCycle;      (* relay contact in the modem's supply *)
IF LinkSup.RebootReq THEN
  (* ask the controller to reboot *)
END_IF;
```
