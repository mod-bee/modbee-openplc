# Migrating from 0.1

modbee-beebus 0.2.0 replaces the 16 blocks of 0.1.x with one, `FB_BeeBusNode`.
A segment is one node; everything per topic, `STRUCT`, address or request is a
method of it; the configuration and status blocks are option structures and
methods. Names follow Beckhoff's TwinCAT 3 conventions: `FB_` blocks, `ST_`
structures, `E_` enumerations used qualified, pins and parameters with a type
prefix (`nNodeId`, `bConnect`, `stSerialConfig`).

**You do not have to move.** A project built on 0.1.x stays on 0.1.x and runs
unchanged: pin it (`openplc-cli library pin <project> modbee-beebus@0.1.1`) and
build it with the editor it was written with - ModBee OpenPLC Editor
4.3.4-modbee.2 or earlier, with library collection v0.2.1 or earlier. From
editor 4.3.4-modbee.3 the compiler builds libraries differently and refuses a
0.1.x library, so moving that project to a newer editor means moving it to
0.2. Move when you choose. **The wire does not change**: the same topics, ids, names, registers
and frames for the same variables, so a 0.1 node and a 0.2 node share a ring,
and an HMI's firmware needs nothing.

## The shape of a 0.2.0 program

```st
VAR
  node : FB_BeeBusNode;
END_VAR

node(nNodeId := 1, eTransport := E_BeeBusTransport.RuntimeUdp, bFailsafe := TRUE);
node.PublishStruct(anyData := STS, nTopicId := 100);
node.ModbusMap(anyData := CFG, nAddress := 0, bWritten => bCfgWritten,
               sWrittenName => sCfgWrittenName);
node.Serve(anyData := SET, nTopicId := 300, bWritable := TRUE);
eRead := node.ModbusRead(anyData := iRemote, nPeer := 2, nAddress := 40, bExecute := bRead);
```

was, in 0.1.x:

```
node  ( NODE_ID := 1, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP, FAILSAFE := TRUE );
sts   ( NODE := node, VALUE := STS, TOPIC_ID := 100 );
cfgMap( NODE := node, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 0, VALUE := CFG );
set   ( NODE := node, VALUE := SET, TOPIC_ID := 300, WRITABLE := TRUE );
rd    ( REQ := bRead, NODE := node, PEER := 2, TABLE := BEEBUS_MB_HOLDING_REG,
        ADDRESS := 40, VALUE := iRemote );
```

- **A method call has no instance.** Drop the 0.1.x instance (`sts`, `cfgMap`,
  `rd`) and call the method on the node. A call is found again each scan by
  **the variable it is about** - its declared name and type - so one variable is
  one record per method. Two 0.1.x instances on the same variable (a
  `BEEBUS_TP_TOPIC` and a `BEEBUS_TP_PUBLISH` of it) are two methods and still
  work; two instances of one block on one variable need two variables now. So
  does an array of 0.1.x instances called in a `FOR` loop on one variable:
  give each call its own variable, with a constant index.
- **The `NODE` pin is gone**: the method's instance is the node.
- **Each method returns an `E_BeeBusResult`.** The `ERROR` / `STATUS` pair of
  every 0.1.x block is that result; `BOUND` is `Ok`.
