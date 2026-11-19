# FB_Cmd — Command arbiter for two masters

Arbitrates commands from two masters, the local panel HMI and a remote SCADA / IoT system: stop bits win, local wins over remote, and remote control can be switched off.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `nLocalCommandBits` | `DWORD` |  | command bits (rising edge acts) |
| in | `nRemoteCommandBits` | `DWORD` |  | command bits from the remote master (a rising bit acts) |
| in | `nLocalModeRequest` | `INT` | `-1` | mode request (acts on a change to 0..15) |
| in | `nRemoteModeRequest` | `INT` | `-1` | mode request from the remote master (acts on a change to 0..15) |
| in | `nLocalSelection` | `INT` | `-1` | selection (auto type, preset, route ...) |
| in | `nRemoteSelection` | `INT` | `-1` | selection from the remote master |
| in | `bRemoteAllowed` | `BOOL` | `TRUE` | FALSE: local control |
| in | `refData` | `REFERENCE TO ST_CmdData` |  | the block's record |
| out | `bCommandBit0` | `BOOL` |  | command bit 0 accepted (one scan) |
| out | `bCommandBit1` | `BOOL` |  | command bit 1 accepted (one scan) |
| out | `bCommandBit2` | `BOOL` |  | command bit 2 accepted (one scan) |
| out | `bCommandBit3` | `BOOL` |  | command bit 3 accepted (one scan) |
| out | `bCommandBit4` | `BOOL` |  | command bit 4 accepted (one scan) |
| out | `bCommandBit5` | `BOOL` |  | command bit 5 accepted (one scan) |
| out | `bCommandBit6` | `BOOL` |  | command bit 6 accepted (one scan) |
| out | `bCommandBit7` | `BOOL` |  | command bit 7 accepted (one scan) |
| out | `nCommandBits` | `DWORD` |  | accepted bits, one scan |
| out | `nModeRequest` | `INT` |  | accepted mode request, one scan, else -1 |
| out | `nSelection` | `INT` |  | accepted selection, one scan, else -1 |
| out | `bRequestRefused` | `BOOL` |  | one scan: a remote request was refused |

## Record `ST_CmdData` (pin `refData`)

**Settings `set`** (`ST_CmdSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nStopBits` | `DWORD` | `16#00000001` | the stop / off bits: they win in a scan |
| `nLocalOnlyBits` | `DWORD` |  | bits only the local master may give (e.g. a reset) |
| `nRemoteAllowedModeBits` | `WORD` | `16#FFFF` | mode codes the remote master may ask for (bit n = code n) |
| `bRemoteStopUnderLocal` | `BOOL` | `TRUE` | remote stop bits and mode 0 still act under local control |
| `bRemoteMaySelect` | `BOOL` | `TRUE` | the remote master may change the selection |

**Status `sts`** (`ST_CmdSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eLastCommandFrom` | `E_CmdFrom` |  | who gave the last accepted command: Local or Remote |
| `nLastCommandBits` | `DWORD` |  | the last accepted command bits |
| `nLastModeRequest` | `INT` | `-1` | the last accepted mode request (-1 = none) |
| `nLastSelection` | `INT` | `-1` | the last accepted selection (-1 = none) |
| `nRemoteRefusedCount` | `UDINT` |  | remote requests refused (not kept) |
| `bLocalControlOnly` | `BOOL` |  | under local control now |

## Lists

- `E_CmdFrom`: `None`, `Local`, `Remote` (default `None`)

## How it works

Command arbiter for two masters: the local one (panel HMI) and the remote one (SCADA / IoT).

Stop / off bits (`set.nStopBits`) and mode 0 win over everything else in a scan; local wins over remote. `bRemoteAllowed` FALSE: remote requests are refused (`bRequestRefused`, `sts.nRemoteRefusedCount`), except the stop bits and mode 0 when `set.bRemoteStopUnderLocal`. `set.nLocalOnlyBits` bits are never taken from the remote master; `set.nRemoteAllowedModeBits` says which mode codes it may ask for; `set.bRemoteMaySelect` whether it may change the selection. Every value of the settings is usable: they are kept by the block (restored at power-up), never put back. No errors of its own.

## Example

A pump that the panel HMI and a SCADA both command. Bit 0 = start, bit 1 = stop.

| Pin | Wire |
| --- | --- |
| `nLocalCommandBits` | the HMI's command word `nHmiCmd` |
| `nRemoteCommandBits` | the SCADA's command word `nScadaCmd` |
| `bRemoteAllowed` | `fbSystem.bIsAuto` |
| `refData` | `stCmd1` |
| `bCommandBit0` | a coil on `stMotor1.bCmdStart` |
| `bCommandBit1` | a coil on `stMotor1.bCmdStop` |

Set `stCmd1.set.nStopBits := 2` so the stop bit always wins.

**Back to** [the index](../README.md).
