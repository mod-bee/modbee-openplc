# 04 - Being a device

`MODBUS_MAP` makes your PLC a Modbus device. A SCADA package, an HMI, a
datalogger or another PLC can then read it — and write it, where you let them.

## The whole idea

Set the node's role, then say what lives where:

```
VAR
    node  : MODBUS_NODE;
    pub   : MODBUS_MAP;
    trend : ARRAY [0..9] OF WORD;
END_VAR

node( TRANSPORT := MODBUS_RUNTIME_SERIAL,
      SERIAL_DEVICE    := '/dev/ttyUSB0', SERIAL_BAUD := 19200,
      ROLE      := MODBUS_ROLE_BOTH,
      SERIAL_UNIT_ID   := 7 );

pub( NODE := node, TABLE := MODBUS_INPUT_REGISTERS,
     ADDRESS := 100, VALUE := trend );
```

`trend` now **is** input registers 100 to 109.

**There is no request pin, and nothing is copied.** A client reading address
103 gets whatever `trend[3]` holds at that instant. A client writing a holding
register changes your variable directly. There is nothing to schedule and
nothing to keep in step.

**The array's lower bound maps to `ADDRESS`, whatever that bound is.**
`ARRAY [0..9]` at `ADDRESS := 100` is 100 to 109; so is `ARRAY [1..10]`.

## Choose the list on purpose

```
MODBUS_COILS             on/off,  a client may write it   FC 1, 5, 15
MODBUS_DISCRETE_INPUTS   on/off,  read only               FC 2
MODBUS_HOLDING_REGISTERS 16 bits, a client may write it   FC 3, 6, 16, 22
MODBUS_INPUT_REGISTERS   16 bits, read only               FC 4
```

**Put anything a client must not change in a read-only list.** This is worth
being deliberate about. It is not a permission setting that somebody can alter
later — the list itself has no write function code, so a client that tries is
answered with an exception. A measured value, a status word, a running hours
counter: input registers. A setpoint somebody is meant to adjust: holding
registers.

The four lists are separate, so you can use address 0 in all four without
collision, and most devices do.

## A BOOL goes in a bit list, a number in a register list

Crossing them is refused with `MODBUS_INVALID_ARGUMENT` rather than
reinterpreted. A coil holds one bit and a register holds sixteen, so binding
one to the other would leave half a register pointing at whatever happens to
sit beside your variable in memory.

**Use `WORD` for registers, not `INT`.** A register is sixteen raw bits, and
`WORD` is what a program can mask, shift and take a bit of — `statusWord.6` for
bit 6 — while `AND`, `OR` and `SHL` are all typed `ANY_BIT`, which `INT` is
not. Use `WORD_TO_INT` where you want a signed number.

**An array must have fixed bounds.** A generic pin takes a variable, and
`ARRAY [*]` is not one — it is a view, and views ride in-out pins only.

## A mapped number is sixteen bits

`INT`, `UINT` and `WORD` map. **`REAL`, `DINT` and the 64-bit types do not** —
they are refused with `MODBUS_INVALID_ARGUMENT`. This is the one place
`MODBUS_MAP` asks more of you than `MODBUS_READ`, which takes all of them, so
it is worth saying why.

Nothing is copied here. The register a client reads **is** your variable, at
that address in memory, this instant. A `REAL` is not a pair of registers; it
is four bytes in a layout that `ORDER` would have to rearrange, and
rearranging means copying, and copying means a client can read half of an old
value and half of a new one with nothing on the wire to say so. A torn reading
is worse than a refused binding, so the block refuses.

Publish a scaled integer instead, which is what a real device does:

```
(* 4.7 mA becomes 470 - 0.01 mA of resolution, and the client divides *)
scaled := REAL_TO_INT( milliamps * 100.0 );
MODBUS_MAP( NODE := node, TABLE := MODBUS_INPUT_REGISTERS,
            ADDRESS := 0, VALUE := scaled );
```

Say the scaling in your address list, the same way every instrument manual
does. If you would rather not scale, put the `REAL` behind `MODBUS_READ` on
the other end instead: a read completes as one operation, so it has no torn
value to cause.

## Several ranges

Call the block more than once in a scan and it maps that many ranges. That is
how two non-consecutive ranges are expressed:

```
VAR
    measured : MODBUS_MAP;
    commands : MODBUS_MAP;
    lamps    : MODBUS_MAP;
END_VAR

measured( NODE := node, TABLE := MODBUS_INPUT_REGISTERS,
          ADDRESS := 0,   VALUE := readings );

commands( NODE := node, TABLE := MODBUS_HOLDING_REGISTERS,
          ADDRESS := 100, VALUE := setpoints );

lamps   ( NODE := node, TABLE := MODBUS_COILS,
          ADDRESS := 0,   VALUE := indicators );
```

Use one block instance per range. They are independent: each has its own
`BOUND`, `COUNT` and `WRITTEN`.

## Knowing when a client wrote

`WRITTEN` pulses for one scan when a client writes **any** address in this
block's range, whether or not the value changed:

```
commands( NODE := node, TABLE := MODBUS_HOLDING_REGISTERS,
          ADDRESS := 100, VALUE := setpoints );

IF commands.WRITTEN THEN
    (* validate before acting on anything a stranger sent *)
    IF setpoints[0] > 1500 THEN setpoints[0] := 1500; END_IF;
    newSetpoint := TRUE;
END_IF;
```

It is counted per binding, so two blocks mapping two ranges never take each
other's edges.

**Validate what arrives.** A client can write any sixteen-bit value it likes
into a holding register, including one that will hurt. The register is your
variable, so the check belongs in your program and nowhere else.

## Failsafe — what happens when the client stops

A machine being driven over Modbus needs an answer to "what if the master goes
away". Two pins:

```
cfg( NODE := node, TIMEOUT := T#0s, FAILSAFE := T#5s );   (* MODBUS_CONFIG *)

speed( NODE := node, TABLE := MODBUS_HOLDING_REGISTERS, ADDRESS := 40,
       ON_LOSS := MODBUS_RESET_TO_VALUE, SAFE_VALUE := 0,
       VALUE := demandSpeed );
```

`FAILSAFE` on `MODBUS_CONFIG` is the silence that counts as loss. `ON_LOSS`
on the map says what that address does about it. `SAFE_APPLIED` pulses when it
happens.

**Both are needed.** Without `FAILSAFE` there is no silence to measure, so
`ON_LOSS` never fires — which is a quiet way to have no safety at all, and
worth checking on commissioning by pulling the cable and watching the pin.

`MODBUS_RESET_TO_VALUE` applies to a **single value only**. A range has no one
safe value, and guessing one would be worse than holding. Bind the few
addresses that need a safe state individually.

**`MODBUS_HOLD_LAST_VALUE`, the default, is a real choice and often the right
one** — a temperature setpoint should probably stay where it was. A speed
demand probably should not.

## Reading your own registers back

Nothing special is needed: the variable is the register, so read the variable.
`MODBUS_MAP` does not give you a copy because there is no copy.

## What it costs

Nothing per scan. Binding is done once; after that a client's request is served
straight out of your variable by the node, in the node's own task. Mapping two
thousand registers costs the same per scan as mapping two.

**Next:** [05 - Reading and writing](05-reading-and-writing.md)
