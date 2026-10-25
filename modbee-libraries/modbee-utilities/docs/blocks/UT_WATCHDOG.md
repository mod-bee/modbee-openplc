# UT_WATCHDOG — Comms / heartbeat monitor and generator

Tells you a remote device, link or task is **alive**: it watches a value that should
keep changing (a heartbeat bit or counter from a remote PLC, a Modbus register, an
MQTT message counter) and raises `CommsFail` when it stops. It also produces a
heartbeat for the other side to watch.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Beat` | BOOL | FALSE | Heartbeat bit from the remote (any change counts) |
| in | `Counter` | DINT | 0 | Or a counter/register from the remote (any change counts) |
| in | `Enable` | BOOL | TRUE | FALSE: not monitored (`Ok` and `CommsFail` off); on again starts over |
| in | `Reset` | BOOL | FALSE | Rising edge: reset a held failure (panel button) |
| out | `Ok` | BOOL | | Remote alive (off at start until the first change) |
| out | `CommsFail` | BOOL | | No change for `timeout` |
| out | `HeartbeatOut` | BOOL | | Toggles every `beatPeriod`; send this to the remote |
| out | `HeartbeatCount` | DINT | | Increments every `beatPeriod` |
| inout | `Data` | UT_WATCHDOG_DATA | | |

## Record `UT_WATCHDOG_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `timeout` | TIME | T#10s | No change for this long = link dead. Make it longer than the remote's beat and the PLC scan (T#0s: always failed) |
| `recoverTime` | TIME | T#0s | Must be alive this long before `Ok` returns (and AUTO clears `CommsFail`) |
| `beatPeriod` | TIME | T#1s | `HeartbeatOut` toggles every `beatPeriod` (0 = off) |
| `failReset` | UT_RESET_MODE | UT_RST_AUTO | AUTO clears by itself; RETRY as AUTO three times an hour, then as MANUAL; MANUAL holds `CommsFail` until reset |
| `cmdReset` | BOOL | | HMI: reset a held failure |
| `cmdResetCount` | BOOL | | HMI: `failures` and `downTime` back to 0 |
| `ok` | BOOL | | Status: same as `Ok` |
| `lastChange` | TIME | | Status: time since the remote last changed |
| `failures` | UDINT | | Status: comms failures |
| `downTime` | TIME | | Status: total time dead, from each timeout to the next change |

## How it works
- The failure is a [UT_PROTECT](UT_PROTECT.md) trip, so the reset modes work as on every
  device. A reset while the link is still dead is refused.
- A link that drops out again while recovering fails again (and is counted again).
- A link that is dead at start counts as a failure once `timeout` has passed.
- The heartbeat keeps going when `Enable` is off. A `beatPeriod` shorter than the scan
  toggles every scan.
- A held command acts once.
- **Power cut**: nothing is kept. `failures` and `downTime` start at 0, a held (MANUAL)
  failure is forgotten, and a link that is still dead fails again after `timeout`.

## Using it
```iecst
LinkWd(Counter := RemoteHeartbeatReg, Data := LinkWdCfg);
RemoteHeartbeatOut := LinkWd.HeartbeatCount;     (* write to the remote *)
CommsAlarm(In := LinkWd.CommsFail, Data := Alarms[5]);
```
