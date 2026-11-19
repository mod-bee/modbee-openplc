# 08 - Patterns

Worked examples, and the habits that make a program readable a year later.

## Habits worth keeping

**One call per thing, one variable per call.** Each call is found again by its
variable, so sixteen subscriptions are sixteen calls on sixteen variables, and
each line says what it brings in and where the value lands.

```
node.Subscribe(anyValue := rOutsideTemp, nPeerNodeId := 4, sTopic := 'outside_temp', nTopicId := 1, ...);
node.Subscribe(anyValue := rWindSpeed,   nPeerNodeId := 4, sTopic := 'wind_speed',   nTopicId := 2, ...);
node.Subscribe(anyValue := rRainfall,    nPeerNodeId := 4, sTopic := 'rainfall_mm',  nTopicId := 3, ...);
```

**The node first.** Always, at the top, with its methods after it. Once the
ring is more than a few nodes, the node's program goes in its own fast task -
it is the only thing that services the protocol, and how often it runs decides
how fast the ring is. See [10 - Scan rate](10-scan-rate.md).

**Call standing methods unconditionally; act conditionally.** `Topic`,
`Subscribe`, `PublishStruct`, `Serve`, `Bind` and `ModbusMap` are declarations
of what this node shares. Call them every scan with no `IF` around them. Put the
logic on what you do with the values.

**Subscribe once and forget it.** A subscription is a standing intent: it is
held until the peer arrives and re-established if the peer restarts. Do not
write code to watch for the peer and re-subscribe.

**Requests on an edge, never a level.** `bExecute` starts a request on its
rising edge. Raising a new one every scan fills the queue and gets you
`QueueFull`.

**Read a request's result from the scan after its edge.** The result holds
until the next edge, so in the scan you raise `bExecute` it still shows the last
run's outcome.

## Round-robin: many requests, one at a time

Reads and writes go out on a turn of the ring. Raising ten at once fills the
queue; raising one every so often does not. A small step counter is the usual
shape:

```
stepTicks := stepTicks + 1;
bFire := FALSE;
IF stepTicks >= 25 THEN          (* every half second at a 20 ms scan *)
    stepTicks := 0;
    bFire := TRUE;
    iStep := iStep + 1;
    IF iStep > 3 THEN iStep := 0; END_IF;
END_IF;

node.ModbusRead(anyData := aCoils, nPeerNodeId := 20, eTable := E_BeeBusModbusTable.Coil,
                nStartAddress := 0, bExecute := bFire AND iStep = 0);
node.ModbusRead(anyData := aHolding, nPeerNodeId := 20, nStartAddress := 0, bExecute := bFire AND iStep = 1);
node.ModbusRead(anyData := sText, nPeerNodeId := 20, nStartAddress := 100, bExecute := bFire AND iStep = 2);
node.ModbusRead(anyData := aRange, nPeerNodeId := 20, nStartAddress := 200, bExecute := bFire AND iStep = 3);
```

One request per turn, in order, forever. It reads well and it never floods.

## The sleeping sensor

A battery device that wakes, reports and sleeps again. The whole point is **one
turn on the bus per wake**.

```
VAR
    node       : FB_BeeBusNode;
    rSoilTemp  : REAL;
    bAwake     : BOOL;
    cycleTicks : DINT;
END_VAR

(* awake ten seconds in every twenty *)
cycleTicks := cycleTicks + 1;
IF cycleTicks >= 1000 THEN cycleTicks := 0; END_IF;
bAwake := cycleTicks < 500;

node(nNodeId := 88, bConnect := bAwake);

(* hold the readings taken while asleep *)
node.Buffer(sTopic := 'soil_temp', nOfflineBufferDepth := 8);

(* report once the ring has taken us back *)
node.Publish(anyValue := rSoilTemp, sTopic := 'soil_temp', nTopicId := 1,
             bExecute := bAwake AND node.bConnected);
```

Three things make this work:

**`bConnect := bAwake`** leaves the ring properly rather than going silent, so
peers are told instead of timing it out.

