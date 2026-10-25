# UT_ALARM_TABLE — All of a site's alarms in one block

Every alarm of a project in one array, one row each, with the siren (horn), the
beacon and one status line for the whole site. Each row has its own on and off
delay, warn or trip, and how it clears: by itself, latched until reset, or
retrying a few times and then locking out. The block holds no texts: the HMI shows
the row numbers, states and codes in its own words.

For alarms that need shelving, priorities and time stamps, use
[UT_ALARM](UT_ALARM.md) per alarm with [UT_ANNUNCIATOR](UT_ANNUNCIATOR.md).

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Silence` | BOOL | FALSE | Rising edge: silence the siren. A new alarm sounds again. Does not acknowledge |
| in | `Reset` | BOOL | FALSE | Rising edge: acknowledge every alarm, and reset the latched and locked-out ones whose condition has gone |
| out | `AnyWarning` | BOOL | | A warning alarm is on |
| out | `AnyTrip` | BOOL | | A trip alarm is on: stop the plant (or use each row's `q`) |
| out | `AnyUnacked` | BOOL | | An alarm waits for acknowledging (flash the lamp, e.g. with [UT_FLASHER](UT_FLASHER.md)) |
| out | `Siren` | BOOL | | Sound the siren / horn |
| out | `Beacon` | BOOL | | Light the beacon: an alarm is on, or waits for acknowledging |
| inout | `Alarms` | ARRAY[*] OF UT_AT_ALARM | | One row per alarm: its settings, its condition and its state |
| inout | `Data` | UT_ALARM_TABLE_DATA | | HMI commands and the summary |

**Number the rows from 1** (`ARRAY[1..n]`). The row number is the alarm's number for
the HMI and SCADA, and 0 means "none" in `first` and `latest`: a row 0 never shows
in the status line. Put the most important alarms in the lowest rows.

## Using it
```iecst
VAR
  AlmTab : UT_ALARM_TABLE;
  Alarms : ARRAY[1..20] OF UT_AT_ALARM;  (* 1 = sump high-high, 2 = pump 1 overload, ... *)
  AlmSt  : UT_ALARM_TABLE_DATA;
END_VAR

IF FirstScan THEN
  Alarms[1].response := UT_RESP_TRIP;
  Alarms[1].onDelay := T#5s;
  Alarms[1].code := UT_F_HIGH_HIGH;
  Alarms[2].response := UT_RESP_TRIP;
  Alarms[2].reset := UT_RST_MANUAL;
  Alarms[2].code := UT_F_OVERLOAD;
END_IF;

Alarms[1].in := SumpHighHigh;
Alarms[2].in := M1.Fault;
AlmTab(Silence := SilenceBtn, Reset := ResetBtn, Alarms := Alarms, Data := AlmSt);
Horn := AlmTab.Siren;
Beacon := AlmTab.Beacon;
```

## One alarm `UT_AT_ALARM`
Your logic writes `in` every scan. The settings have working defaults: a row with
only `in` wired is a warning that sounds the siren and clears by itself.

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `in` | BOOL | FALSE | The condition, written by your logic every scan |
| `response` | UT_RESPONSE | UT_RESP_WARN | `UT_RESP_OFF` (the alarm is switched off) · `UT_RESP_WARN` (a warning) · `UT_RESP_TRIP` (the plant must stop: use `q` or `AnyTrip`) |
| `reset` | UT_RESET_MODE | UT_RST_AUTO | `UT_RST_AUTO`: clears by itself when the condition goes · `UT_RST_MANUAL`: latched, stays on until `Reset` · `UT_RST_RETRY`: clears by itself, but locks out after too many raises (below) |
| `onDelay` | TIME | T#0s | The condition must last this long to raise the alarm |
| `offDelay` | TIME | T#0s | And be gone this long to clear it, or to allow its reset |
| `maxRetries` | USINT | 3 | RETRY: raises that may clear by themselves in the window. The next one locks out (0 = the first one locks out) |
| `retryWindow` | TIME | T#0s | RETRY: the window, from the first raise counted. `T#0s` = no window: the count clears only on a `Reset` |
| `siren` | BOOL | TRUE | This alarm sounds the siren |
| `rearm` | TIME | T#0s | Silenced or acknowledged but still on after this long: it sounds again and needs acknowledging again. `T#0s` = never |
| `code` | UT_FAULT | UT_F_CONDITION | What it is, for the status line and SCADA (e.g. `UT_F_OVERLOAD`, `UT_F_HIGH_HIGH`, `UT_F_DRY_RUN`) |
| `state` | UT_AT_STATE | | Status: below |
| `q` | BOOL | | Status: the alarm is on (ACTIVE, LATCHED or LOCKED) |
| `unacked` | BOOL | | Status: waits for acknowledging |
| `retries` | USINT | | Status: raises counted in the retry window |
| `cond`, `inPrev`, `silenced`, `t`, `tWin`, `tAck` | | | Kept by the block. Don't write them |

## States `UT_AT_STATE`
| No. | State | Condition | `q` | Next |
| --- | --- | --- | --- | --- |
| 0 | `UT_AT_NORMAL` | Gone | | The condition lasts `onDelay` → ACTIVE (RETRY past its count: LOCKED) |
| 1 | `UT_AT_ACTIVE` | Present | yes | Gone for `offDelay`: MANUAL → LATCHED; AUTO / RETRY → RETURNED if not yet acknowledged, else NORMAL |
| 2 | `UT_AT_RETURNED` | Went before it was acknowledged | | `Reset` → NORMAL; the condition again → ACTIVE |
| 3 | `UT_AT_LATCHED` | Gone (MANUAL) | yes | `Reset` → NORMAL; the condition again → ACTIVE |
| 4 | `UT_AT_LOCKED` | Present or gone | yes | `Reset` once the condition has gone → NORMAL. The condition again: stays LOCKED and is annunciated again |
| 5 | `UT_AT_OFF` | (ignored) | | `response` set to WARN or TRIP → NORMAL |

