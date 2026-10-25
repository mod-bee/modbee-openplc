# UT_STATUS_TEXT — A status in words (function), and UT_STATUS_KIND

Two functions for the status every device block keeps in its record
(see [conventions](../conventions.md#status-every-critical-block-says-what-it-is-doing-and-why)):

- **UT_STATUS_TEXT** turns a `statusCode` and a `faultId` into a short line of words,
  such as `Running: Auto`, `Waiting: restart delay` or `Latched: overload`.
- **UT_STATUS_KIND** tells you the kind of a `statusCode`: normal, held, warning,
  fault or configuration. Use it for a colour on the HMI or to filter messages.

The device blocks already call UT_STATUS_TEXT for their own `statusText`. Use these
functions in your own blocks, or to show a status from somewhere else.

## Pins

**UT_STATUS_TEXT**
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Status` | UT_STATUS | UT_ST_IDLE | A block's `statusCode` |
| in | `Fault` | UT_FAULT | UT_F_NONE | The same block's `faultId`. Only the warning, fault and configuration statuses use it |
| returns | | STRING(30) | | The status in words, at most 30 characters |

**UT_STATUS_KIND**
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Status` | UT_STATUS | UT_ST_IDLE | A block's `statusCode` |
| returns | | UT_KIND | | `UT_KIND_NORMAL` (0) · `UT_KIND_HELD` · `UT_KIND_WARNING` · `UT_KIND_FAULT` · `UT_KIND_CONFIG` |

```iecst
MyData.statusText := UT_STATUS_TEXT(MyData.statusCode, MyData.faultId);
(* UT_ST_RESTART_DELAY            -> 'Waiting: restart delay'  *)
(* UT_ST_FAULT_RESET, UT_F_OVERLOAD -> 'Latched: overload'      *)
(* UT_ST_CONFIG, UT_F_VALVE_TYPE  -> 'Config: valve type'       *)

PumpIsFaulted := UT_STATUS_KIND(Pump1Data.statusCode) = UT_KIND_FAULT;
```

## How it works

**The words.** Each normal or held status has its own words (`Idle`, `Running:
Auto`, `Blocked: interlock`). The warning, fault and configuration statuses are a
prefix that says how the fault behaves, followed by the words of the fault or
setting in `Fault`:

| Status | Prefix | Meaning |
| --- | --- | --- |
| `UT_ST_FAULT` | `Fault: ` | A trip that resets by itself once the cause has gone (AUTO) |
| `UT_ST_FAULT_RETRY` | `Retrying: ` | A trip that retries (RETRY), retries still left |
| `UT_ST_FAULT_RESET` | `Latched: ` | A trip that needs a reset (MANUAL) |
| `UT_ST_FAULT_LOCKED` | `Locked: ` | A RETRY trip whose retries are used up: it needs a reset |
| `UT_ST_WARNING` | `Warning: ` | It runs, but something needs looking at |
| `UT_ST_WARN_SETTING` | `Setting: ` | A setting is not valid; a safe value is used instead |
| `UT_ST_CONFIG` | `Config: ` | A setting is not valid and keeps the device off until it is fixed |

So `UT_ST_FAULT_RETRY` with `UT_F_NO_FEEDBACK` reads `Retrying: no run feedback`,
and `UT_ST_WARN_SETTING` with `UT_F_FLC` reads `Setting: full load current`. A
setting with no words of its own reads `a setting`.

The text never holds a number. The time left, the pump number or the count that
goes with a status is in the block's record (`timeLeft`, `statusUnit`,
`runningCount` and so on), so an HMI can show it beside the words.

The full lists of statuses, faults and their words are in
[conventions.md, Status](../conventions.md#status-every-critical-block-says-what-it-is-doing-and-why).

**The kinds.** UT_STATUS_KIND returns the kind of any status. Use it rather than the
status's number: the statuses after `UT_ST_CONFIG` are not in the kind groups.

| Kind | What it means | Example |
| --- | --- | --- |
| `UT_KIND_NORMAL` | Idle, off, running, moving | `Running: Auto` |
| `UT_KIND_HELD` | Asked to run, but something holds it back (not a fault) | `Waiting: restart delay` |
| `UT_KIND_WARNING` | It runs, but something needs looking at | `Warning: current signal` |
| `UT_KIND_FAULT` | A protection holds it off, or it runs in a fallback | `Latched: overload` |
| `UT_KIND_CONFIG` | A setting keeps it off | `Config: valve type` |

**Cost.** Both are plain functions with no memory of their own. The device blocks
call UT_STATUS_TEXT only when the status or the fault changes, not every scan.
