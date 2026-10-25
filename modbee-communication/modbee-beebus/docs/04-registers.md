# 04 - Registers

The Modbus side. Your variables sit at numbered addresses, and peers reach them
the way they would reach any Modbus device.

Three blocks:

| | |
| --- | --- |
| `BEEBUS_MB_MAP` | put **your** variables at addresses, so peers can reach them |
| `BEEBUS_MB_READ` | read **a peer's** addresses |
| `BEEBUS_MB_WRITE` | write **a peer's** addresses |

## The four lists

Modbus has four separate numbered lists. Address 40 in one is a different thing
from address 40 in another.

| `TABLE` | holds | peers may | function codes |
| --- | --- | --- | --- |
| `BEEBUS_MB_COIL` | on/off | read and **write** | 1, 5, 15 |
| `BEEBUS_MB_DISCRETE_INPUT` | on/off | read only | 2 |
| `BEEBUS_MB_HOLDING_REG` | 16 bits | read and **write** | 3, 6, 16 |
| `BEEBUS_MB_INPUT_REG` | 16 bits | read only | 4 |

The rule of thumb: **inputs are read-only, coils and holding registers are
writable.** Put anything a peer should be able to change in a coil or a holding
register, and anything that is purely a reading in a discrete or input register.

## Saying what you are passing

Every one of the three blocks has a single `VALUE` pin. Put the variable on it:

```
VALUE := iSetpoint        (* one value *)
VALUE := aTrend           (* ARRAY [0..99] OF WORD — a range of registers *)
VALUE := aValves          (* ARRAY [0..7] OF BOOL  — a range of coils *)
VALUE := CFG              (* a STRUCT — every member, one after the other *)
```

Nothing is wrapped. The pin carries the address, the type and — for a STRUCT —
its layout, so one block covers a single value, a whole range and a whole
STRUCT without different blocks for each.

**`TABLE` is what says bits or registers**, and it is a pin you were setting
anyway. A block reading `TABLE := BEEBUS_MB_COIL` knows it is dealing with bits; one
reading `BEEBUS_MB_HOLDING_REG` knows it is dealing with 16-bit values. The variable
does not have to say so a second time.

An array has to be declared with **fixed bounds** — `ARRAY [0..99] OF WORD`, not
`ARRAY [*]`. A variable-length array is a view rather than a variable, and views
travel on in-out pins only.

### How a value is laid out

Every value takes the registers its type needs, from `ADDRESS` on, one after the
other in declaration order:

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
which `INT` is not. A VFD control or status word belongs in a `WORD`. Use `INT`
for a signed reading and `UINT` for an unsigned one.

In `BEEBUS_MB_COIL` and `BEEBUS_MB_DISCRETE_INPUT` every member has to be a
`BOOL`, one address each. `WSTRING` is refused everywhere — a value quietly cut
down would be wrong rather than missing. A refused variable is refused **whole**, with `LAST_ERROR` naming
the member: skipping it would move every address after it.

## Sharing your variables — `BEEBUS_MB_MAP`

```
mapSpeed( NODE := node, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 40,
          VALUE := iSpeed );
```

`iSpeed` **is** holding register 40 from that moment. A peer reading gets what
it holds now; a peer writing changes it. Nothing is copied, and there is no
request pin.

A range works the same way:

```
mapTrend( NODE := node, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 100,
          VALUE := aTrend );
```

`aTrend : ARRAY[0..99] OF WORD` at address 100 becomes addresses 100 to 199. The
array's lower bound maps to `ADDRESS` whatever that bound is.

### Outputs

| | |
| --- | --- |
| `BOUND` | the addresses are live |
| `COUNT` | how many addresses were taken |
| `WRITTEN` | one scan, when a peer wrote any of them |
| `WRITTEN_NAME` | which member, e.g. `levelHiMm` or `spare[3]` (held until the next write) |
| `WRITTEN_INDEX` | its position, from 1, every array element and nested member one position (held) |
| `WRITTEN_ADDRESS` | its first address (held) |
| `WRITTEN_COUNT` | how many members that write covered (held) |
| `SAFE_APPLIED` | one scan, when the safe state was applied |
| `LAST_ERROR` | when refused, which member and why |

