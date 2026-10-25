# UT_CMD — Commands from two masters, with local / remote

A site often has two masters that both command the same device: the **local**
panel HMI and a **remote** SCADA. UT_CMD sits between them and the device:

- Each master writes **its own** variables, and nobody clears them. The block
  reacts to each **change**, so a SCADA that rewrites the same value every poll,
  or a value left set, acts only once.
- **Local / remote**: with `RemoteEnabled` FALSE (a technician on site) remote
  requests are refused, counted and reported, except a stop.
- **Stop wins**: a stop and a start in the same scan give the stop.
- The outputs are one-scan requests you wire into the device record's `cmdXxx`
  and `cmdMode`.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `LocalCmd` | DWORD | 0 | The local master's command bits (bit 0 stop, bit 1 start … you choose the map). Each bit acts on its rising edge. Wire it (0 if the local master has no command bits) |
| in | `RemoteCmd` | DWORD | 0 | The remote master's command bits, same map |
| in | `LocalMode` | INT | −1 | The local master's mode request: acts when it changes to 0 or more. −1 = no request |
| in | `RemoteMode` | INT | −1 | The remote master's mode request |
| in | `RemoteEnabled` | BOOL | TRUE | FALSE: local control. The remote master is refused (see `remoteStop`). Wire a Local / Remote switch here |
| out | `Cmd` | DWORD | | Accepted command bits, for one scan |
| out | `Mode` | INT | | Accepted mode request for one scan, else −1. Wire into the record's `cmdMode` |
| out | `Refused` | BOOL | | One scan: a remote request was refused |
| out | `Cmd0` … `Cmd7` | BOOL | | Bits 0 to 7 of `Cmd`, for Ladder and FBD. Wire into the record's `cmdStop`, `cmdStart`, `cmdReset` … |
| inout | `Data` | UT_CMD_DATA | | Settings and status |

## Record `UT_CMD_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stopMask` | DWORD | 16#00000001 | The stop / off bits. When one is accepted, every other bit and mode request of that scan is dropped |
| `localOnlyMask` | DWORD | 0 | Bits only the local master may give, e.g. a reset that needs someone on site. Refused from remote at all times |
| `remoteModes` | WORD | 16#FFFF | The mode codes the remote master may ask for: bit n = code n. 16#0005 = Off (0) and Auto (2) only. Codes above 15 are refused from remote |
| `remoteStop` | BOOL | TRUE | Under local control, the remote stop bits and mode 0 (Off) still act. FALSE refuses them too |
| `lastSource` | UT_CMD_FROM | | *status*: who gave the last accepted request: `UT_FROM_NONE` · `UT_FROM_LOCAL` · `UT_FROM_REMOTE` |
| `lastCmd` | DWORD | | *status*: its command bits |
| `lastMode` | INT | −1 | *status*: its mode request (−1 = none) |
| `refused` | UDINT | | *status*: remote requests refused (not kept over a power cut) |
| `statusCode` | UT_STATUS | | *status*: see Status codes |
| `statusText` | STRING(30) | | *status*: `statusCode` in words |

## How it works
**What the masters write.**
- **Command bits**: set the bit, and clear it again before the next command (an
  HMI momentary button does this: 1 while pressed, 0 when released). A master that
  rewrites the same value every poll is fine: only a change from 0 to 1 acts.
- **Mode**: write the code (0 Off, 1 Hand, 2 Auto, 3 OOS, or the device's own
  codes). It acts when the value changes. To ask for the same mode again after
  someone else changed it, write −1 (or any negative number) first. The block
  passes codes 0 and up through; the device checks them.

**In each scan:**
1. Each master's new bits (0 → 1) and new mode request are found.
2. Remote requests are filtered: with `RemoteEnabled` FALSE only the `stopMask`
   bits and mode 0 pass (and only while `remoteStop`); `localOnlyMask` bits and
   modes not in `remoteModes` never pass. A refused request sets `Refused` for one
   scan, adds 1 to `refused` and is shown in the status.
3. **Stop wins**: if a stop bit or mode 0 is accepted, every other bit and any
   other mode request in that scan is dropped. Otherwise, when both masters ask for
   a mode in the same scan, the local one is used.
4. `Cmd`, `Cmd0`…`Cmd7` and `Mode` carry the result for one scan.

**Nothing acts on the first scan** after a power cut or PLC start: the block only
reads the masters' values. A command bit or mode left set over a power cut does not
act, so `UT_PU_OFF` (a mode that comes back Off) can't be undone by a value SCADA
left behind.

## Status codes
`statusCode` is a `UT_STATUS` (an HMI reads its number); `statusText` is the same in words.

| `statusCode` | `statusText` | When |
| --- | --- | --- |
| `UT_ST_LOCAL_REMOTE` | `Local and remote` | `RemoteEnabled` TRUE |
| `UT_ST_LOCAL` | `Local control` | `RemoteEnabled` FALSE |
| `UT_ST_REFUSED_LOCAL` | `Refused: local control` | A remote request was refused under local control |
| `UT_ST_REFUSED_LOCAL_ONLY` | `Refused: local only` | A `localOnlyMask` bit, or a mode not in `remoteModes` |

A refusal stays shown until the next accepted request, or until
`RemoteEnabled` changes.

## Using it
Bit map for this pump: bit 0 stop, bit 1 start, bit 2 reset (on site only).

```iecst
Pump1Cmd(LocalCmd := HMI_P1_Cmd, RemoteCmd := SCADA_P1_Cmd,
         LocalMode := HMI_P1_Mode, RemoteMode := SCADA_P1_Mode,
         RemoteEnabled := NOT LocalSwitch, Data := Pump1CmdData);  (* localOnlyMask := 16#4 *)
Pump1.cmdStop := Pump1Cmd.Cmd0;
Pump1.cmdStart := Pump1Cmd.Cmd1;
Pump1.cmdReset := Pump1Cmd.Cmd2;
Pump1.cmdMode := Pump1Cmd.Mode;
```

The masters write only `HMI_P1_*` and `SCADA_P1_*`, never `Pump1.cmd…`.
