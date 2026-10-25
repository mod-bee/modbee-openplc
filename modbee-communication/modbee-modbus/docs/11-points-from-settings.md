# 11 - Points from settings

A pump controller set up from an HMI cannot have a Modbus address in its
program. The flow meter might be unit 3 holding register 4100 as a FLOAT32 in
CDAB order on one site, and unit 1 input register 0 as a UINT32 in litres on
the next. `MODBUS_POINT` and `MODBUS_POINTS` read (or write) a value whose every
detail comes from settings, read again every scan, so a different meter is a
settings change and not a PLC change.

## Pins first

`MODBUS_POINT` - one point:

| Pin | | |
| --- | --- | --- |
| `NODE` | in-out | which node |
| `UNIT` | in, BYTE | the device's address, 1..247 |
| `FC` | in, MODBUS_PT_FC | `..._FC01_READ_COILS`, `..._FC02_READ_DISCRETE_INPUTS`, `..._FC03_READ_HOLDING_REGISTERS`, `..._FC04_READ_INPUT_REGISTERS`; `..._FC05_WRITE_COIL`, `..._FC06_WRITE_REGISTER`, `..._FC16_WRITE_REGISTERS` |
| `ADDRESS` | in, UINT | the register or coil, numbered from 0 |
| `DTYPE` | in, MODBUS_PT_TYPE | `MODBUS_PT_BIT`, `_INT16`, `_UINT16`, `_INT32`, `_UINT32`, `_FLOAT32`, `_REG_BIT` |
| `ORDER` | in, MODBUS_ORDER | word order of a 32-bit value (see [05](05-reading-and-writing.md)) |
| `BIT` | in, USINT | `_REG_BIT` only: which bit of the register |
| `SCALE`, `OFFSET` | in, REAL | value = raw × `SCALE` + `OFFSET` |
| `EVERY` | in, TIME | how often to read it - or to send a write again |
| `STALE` | in, TIME | no good answer this long and it is lost; `T#0s` = 3 × `EVERY` |
| `TIMEOUT` | in, TIME | this device's answer time limit; `T#0s` = measured |
| `WRITE_VALUE` | in, REAL | a write point's value, in engineering units |
| `ENABLE` | in, BOOL | `FALSE` = not fitted here |
| `VALUE` | out, REAL | engineering units; the last good one held while not ok |
| `Q` | out, BOOL | `VALUE <> 0` |
| `OK` | out, BOOL | good, or a little late. **Interlock on this** |
| `QUALITY` | out, MODBUS_QUALITY | `UNKNOWN`, `GOOD`, `UNCERTAIN`, `BAD` |
| `AGE`, `FAILURES`, `ERROR`, `STATUS` | out | how long, how often, why |

`MODBUS_POINTS` - the same, as two tables: `SETTINGS : ARRAY OF MODBUS_PT_CFG`
(one row a point: `unit`, `fc`, `address`, `dtype`, `order`, `bit`, `scale`,
`offset`, `every`, `stale`, `timeout`, `enable`) and `POINTS : ARRAY OF
MODBUS_PT_STS` (`w` to write; `v`, `q`, `ok`, `quality`, `age`, `failures`,
`result`). Outputs: `GOOD_COUNT`, `LOST_COUNT`, `FIRST_LOST`, `ERROR`, `STATUS`,
`STATUS_TEXT` (`pt 3 unit 5 lost`).

## A table of field points

```
VAR_GLOBAL RETAIN
  FIELD_CFG : ARRAY[1..16] OF MODBUS_PT_CFG;   (* the site's points: from the HMI *)
END_VAR
VAR_GLOBAL
  FIELD : ARRAY[1..16] OF MODBUS_PT_STS;       (* not retained *)
END_VAR

field(TRANSPORT := MODBUS_TRANSPORT#MODBUS_ARDUINO_SERIAL, SERIAL_BAUD := 9600);
points(NODE := field, SETTINGS := FIELD_CFG, POINTS := FIELD);

flowLps := FIELD[1].v;   flowOk := FIELD[1].ok;
FIELD[4].w := BOOL_TO_REAL(valveOpen);      (* a remote relay, FC05 *)
```

