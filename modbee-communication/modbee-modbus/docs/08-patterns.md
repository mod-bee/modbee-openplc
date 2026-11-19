# 08 - Patterns

Worked examples, and the habits worth keeping.

## The two-task split

Every project should look like this, and it is the one piece of structure that
matters:

| task | interval | priority | holds |
| --- | --- | --- | --- |
| `APP_TASK` | `T#20ms` | `0` | the machine - no Modbus at all |
| `NET_TASK` | `T#1ms` on the Runtime, `T#50ms` on a board to start | `20` | `FB_ModbusNode`, its method calls, `FB_ModbusBridge` |

Values cross between them through globals, each written by one task.

```
PROGRAM net
VAR
    node   : FB_ModbusNode;
    serial : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200, nServerUnitId := 7);
END_VAR

node(eTransport := E_ModbusTransport.RuntimeSerial, eRole := E_ModbusRole.Both,
     stSerialConfig := serial);
(* every method call on node goes here, below it *)

END_PROGRAM
```

Declare the node in the network task's program, never in a global list: a
method called from another task returns `WrongTask` and does nothing. The node
is the only block that touches the wire, so its period is the floor on how
fast anything happens. [10 - Scan rate](10-scan-rate.md) has the numbers.

## Call the node before its methods

Within a scan, a method called above the node acts on the previous scan's
state. It corrects itself and costs one scan - it is not fatal - but there is
no reason to have it happen.

## Keep the bus quiet for what matters

**This is the habit that separates a Modbus system that works from one that
nearly works.**

A Modbus segment carries one conversation at a time. Every read you issue is
time that a control word cannot have. So:

**Read on demand what is only needed on demand.** A nameplate, a serial number,
a configuration block, a recipe - read it once with a request on a rising edge
and keep it. It does not change.

**Watch only what genuinely has to stay fresh**, and at the rate the process
actually needs:

```
(* a tank level: seconds is plenty *)
node.Watch(anyData := nTankLevel, nUnitId := 1, eTable := E_ModbusTable.InputRegister,
           nStartAddress := 30, tReadInterval := T#2s, eQuality => eTankQ);

(* a torque feedback in a closed loop: as fast as the bus will bear *)
node.Watch(anyData := nMotorTorque, nUnitId := 2, eTable := E_ModbusTable.InputRegister,
           nStartAddress := 10, tReadInterval := T#100ms, eQuality => eTorqueQ);
```

**Stop watching what you are not using.** `bEnable` stops and starts a watch in
place, with no second record and no cost while it is off:

```
(* the dryer's sensors matter only while the dryer runs *)
node.Watch(anyData := aDryerTemps, nUnitId := 5, eTable := E_ModbusTable.InputRegister,
           nStartAddress := 0, tReadInterval := T#500ms, bEnable := bDryerRunning);
```

**Write only when the value changed.** A write is a request, so it goes on an
edge - make the edge the change:

```
bSendSpeed := nNewSpeed <> nLastSpeed;
eSpeed := node.WriteSingleRegister(nValue := nNewSpeed, nUnitId := 2, nAddress := 40,
                                   bExecute := bSendSpeed);
IF bSendSpeed THEN nLastSpeed := nNewSpeed; END_IF;
```

Or, for a setpoint a device should be told again every so often - a remote
relay with a watchdog - a write `Point`, which sends on change and every
`tReadInterval` ([11 - Points from settings](11-points-from-settings.md)).

**Read a range, not an address at a time.** One request for a hundred registers
is one frame. A hundred requests is a hundred frames and a hundred turnarounds:
at 19200 baud that is 126 ms against 1.3 seconds, for exactly the same data.

**It is safe to call a request in the loop.** Nothing floods: a held
`bExecute` reads once on the edge, a duplicate is refused, a superseded write
is replaced. The advice above is about the bus, not about safety.

## A device that must be there

```
VAR
    aFeedback     : ARRAY [0..1] OF WORD;
    eFeedbackQ    : E_ModbusQuality;
    bDriveSeen    : BOOL;
    bDriveAnswers : BOOL;
    bDriveMissing : BOOL;
    bDriveLost    : BOOL;
END_VAR

node.Watch(anyData := aFeedback, nUnitId := 2, eTable := E_ModbusTable.InputRegister,
           nStartAddress := 10, tReadInterval := T#200ms, eQuality => eFeedbackQ);
node.Device(nUnitId := 2, bEverAnswered => bDriveSeen, bAnswering => bDriveAnswers);

(* Two different faults, two different alarms, two different engineers *)
bDriveMissing := NOT bDriveSeen;                      (* never answered: commissioning *)
bDriveLost    := bDriveSeen AND NOT bDriveAnswers;    (* was, is not: running *)

(* Act on the value only while it is worth acting on *)
IF eFeedbackQ = E_ModbusQuality.Good THEN
    nActualSpeed := aFeedback[0];
ELSE
    bDriveTrip := TRUE;
END_IF;
```