## Record `UT_ALARM_TABLE_DATA`
| Field | Type | Meaning |
| --- | --- | --- |
| `cmdSilence` | BOOL | HMI: silence the siren |
| `cmdReset` | BOOL | HMI: acknowledge all, reset what can be reset |
| `statusCode` | UT_STATUS | Status: the first trip, else the first warning, else OK (below) |
| `faultId` | UT_FAULT | Status: that alarm's `code` |
| `statusText` | STRING(30) | Status: the two in words, e.g. `Latched: overload` |
| `first` | INT | Status: the row shown in the status line (0 = none) |
| `latest` | INT | Status: the row raised last (0 = none yet) |
| `onCount` | INT | Status: alarms on (`q`) |
| `tripCount` | INT | Status: trip alarms on |
| `unackedCount` | INT | Status: alarms waiting for acknowledging |

The commands act once, on their rising edge, and the block clears them. A command
held on (a Modbus coil left on) acts once.

## Status
The status line names **one** alarm: the lowest row with a trip on, else the lowest
row with a warning on. A trip in row 9 beats a warning in row 1. The words are the
prefix and the alarm's `code` ([UT_STATUS_TEXT](UT_STATUS_TEXT.md)). The text is
rebuilt only when the code or the fault changes. The numbers are in
[conventions](../conventions.md#the-numbers).

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_FAULT` | its `code` | `Fault: <code>`, e.g. `Fault: overload` | The first trip is ACTIVE |
| `UT_ST_FAULT_RESET` | its `code` | `Latched: <code>` | The first trip is LATCHED (MANUAL, the condition has gone) |
| `UT_ST_FAULT_LOCKED` | its `code` | `Locked: <code>`, e.g. `Locked: dry run` | The first trip is LOCKED |
| `UT_ST_WARNING` | its `code` | `Warning: <code>`, e.g. `Warning: high` | No trip on; the first warning is on (ACTIVE, LATCHED or LOCKED alike) |
| `UT_ST_WARN_SETTING` | `UT_F_SETTING` | `Setting: a setting` | No alarm on, and a row has a negative time |
| `UT_ST_OK` | | `OK` | No alarm on |

A row with no `code` of its own reads `condition`, e.g. `Warning: condition`.

## How it works
1. **Delays.** The condition must last `onDelay` to raise the alarm, and be gone
   `offDelay` to clear it. Each delay counts from the last change of `in`, so a
   pulse shorter than `onDelay` is ignored.
2. **Raise.** The alarm goes ACTIVE (or LOCKED, below), waits for acknowledging,
   and sounds the siren if its `siren` is TRUE. `latest` is set to its row.
3. **Clear.** When the condition has gone: AUTO and RETRY alarms go to RETURNED until
   acknowledged (or straight to NORMAL if already acknowledged); MANUAL alarms go to
   LATCHED and stay on until `Reset`.
4. **Retry and lockout** (RETRY). Each raise is counted (`retries`) from the first in
   the window. Up to `maxRetries` raises clear by themselves; the next one within
   `retryWindow` goes LOCKED and stays on until a `Reset` with the condition gone.
   When the window has passed, the count starts again. With `retryWindow` `T#0s`
   the count clears only on a `Reset`.
5. **Reset** (the pin or `cmdReset`) acknowledges every alarm. For each alarm whose
   condition has gone (and stayed gone `offDelay`), it also clears `retries` and
   puts a LATCHED, LOCKED or RETURNED alarm back to NORMAL. Pressed while the
   condition is still there, it only acknowledges.
6. **Siren.** An alarm sounds while its `siren` is TRUE, it waits for acknowledging,
   it is not silenced, and its condition is present (ACTIVE, or LOCKED with the
   condition back). So the siren stops on `Silence`, on `Reset`, or when the
   condition goes; the beacon stays on until it is acknowledged.
7. **Silence** (the pin or `cmdSilence`) silences the alarms sounding now. It does
   not acknowledge them. A new alarm, raised later, sounds again.
8. **Re-arm.** An alarm whose condition is still present `rearm` after it was
   silenced or acknowledged waits for acknowledging again and sounds again (if
   `siren`). `T#0s` = never.
9. **Beacon** is on while any alarm is on (`q`) or waits for acknowledging. It is
   steady: flash a lamp from `AnyUnacked` if you want one.
10. **Response OFF** switches a row off: its state is OFF, nothing is annunciated,
    its retries are cleared. Set back to WARN or TRIP, it starts at NORMAL.
11. Changing a LATCHED alarm's `reset` from MANUAL to AUTO or RETRY puts it back to
    NORMAL.

### Invalid settings
- A negative `onDelay`, `offDelay`, `retryWindow` or `rearm` works as `T#0s`, with
  `Setting: a setting` while no alarm is on.
- An unknown `response` acts as WARN, an unknown `reset` as AUTO.

### Power cut
The block keeps nothing: every alarm starts NORMAL, and a condition still present
raises it again (after `onDelay`). This assumes the `Alarms` array is not `RETAIN`:
a retained array keeps the states with the settings. Write the settings from your
program instead (as in the example).
