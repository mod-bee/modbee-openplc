# FB_Cmd — Command arbiter for two masters

Arbitrates commands from two masters, the local panel HMI and a remote SCADA / IoT system: stop bits win, local wins over remote, and remote control can be switched off.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `nLocalCmd` | `DWORD` |  | command bits (rising edge acts) |
| in | `nRemoteCmd` | `DWORD` |  | command bits; a rising edge acts |
| in | `nLocalMode` | `INT` | `-1` | mode request (acts on a change to 0..15) |
| in | `nRemoteMode` | `INT` | `-1` | a mode request, acts on a change to 0..15 |
| in | `nLocalSel` | `INT` | `-1` | selection (auto type, preset, route ...) |
| in | `nRemoteSel` | `INT` | `-1` | a selection, acts on a change to 0 or more |
| in | `bRemoteEnabled` | `BOOL` | `TRUE` | FALSE: local control |
| in | `refData` | `REFERENCE TO ST_CmdData` |  | Its record (a variable of this type) |
| out | `bCmd0` | `BOOL` |  | Command bit 0 accepted (one scan) |
| out | `bCmd1` | `BOOL` |  | Command bit 1 accepted (one scan) |
| out | `bCmd2` | `BOOL` |  | Command bit 2 accepted (one scan) |
| out | `bCmd3` | `BOOL` |  | Command bit 3 accepted (one scan) |
| out | `bCmd4` | `BOOL` |  | Command bit 4 accepted (one scan) |
| out | `bCmd5` | `BOOL` |  | Command bit 5 accepted (one scan) |
| out | `bCmd6` | `BOOL` |  | Command bit 6 accepted (one scan) |
| out | `bCmd7` | `BOOL` |  | Command bit 7 accepted (one scan) |
| out | `nCmd` | `DWORD` |  | accepted bits, one scan |
| out | `nMode` | `INT` |  | accepted mode request, one scan, else -1 |
| out | `nSel` | `INT` |  | accepted selection, one scan, else -1 |
| out | `bRefused` | `BOOL` |  | one scan: a remote request was refused |

## Record `ST_CmdData` (pin `refData`)

**Settings `set`** (`ST_CmdSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nStopMask` | `DWORD` | `16#00000001` | the stop / off bits: they win in a scan |
| `nLocalOnlyMask` | `DWORD` |  | bits only the local master may give (e.g. a reset) |
| `nRemoteModes` | `WORD` | `16#FFFF` | mode codes the remote master may ask for (bit n = code n) |
| `bRemoteStop` | `BOOL` | `TRUE` | remote stop bits and mode 0 still act under local control |
| `bRemoteSel` | `BOOL` | `TRUE` | the remote master may change the selection |

**Status `sts`** (`ST_CmdSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eLastSource` | `E_CmdFrom` |  |  |
| `nLastCmd` | `DWORD` |  |  |
| `nLastMode` | `INT` | `-1` |  |
| `nLastSel` | `INT` | `-1` |  |
| `nRefusedCount` | `UDINT` |  | remote requests refused (not kept) |
| `bLocalOnly` | `BOOL` |  | under local control now |

## Lists

- `E_CmdFrom`: `None`, `Local`, `Remote` (default `None`)

## How it works

Command arbiter for two masters: the local one (panel HMI) and the remote one (SCADA / IoT).

Stop / off bits (`set.nStopMask`) and mode 0 win over everything else in a scan; local wins over remote. `bRemoteEnabled` FALSE: remote requests are refused (`bRefused`, `sts.nRefusedCount`), except the stop bits and mode 0 when `set.bRemoteStop`. `set.nLocalOnlyMask` bits are never taken from the remote master; `set.nRemoteModes` says which mode codes it may ask for; `set.bRemoteSel` whether it may change the selection. Every value of the settings is usable: they are kept by the block (restored at power-up), never put back. No errors of its own.

## Example

A pump that the panel HMI and a SCADA both command. Bit 0 = start, bit 1 = stop.

| Pin | Wire |
| --- | --- |
| `nLocalCmd` | the HMI's command word `nHmiCmd` |
| `nRemoteCmd` | the SCADA's command word `nScadaCmd` |
| `bRemoteEnabled` | `fbSystem.bIsAuto` |
| `refData` | `stCmd1` |
| `bCmd0` | a coil on `stMotor1.bCmdStart` |
| `bCmd1` | a coil on `stMotor1.bCmdStop` |

Set `stCmd1.set.nStopMask := 2` so the stop bit always wins.

**Back to** [the index](../README.md).
