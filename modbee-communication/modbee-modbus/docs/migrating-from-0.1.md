# Migrating from 0.1

modbee-modbus 0.2.0 replaces the 13 blocks of 0.1.x with 2. Each link is one
block, `FB_ModbusNode`; every request, watch, point, device and mapped range
is a method of it; the helper blocks are option structures on its inputs.
`FB_ModbusBridge` stays a block of its own. Names follow Beckhoff's TwinCAT 3
conventions: `FB_` blocks, `ST_` structures, `E_` enumerations used qualified,
pins with a type prefix (`bConnect`, `sHost`, `nPort`).

**You do not have to move.** A project built on 0.1.x stays on 0.1.x and runs
unchanged: pin it (`openplc-cli library pin <project> modbee-modbus@0.1.0`) and
it keeps building against the version it was written for. Move when you
choose. **The wire does not change**: the same configuration sends the same
frames, answers on the same addresses and uses the same timing.

## The shape of a 0.2.0 program

```st
VAR
  node    : FB_ModbusNode;
  serial  : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200);
  timing  : ST_ModbusTimingConfig := (tFailsafe := T#5s);
  aRegs   : ARRAY [0..3] OF WORD;
  nLevel  : WORD;
  eRead   : E_ModbusResult;
  eLevelQ : E_ModbusQuality;
END_VAR

node(eTransport := E_ModbusTransport.RuntimeSerial, stSerialConfig := serial,
     stTimingConfig := timing);
eRead := node.ReadHoldingRegisters(anyData := aRegs, nUnitId := 2, nAddress := 40,
                                   bExecute := bRead);
node.Watch(anyData := nLevel, nUnitId := 2, eTable := E_ModbusTable.InputRegister,
           nAddress := 30, tPeriod := T#2s, eQuality => eLevelQ);
```

was, in 0.1.x:

```
node ( TRANSPORT := MODBUS_RUNTIME_SERIAL, SERIAL_DEVICE := '/dev/ttyUSB0',
       SERIAL_BAUD := 19200 );
cfg  ( NODE := node, TIMEOUT := T#0s, FAILSAFE := T#5s );
rd   ( NODE := node, REQ := bRead, UNIT := 2,
       FC := MODBUS_FC03_READ_HOLDING_REGISTERS, ADDRESS := 40, VALUE := aRegs );
level( NODE := node, UNIT := 2, FC := MODBUS_FC04_READ_INPUT_REGISTERS,
       ADDRESS := 30, EVERY := T#2s, VALUE := nLevel );
```

- **A method call has no instance.** Drop the 0.1.x instance (`rd`, `level`)
  and call the method on the node. A call is found again each scan by **the
  variable it is about** - its declared name and type - so one variable is one
  record per method. Two 0.1.x instances that read into the same variable need
  two variables now. Calls with no variable (`WriteSingleCoil`,
  `WriteSingleRegister`, `MaskWriteRegister`, `Device`,
  `ReadDeviceIdentification`) are found by unit and address.