## Reading a float from a device

```
VAR
    fFlowRate : REAL;
    eFlowQ    : E_ModbusQuality;
END_VAR

node.Watch(anyData := fFlowRate, nUnitId := 3, eTable := E_ModbusTable.InputRegister,
           nStartAddress := 30, tReadInterval := T#1s, eWordOrder := E_ModbusOrder.CDAB,
           eQuality => eFlowQ);
```

If it reads `4.6e-41` instead of `1234.5`, the address is right and `eWordOrder` is
wrong. Try `CDAB` first if you were on `ABCD`, and the other way round. See
[05 - Reading and writing](05-reading-and-writing.md).

## A PLC that is also a device

```
PROGRAM net
VAR
    node       : FB_ModbusNode;
    serial     : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200, nServerUnitId := 7);
    timing     : ST_ModbusTimingConfig := (tWriterLossAfter := T#5s);
    ident      : ST_ModbusIdentityConfig := (sVendorName := 'Example Co', sProductCode := 'Pump House');
    aReadings  : ARRAY [0..15] OF WORD;
    aSetpoints : ARRAY [0..3] OF WORD;
    bWrittenByClient  : BOOL;
END_VAR

node(eTransport := E_ModbusTransport.RuntimeSerial, eRole := E_ModbusRole.Both,
     stSerialConfig := serial, stTimingConfig := timing, stIdentityConfig := ident);

(* Read-only to anyone outside: the table has no write function code *)
node.Map(anyData := aReadings, eTable := E_ModbusTable.InputRegister, nStartAddress := 0);

(* Writable, and therefore validated *)
node.Map(anyData := aSetpoints, eTable := E_ModbusTable.HoldingRegister, nStartAddress := 100,
         bWrittenByClient => bWrittenByClient);
IF bWrittenByClient THEN
    IF aSetpoints[0] > 1500 THEN aSetpoints[0] := 1500; END_IF;
    bAcceptSetpoint := TRUE;
END_IF;
END_PROGRAM
```

The machine's program writes `aReadings` and reads `aSetpoints` through
globals, if it runs in another task.

## A terminal server

A serial-to-Ethernet converter with three RS-485 ports is three nodes, one per
TCP port:

```
VAR
    segmentA, segmentB : FB_ModbusNode;
    rtuOverTcp         : ST_ModbusTimingConfig := (eFraming := E_ModbusFraming.Rtu);
END_VAR

segmentA(eTransport := E_ModbusTransport.RuntimeTcp, sHostName := '192.168.1.50',
         nTcpPort := 4001, stTimingConfig := rtuOverTcp);
segmentB(eTransport := E_ModbusTransport.RuntimeTcp, sHostName := '192.168.1.50',
         nTcpPort := 4002, stTimingConfig := rtuOverTcp);
```

Both in the fast task. Two nodes are two independent buses, which is exactly
what they are physically.

## A gateway

Several SCADA clients sharing one RS-485 segment:

```
PROGRAM gateway
VAR
    bridge  : FB_ModbusBridge;
    segment : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200);
END_VAR

bridge(stSerialConfig := segment, nTcpPort := 502, nFirstUnitId := 1, nLastUnitId := 32);

(* Two alarms, because they send you to different places *)
bGatewayFault := bridge.nGatewayPathUnavailableCount > 0;      (* our routing is wrong *)
bFieldFault   := bridge.nGatewayTargetFailedCount > 0;    (* a device is not answering *)
END_PROGRAM
```

## Habits worth keeping

**Interlock on `eQuality` or `bGood`, never on a value alone.** A stale register
looks exactly like a steady process.

**Give `Unknown` and `Bad` separate alarms.** One is a commissioning fault, the
other is a running fault.

**Read `sLastError` before anything else when a node will not start.** It
carries the operating system's own words.

**Give each request its own variable.** A call is found again by its
variable's name; two calls sharing one are one request.

**Put anything a client must not change in a read-only table.** It is not a
permission somebody can alter later.

**Validate what a client writes.** The register is your variable, so the check
belongs in your program.

**Test the failsafe by pulling the cable**, on commissioning, and watch
`bSafeValueApplied`. A failsafe nobody has seen fire is a failsafe nobody knows
works.

**Use `WORD` for registers, not `INT`.** `WORD` is what you can mask, shift and
take a bit of.

**Next:** [09 - Troubleshooting](09-troubleshooting.md)
