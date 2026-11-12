# 04 - Registers

The Modbus side. Your variables sit at numbered addresses, and peers reach them
the way they would reach any Modbus device.

Three methods of the node:

| | |
| --- | --- |
| `node.ModbusMap` | put **your** variables at addresses, so peers can reach them |
| `node.ModbusRead` | read **a peer's** addresses |
| `node.ModbusWrite` | write **a peer's** addresses |

## The four tables

Modbus has four separate numbered lists. Address 40 in one is a different thing
from address 40 in another.

| `eTable` | holds | peers may | function codes |
| --- | --- | --- | --- |
| `E_BeeBusModbusTable.Coil` | on/off | read and **write** | 1, 5, 15 |
| `E_BeeBusModbusTable.DiscreteInput` | on/off | read only | 2 |
| `E_BeeBusModbusTable.HoldingRegister` (default) | 16 bits | read and **write** | 3, 6, 16 |
| `E_BeeBusModbusTable.InputRegister` | 16 bits | read only | 4 |

The rule of thumb: **inputs are read-only, coils and holding registers are
writable.** Put anything a peer should be able to change in a coil or a holding
register, and anything that is purely a reading in a discrete input or an input
register.

## Saying what you are passing

Each of the three methods takes one `anyData`. Put the variable on it:

```
anyData := iSetpoint        (* one value *)
anyData := aTrend           (* ARRAY [0..99] OF WORD - a range of registers *)
anyData := aValves          (* ARRAY [0..7] OF BOOL  - a range of coils *)
anyData := CFG              (* a STRUCT - every member, one after the other *)
```

Nothing is wrapped. The parameter carries the address, the type and - for a
`STRUCT` - its layout, so one method covers a single value, a whole range and a
whole `STRUCT`.

**`eTable` is what says bits or registers.** A call with `eTable := Coil` knows
it is dealing with bits; one with `HoldingRegister` knows it is dealing with
16-bit values. The variable does not have to say so a second time.

An array has to be declared with **fixed bounds** - `ARRAY [0..99] OF WORD`,
not `ARRAY [*]`.

### How a value is laid out

Every value takes the registers its type needs, from `nAddress` on, one after
the other in declaration order:

| type | registers | on the wire |
| --- | --- | --- |
| `BOOL` | 1 | 0 or 1 (a peer writing any other number writes TRUE) |
| `SINT`, `USINT`, `BYTE` | 1 | the number; one the type cannot hold (300 into a `USINT`) is refused |
| `INT`, `UINT`, `WORD` | 1 | the number |
| `DINT`, `UDINT`, `DWORD` | 2 | **high word first** |
| `LINT`, `ULINT`, `LWORD` | 4 | high word first |
| `REAL` | 2 | IEEE-754, high word first |
| `LREAL` | 4 | IEEE-754 double, high word first |
| `TIME`, `TOD` | 2 | `DINT` milliseconds |
| `LTIME` | 4 | `LINT` nanoseconds (IEC 61131-3) |
| `DT`, `DATE` | 2 | `UDINT` seconds since 1970-01-01 |
| `STRING(n)` | n/2 + 1 | two characters a register, first in the high byte, then the terminator |
| a nested `STRUCT` | its members | in place |
| an array | its elements | in place, first one first |

**High word first** is what a Modbus master or HMI calls "ABCD", "big-endian"
or "high word first" ("ABCDEFGH" for a 64-bit value). Set that on the far end
once and every 32- and 64-bit value reads right. A 32-bit value takes both its
registers in one write, a 64-bit one all four.

**A register you mask is a `WORD`, not an `INT`.** A register is sixteen raw
bits, and `WORD` is the type a program can work on bit by bit: `myWord.6` is bit
6, and `AND`, `OR`, `XOR`, `NOT`, `SHL`, `SHR`, `ROL` and `ROR` take `ANY_BIT`,
which `INT` is not. A drive's control or status word belongs in a `WORD`. Use
`INT` for a signed reading and `UINT` for an unsigned one.

In a `Coil` or `DiscreteInput` table every member has to be a `BOOL`, one
address each. `WSTRING` is refused everywhere - a value quietly cut down would
be wrong rather than missing. A refused variable is refused **whole**, with the
node's `sLastError` naming the member (*"ModbusMap CFG: levelHi is not a BOOL;
a coil or input table holds BOOLs only"*): skipping it would move every address
after it.

## Sharing your variables - `node.ModbusMap`

```
node.ModbusMap(anyData := iSpeed, nAddress := 40);
```

`iSpeed` **is** holding register 40 from that moment. A peer reading gets what
it holds now; a peer writing changes it. Nothing is copied, and there is no
request. Call it every scan; it returns `Ok` while the addresses are live.