- **The `NODE` pin is gone**: the node is the method's instance.
- **The function code is the method's name.** `MODBUS_READ` with `FC :=
  MODBUS_FC03_READ_HOLDING_REGISTERS` is `ReadHoldingRegisters`; `MODBUS_WRITE`
  with `MODBUS_FC_AUTO` is whichever of the four write methods it would have
  chosen.
- **Each method returns an `E_ModbusResult`.** The `ERROR`/`STATUS` pair of
  every 0.1.x block is that result. A request's `BUSY` is `Queued`, and `DONE`
  - a one-scan pulse in 0.1 - is `Ok`, **held until the next rising edge** of
  `bExecute`. A test `IF rd.DONE THEN` becomes `IF eRead = E_ModbusResult.Ok
  THEN`, true on every scan until the next request.
- **Outputs are read with `=>`**: `node.Watch(..., eQuality => q)`.
- **Enumerations are qualified**: `E_ModbusResult.Ok`, not `MODBUS_OK`. Each
  type is `{attribute 'qualified_only'}`, so a bare `Ok` does not compile.
- **A failing call is named on the node**: `bError`, `eErrorId`, `sLastError`
  read *"ReadHoldingRegisters aRegs: Timeout"* until that call succeeds.
- **Every method runs in the node's task**, as in 0.1, and returns
  `WrongTask` in any other.

## Blocks

| 0.1.x | 0.2.0 |
| --- | --- |
| `MODBUS_NODE` | `FB_ModbusNode` |
| `MODBUS_CONFIG` | `FB_ModbusNode.stTimingConfig : ST_ModbusTimingConfig` |
| `MODBUS_IDENTITY` | `FB_ModbusNode.stIdentityConfig : ST_ModbusIdentityConfig` |
| `MODBUS_ARDUINO` | `FB_ModbusNode.stSerialConfig` (serial port and pins) and `stNetworkConfig : ST_ModbusNetworkConfig` (Wi-Fi and Ethernet) |
| `MODBUS_READ` | `node.ReadCoils`, `ReadDiscreteInputs`, `ReadHoldingRegisters`, `ReadInputRegisters` |
| `MODBUS_WRITE` | `node.WriteSingleCoil`, `WriteSingleRegister`, `WriteMultipleCoils`, `WriteMultipleRegisters`, `MaskWriteRegister` |
| (new) | `node.ReadWriteMultipleRegisters` - function code 23 |
| `MODBUS_WATCH` | `node.Watch` |
| `MODBUS_POINT` | `node.Point` |
| `MODBUS_POINTS` | `node.Points` |
| `MODBUS_DEVICE` | `node.Device`; its `IDENTIFY` is `node.ReadDeviceIdentification` |
| `MODBUS_MAP` | `node.Map` |
| `MODBUS_STATUS` | `node.Statistics`; `CONNECTED` and `CLIENTS` are the node's `bConnected` and `nClients` |
| `MODBUS_BRIDGE` | `FB_ModbusBridge` |

## Pins and parameters

### MODBUS_NODE, MODBUS_CONFIG, MODBUS_IDENTITY, MODBUS_ARDUINO -> FB_ModbusNode

| 0.1.x | 0.2.0 |
| --- | --- |
| `TRANSPORT` | `eTransport : E_ModbusTransport` |
| `ROLE` | `eRole : E_ModbusRole` |
| `TCP_HOST`, `TCP_PORT` | `sHost`, `nPort` |
| `SERIAL_DEVICE`, `SERIAL_BAUD`, `SERIAL_PARITY`, `SERIAL_UNIT_ID` | `stSerialConfig.sDevice`, `nBaudRate`, `eParity`, `nUnitId` |
| `RESET_STATS` | `node.Statistics(bReset := ...)` |
| `CONNECT` | `bConnect` |
| `READY` | `bLinkUp` |
| `CONNECTED`, `CLIENTS` | `bConnected`, `nClients` |
| `ERROR`, `STATUS`, `LAST_ERROR` | `bError`, `eErrorId`, `sLastError` |
| `MODBUS_CONFIG.TIMEOUT`, `RETRIES` | `stTimingConfig.tTimeout`, `nRetries` |
| `MODBUS_CONFIG.RECONNECT` | `stTimingConfig.tReconnect`; `bAutoReconnect := FALSE` turns recovery off (0.1's `-1` could never be given: a `TIME` is never negative) |
| `MODBUS_CONFIG.FRAMING` | `stTimingConfig.eFraming : E_ModbusFraming` |
| `MODBUS_CONFIG.FAILSAFE`, `IDLE`, `MAX_CLIENTS` | `stTimingConfig.tFailsafe`, `tIdle`, `nMaxClients` |
| `MODBUS_CONFIG.QUEUE`, `QUEUE_BYTES` | `stTimingConfig.nMaxPending`, `nMaxPendingBytes` |
| `MODBUS_IDENTITY.VENDOR`, `PRODUCT`, `REVISION` | `stIdentityConfig.sVendor`, `sProduct`, `sRevision` |
| `MODBUS_ARDUINO.PORT`, `RX_PIN`, `TX_PIN`, `DE_PIN`, `DE_HOLD` | `stSerialConfig.nUart`, `nRxPin`, `nTxPin`, `nDePin`, `tDeHold` |
| `MODBUS_ARDUINO.SSID`, `PASSWORD`, `MAC`, `IP`, `GATEWAY`, `SUBNET` | `stNetworkConfig.sSsid`, `sWiFiPassword`, `sMac`, `sIp`, `sGateway`, `sSubnet` |
| `APPLIED`, `ERROR`, `STATUS` of the helper blocks | gone: a structure is checked by the compiler, and what the node cannot use is reported on its own `bError` |

`stTimingConfig.tIdle := T#0s` is now sixty seconds, the library's default (0.1
passed 0 through, which never closed an idle connection). A server now needs
at least one `Map`: `MODBUS_IDENTITY` alone no longer opens one. The nameplate
still answers function code 43 once a `Map` is there.

### MODBUS_READ, MODBUS_WRITE -> the request methods