- **Requests** (`Publish`, `Write`, `ModbusRead`, `ModbusWrite`) take
  `bExecute` for `REQ`. `BUSY` is the result `Queued`; the one-scan `DONE` and
  `ERROR` are the result, `Ok` or the reason, **held until the next edge**. A
  sequence that waited for `DONE` waits for the result to leave `Queued` after
  the edge (see [04 - Registers](04-registers.md#reading-a-peer---nodemodbusread)).
- **Outputs are read with `=>`**: `node.Subscribe(..., eQuality => q)`. A
  one-scan output (`WRITTEN`, `NEW_VALUE`, `CHANGED`, `SAFE_APPLIED`) now means
  "since the last call", which is the same thing when the method is called
  every scan.
- **`LAST_ERROR` of each block** is the node's `sLastError`, naming the method
  and the variable: *"PublishStruct STS: name too long (256 > 255): ..."*.
- **Enumerations are qualified**: `E_BeeBusResult.Ok`, not `BEEBUS_OK`. Each
  type is `{attribute 'qualified_only'}`, so a bare `Ok` does not compile.
- **What a record is is taken once.** 0.1 took `TOPIC_ID`, `PREFIX`, `TABLE`,
  `ADDRESS` on the first scan and ignored later changes silently; 0.2 does the
  same and says so: a later call that changes them returns `InvalidArgument`.

## Blocks

| 0.1.x | 0.2.0 |
| --- | --- |
| `BEEBUS_NODE` | `FB_BeeBusNode` |
| `BEEBUS_ARDUINO` | `FB_BeeBusNode.stSerialConfig : ST_BeeBusSerialConfig` and `.stNetworkConfig : ST_BeeBusNetworkConfig` |
| `BEEBUS_NODE_STATUS` | `node.Statistics`; `CONNECTED` is the node's `bConnected`, `DEBUG_ENABLE` its `bDebug` |
| `BEEBUS_NODE_PEER_STATUS` | `node.PeerStatus(nPeer := ...)` |
| `BEEBUS_TP_TOPIC` | `node.Topic` |
| `BEEBUS_TP_PUBLISH` | `node.Publish` |
| `BEEBUS_TP_SUBSCRIBE` | `node.Subscribe` |
| `BEEBUS_TP_STRUCT` | `node.PublishStruct` |
| `BEEBUS_TP_STRUCT_SUBSCRIBE` | `node.SubscribeStruct` |
| `BEEBUS_TP_SERVE` | `node.Serve` |
| `BEEBUS_TP_BIND` | `node.Bind` |
| `BEEBUS_TP_WRITE` | `node.Write` |
| `BEEBUS_TP_BUFFER` | `node.Buffer` |
| `BEEBUS_MB_MAP` | `node.ModbusMap` |
| `BEEBUS_MB_READ` | `node.ModbusRead` |
| `BEEBUS_MB_WRITE` | `node.ModbusWrite` |

## Enumerations and structures

| 0.1.x | 0.2.0 | values |
| --- | --- | --- |
| `BEEBUS_RESULT` | `E_BeeBusResult` | `BEEBUS_QUEUED` `Queued`, `BEEBUS_OK` `Ok`, `BEEBUS_NOT_INITIALISED` `NotInitialised`, `BEEBUS_INVALID_ARGUMENT` `InvalidArgument`, `BEEBUS_UNKNOWN_NODE` `UnknownNode`, `BEEBUS_DUPLICATE_NODE_ID` `DuplicateNodeId`, `BEEBUS_NOT_MAPPED` `NotMapped`, `BEEBUS_DUPLICATE` `Duplicate`, `BEEBUS_QUEUE_FULL` `QueueFull`, `BEEBUS_TIMEOUT` `Timeout`, `BEEBUS_NODE_LOST` `NodeLost`, `BEEBUS_SUPERSEDED` `Superseded`, `BEEBUS_CANCELLED` `Cancelled`, `BEEBUS_REFUSED` `Refused`, `BEEBUS_TYPE_MISMATCH` `TypeMismatch`, `BEEBUS_NOT_SUBSCRIBED` `NotSubscribed`, `BEEBUS_BUFFER_FULL` `BufferFull`, `BEEBUS_WRONG_TASK` `WrongTask` - same order |
| `BEEBUS_NODE_LINK` | `E_BeeBusTransport` | `BEEBUS_NODE_RUNTIME_UDP` `RuntimeUdp`, `BEEBUS_NODE_RUNTIME_SERIAL` `RuntimeSerial`, `BEEBUS_NODE_ARDUINO_SERIAL` `ArduinoSerial`, `BEEBUS_NODE_ARDUINO_WIFI` `ArduinoWiFi`, `BEEBUS_NODE_ARDUINO_ETHERNET` `ArduinoEthernet` |
| `BEEBUS_MB_TABLE` | `E_BeeBusModbusTable` | `BEEBUS_MB_COIL` `Coil`, `BEEBUS_MB_HOLDING_REG` `HoldingRegister`, `BEEBUS_MB_DISCRETE_INPUT` `DiscreteInput`, `BEEBUS_MB_INPUT_REG` `InputRegister` |
| `BEEBUS_MB_FAILSAFE` | `E_BeeBusModbusFailsafe` | `BEEBUS_MB_HOLD_LAST_VALUE` `HoldLastValue`, `BEEBUS_MB_RESET_TO_VALUE` `ResetToValue` |
| `BEEBUS_TP_QUALITY` | `E_BeeBusQuality` | `BEEBUS_TP_UNKNOWN` `Unknown`, `BEEBUS_TP_GOOD` `Good`, `BEEBUS_TP_UNCERTAIN` `Uncertain`, `BEEBUS_TP_BAD` `Bad` |
| `BEEBUS_TP_BIND_STATE` | `E_BeeBusBindState` | `BEEBUS_BIND_OFFLINE` `Offline`, `BEEBUS_BIND_SYNCING` `Syncing`, `BEEBUS_BIND_IN_SYNC` `InSync`, `BEEBUS_BIND_PENDING` `Pending`, `BEEBUS_BIND_REFUSED` `Refused`, `BEEBUS_BIND_FAILED` `Failed` |
| `BEEBUS_TP_OUTCOME` | `E_BeeBusOutcome` | `BEEBUS_TP_ACCEPTED` `Accepted`, `BEEBUS_TP_CHANGED` `Changed`, `BEEBUS_TP_REFUSED` `Refused`, `BEEBUS_TP_READ_ONLY` `ReadOnly`, `BEEBUS_TP_NO_TOPIC` `NoTopic`, `BEEBUS_TP_WRONG_TYPE` `WrongType`, `BEEBUS_TP_BUSY` `Busy`, `BEEBUS_TP_NO_ANSWER` `NoAnswer` |
| `BEEBUS_TP_SEND` | `E_BeeBusPublishMode` | `BEEBUS_TP_PUBLISH_ALL` `All`, `BEEBUS_TP_PUBLISH_TO` `ToPeer` |
| (new) | `ST_BeeBusSerialConfig` | `sDevice`, `nBaud`, `nPort`, `nRxPin`, `nTxPin` |
| (new) | `ST_BeeBusNetworkConfig` | `sGroupAddr`, `nUdpPort`, `nTtl`, `sInterfaceAddr`, `sSsid`, `sWiFiPassword`, `sMac`, `sIp` |

## Pins and parameters

### BEEBUS_NODE, BEEBUS_ARDUINO, the status blocks

| 0.1.x | 0.2.0 |
| --- | --- |
| `NODE_ID`, `TRANSPORT`, `FAILSAFE`, `CONNECT`, `QUEUE` | `nNodeId`, `eTransport`, `bFailsafe`, `bConnect`, `nMaxPending` |
| `DEVICE`, `BAUD` | `stSerialConfig.sDevice`, `.nBaud` |
| `GROUP`, `UDP_PORT`, `TTL`, `IFACE` | `stNetworkConfig.sGroupAddr`, `.nUdpPort`, `.nTtl`, `.sInterfaceAddr` |
| `BEEBUS_ARDUINO`: `PORT`, `RX_PIN`, `TX_PIN` | `stSerialConfig.nPort`, `.nRxPin`, `.nTxPin` |
| `BEEBUS_ARDUINO`: `WIFI_SSID`, `PASSWORD`, `MAC`, `IP` | `stNetworkConfig.sSsid`, `.sWiFiPassword`, `.sMac`, `.sIp` |
| `READY`, `LINK`, `CONNECTED`, `ERROR`, `STATUS`, `LAST_ERROR`, `ATTEMPTS`, `RETRY_IN` | `bReady`, `bLinkUp`, `bConnected`, `bError`, `eErrorId`, `sLastError`, `nAttempts`, `tRetryIn` |
| `BEEBUS_ARDUINO`: `APPLIED`, `ERROR`, `STATUS` | gone: a member for the other target is reported on the node's `bError`, `eErrorId`, `sLastError` |
| `BEEBUS_NODE_STATUS`: `DEBUG_ENABLE` | the node's `bDebug`, which may now change while running |
| `BEEBUS_NODE_STATUS`: `NODE_ID`, `MEMBERS`, `ROTATION`, `PENDING_OPS`, `CRC_ERRORS`, `NOISE_BYTES` | `node.Statistics`: `nIdInUse`, `nMembers`, `tRotation`, `nPendingOps`, `nCrcErrors`, `nNoiseBytes` |
| `BEEBUS_NODE_PEER_STATUS`: `PEER`; `ALIVE`, `SEEN`, `SILENT`, `HOP`, `HOP_TIMEOUT` | `node.PeerStatus`: `nPeer`; `bAlive`, `bSeen`, `tSilent`, `tHop`, `tHopTimeout` |

`bLinkUp` is `bReady` on the Runtime and on serial (0.1's `LINK` was `FALSE`
there).

### Topics

| 0.1.x | 0.2.0 |
| --- | --- |
| `TP_TOPIC`: `NAME`, `TOPIC_ID`, `VALUE`; `BOUND` | `Topic`: `sName`, `nTopicId`, `anyValue`; result `Ok` |
| `TP_PUBLISH`: `REQ`, `NAME`, `TOPIC_ID`, `MODE`, `PEER`, `CONFIRMED`, `VALUE`; `BUSY`, `DONE` | `Publish`: `bExecute`, `sName`, `nTopicId`, `ePublishMode`, `nPeer`, `bConfirmed`, `anyValue`; result `Queued`, `Ok` |
| `TP_SUBSCRIBE`: `PEER`, `NAME`, `TOPIC_ID`, `DEADBAND`, `PERIOD`, `RELIABLE`, `VALUE` | `Subscribe`: `nPeer`, `sName`, `nTopicId`, `fDeadband`, `tPeriod`, `bReliable`, `anyValue` |
| `TP_SUBSCRIBE`: `QUALITY`, `SEEN`, `AGE`, `NEW_VALUE`, `MISSED` | `eQuality`, `bSeen`, `tAge`, `bNewValue`, `nMissed` |
| `TP_STRUCT`: `VALUE`, `TOPIC_ID`, `PREFIX`, `WRITABLE`, `PULSE`, `SETTLE` | `PublishStruct`: `anyData`, `nTopicId`, `sPrefix`, `bWritable`, `tPulse`, `tSettle` |
| `TP_STRUCT`: `COUNT`, `WRITTEN`, `WRITTEN_COUNT`, `WRITTEN_NAME`, `WRITTEN_INDEX`, `WRITTEN_BY`, `LOST` | `nMembers`, `bWritten`, `nWritten`, `sWrittenName`, `nWrittenIndex`, `nWrittenBy`, `nLost` |
| `TP_STRUCT_SUBSCRIBE`: `VALUE`, `PEER`, `TOPIC_ID`, `PREFIX`, `DEADBAND`, `PERIOD`, `RELIABLE` | `SubscribeStruct`: `anyData`, `nPeer`, `nTopicId`, `sPrefix`, `fDeadband`, `tPeriod`, `bReliable` |
| `TP_STRUCT_SUBSCRIBE`: `COUNT`, `QUALITY`, `SEEN`, `AGE`, `NEW_VALUE`, `NEW_COUNT`, `NEW_NAME`, `NEW_INDEX`, `MISSED` | `nMembers`, `eQuality`, `bSeen`, `tOldest`, (`nNewValues` > 0), `nNewValues`, `sNewName`, `nNewIndex`, `nMissed` |
| `TP_SERVE`: `VALUE`, `TOPIC_ID`, `PREFIX`, `WRITABLE`, `COMMAND`, `PULSE`, `SETTLE`, `DEPTH` | `Serve`: `anyData`, `nTopicId`, `sPrefix`, `bWritable`, `bCommand`, `tPulse`, `tSettle`, `nDepth` |
| `TP_SERVE`: `COUNT`, `CHANGED`, `CHANGED_COUNT`, `CHANGED_NAME`, `CHANGED_INDEX`, `CHANGED_BY`, `REFUSED_COUNT`, `LOST` | `nMembers`, `bChanged`, `nChanged`, `sChangedName`, `nChangedIndex`, `nChangedBy`, `nRefused`, `nLost` |
| `TP_BIND`: `VALUE`, `PEER`, `TOPIC_ID`, `PREFIX`, `RELIABLE`, `DEADBAND` | `Bind`: `anyData`, `nPeer`, `nTopicId`, `sPrefix`, `bReliable`, `fDeadband` |
| `TP_BIND`: `COUNT`, `STATE`, `IN_SYNC`, `PENDING`, `REFUSED`, `REFUSED_NAME`, `REFUSED_INDEX`, `FAILED`, `AGE`, `NEW_VALUE` | `nMembers`, `eBindState`, `bInSync`, `bPending`, `bRefused`, `sRefusedName`, `nRefusedIndex`, `bFailed`, `tOldest`, `bNewValue` |
| `TP_WRITE`: `REQ`, `PEER`, `TOPIC_ID`, `CONFIRMED`, `WANT_RESULT`, `VALUE` | `Write`: `bExecute`, `nPeer`, `nTopicId`, `bConfirmed`, `bWantResult`, `anyValue` |
| `TP_WRITE`: `BUSY`, `DONE`, `RESULT`, `ACCEPTED`, `REFUSED`, `KEPT_VALUE` | result `Queued`, `Ok`; `eOutcome`, `bAccepted`, `bRefused`, `fKeptValue` |
| `TP_BUFFER`: `NAME`, `DEPTH`; `HELD` | `Buffer`: `sName`, `nDepth`; `nHeld` |

### Registers

| 0.1.x | 0.2.0 |
| --- | --- |
| `MB_MAP`: `TABLE`, `ADDRESS`, `ON_LOSS`, `SAFE_VALUE`, `VALUE` | `ModbusMap`: `eTable`, `nAddress`, `eOnLoss`, `nSafeValue`, `anyData` |
| `MB_MAP`: `COUNT`, `WRITTEN`, `WRITTEN_NAME`, `WRITTEN_INDEX`, `WRITTEN_ADDRESS`, `WRITTEN_COUNT`, `SAFE_APPLIED` | `nCount`, `bWritten`, `sWrittenName`, `nWrittenIndex`, `nWrittenAddr`, `nWritten`, `bSafeApplied` |
| `MB_READ`: `REQ`, `PEER`, `TABLE`, `ADDRESS`, `LENGTH`, `VALUE` | `ModbusRead`: `bExecute`, `nPeer`, `eTable`, `nAddress`, `nLength`, `anyData` |
| `MB_WRITE`: `REQ`, `PEER`, `TABLE`, `ADDRESS`, `CONFIRMED`, `LENGTH`, `VALUE` | `ModbusWrite`: `bExecute`, `nPeer`, `eTable`, `nAddress`, `bConfirmed`, `nLength`, `anyData` |
| `BUSY`, `DONE`, `ERROR`, `STATUS` of a read or a write | the result: `Queued`, then `Ok` or the reason, held until the next edge |

## What else changed

- **`DEBUG_ENABLE` worked only if the node existed at start-up**, which it never
  did (the link opens on the second scan), so it printed nothing. `bDebug`
  takes effect whenever it changes.
- **`BEEBUS_TP_BUFFER` set its depth only at start-up**, before the node had
  opened, so it never buffered anything. `Buffer` sets the depth once the topic
  is there, and again when `nDepth` changes.
- **An array on `BEEBUS_TP_TOPIC`, `TP_PUBLISH`, `TP_SUBSCRIBE` or `TP_WRITE`
  bound its first element alone.** `Topic`, `Publish`, `Subscribe` and `Write`
  refuse an array with `InvalidArgument`: an array is `PublishStruct`'s.
- **A refused 0.1 block was final until the PLC restarted.** A 0.2 record is
  tried again as soon as what it is (its topic id, prefix, table, address)
  changes.
- **Topic ids, names, register layout, wire types: unchanged.**
