# FB_Object — The base of every block

The base of every block: the error outputs and the system link. bError: a trip is active now. bWarning: a warning is active now. eErrorId: the first error since the last reset (first-out), else the first warning; None when nothing is active. eState: what the block is doing. Kept settings (every block that keeps a last-good copy): a bad write is put back and shown by bSettingRefused and eSettingRefusedErrorId, the kind of the first bad setting: TimeBad (a time), ProtectionBad (a protection's settings), ChoiceBad (a choice the block does not have), LimitsBad (two settings in the wrong order), BelowMin / AboveMax (a number below / above its range), ValueBad (a number that is not valid), IoAddress (an IO address). Both clear with the block's reset (its record's bCmdResetFaults, the equipment's reset, or the plant reset).

An abstract base: not placed on its own; the blocks that extend it are.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault |

**Back to** [the index](../README.md).
