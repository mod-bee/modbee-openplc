# UT_INTERLOCK — Interlock / permissive list with first-out and bypass

Collects all the conditions that must be healthy before a device may run (guards,
pull cords, levels, pressures, upstream running…) into one `Ok` signal for the
device's `Interlock` or `Permissive` pin. It records **which condition tripped first**
(first-out) and allows controlled maintenance bypasses.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `BypassEnable` | BOOL | FALSE | Key switch / HMI permission that lets bypasses take effect. Always wire it (FALSE if bypasses are never allowed) |
| in | `Reset` | BOOL | FALSE | Rising edge: clear the first-out and the held conditions |
| out | `Ok` | BOOL | | All conditions OK (or bypassed) → device `Interlock`/`Permissive` |
| out | `FirstOut` | INT | | Position of the first condition to stop it since the last reset (0 = none) |
| out | `Bypassed` | BOOL | | At least one bypass is in effect (show it on the HMI!) |
| out | `NotOkCount` | INT | | Conditions holding `Ok` FALSE |
| inout | `Conditions` | ARRAY[*] OF UT_INTLK_COND | | One element per condition, any length |
| inout | `Data` | UT_INTLK_DATA | | |

## Condition slot `UT_INTLK_COND`
| Field | Type | Default | Who writes it | Meaning |
| --- | --- | --- | --- | --- |
| `ok` | BOOL | TRUE | **you** | Condition healthy |
| `delay` | TIME | T#0s | you | Must be not OK this long to count (filter) |
| `reset` | UT_RESET_MODE | UT_RST_AUTO | you | AUTO: OK again as soon as healthy. MANUAL: stays out until a reset (pull cord, e-stop). RETRY acts as MANUAL |
| `bypass` | BOOL | FALSE | you / HMI | Request a bypass (only effective with `BypassEnable`) |
| `bad` | BOOL | | block | Not OK now (before the delay) |
| `tripped` | BOOL | | block | Counts against `Ok` (after the delay, or held); still shown while bypassed |
| `latched` | BOOL | | block | MANUAL: held until a reset |
| `bypassed` | BOOL | | block | The bypass is in effect |
| `badFor` | TIME | | block | How long it has been not OK |
| `bypassFor` | TIME | | block | How long the bypass has been in effect |
| `delayLeft` | TIME | | block | Not OK and still within its `delay`: the time until it counts (0 otherwise) |
| `bypassLeft` | TIME | | block | Bypass in effect: the time until it drops out (0 = no bypass, or `bypassTimeout` 0) |

## Record `UT_INTLK_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bypassTimeout` | TIME | T#8h | A bypass drops out after this (0 = never) |
| `cmdReset` | BOOL | FALSE | HMI reset: acts once, on its rising edge (cleared by the block) |
| `ok`, `firstOut`, `bypassed`, `notOkCount` | | | *status*, as the pins |
| `trips` | UDINT | | *status*: times `Ok` went FALSE (not kept over a power cut) |
| `configBad` | BOOL | | *status*: a setting is invalid (a warning, see Bad settings) |
| `statusCode` | UT_STATUS | | *status*: what holds `Ok` FALSE, or a bypass in effect, or OK (see [Status codes](#status-codes)) |
| `faultId` | UT_FAULT | | *status*: `UT_F_CONDITION` when the status is about a condition (`statusCond`), the setting for a bad setting, else `UT_F_NONE` |
| `statusText` | STRING(30) | | *status*: `statusCode` and `faultId` in words, e.g. `Blocked: interlock` |
| `timeLeft` | TIME | | *status*: the countdown the status shows (a bypass's time left, or a condition's delay left); 0 when it shows none |
| `statusCond` | INT | | *status*: the condition the status is about, by its position from 1 (0 = none) |

## How it works
- **`Ok`** is FALSE while any condition is tripped and not bypassed, and always with no
  conditions at all (an empty array: a config fault, `configBad`).
- **Delay.** A condition counts once it has been not OK for its `delay`, timed from
  the scan it was first seen. A loss shorter than that, or a chattering input, never counts.
- **Reset.** `Reset` or `cmdReset`, each on its rising edge, clears the first-out and
  releases MANUAL conditions that are healthy again. A condition that is still not
  OK stays out: the reset is refused, not remembered. A reset held on (a stuck
  button, a Modbus coil left on, a debugger force) acts once: a pull cord pulled again
  stays out until a new reset.
- **First-out** is the first condition to stop it since the last reset. Several at
  once: the lowest position. After a reset with conditions still out: the lowest of
  those. It counts positions from 1, whatever the array's lower bound, so declare the
  array from 1 and `FirstOut` is the index.
- **Bypass.** `bypass` takes effect only while `BypassEnable` is TRUE. It drops out
  after `bypassTimeout`, and stays out until the request or `BypassEnable` goes FALSE
  and back. `Bypassed` shows any bypass in effect, even on a healthy condition. A
  MANUAL condition still latches while bypassed; reset it before removing the bypass.
- Every condition keeps its own timing in its element, so the array can be any length
  and the block has no fixed limit.

## Status codes
`statusCode` / `faultId` / `statusText` say why `Ok` is FALSE, or what to watch while
it is TRUE, and `statusCond` says which condition. The most important wins: config >
blocked > bypassed or a bad setting > OK. It names the **lowest condition holding `Ok`
FALSE now** (not the first-out, which stays until a reset), by its position from 1.
Name the conditions on the HMI, by position. `statusText` changes only when the code
or `faultId` changes.

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_OK` | `UT_F_NONE` | `OK` | All conditions healthy |
| `UT_ST_OK` | `UT_F_CONDITION` | `OK` | Condition `statusCond` is not OK but still within its `delay` (`timeLeft`: the time until it counts) |
| `UT_ST_INTERLOCK` | `UT_F_CONDITION` | `Blocked: interlock` | Condition `statusCond`, the lowest holding `Ok` FALSE, is not OK now |
| `UT_ST_RESET_NEEDED` | `UT_F_CONDITION` | `Waiting: reset` | It is healthy again but MANUAL: a reset releases it |
| `UT_ST_BYPASSED` | `UT_F_CONDITION` | `Bypassed` | A bypass in effect (the lowest, `statusCond`); `timeLeft` the time until it drops out (0 with `bypassTimeout` 0) |
| `UT_ST_WARN_SETTING` | `UT_F_BYPASS_TIMEOUT` | `Setting: bypass timeout` | `bypassTimeout` negative (see Bad settings) |
| `UT_ST_WARN_SETTING` | `UT_F_CONDITION` | `Setting: condition` | Condition `statusCond` has a negative `delay` or an unknown `reset` |
| `UT_ST_CONFIG` | `UT_F_NO_CONDITIONS` | `Config: no conditions` | An empty array: `Ok` is always FALSE |

## Using it
```
|--[ GuardClosed ]----------------( Crusher[1].ok )--|
|--[ PullCordHealthy ]------------( Crusher[2].ok )--|
|--[ Conveyor2.Running ]----------( Crusher[3].ok )--|
```
```iecst
CrusherIntlk(BypassEnable := MaintKey, Reset := ResetPB, Conditions := Crusher, Data := CrusherIntlkData);
Crusher1(AutoCmd := StartChain.Step3, Interlock := CrusherIntlk.Ok, Data := Crusher1Motor);
```

## Bad settings
Invalid settings warn (`configBad`) and fall back to the safe side: a negative
`bypassTimeout` allows no bypass at all; a negative condition `delay` acts at once (as 0);
an unknown `reset` holds the condition until a reset (as MANUAL).
