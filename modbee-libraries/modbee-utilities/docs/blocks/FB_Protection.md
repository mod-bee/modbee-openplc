# FB_Protection — One protection (a part)

One protection on any condition, added to a motor, pump or valve: a thermistor, a drive fault, an external fault, a seal leak, a phase failure, a maximum run time.

It is a **part**: it adds itself to its owner (`ipOwner`) and acts through the owner. See [parts](../conventions.md#parts-and-observers).

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bConditionPresent` | `BOOL` |  | TRUE = the condition is present |
| in | `eCountsWhen` | `E_Cause` |  | when it counts |
| in | `ipOwner` | `I_PartOwner` |  | the equipment it protects (required). An instance of a block that offers I_PartOwner (FB_Alarm, FB_AlarmBeacon, FB_AlarmTable, FB_AnalogIn, FB_AnalogOut, ...) |
| in | `refData` | `REFERENCE TO ST_ProtectionData` |  | the protection's record |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_ProtectionData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdResetFaults` | `BOOL` |  | HMI: reset trips and alarms whose cause has gone (acts once, cleared by the block) |
| `bSettingRefused` | `BOOL` |  | a bad settings write was put back (cleared by its reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**Settings `set`** (`ST_ProtectionPartSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eActionOnFault` | `E_Response` | `E_Response.Trip` | what it does when the condition lasts: Off, Warn, Trip or Signal |
| `tTripDelay` | `TIME` | `T#1s` | the condition must last this long before it acts |
| `eResetMode` | `E_ResetMode` | `E_ResetMode.Retry` | how it clears: Auto, Manual (held until a reset) or Retry (locks out after too many) |
| `tAutoRecoverAfter` | `TIME` | `T#10s` | the condition must be gone this long before it clears |
| `nMaxRetriesBeforeLockout` | `INT` | `3` | Retry: trips within the retry window before it locks out |
| `eErrorRaised` | `E_UtError` | `E_UtError.Protection` | the error the owner shows |
| `tRetryCountWindow` | `TIME` | `T#1h` | a Retry protection counts its trips within this window (0 = until a reset) |

**Status `sts`** (`ST_ProtectionSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eFaultState` | `E_ProtState` |  | Clear, Pending, Warning, Tripped, Locked, Recovering or Signal |
| `nRetriesUsed` | `INT` |  | trips counted in the current retry window |
| `nTripCount` | `UDINT` |  | trips since the counter was cleared |
| `tTimeLeft` | `TIME` |  | delay before it acts, or recover wait before it clears |

## How it works

One protection on any condition, as a part of its owner: a thermistor, a drive fault, an external fault, a seal leak, a phase failure, a maximum run time (`eCountsWhen` := Running, a long delay).

A protection that is not Clear and whose rung stops being called raises PartLost on its owner until reset.

A thermistor: `set.eErrorRaised` := `E_UtError.Thermistor`; while it is tripped, a motor holds its coil off (`bHoldOutputOff`), even against an IO-page force.

A bad settings write is put back (`bSettingRefused` / `eSettingRefusedErrorId`) and warns its owner (SettingRefused) until its reset (`bCmdResetFaults`) or the owner's.

## Example

A motor thermistor relay.

| Pin | Wire |
| --- | --- |
| `bConditionPresent` | `DI_M1_Thermistor` (TRUE = tripped) |
| `eCountsWhen` | `E_Cause.Always` |
| `ipOwner` | `fbMotor1` |
| `refData` | `stThermistor1` |

Set `stThermistor1.set.eErrorRaised := E_UtError.Thermistor` so the motor shows the right code.

**Back to** [the index](../README.md).
