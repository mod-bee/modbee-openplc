# 11 - Points from settings

A pump controller set up from an HMI cannot have a Modbus address in its
program. The flow meter might be unit 3 holding register 4100 as a `Float32` in
CDAB order on one site, and unit 1 input register 0 as a `UInt32` in litres on
the next. `node.Point` and `node.Points` read (or write) a value whose every
detail comes from settings, read again every scan, so a different meter is a
settings change and not a PLC change.

## One point

```
eFlow := node.Point(anyValue := fFlowLps, nUnitId := nFlowUnit,
                    eFunction := eFlowFunction, nAddress := nFlowAddress,
                    eType := eFlowType, eOrder := eFlowOrder,
                    fScale := fFlowScale, tPeriod := T#2s,
                    bOk => bFlowOk, eQuality => eFlowQ);
IF bFlowOk THEN ... END_IF;
```

**The point is its variable**, `anyValue`: a `REAL` or `LREAL`, an integer, or
a `BOOL`. A read point writes `raw x fScale + fOffset` into it; a write point
sends what it holds. Every other input is a setting, read every scan:

| | |
| --- | --- |
| `nUnitId` | the device's address, 1..247 |
| `eFunction` | `E_ModbusPointFunction.ReadCoils`, `ReadDiscreteInputs`, `ReadHoldingRegisters` (default), `ReadInputRegisters`; `WriteSingleCoil`, `WriteSingleRegister`, `WriteMultipleRegisters` |
| `nAddress` | the register or coil, numbered from 0 |
| `eType` | `E_ModbusPointType.Bit`, `Int16`, `UInt16` (default), `Int32`, `UInt32`, `Float32`, `RegisterBit` |
| `eOrder` | word order of a 32-bit value (see [05](05-reading-and-writing.md)) |
| `nBit` | `RegisterBit` only: which bit of the register |
| `fScale`, `fOffset` | value = raw x `fScale` + `fOffset` |
| `tPeriod` | how often to read it - or to send a write again. `T#0s` = 1 s |
| `tStale` | no good answer this long and it is lost; `T#0s` = 3 x `tPeriod` |
| `tTimeout` | this device's answer time limit; `T#0s` = measured |
| `bEnable` | `FALSE` = not fitted here: never asked, never ok |

It returns the last attempt's result, and `InvalidArgument` for settings that
cannot work (a `Float32` with `WriteSingleRegister`, a bit above 15, a
`RegisterBit` write). Outputs: `bOk` - good, or a little late, **interlock on
this** - `eQuality`, `tAge` and `nFailures`.

## A table of field points

```
VAR_GLOBAL RETAIN
  FIELD_CFG : ARRAY[1..16] OF ST_ModbusPointConfig;   (* the site's points: from the HMI *)
END_VAR
VAR_GLOBAL
  FIELD : ARRAY[1..16] OF ST_ModbusPointStatus;       (* not retained *)
END_VAR

PROGRAM net
VAR
    field  : FB_ModbusNode;
    serial : ST_ModbusSerialConfig := (nUart := 2, nBaudRate := 9600, nRxPin := 16, nTxPin := 17);
    sText  : STRING(30);
END_VAR

field(eTransport := E_ModbusTransport.ArduinoSerial, stSerialConfig := serial);
field.Points(anySettings := FIELD_CFG, anyPoints := FIELD, sStatusText => sText);

fFlowLps := FIELD[1].fValue;   bFlowOk := FIELD[1].bOk;
FIELD[4].fWriteValue := BOOL_TO_REAL(bValveOpen);   (* a remote relay, WriteSingleCoil *)
```

`anySettings` is an `ARRAY OF ST_ModbusPointConfig` - one row a point:
`nUnitId`, `eFunction`, `nAddress`, `eType`, `eOrder`, `nBit`, `fScale`,
`fOffset`, `tPeriod`, `tStale`, `tTimeout`, `bEnable`, the same as `Point`'s
inputs. `anyPoints` is an `ARRAY OF ST_ModbusPointStatus` of the same length:
`fWriteValue` is your logic's, the value to write; `fValue`, `bValue`, `bOk`,
`eQuality`, `tAge`, `nFailures`, `eResult` are each row's status. Anything
else on either is refused with `InvalidArgument` and *"not point tables"*.