Retain the settings, never the status: the status changes every scan, and a
retained struct that changes every scan rewrites the retained store every save
period.

The table is fixed when the program starts. Its length is how many points the
project can have; an unused row is `enable := FALSE`.

## A lost device is never a valid 0

The rule the IO map relies on:

| | `ok` | `v` | `quality` |
| --- | --- | --- | --- |
| never answered | FALSE | 0 | `UNKNOWN` - a commissioning fault: check unit and address |
| answered, on time | TRUE | the value | `GOOD` |
| answered, late (one interval's grace has gone, or one failure) | TRUE | the value | `UNCERTAIN` |
| no good answer for `stale`, or two failures in a row | FALSE | **the last good value** | `BAD` |
| `enable` FALSE | FALSE | - | `UNKNOWN` |
| settings that cannot work | FALSE | - | `UNKNOWN`, `result` `MODBUS_INVALID_ARGUMENT` |

A function mapped to a point that is not ok takes its fail-safe. Nothing reads
a dead radio as a valid OFF or a valid 0.

## Changing settings while running

Every setting is read every scan. A new unit, function code, address, type,
word order or bit is a **different point**: its value, age and failures are
dropped, `quality` goes back to `UNKNOWN` and the next read goes to the new
place. A reply still on its way for the old address is discarded. Scale,
offset, `every`, `stale` and `timeout` change in place.

`MODBUS_WATCH` follows a new `UNIT`, `FC`, `ADDRESS` or `ORDER` the same way.

## Writes

`FC05` (a coil), `FC06` (one register: `INT16` / `UINT16`) and `FC16` (one or
two registers: any register type) write `w` (or `WRITE_VALUE`), scaled back:
raw = (value − `offset`) / `scale`, rounded and held to the type's range. A
write goes as soon as the value changes, and again every `every`, so a remote
output with a watchdog is kept alive and one that lost power is told again.
`ok` on a write point means the last write was acknowledged.

A `REG_BIT` is never written: setting one bit of a register would be a
read-modify-write that races every other writer of that register. Use a coil,
or `MODBUS_WRITE` with FC 22.

## Radio devices (the LoRa mesh)

The LoRa mesh HAT joins the field bus, so a device behind the mesh is just
another unit on the same `MODBUS_NODE` - with answers that take seconds.

- **Set `timeout`** to the worst round trip you expect, one hop or several:
  2 to 5 s. The client then waits that long for that unit. Without it the
  client's first, generous timeout is about 200 ms and the device is never
  heard.
- **Set `every`** to seconds or minutes: soil and rain sensors 60 s, a pond
  level 30 s, an irrigator fail-safe 10 to 15 s.
- **Set `stale`** to about 3 × `every`, so one lost reply is `UNCERTAIN`, not a
  trip.
- The longest `timeout` among a unit's rows is that unit's. Rows without one
  are measured.
- One request is on a serial bus at a time. A radio reply holds the wired
  devices meanwhile, so a fast protection read (a mag meter used for no-flow)
  does not belong on a bus that carries radio traffic: put it on its own port,
  or give its protection delay more than the worst radio round trip.
- A device that stops answering is asked less often - up to eight intervals,
  and never more than a minute apart - so it does not take the bus from the
  live ones, and is found again soon after it comes back.

## The protocol underneath

`ModbusPoint` and `ModbusClient::setUnitTimeout()` in the modbee-modbus
library. The per-unit timeout fixed a real fault: the client's last expiry pass
used to judge every outstanding request against the cold-start timeout, so a
unit with a longer timeout of its own was cut off at about 200 ms anyway.

**Next:** [07 - Block reference](07-block-reference.md)