| 0.1.x | 0.2.0 |
| --- | --- |
| `REQ` | `bExecute` |
| `UNIT` | `nUnitId` |
| `FC` | the method's name |
| `ADDRESS` | `nAddress` |
| `LENGTH` | `nQuantity` |
| `ORDER` | `eOrder` (the register reads and `WriteMultipleRegisters`) |
| `VALUE` | `anyData`; `bValue` on `WriteSingleCoil`, `nValue : WORD` on `WriteSingleRegister` |
| `AND_MASK`, `OR_MASK` | `MaskWriteRegister`'s `nAndMask`, `nOrMask` |
| `BUSY`, `DONE`, `ERROR`, `STATUS` | the result: `Queued`, `Ok`, the failure |
| `COUNT` | gone: it is `nQuantity`, or the variable's count |

### MODBUS_WATCH -> node.Watch

| 0.1.x | 0.2.0 |
| --- | --- |
| `UNIT`, `ADDRESS`, `LENGTH`, `ORDER`, `DEADBAND`, `ENABLE`, `VALUE` | `nUnitId`, `nAddress`, `nQuantity`, `eOrder`, `nDeadband`, `bEnable`, `anyData` |
| `FC : MODBUS_READ_FC` | `eTable : E_ModbusTable` (the four reads are the four tables) |
| `EVERY` | `tPeriod` |
| `QUALITY`, `SEEN`, `AGE`, `FAILURES` | `eQuality`, `bSeen`, `tAge`, `nFailures` |
| `WATCHING`, `COUNT` | gone: `bEnable`, and the variable's count |
| `ERROR`, `STATUS` | the result: the last read's |

### MODBUS_POINT -> node.Point

| 0.1.x | 0.2.0 |
| --- | --- |
| `VALUE`, `Q`, `WRITE_VALUE` | `anyValue`: the variable is the point. A read point writes the value into it once the device has answered (it is not touched before); a write point sends it |
| `UNIT`, `FC`, `ADDRESS`, `DTYPE`, `ORDER`, `BIT` | `nUnitId`, `eFunction : E_ModbusPointFunction`, `nAddress`, `eType : E_ModbusPointType`, `eOrder`, `nBit` |
| `SCALE`, `OFFSET`, `EVERY`, `STALE`, `TIMEOUT`, `ENABLE` | `fScale`, `fOffset`, `tPeriod`, `tStale`, `tTimeout`, `bEnable` |
| `OK`, `QUALITY`, `AGE`, `FAILURES` | `bOk`, `eQuality`, `tAge`, `nFailures` |

### MODBUS_POINTS -> node.Points

| 0.1.x | 0.2.0 |
| --- | --- |
| `SETTINGS : ARRAY OF MODBUS_PT_CFG` | `anySettings`: an `ARRAY OF ST_ModbusPointConfig` |
| `POINTS : ARRAY OF MODBUS_PT_STS` | `anyPoints`: an `ARRAY OF ST_ModbusPointStatus` |
| `RUN` | `bEnable` |
| `GOOD_COUNT`, `LOST_COUNT`, `STATUS_TEXT` | `nGoodCnt`, `nLostCnt`, `sStatusText` |
| `FIRST_LOST` (the array index) | `nFirstLost`: the row counted from 1, 0 when none |
| `MODBUS_PT_CFG` members `unit`, `fc`, `address`, `dtype`, `order`, `bit`, `scale`, `offset`, `every`, `stale`, `timeout`, `enable` | `nUnitId`, `eFunction`, `nAddress`, `eType`, `eOrder`, `nBit`, `fScale`, `fOffset`, `tPeriod`, `tStale`, `tTimeout`, `bEnable` |
| `MODBUS_PT_STS` members `w`, `v`, `q`, `ok`, `quality`, `age`, `failures`, `result` | `fWriteValue`, `fValue`, `bValue`, `bOk`, `eQuality`, `tAge`, `nFailures`, `eResult` |

A retained `ARRAY OF MODBUS_PT_CFG` does not carry over to the new type: set
the site's points again after the move.

### MODBUS_DEVICE -> node.Device and node.ReadDeviceIdentification

| 0.1.x | 0.2.0 |
| --- | --- |
| `UNIT`, `POLL`, `GONE` | `nUnitId`, `tPoll`, `tGone` |
| `ANSWERING`, `SEEN`, `SILENT`, `ROUND_TRIP` | `bAnswering`, `bSeen`, `tSilent`, `tRoundTrip` |
| `IDENTIFY`, `IDENTIFIED`, `VENDOR`, `PRODUCT`, `REVISION` | `ReadDeviceIdentification(nUnitId, bExecute, sVendor =>, sProduct =>, sRevision =>)`; `IDENTIFIED` is its result `Ok` |

### MODBUS_MAP -> node.Map

| 0.1.x | 0.2.0 |
| --- | --- |
| `TABLE : MODBUS_TABLE`, `ADDRESS`, `VALUE` | `eTable : E_ModbusTable`, `nAddress`, `anyData` |
| `ON_LOSS : MODBUS_FAILSAFE`, `SAFE_VALUE` | `eOnLoss : E_ModbusFailsafe`, `nSafeValue` |
| `WRITTEN`, `SAFE_APPLIED` | `bWritten`, `bSafeApplied` |
| `BOUND`, `ERROR`, `STATUS` | the result: `Ok` while bound |
| `COUNT` | gone: the variable's count |