A range works the same way:

```
node.ModbusMap(anyData := aTrend, nAddress := 100);
```

`aTrend : ARRAY[0..99] OF WORD` at address 100 becomes addresses 100 to 199. The
array's lower bound maps to `nAddress` whatever that bound is.

### Outputs

| | |
| --- | --- |
| `nCount` | how many addresses were taken: registers, or coils |
| `bWritten` | a peer wrote some of them since the last call |
| `sWrittenName` | which member, e.g. `levelHiMm` or `spare[3]` (held until the next write) |
| `nWrittenIndex` | its position, from 1, every array element and nested member one position (held) |
| `nWrittenAddr` | its first address (held) |
| `nWritten` | how many members that write covered (held) |
| `bSafeApplied` | the safe value was applied since the last call |

**`bWritten` is the one to use.** It tells you a peer changed the value rather
than your own program doing it:

```
node.ModbusMap(anyData := iSetpoint, nAddress := 40, bWritten => bSetpointWritten);
IF bSetpointWritten THEN
    bNewSetpoint := TRUE;      (* somebody sent us a new setpoint - act on it *)
END_IF;
```

When one write covers several members - an HMI sending a whole block - the
`sWrittenName`, `nWrittenIndex` and `nWrittenAddr` name the first (lowest
address) and `nWritten` says how many there were.

### One variable, one mapping

`eTable`, `nAddress`, `eOnLoss` and `nSafeValue` are taken on the first call
that binds. A later call that changes them returns `InvalidArgument` and the
mapping goes on as bound. Two separate ranges are two variables - or one
`STRUCT`.

## A whole STRUCT of settings

This is what an HMI needs. Put every setting in one `STRUCT`:

```
TYPE PLANT_CFG : STRUCT
  levelHiMm   : REAL := 1500.0;   (* 0..1 *)
  levelLoMm   : REAL := 500.0;    (* 2..3 *)
  runTime     : TIME := T#2h;     (* 4..5   DINT ms *)
  pumpEnable  : BOOL := TRUE;     (* 6      0 / 1 *)
  siteName    : STRING(16);       (* 7..15  9 registers *)
END_STRUCT END_TYPE

node.ModbusMap(anyData := CFG, nAddress := 0, bWritten => bCfgWritten,
               sWrittenName => sCfgWrittenName);
```

The HMI writes straight into `CFG`. `bWritten` says a write happened and
`sWrittenName` which setting, so the program can check it and put the old value
back when it is out of range:

```
IF bCfgWritten THEN
    IF CFG.levelLoMm >= CFG.levelHiMm THEN
        CFG.levelLoMm := levelLoInUse;                           (* refused *)
        sRefused := CONCAT('Setting refused: ', sCfgWrittenName);
    END_IF;
END_IF;
levelLoInUse := CFG.levelLoMm;
```

**Add new members at the end.** One added in the middle moves every address
after it. A spare or two at the end costs nothing.

**The address table is generated, not typed.** A table generator reads the
`.st` file that declares the `STRUCT` and prints every member's address, type
and register count as Markdown, and as JSON for an HMI's firmware.

## Safe states

**Never on a setting or a command.** A safe value is for a live setpoint a peer
keeps driving; a setting or a command written by an HMI or SCADA must never
change because the link dropped - the PLC runs on its own.

A writable address has a problem: the peer that was driving it goes quiet, and
the last value it sent sits there forever. On a setpoint that can be dangerous.

```
node(nNodeId := 60, bFailsafe := TRUE);
node.ModbusMap(anyData := iSetpoint, nAddress := 40,
               eOnLoss := E_BeeBusModbusFailsafe.ResetToValue, nSafeValue := 5,
               bSafeApplied => bWentSafe);
```

| `eOnLoss` | |
| --- | --- |
| `E_BeeBusModbusFailsafe.HoldLastValue` | leave it where it was (the default) |
| `E_BeeBusModbusFailsafe.ResetToValue` | put `nSafeValue` in it, in the variable's own type: 5 on a `REAL` is 5.0 |

`bSafeApplied` is `TRUE` on the call after it happens, so you can log it or
raise an alarm.

Two things to know:

**`bFailsafe := TRUE` on the node turns the whole mechanism on.** Without it,
`eOnLoss` does nothing.

**Only a single value has a safe state.** A range has no one safe value and a
string has no numeric one, so `eOnLoss` applies to a single number on a writable
table. Anything else ignores it.

## Reading a peer - `node.ModbusRead`

```
eRead := node.ModbusRead(anyData := iRemoteLevel, nPeer := 20, nAddress := 40,
                         bExecute := bReadNow);
```