**`WRITTEN` is the one to use.** It tells you a peer changed the value rather
than your own program doing it:

```
IF mapSetpoint.WRITTEN THEN
    (* somebody sent us a new setpoint — act on it *)
    bNewSetpoint := TRUE;
END_IF;
```

When one write covers several members — an HMI sending a whole block — the
`WRITTEN_*` outputs name the first (lowest address) and `WRITTEN_COUNT` says how
many there were.

### One instance, one mapping

`TABLE`, `ADDRESS` and `VALUE` are taken on the first scan the node is there.
Changing them later does nothing, and calling the same instance twice does not
map a second range. Two separate ranges are two instances — or one `STRUCT`.

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

cfgMap( NODE := node, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 0,
        VALUE := CFG );
```

The HMI writes straight into `CFG`. `WRITTEN` says a write happened and
`WRITTEN_NAME` which setting, so the program can check it and put the old value
back when it is out of range:

```
IF cfgMap.WRITTEN THEN
    IF CFG.levelLoMm >= CFG.levelHiMm THEN
        CFG.levelLoMm := levelLoInUse;                     (* refused *)
        sRefused := CONCAT('Setting refused: ', cfgMap.WRITTEN_NAME);
    END_IF;
END_IF;
```

**Add new members at the end.** One added in the middle moves every address
after it. A spare or two at the end costs nothing.

**The address table is generated, not typed.** A table generator
reads the `.st` file that declares the `STRUCT` and prints every member's
address, type and register count as Markdown, and as JSON for an HMI's
firmware.


## Safe states

**Never on a setting or a command.** A safe value is for a live setpoint a peer
keeps driving; a setting or a command written by an HMI or SCADA must never
change because the link dropped — the PLC runs on its own.


A writable address has a problem: the peer that was driving it goes quiet, and
the last value it sent sits there forever. On a setpoint that can be dangerous.

```
mapSetpoint( NODE := node, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 40,
             ON_LOSS := BEEBUS_MB_RESET_TO_VALUE, SAFE_VALUE := 5,
             VALUE := iSetpoint );
```

| `ON_LOSS` | |
| --- | --- |
| `BEEBUS_MB_HOLD_LAST_VALUE` | leave it where it was (the default) |
| `BEEBUS_MB_RESET_TO_VALUE` | put `SAFE_VALUE` in it |

`SAFE_APPLIED` pulses when it happens, so you can log it or raise an alarm.

Two things to know:

**`FAILSAFE := TRUE` on the node block turns the whole mechanism on.** Without
it, `ON_LOSS` does nothing.

**Only a single value has a safe state.** A range has no one safe value and a
string has no numeric one, so `ON_LOSS` applies to single-value bindings on a
writable table. Anything else ignores it.

## Reading a peer — `BEEBUS_MB_READ`

```
readLevel( REQ := bReadNow, NODE := node, PEER := 20,
           TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 40,
           VALUE := iRemoteLevel );
```

**Edge-triggered.** The read goes out on the rising edge of `REQ`. Holding
`REQ` high gives you one read, not a stream.

| output | |
| --- | --- |
| `BUSY` | outstanding |
| `DONE` | one scan, when the answer landed in your variable |
| `ERROR` | it did not |
| `STATUS` | why |

The usual shape:

```
readLevel( REQ := bReadNow, ... );

IF readLevel.DONE THEN
    (* iRemoteLevel is fresh this scan *)
END_IF;

IF readLevel.ERROR THEN
    eLastFault := readLevel.STATUS;
END_IF;
```

A range is the same with a different wrapper:

```
readTrend( REQ := bReadNow, NODE := node, PEER := 20,
           TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 100,
           VALUE := aRemoteTrend );
