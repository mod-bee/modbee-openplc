# FB_RunGate — Run waits for a permissive (a part)

A run waits for a permissive (a tank, a valve's open confirmation, a pressure), with a maximum wait.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipRun` | `I_Run` |  | required. The FB_Run instance |
| in | `bPermit` | `BOOL` | `TRUE` | The run may go on (FALSE: it waits) |
| in | `refData` | `REFERENCE TO ST_RunGateData` |  | Its record (a variable of this type) |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bWaiting` | `BOOL` |  | The run waits for `bPermit` |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunGateData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bWaiting` | `BOOL` |  | status |
| `tWaited` | `TIME` |  |  |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |
| `eRefusedWhy` | `E_UtError` |  | why the last write was refused (cleared with bRefused) |

**Settings `set`** (`ST_RunGateSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tMaxWait` | `TIME` |  | 0 = wait for ever |

## How it works

A run waits for a permissive: while the run is active and `bPermit` is FALSE the run is paused (`E_PartAction.Stop`: the equipment waits, nothing counts). Waiting longer than `set.tMaxWait` (0 = no limit) in one stretch trips the run (GateTimeout; the run ends as a fault). Typical: a run waits for its supply tank, a valve's open confirmation, a pressure. The wait restarts each time `bPermit` comes back.

## Example

The run waits while the supply tank is low.

| Pin | Wire |
| --- | --- |
| `ipRun` | `fbRun` |
| `bPermit` | `NOT fbTankLow.bQ` |
| `refData` | `stGate` |

**Back to** [the index](../README.md).
