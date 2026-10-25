# UT_ANNUNCIATOR — Alarm group: horn, lamp, first-out, ack / silence / test

Drives a panel horn and alarm lamp (or beacon) for a group of
[UT_ALARM](UT_ALARM.md)s. It follows the standard annunciator sequence: a new
alarm gives a fast flash plus the horn; after acknowledge the lamp goes steady;
an alarm cleared but not acknowledged gives a slow flash. It also identifies which
alarm came first.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Ack` | BOOL | FALSE | Rising edge: acknowledge all (panel button) |
| in | `Silence` | BOOL | FALSE | Rising edge: silence the horn without acknowledging |
| in | `LampTest` | BOOL | FALSE | Lamp and horn on while held |
| out | `Horn` | BOOL | | |
| out | `Lamp` | BOOL | | Fast flash = new, steady = acknowledged, slow flash = cleared/unacked |
| out | `AnyActive` | BOOL | | Any alarm present |
| out | `AnyUnacked` | BOOL | | Any alarm waiting for acknowledgement |
| out | `FirstOut` | INT | | Array index of the first alarm in the current event (none: one below the first index, so 0 for `ARRAY[1..n]`) |
| out | `Highest` | UT_PRIORITY | | Highest priority present (`UT_PRIO_LOW` when none) |
| out | `ActiveCount` | INT | | Alarms present |
| inout | `Alarms` | ARRAY[*] OF UT_ALARM_DATA | | The group's alarm records |
| inout | `Data` | UT_ANNUN_DATA | | |

## Record `UT_ANNUN_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `hornPriority` | UT_PRIORITY | UT_PRIO_LOW | Only alarms at or above this sound the horn |
| `hornTimeout` | TIME | T#0s | The horn stops by itself after this (0 = never) |
| `reHorn` | TIME | T#0s | Sound again after this while still unacknowledged (0 = off) |
| `fastFlash` | TIME | T#250ms | New alarm: lamp on this long, off this long (0 = steady) |
| `slowFlash` | TIME | T#1s | Cleared, not acknowledged: lamp on this long, off this long (0 = steady) |
| `cmdAck` | BOOL | | HMI: acknowledge all |
| `cmdSilence` | BOOL | | HMI: silence the horn |
| `firstOut` | INT | | Status: same as `FirstOut`. The HMI shows that alarm's message by its index |
| `activeCount` | INT | | Status: alarms present |
| `unackedCount` | INT | | Status: alarms waiting for acknowledgement |

## How it works
| Alarms in the group | Lamp |
| --- | --- |
| any new (UNACKED) | fast flash |
| else any cleared, not acknowledged (RTN_UNACKED) | slow flash |
| else any present and acknowledged | steady |
| none | off |

- **Horn**: sounds for each **new** alarm at or above `hornPriority`, until `Ack`,
  `Silence`, `hornTimeout`, or until nothing at that priority is left to acknowledge
  (e.g. acknowledged one by one on the HMI). A new alarm after a silence sounds it again.
- **Ack** writes `cmdAck` into every unacknowledged alarm in the group; each alarm
  acknowledges itself on its next call. The horn stops at once.
- **First-out**: the event starts when the first alarm appears in a quiet group. The
  alarm with the earliest `sequence` is the first-out (alarms raised in the same
  millisecond: the lowest index). It stays until the event is over, i.e. no alarm is
  present or waiting for acknowledgement.
- Shelved, suppressed and out-of-service alarms are ignored completely.
- A flash shorter than the PLC scan can't be shown: the lamp then changes every scan.
- A command held on acts only once.
- An empty group is fine: everything stays off.

## Using it
```iecst
VAR  PumpAlarms : ARRAY[1..3] OF UT_ALARM_DATA;  END_VAR

A1(In := P1Fault, Data := PumpAlarms[1]);
A2(In := P2Fault, Data := PumpAlarms[2]);
A3(In := HighLevel, Data := PumpAlarms[3]);
Panel(Ack := AckPB, Silence := SilencePB, LampTest := TestPB, Alarms := PumpAlarms, Data := PanelCfg);
Siren := Panel.Horn;
Beacon := Panel.Lamp;
```