### MODBUS_STATUS -> node.Statistics

| 0.1.x | 0.2.0 |
| --- | --- |
| `PENDING`, `SENT`, `RECEIVED` | `nPending`, `nSent`, `nReceived` |
| `CHECKSUM_ERRORS`, `FRAMING_ERRORS`, `NOISE_BYTES`, `RECONNECTS` | `nChecksumErrors`, `nFramingErrors`, `nNoiseBytes`, `nReconnects` |
| `FRAMING_REASON` | `sFramingReason` |
| `CONNECTED`, `CLIENTS` | the node's `bConnected`, `nClients` |
| the node's `RESET_STATS` | `bReset` |

### MODBUS_BRIDGE -> FB_ModbusBridge

| 0.1.x | 0.2.0 |
| --- | --- |
| `SERIAL_DEVICE`, `SERIAL_BAUD`, `SERIAL_PARITY` | `stSerialConfig.sDevice`, `nBaudRate`, `eParity` |
| `PORT`, `RX_PIN`, `TX_PIN`, `DE_PIN`, `DE_HOLD` | `stSerialConfig.nUart`, `nRxPin`, `nTxPin`, `nDePin`, `tDeHold` |
| `TCP_PORT` | `nPort` |
| `FIRST_UNIT`, `LAST_UNIT` | `nFirstUnitId`, `nLastUnitId` |
| `MAX_CLIENTS`, `MAX_PENDING`, `PASS_OTHERS`, `CONNECT` | `nMaxClients`, `nMaxPending`, `bPassOthers`, `bConnect` |
| `READY`, `CLIENTS`, `FORWARDED`, `NO_PATH`, `NO_DEVICE` | `bLinkUp`, `nClients`, `nForwarded`, `nNoPath`, `nNoDevice` |
| `FRAMING_REASON`, `ERROR`, `STATUS`, `LAST_ERROR` | `sFramingReason`, `bError`, `eErrorId`, `sLastError` |

## Types

| 0.1.x | 0.2.0 |
| --- | --- |
| `MODBUS_RESULT` (`MODBUS_OK`, `MODBUS_TIMEOUT`, ..., `MODBUS_WRONG_TASK`) | `E_ModbusResult` (`Ok`, `Timeout`, ..., `WrongTask`), same order |
| `MODBUS_TRANSPORT` (`MODBUS_RUNTIME_SERIAL`, ...) | `E_ModbusTransport` (`RuntimeSerial`, `RuntimeTcp`, `ArduinoSerial`, `ArduinoWiFi`, `ArduinoEthernet`) |
| `MODBUS_ROLE` | `E_ModbusRole` (`Client`, `Server`, `Both`) |
| `MODBUS_PARITY` | `E_ModbusParity` (`Even`, `Odd`, `None`, `None8N1`) |
| `MODBUS_FRAMING` | `E_ModbusFraming` (`Auto`, `Rtu`, `Ascii`, `Tcp`) |
| `MODBUS_ORDER` | `E_ModbusOrder` (`ABCD`, `CDAB`, `BADC`, `DCBA`) |
| `MODBUS_QUALITY` | `E_ModbusQuality` (`Unknown`, `Good`, `Uncertain`, `Bad`) |
| `MODBUS_TABLE`, `MODBUS_READ_FC` | `E_ModbusTable` (`Coil`, `DiscreteInput`, `HoldingRegister`, `InputRegister`) |
| `MODBUS_WRITE_FC` | gone: the write methods |
| `MODBUS_FAILSAFE` | `E_ModbusFailsafe` (`HoldLastValue`, `ResetToValue`) |
| `MODBUS_PT_FC` | `E_ModbusPointFunction` (`ReadCoils`, `ReadDiscreteInputs`, `ReadHoldingRegisters`, `ReadInputRegisters`, `WriteSingleCoil`, `WriteSingleRegister`, `WriteMultipleRegisters`) |
| `MODBUS_PT_TYPE` | `E_ModbusPointType` (`Bit`, `Int16`, `UInt16`, `Int32`, `UInt32`, `Float32`, `RegisterBit`) |
| `MODBUS_PT_CFG`, `MODBUS_PT_STS` | `ST_ModbusPointConfig`, `ST_ModbusPointStatus` |
| (new) | `ST_ModbusSerialConfig`, `ST_ModbusTimingConfig`, `ST_ModbusIdentityConfig`, `ST_ModbusNetworkConfig` |

**Back to** [README](README.md)