**A request.** The read goes out on the rising edge of `bExecute`, its inputs
taken at that edge. Holding `bExecute` high gives you one read, not a stream.

| `eRead` | |
| --- | --- |
| `Queued` | outstanding |
| `Ok` | the answer is in your variable; held until the next edge |
| anything else | it did not happen, and why; held until the next edge |

The usual shape:

```
eRead := node.ModbusRead(anyData := iRemoteLevel, nPeer := 20, nAddress := 40,
                         bExecute := bReadNow);
IF bReadNow AND eRead <> E_BeeBusResult.Queued THEN
    bReadNow := FALSE;                     (* ended: Ok, or the reason *)
    IF eRead <> E_BeeBusResult.Ok THEN eLastFault := eRead; END_IF;
END_IF;
```

Remember the result is **held**: before the first scan of a new request it
still shows the last one's. A sequence that raises `bExecute` and checks the
result in the same scan reads the previous outcome; check it from the next
scan on, as above.

A range is the same, with an array:

```
node.ModbusRead(anyData := aRemoteTrend, nPeer := 20, nAddress := 100, bExecute := bReadNow);
```

`nLength` lets you move fewer values than the variable holds - `0` uses all of
it. Asking for more than it holds is refused (`InvalidArgument`) rather than
reading off the end.

A `STRUCT` reads the same way, laid out exactly as `ModbusMap` lays it out, so
reading a peer's whole settings block into a `STRUCT` of the same type lands
member for member - up to 125 registers in one request. The answers are
unpacked on the scan the result turns `Ok`, never half a value at a time. A
register holding a number its member cannot (300 for a `USINT`) leaves that
member as it was and ends the read with `TypeMismatch`.

## Writing to a peer - `node.ModbusWrite`

```
eWrite := node.ModbusWrite(anyData := iNewSetpoint, nPeer := 20, nAddress := 40,
                           bConfirmed := TRUE, bExecute := bSend);
```

**Only two of the four tables can be written**: `Coil` and `HoldingRegister`.
There is no Modbus function code for writing a discrete input or an input
register, so naming one is refused with `InvalidArgument` rather than sent and
lost.

A range or a whole `STRUCT` writes the same way, and is one request rather than
one per address (up to 123 registers). The values are the ones the variable
held at the edge. To change one setting in a peer's settings `STRUCT`, write a
variable of that member's type to that member's address - a `REAL` to its two
registers, a `STRING(16)` to its nine. A peer refuses a value its member cannot
hold, and the write ends in an error.

### `bConfirmed` - the parameter that matters

**`bConfirmed := FALSE`** puts the value on the wire once and forgets it. The
result is `Ok` at the edge: *it was sent*. Nothing is retried, and a lost frame
is a lost value you will not hear about. That is the right trade for a value
you send often anyway, where the next one is along shortly.

**`bConfirmed := TRUE`** keeps it queued until the peer says it took it,
retries if nothing comes back, and reports failure. `Queued`, then `Ok` means
*the peer has it*.

**Use `bConfirmed := TRUE` for setpoints and commands.** A lost setpoint looks
exactly like a delivered one otherwise, and you find out when the plant does
the wrong thing.

## Strings

A `STRING` maps like anything else:

```
node.ModbusMap(anyData := sStatusText, eTable := E_BeeBusModbusTable.InputRegister,
               nAddress := 200);
```

It is packed two characters to a register, then the terminator, so a
`STRING(n)` takes n/2 + 1 addresses: a `STRING(32)` takes 17 and carries all 32
characters. A peer reads it with `ModbusRead` into its own `STRING` and gets the
text back. A `STRING` on its own is written with the length of its text, not
the size of the field it lands in.

`bWritten` comes once for the whole string rather than once per register.

## What can go wrong

| result | what happened |
| --- | --- |
| `UnknownNode` | that peer is not on the network (at the edge: nothing was sent) |
| `DuplicateNodeId` | **this** node stood down - another has its id |
| `NotMapped` | nothing is mapped at that address |
| `Timeout` | a confirmed write was never acknowledged |
| `NodeLost` | the peer left before it was delivered |
| `Refused` | the peer rejected it |
| `InvalidArgument` | wrong table for the type, a count Modbus disallows, `nLength` past the variable; `sLastError` says which |
| `TypeMismatch` | a read brought a number a member cannot hold; that member kept its value |
| `QueueFull` | more requests than `nMaxPending` at once; raise it the next scan |
| `Superseded` | a newer write to the same address replaced it before it went out |

`Superseded` is not a fault. If you write the same address twice before the
first goes out, the newer value wins and the older one is reported rather than
vanishing.

---

Next: [05 - Topics](05-topics.md), or [08 - Patterns](08-patterns.md) for these
in a real program.