```

`LENGTH` lets you move fewer values than the variable holds — `LENGTH := 0` uses
all of it. Asking for more than it holds is refused rather than reading off the
end.

A `STRUCT` reads the same way, laid out exactly as `BEEBUS_MB_MAP` lays it out,
so reading a peer's whole settings block into a `STRUCT` of the same type lands
member for member — up to 125 registers in one request. The answers are
unpacked on the scan `DONE` is set, never half a value at a time.

## Writing to a peer — `BEEBUS_MB_WRITE`

```
writeSetpoint( REQ := bSend, NODE := node, PEER := 20,
               TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 40, CONFIRMED := TRUE,
               VALUE := iNewSetpoint );
```

**Only two of the four lists can be written**: `BEEBUS_MB_COIL` and `BEEBUS_MB_HOLDING_REG`.
There is no Modbus function code for writing a discrete input or an input
register, so naming one is refused with `BEEBUS_INVALID_ARGUMENT` rather than
sent and lost.

A range or a whole `STRUCT` writes the same way, and is one request rather than
one per address (up to 123 registers). To change one setting in a peer's
settings `STRUCT`, write a variable of that member's type to that member's
address — a `REAL` to its two registers, a `STRING(16)` to its nine. A peer
refuses a value its member cannot hold, and the write ends in `ERROR`.

```
writeValves( REQ := bSend, NODE := node, PEER := 20,
             TABLE := BEEBUS_MB_COIL, ADDRESS := 0, CONFIRMED := TRUE,
             VALUE := aValves );
```

### `CONFIRMED` — the pin that matters

**`CONFIRMED := FALSE`** puts the value on the wire once and forgets it. `DONE`
means *it was sent*. Nothing is retried, and a lost frame is a lost value you
will not hear about. That is the right trade for a value you send every scan
anyway, where the next one is along shortly.

**`CONFIRMED := TRUE`** keeps it queued until the peer says it took it, retries
if nothing comes back, and reports failure. `DONE` means *the peer has it*.

**Use `CONFIRMED := TRUE` for setpoints and commands.** A lost setpoint looks
exactly like a delivered one otherwise, and you find out when the plant does
the wrong thing.

Use `FALSE` for a fast cyclic value where the next update fixes any loss.

## Strings

A `STRING` maps like anything else:

```
mapStatus( NODE := node, TABLE := BEEBUS_MB_INPUT_REG, ADDRESS := 200,
           VALUE := sStatusText );
```

It is packed two characters to a register, then the terminator, so a
`STRING(n)` takes n/2 + 1 addresses: a `STRING(32)` takes 17 and carries all 32
characters. A peer reads it with `BEEBUS_MB_READ` into its own `STRING` and
gets the text back.

`WRITTEN` fires once for the whole string rather than once per register.

## What can go wrong

| `STATUS` | what happened |
| --- | --- |
| `BEEBUS_UNKNOWN_NODE` | that peer is not on the network |
| `BEEBUS_DUPLICATE_NODE_ID` | **this** node stood down — another has its ID |
| `BEEBUS_NOT_MAPPED` | the peer has nothing at that address |
| `BEEBUS_TIMEOUT` | a confirmed write was never acknowledged |
| `BEEBUS_NODE_LOST` | the peer left before it was delivered |
| `BEEBUS_REFUSED` | the peer rejected it |
| `BEEBUS_INVALID_ARGUMENT` | wrong table for the type, or a count Modbus disallows; `LAST_ERROR` says which member |
| `BEEBUS_TYPE_MISMATCH` | a read brought a number a member cannot hold; that member kept its value |
| `BEEBUS_SUPERSEDED` | a newer write to the same address replaced it before it went out |

`BEEBUS_SUPERSEDED` is not a fault. If you write the same address twice before
the first goes out, the newer value wins and the older one is reported rather
than vanishing.

---

Next: [05 - Topics](05-topics.md), or [08 - Patterns](08-patterns.md) for these
in a real program.