`Points` returns `Ok` while every enabled row is ok, else the first lost row's
result. Its outputs: `nGoodCnt`, `nLostCnt`, `nFirstLost` (that row, counted
from 1, 0 when none) and `sStatusText`, one line for a
panel: *"pt 3 unit 5 lost"*, *"pt 2 unit 9 no answer"* (never answered: check
the address), *"pt 4 bad settings"*, *"tables differ"*, *"field bus down"*.

Retain the settings, never the status: the status changes every scan, and a
retained structure that changes every scan rewrites the retained store every
save period.

The table is fixed the first time the link is up. Its length is how many
points the project can have; an unused row is `bEnable := FALSE`.

## A lost device is never a valid 0

The rule the IO map relies on:

| | `bOk` | the value | `eQuality` |
| --- | --- | --- | --- |
| never answered | FALSE | `Point`: the variable as it was; a row's `fValue`: 0 | `Unknown` - a commissioning fault: check unit and address |
| answered, on time | TRUE | the value | `Good` |
| answered, late (one period's grace has gone, or one failure) | TRUE | the value | `Uncertain` |
| no good answer for `tStale`, or two failures in a row | FALSE | **the last good value** | `Bad` |
| `bEnable` FALSE | FALSE | - | `Unknown` |
| settings that cannot work | FALSE | - | `Unknown`, result `InvalidArgument` |

A function mapped to a point that is not ok takes its fail-safe. Nothing reads
a dead radio as a valid OFF or a valid 0.

## Changing settings while running

Every setting is read every scan. A new unit, function, address, type, word
order or bit is a **different point**: its value, age and failures are dropped,
`eQuality` goes back to `Unknown` and the next read goes to the new place. A
reply still on its way for the old address is discarded. Scale, offset,
`tPeriod`, `tStale` and `tTimeout` change in place.

`Watch` follows a new `nUnitId`, `eTable`, `nAddress` or `eOrder` the same way.

## Writes

`WriteSingleCoil`, `WriteSingleRegister` (`Int16` / `UInt16`) and
`WriteMultipleRegisters` (one or two registers: any register type) write the
point's value - `anyValue`, or a row's `fWriteValue` - scaled back:
raw = (value - `fOffset`) / `fScale`, rounded and held to the type's range. A
write goes as soon as the value changes, and again every `tPeriod`, so a remote
output with a watchdog is kept alive and one that lost power is told again.
`bOk` on a write point means the last write was acknowledged.

A `RegisterBit` is never written: setting one bit of a register would be a
read-modify-write that races every other writer of that register. Use a coil,
or `MaskWriteRegister`.

## Radio devices (the LoRa mesh)

The LoRa mesh HAT joins the field bus, so a device behind the mesh is just
another unit on the same node - with answers that take seconds.

- **Set `tTimeout`** to the worst round trip you expect, one hop or several:
  2 to 5 s. The client then waits that long for that unit. Without it the
  client's first, generous timeout is about 200 ms and the device is never
  heard.
- **Set `tPeriod`** to seconds or minutes: soil and rain sensors 60 s, a pond
  level 30 s, an irrigator fail-safe 10 to 15 s.
- **Set `tStale`** to about 3 x `tPeriod`, so one lost reply is `Uncertain`,
  not a trip.
- The longest `tTimeout` among a unit's points is that unit's. Points without
  one are measured.
- One request is on a serial bus at a time. A radio reply holds the wired
  devices meanwhile, so a fast protection read (a mag meter used for no-flow)
  does not belong on a bus that carries radio traffic: put it on its own port,
  or give its protection delay more than the worst radio round trip.
- A device that stops answering is asked less often - up to eight periods,
  and never more than a minute apart - so it does not take the bus from the
  live ones, and is found again soon after it comes back.

## The protocol underneath

`ModbusPoint` and `ModbusClient::setUnitTimeout()` in the modbee-modbus
library. The per-unit timeout fixed a real fault: the client's last expiry pass
used to judge every outstanding request against the cold-start timeout, so a
unit with a longer timeout of its own was cut off at about 200 ms anyway.

**Next:** [Migrating from 0.1](migrating-from-0.1.md)
