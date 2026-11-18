# FB_Protection — One protection (a part)

One protection on any condition, added to a motor, pump or valve: a thermistor, a drive fault, an external fault, a seal leak, a phase failure, a maximum run time.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bIn` | `BOOL` |  | TRUE = the condition is present |
| in | `eCause` | `E_Cause` |  | when it counts |
| in | `ipOwner` | `I_PartOwner` |  | the equipment it protects (required). The owner's instance |
| in | `refData` | `REFERENCE TO ST_ProtectionData` |  | its record: settings with the error it raises, status |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ProtectionData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdReset` | `BOOL` |  | Reset trips whose cause has gone (HMI command; cleared by the block) |

**Settings `set`** (`ST_ProtectionPartSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eResponse` | `E_Response` | `E_Response.Trip` | `Off`, `Warn`, `Trip` or `Signal` (see conventions) |
| `tDelay` | `TIME` | `T#1s` | The condition must last this long |
| `eReset` | `E_ResetMode` | `E_ResetMode.Retry` | `Auto`, `Manual` or `Retry` (see conventions) |
| `tRecover` | `TIME` | `T#10s` | The cause must be gone this long before it clears |
| `nMaxRetries` | `INT` | `3` | Retry: trips in the window before it locks out |
| `eErrorId` | `E_UtError` | `E_UtError.Protection` | the error the owner shows |

**Status `sts`** (`ST_ProtectionSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_ProtState` |  | What it is doing now (status) |
| `nRetries` | `INT` |  | Trips counted in the retry window |
| `nCount` | `UDINT` |  | trips since the counter was cleared |
| `tTimeLeft` | `TIME` |  | delay before it acts, or recover wait before it clears |

## How it works

One protection on any condition, as a part of its owner: a thermistor, a drive fault, an external fault, a seal leak, a phase failure, a maximum run time (`eCause` := Running, a long delay).

A protection that is not Clear and whose rung stops being called raises PartLost on its owner until reset.

A thermistor: `set.eErrorId` := `E_UtError.Thermistor`; while it is tripped, a motor holds its coil off (`bHoldOff`), even against an IO-page force.

## Example

A motor thermistor relay.

| Pin | Wire |
| --- | --- |
| `bIn` | `DI_M1_Thermistor` (TRUE = tripped) |
| `eCause` | `E_Cause.Always` |
| `ipOwner` | `fbMotor1` |
| `refData` | `stThermistor1` |

Set `stThermistor1.set.eErrorId := E_UtError.Thermistor` so the motor shows the right code.

**Back to** [the index](../README.md).