**`E_BeeBusPublishMode.All`** (the default) is one frame for every listener. A
SCADA and a controller both subscribed cost the same one turn as either alone.

**Waiting for `bConnected`.** Rejoining takes a few turns, and how many is not
fixed. Publishing the instant `bConnect` goes high publishes into a ring you
have not joined yet.

`Buffer` is optional but usually right here: if the wake window is too short
one cycle, the reading is held and goes out on the next.

## Settings and commands from a panel

The panel binds what the PLC serves; nothing else is written for it on either
side. The full chapter is [11 - Settings both ways](11-bidirectional-binding.md).

On the PLC:

```
node.Serve(anyData := SET, nFirstTopicId := 300, bPeersMayChange := TRUE);
node.Serve(anyData := CMD, nFirstTopicId := 400, bPeersMayChange := TRUE, bMembersAreCommands := TRUE,
           tPulseLength := T#500ms);
```

On the panel:

```
node.Bind(anyData := SET, nPeerNodeId := 1, nFirstTopicId := 300, bDeliverEveryChange := TRUE);
node.Bind(anyData := CMD, nPeerNodeId := 1, nFirstTopicId := 400, bDeliverEveryChange := TRUE);
```

The block that uses a setting decides it, as it always did: one that refuses a
value and puts its own back is reported to the panel as `Changed`, with the
value kept, which the panel member already shows. `bDeliverEveryChange` for settings and
commands; live values stay Live.

## Commanding a device, and knowing it arrived

Run the ownership backwards: **the commander owns the topic, the device
subscribes to it.**

On the commander:

```
eCmd := node.Publish(anyValue := rDemand, sTopic := 'pump_speed_cmd', nTopicId := 20,
                     ePublishMode := E_BeeBusPublishMode.ToPeer, nPeerNodeId := 31,
                     bRequireAcknowledge := TRUE, bExecute := bSendCmd);
IF bSendCmd AND eCmd <> E_BeeBusResult.Queued THEN
    IF eCmd = E_BeeBusResult.Ok THEN udCmdSent := udCmdSent + 1;
    ELSE udCmdFailed := udCmdFailed + 1; eCmdStatus := eCmd;
    END_IF;
    bSendCmd := FALSE;
END_IF;
```

On the pump:

```
node.Subscribe(anyValue := rSpeedSetpoint, nPeerNodeId := 200, sTopic := 'pump_speed_cmd',
               nTopicId := 20, tMaxSendInterval := T#5s, eQuality => eCmdQuality);

(* the setpoint is only as good as the link that delivered it *)
IF eCmdQuality = E_BeeBusQuality.Bad THEN
    rSpeedSetpoint := 0.0;
    bCommandLost := TRUE;
END_IF;
```

`ToPeer` with `bRequireAcknowledge` means `Ok` is *the pump has it*, not *it was sent*.
And the pump gets staleness detection for free.

A register write does the same job if the far end is a Modbus address rather
than a topic:

```
node.ModbusWrite(anyData := iRunMinutes, nPeerNodeId := 60, nStartAddress := 300,
                 bRequireAcknowledge := TRUE, bExecute := bSend);
```

## Failsafe on a setpoint

The device that receives a command should decide what happens if the commander
goes quiet. That belongs on the receiving node, at the address:

```
node(nNodeId := 60, bApplySafeValueOnWriterLoss := TRUE);
node.ModbusMap(anyData := iRunMinutes, nStartAddress := 300,
               eActionOnWriterLoss := E_BeeBusModbusFailsafe.ResetToValue, nSafeValue := 5,
               bSafeValueApplied => bSafeNow);
IF bSafeNow THEN
    bWentToSafeState := TRUE;      (* worth logging *)
END_IF;
```

The commander disappears, the setpoint falls back to 5 by itself, and the
program is told it happened. Note `bApplySafeValueOnWriterLoss := TRUE` on the node. Without it
`eActionOnWriterLoss` does nothing.

## A SCADA node

One that watches everything and commands a little.

