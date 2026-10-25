# UT_ALARM_BEACON — Flash alarm numbers on a single lamp

For sites with one fault lamp and no HMI. It steps through every active alarm in
turn and flashes its number, so a tech can read the fault code off the lamp.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Enable` | BOOL | TRUE | FALSE: lamp off, `Code` 0; on again starts over |
| out | `Lamp` | BOOL | | |
| out | `Code` | INT | | Alarm number being shown (0 = none) |
| out | `Active` | BOOL | | Any alarm (also while `Enable` is off) |
| inout | `Alarms` | ARRAY[*] OF BOOL | | Alarm n = element n (write with coils) |
| inout | `Data` | UT_BEACON_DATA | | |

## Record `UT_BEACON_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `style` | UT_BEACON_STYLE | UT_BEACON_COUNT | `UT_BEACON_COUNT`: the number as that many short flashes. `UT_BEACON_BINARY`: long = 1, short = 0, most significant bit first |
| `bits` | INT | 6 | Binary: bits shown (1..15). A number too big for `bits` uses as many as it needs |
| `shortTime` | TIME | T#250ms | Short flash (count, and binary 0) |
| `longTime` | TIME | T#1s | Long flash (binary 1) |
| `gapTime` | TIME | T#500ms | Lamp off between flashes |
| `pauseTime` | TIME | T#3s | Lamp off between numbers |
| `steadyWhenNone` | BOOL | FALSE | Lamp on steady when no alarm is active (a "healthy" light); it goes off for `gapTime` before the first flash |
| `code` | INT | | Status: same as `Code` |
| `activeCount` | INT | | Status: alarms active |

## How it works
- Alarm number = index − lower bound + 1, so `ARRAY[0..9]` element 0 is alarm 1.
- After an idle spell it starts from the lowest active alarm, then shows each active
  alarm in turn and goes round again.
- A number that has started is always finished, even if its alarm clears meanwhile;
  then it moves on. Changing `style` mid-number takes effect at the next number.
- Each flash, gap and pause lasts at least one PLC scan, and is rounded up to whole scans.

| Number | Count | Binary, 6 bits |
| --- | --- | --- |
| 1 | 1 short | `SSSSSL` |
| 9 | 9 short | `SSLSSL` |
| 31 | 31 short | `SLLLLL` |

## Using it
```iecst
VAR  Faults : ARRAY[1..20] OF BOOL;  END_VAR
Faults[1] := P1Overload;
Faults[2] := P2Overload;
Faults[3] := HighLevel;
Beacon(Enable := TRUE, Alarms := Faults, Data := BeaconCfg);
FaultLamp := Beacon.Lamp;
```
