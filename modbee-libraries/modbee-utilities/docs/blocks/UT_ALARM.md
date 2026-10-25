# UT_ALARM — One alarm (ISA-18.2 states)

Turns a condition into a properly managed alarm: on/off delays, acknowledge,
latching, operator shelving, suppress-by-design (`Inhibit`), out-of-service,
priority and counts. Group alarms with [UT_ANNUNCIATOR](UT_ANNUNCIATOR.md) by
putting their records in an array. The alarm's message is kept in the HMI, by the
alarm's number (its place in the array); the record holds no text.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | BOOL | FALSE | The alarm condition |
| in | `Inhibit` | BOOL | FALSE | Suppressed by design (e.g. low-flow alarm while the pump is off) |
| in | `Ack` | BOOL | FALSE | Rising edge: acknowledge |
| in | `Clock` | DT | unwired | Real-time clock for the time stamps (e.g. [UT_SCHEDULE](UT_SCHEDULE.md)'s `Data.localTime`); unwired = the controller clock (UTC) |
| out | `Q` | BOOL | | Alarm to annunciate (active, or latched and not yet acknowledged) |
| out | `Unacked` | BOOL | | Needs acknowledging (flash it) |
| out | `Active` | BOOL | | Condition present now (after the delays), even while shelved or suppressed |
| inout | `Data` | UT_ALARM_DATA | | |

## Record `UT_ALARM_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `onDelay` | TIME | T#0s | The condition must last this long to raise the alarm |
| `offDelay` | TIME | T#0s | And be gone this long to clear it |
| `latch` | BOOL | FALSE | `Q` stays on until the condition has cleared **and** it's acknowledged |
| `ackRequired` | BOOL | TRUE | FALSE = no acknowledge needed (event / status alarm); `latch` then has no effect |
| `priority` | UT_PRIORITY | UT_PRIO_MEDIUM | |
| `maxShelve` | TIME | T#8h | Longest an operator may shelve it. T#0s = shelving not allowed |
| `shelveFor` | TIME | T#0s | How long `cmdShelve` shelves it. T#0s = `maxShelve`; longer than `maxShelve` is cut to it |
| `cmdAck` | BOOL | | HMI: acknowledge |
| `cmdShelve` | BOOL | | HMI: shelve for `shelveFor` (again while shelved: starts over) |
| `cmdUnshelve` | BOOL | | HMI: unshelve now |
| `cmdOutOfService` | BOOL | | HMI: out of service |
| `cmdInService` | BOOL | | HMI: back in service |
| `cmdResetCount` | BOOL | | HMI: `count` back to 0 |
| `state` | UT_ALARM_STATE | | Status, see below |
| `active` | BOOL | | Status: same as `Active` |
| `unacked` | BOOL | | Status: same as `Unacked` |
| `shelvedFor` | TIME | | Status: shelve time left |
| `count` | UDINT | | Status: alarms raised |
| `lastDuration` | TIME | | Status: how long the condition lasted last time |
| `sequence` | UDINT | | Status: when it was last raised (milliseconds, wraps after 49 days). Orders alarms for the first-out |
| `grpNew` | BOOL | | Set when the alarm is raised, cleared by UT_ANNUNCIATOR (so it knows to sound the horn). Don't write it |
| `raisedAt` | DT | | Status: when it was last raised (from `Clock`) |
| `ackedAt` | DT | | Status: when it was last acknowledged |
| `clearedAt` | DT | | Status: when its condition last cleared |

## States — `UT_ALARM_STATE`
| State | Condition | Q | Unacked | Next |
| --- | --- | --- | --- | --- |
| `UT_ALM_NORMAL` (0) | clear | | | condition → UNACKED |
| `UT_ALM_UNACKED` | present | ✔ | ✔ | ack → ACKED; clears → RTN_UNACKED |
| `UT_ALM_ACKED` | present | ✔ | | clears → NORMAL |
| `UT_ALM_RTN_UNACKED` | cleared before ack | only if `latch` | ✔ | ack → NORMAL; comes back → UNACKED |
| `UT_ALM_SHELVED` | any | | | expiry or `cmdUnshelve` |
| `UT_ALM_SUPPRESSED` | any | | | `Inhibit` off |
| `UT_ALM_OOS` | any | | | `cmdInService` |

- Out of service beats suppressed, suppressed beats shelved.
- A shelved, suppressed or out-of-service alarm is hidden completely. When it comes back
  with the condition still present it's **raised again as a new alarm** (counted, needs
  an ack); if the condition has gone it comes back NORMAL.
- With `ackRequired` FALSE the alarm goes straight to ACKED; switching `ackRequired`
  off acknowledges it.
- When two commands arrive together the alarm stays live: `cmdInService` beats
  `cmdOutOfService`, `cmdUnshelve` beats `cmdShelve`.
- A command held on (a Modbus coil left on, a debugger force) acts only once. A command
  written again in the very next scan counts as held.
- An ack while shelved, suppressed or out of service does nothing.
- Negative times count as zero.
- `raisedAt`, `ackedAt` and `clearedAt` are stamped from `Clock` and each keeps the
  last one (`DT#1970-01-01-00:00:00` until the first). Unwired, the controller clock
  is used, which is UTC; wire a local clock for local times.

## Power cut
Nothing is kept. After a power-up the alarm is in service and not shelved, `count` is
0, and an alarm whose condition is still present is raised again.

## Using it
```iecst
LowFlowAlm(In := Flow < 2.0, Inhibit := NOT PumpRunning, Ack := AckPB, Data := Alarms[3]);
```