```
node(nNodeId := 200, bApplySafeValueOnWriterLoss := TRUE);

(* one call per value, so each line says what it brings in *)
node.Subscribe(anyValue := rOutsideTempC, nPeerNodeId := 4, sTopic := 'outside_temp',
               nTopicId := 1, fDeadband := 0.2, tMaxSendInterval := T#5s);
node.Subscribe(anyValue := rTankALevelPct, nPeerNodeId := 17, sTopic := 'tank_a_level',
               nTopicId := 1, fDeadband := 0.5, tMaxSendInterval := T#2s, eQuality => eTankQuality);
node.Subscribe(anyValue := rFlowLps, nPeerNodeId := 31, sTopic := 'flow_lps',
               nTopicId := 3, fDeadband := 0.1, tMaxSendInterval := T#2s);

(* alarms come from quality, not from the numbers *)
bTankCommsLost := eTankQuality = E_BeeBusQuality.Bad;
bAlarmTankLow  := eTankQuality = E_BeeBusQuality.Good AND rTankALevelPct < 10.0;
```

**The alarm is gated on quality.** Without that, a communications failure that
freezes the level at 50% reads as a healthy tank, and a failure that leaves it
at 0 raises a low-level alarm that is not real.

## A gateway

Two nodes in one program, one per segment, moving values between them.

```
VAR
    serialNode  : FB_BeeBusNode;
    udpNode     : FB_BeeBusNode;
    serial      : ST_BeeBusSerialConfig;
    rFieldValue : REAL;
END_VAR

serial.sDevice := '/dev/ttyUSB0';
serialNode(nNodeId := 1, eTransport := E_BeeBusTransport.RuntimeSerial, stSerialConfig := serial);
udpNode(nNodeId := 1, eTransport := E_BeeBusTransport.RuntimeUdp);

(* in on the serial segment *)
serialNode.Subscribe(anyValue := rFieldValue, nPeerNodeId := 5, sTopic := 'well_level',
                     nTopicId := 1, fDeadband := 0.1, tMaxSendInterval := T#2s);
(* out on the plant segment *)
udpNode.Topic(anyValue := rFieldValue, sTopic := 'well_level', nTopicId := 1);
```

The same variable is a subscriber's landing spot on one segment and an owned
topic on the other - two records, on two nodes. Node ids only have to be unique
**within** a segment, so both may be 1.

## Choosing deadband and period

| the value | `fDeadband` | `tMaxSendInterval` |
| --- | --- | --- |
| a temperature | 0.2-0.5 °C | `T#5s` |
| a tank level | 0.5 % | `T#2s` |
| a flow that matters | 0.1 | `T#1s` |
| a setpoint or command | 0.0 (every change), or `bDeliverEveryChange` | `T#5s` |
| an on/off state | 0.0 | `T#5s` |

The deadband keeps noise off the network. The period is what proves the link is
alive, so **never leave it at `T#0s`** on anything you will raise an alarm from -
without it, a value that simply stops changing looks identical to a link that
died. Set it to about twice the slowest update you are willing to accept.

## What bites people

**Raising `bExecute` from a level that stays up.** It is an edge: one request.
A sequence that never lowers it never sends a second one.

**Reading a request's result in the scan that raised it.** That is the last
run's result, held.

**One variable for two records.** `node.Write(anyValue := bOne ...)` called for
forty topics in a loop is one record: give each its own variable.

**Forgetting `bApplySafeValueOnWriterLoss := TRUE`** and wondering why `eActionOnWriterLoss` does nothing.

**`bRequireAcknowledge := TRUE` with `E_BeeBusPublishMode.All`.** Nothing acknowledges a
broadcast, so it is refused with `InvalidArgument`. Confirmation needs a named
peer.

**Two nodes on one `nNodeId`.** The second stands down and reports
`DuplicateNodeId`. Look for the code before you look at the wiring.

**Alarming on a number without checking its quality.** The frozen value is the
one that fools you.

**A topic name over 255 characters.** Refused rather than truncated, deliberately
- two long names cut to the same 255 would silently become one topic.

**A method in another task.** It returns `WrongTask` and does nothing. Keep the
node's program and its method calls in one task.
