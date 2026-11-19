# FB_RunGate — Run waits for a permissive (a part)

A run waits for a permissive (a tank, a valve's open confirmation, a pressure), with a maximum wait.

It is a **part**: it adds itself to its run (`ipRun`) and acts through the run. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipRun` | `I_Run` |  | required. An instance of a block that offers I_Run (FB_Run) |
| in | `bPermissive` | `BOOL` | `TRUE` | the run may go on (FALSE: it waits) |
| in | `refData` | `REFERENCE TO ST_RunGateData` |  | the block's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bWaitingForPermissive` | `BOOL` |  | the run waits for bPermissive |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_RunGateData` (pin `refData`)

**Settings `set`** (`ST_RunGateSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `tPermissiveWaitTimeout` | `TIME` |  | 0 = wait for ever |

**Status `sts`** (`ST_RunGateSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bWaitingForPermissive` | `BOOL` |  | the run waits for bPermissive |
| `tWaitedFor` | `TIME` |  | how long the run has waited |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## How it works

A run waits for a permissive: while the run is active and `bPermissive` is FALSE the run is paused (`E_PartAction.Stop`: the equipment waits, nothing counts). Waiting longer than `set.tPermissiveWaitTimeout` (0 = no limit) in one stretch trips the run (GateTimeout; the run ends as a fault). Typical: a run waits for its supply tank, a valve's open confirmation, a pressure. The wait restarts each time `bPermissive` comes back.

## Example

The run waits while the supply tank is low. Declare `fbRun : FB_Run`, `fbTankLow : FB_DigitalIn` (the supply
tank's low float, TRUE = low) and `stGate : ST_RunGateData`.

| Pin | Wire |
| --- | --- |
| `ipRun` | `fbRun` |
| `bPermissive` | `NOT fbTankLow.bSignal` |
| `refData` | `stGate` |

**Back to** [the index](../README.md).
