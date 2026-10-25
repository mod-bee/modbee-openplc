# 08 - Patterns

Worked examples, and the habits that make a program readable a year later.

## Habits worth keeping

**One block per thing.** Sixteen subscriptions is sixteen named blocks, not one
instance called sixteen times. The library supports either — a slot is keyed by
the topic, not by the block — but a named block per subscription means each line
says what it brings in and where the value lands, and you can find any one of
them by name.

```
subOutsideTemp( NODE := node, PEER := 4, NAME := 'outside_temp', ... );
subWindSpeed  ( NODE := node, PEER := 4, NAME := 'wind_speed',   ... );
subRainfall   ( NODE := node, PEER := 4, NAME := 'rainfall_mm',  ... );
```

**The node block first.** Always, at the top. And once the ring is more than a
few nodes, in its own fast task with the blocks given it — it is the only block
that services the protocol, and how often it runs is what decides how fast the
ring is. See [10 - Scan rate](10-scan-rate.md).

**Bind unconditionally; act conditionally.** `BEEBUS_TP_TOPIC`, `BEEBUS_TP_SUBSCRIBE` and
`BEEBUS_MB_MAP` are declarations of what this node shares. Call them every scan with no
`IF` around them. Put the logic on what you do with the values.

**Subscribe once and forget it.** A subscription is a standing intent: it is
held until the peer arrives and re-established if the peer restarts. Do not
write code to watch for the peer and re-subscribe — that job is already done.

**Reads and writes on an edge, never every scan.** `REQ` is edge-triggered.
Firing one every scan fills the queue and gets you `BEEBUS_QUEUE_FULL`.

**Name the simulation.** Where a value stands in for a real measurement, put it
in a named `FUNCTION` — `SIM_TANK_LEVEL`, `SIM_FLOW` — rather than an inline
expression. A reader can then see what the program is supposed to be doing
without reading arithmetic.

## Round-robin: many operations, one at a time

Reads and writes go out on a turn of the ring. Firing ten at once fills the
queue; firing one every so often does not. A small step counter is the usual
shape:

```
VAR
    iStep     : INT;
    stepTicks : DINT;
    bFire     : BOOL;
END_VAR

stepTicks := stepTicks + 1;
bFire := FALSE;
IF stepTicks >= 25 THEN          (* every half second at a 20 ms scan *)
    stepTicks := 0;
    bFire := TRUE;
    iStep := iStep + 1;
    IF iStep > 3 THEN iStep := 0; END_IF;
END_IF;

readCoil   ( REQ := bFire AND (iStep = 0), NODE := node, PEER := 20, ... );
readHolding( REQ := bFire AND (iStep = 1), NODE := node, PEER := 20, ... );
readText   ( REQ := bFire AND (iStep = 2), NODE := node, PEER := 20, ... );
readRange  ( REQ := bFire AND (iStep = 3), NODE := node, PEER := 20, ... );
```

One operation per turn, in order, forever. It reads well and it never floods.

## The sleeping sensor

A battery device that wakes, reports and sleeps again. The whole point is **one
turn on the bus per wake**.

```
VAR
    node       : BEEBUS_NODE;
    report     : BEEBUS_TP_PUBLISH;
    buffer     : BEEBUS_TP_BUFFER;
    rSoilTemp  : REAL;
    bAwake     : BOOL;
    bJustWoke  : BOOL;
    bWasAwake  : BOOL;
    cycleTicks : DINT;
    settleTicks : DINT;
END_VAR

(* awake ten seconds in every twenty *)
cycleTicks := cycleTicks + 1;
IF cycleTicks >= 1000 THEN cycleTicks := 0; END_IF;
bAwake := (cycleTicks < 500);

node( NODE_ID := 88, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP, CONNECT := bAwake );

(* hold the readings taken while asleep *)
buffer( NODE := node, NAME := 'soil_temp', DEPTH := 8 );

(* give the ring a moment to readmit us before reporting *)
IF bAwake AND NOT bWasAwake THEN settleTicks := 0; END_IF;
bWasAwake := bAwake;
IF bAwake AND settleTicks < 100 THEN settleTicks := settleTicks + 1; END_IF;
bJustWoke := bAwake AND (settleTicks = 100);

report( REQ := bJustWoke, NODE := node,
        NAME := 'soil_temp', TOPIC_ID := 1,
        MODE := BEEBUS_TP_PUBLISH_ALL, VALUE := rSoilTemp );
```

Three things make this work:

**`CONNECT := bAwake`** leaves the ring properly rather than going silent, so
peers are told instead of timing it out.

**`BEEBUS_TP_PUBLISH_ALL`** is one frame for every listener. A SCADA and a controller
both subscribed cost the same one turn as either alone.

**The settle delay.** Rejoining takes a few turns. Reporting the instant
`CONNECT` goes high publishes into a ring you have not joined yet.

`BEEBUS_TP_BUFFER` is optional but usually right here: if the wake window is too short
one cycle, the reading is held and goes out on the next.

## Settings and commands from a panel

The panel binds what the PLC serves; nothing else is written for it on either
side. The full chapter is [11 - Settings both ways](11-bidirectional-binding.md).

On the PLC:

```
set( NODE := node, VALUE := SET, TOPIC_ID := 300, WRITABLE := TRUE );
cmd( NODE := node, VALUE := CMD, TOPIC_ID := 400, WRITABLE := TRUE,
     COMMAND := TRUE, PULSE := T#500ms );
```

On the panel:

```
set( NODE := node, VALUE := SET, PEER := 1, TOPIC_ID := 300, RELIABLE := TRUE );
cmd( NODE := node, VALUE := CMD, PEER := 1, TOPIC_ID := 400, RELIABLE := TRUE );
```

The block that uses a setting decides it, as it always did: one that refuses a
value and puts its own back is reported to the panel as `CHANGED`, with the
value kept, which the panel member already shows. `RELIABLE` for settings and
commands; live values stay LIVE.

## Commanding a device, and knowing it arrived

Run the ownership backwards: **the commander owns the topic, the device
subscribes to it.**

On the commander:

```
cmdSpeed( REQ := bSendCmd, NODE := node,
          NAME := 'pump_speed_cmd', TOPIC_ID := 20,
          MODE := BEEBUS_TP_PUBLISH_TO, PEER := 31, CONFIRMED := TRUE,
          VALUE := rDemand );

IF cmdSpeed.DONE  THEN udCmdSent := udCmdSent + 1; END_IF;
IF cmdSpeed.ERROR THEN
    udCmdFailed := udCmdFailed + 1;
    eCmdStatus  := cmdSpeed.STATUS;
END_IF;
```

On the pump:

```
subCmd( NODE := node, PEER := 200,
        NAME := 'pump_speed_cmd', TOPIC_ID := 20,
        DEADBAND := 0.0, PERIOD := T#5s,
        VALUE := rSpeedSetpoint );

(* the setpoint is only as good as the link that delivered it *)
IF subCmd.QUALITY = BEEBUS_TP_BAD THEN
    rSpeedSetpoint := 0.0;
    bCommandLost := TRUE;
END_IF;
```

`BEEBUS_TP_PUBLISH_TO` with `CONFIRMED := TRUE` means `DONE` is *the pump has it*, not
*it was sent*. And the pump gets staleness detection for free.

A register write does the same job if the far end is a Modbus address rather
than a topic:

```
writeRunMinutes( REQ := bSend, NODE := node, PEER := 60,
                 TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 300, CONFIRMED := TRUE,
                 VALUE := iRunMinutes );
```

## Failsafe on a setpoint

The device that receives a command should decide what happens if the commander
goes quiet. That belongs on the receiving node, at the address:

```
node( NODE_ID := 60, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP, FAILSAFE := TRUE );

mapRunMinutes( NODE := node, TABLE := BEEBUS_MB_HOLDING_REG, ADDRESS := 300,
               ON_LOSS := BEEBUS_MB_RESET_TO_VALUE, SAFE_VALUE := 5,
               VALUE := iRunMinutes );

IF mapRunMinutes.SAFE_APPLIED THEN
    bWentToSafeState := TRUE;      (* worth logging *)
END_IF;
```

The commander disappears, the setpoint falls back to 5 by itself, and the
program is told it happened.

Note `FAILSAFE := TRUE` on the node block. Without it `ON_LOSS` does nothing.

## A SCADA node

One that watches everything and commands a little.

```
(* --- the node --- *)
node  ( NODE_ID := 200, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP, FAILSAFE := TRUE );
status( NODE := node );

(* --- one block per value, so each line says what it brings in --- *)
subOutsideTemp( NODE := node, PEER := 4,  NAME := 'outside_temp',
                TOPIC_ID := 1, DEADBAND := 0.2, PERIOD := T#5s,
                VALUE := rOutsideTempC );
subTankLevel  ( NODE := node, PEER := 17, NAME := 'tank_a_level',
                TOPIC_ID := 1, DEADBAND := 0.5, PERIOD := T#2s,
                VALUE := rTankALevelPct );
subFlow       ( NODE := node, PEER := 31, NAME := 'flow_lps',
                TOPIC_ID := 3, DEADBAND := 0.1, PERIOD := T#2s,
                VALUE := rFlowLps );

(* --- alarms come from quality, not from the numbers --- *)
bTankCommsLost := (subTankLevel.QUALITY = BEEBUS_TP_BAD);
bAlarmTankLow  := (subTankLevel.QUALITY = BEEBUS_TP_GOOD) AND (rTankALevelPct < 10.0);
```

**The alarm is gated on quality.** Without that, a communications failure that
freezes the level at 50% reads as a healthy tank, and a failure that leaves it
at 0 raises a low-level alarm that is not real.

## A gateway

Two nodes in one program, moving values between segments. Both `NODE` inputs
must be wired — with two nodes there is no "the only one".

```
VAR
    serialNode : BEEBUS_NODE;
    udpNode    : BEEBUS_NODE;
    subFromField : BEEBUS_TP_SUBSCRIBE;
    tpToPlant    : BEEBUS_TP_TOPIC;
    rFieldValue  : REAL;
END_VAR

serialNode( NODE_ID := 1, TRANSPORT := BEEBUS_NODE_RUNTIME_SERIAL,
            DEVICE := '/dev/ttyUSB0', BAUD := 115200 );
udpNode   ( NODE_ID := 1, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP );

(* in on the serial segment *)
subFromField( NODE := serialNode.NODE, PEER := 5, NAME := 'well_level',
              TOPIC_ID := 1, DEADBAND := 0.1, PERIOD := T#2s,
              VALUE := rFieldValue );

(* out on the plant segment *)
tpToPlant( NODE := udpNode.NODE, NAME := 'well_level', TOPIC_ID := 1,
           VALUE := rFieldValue );
```

The same variable is a subscriber's landing spot on one segment and an owned
topic on the other. Node IDs only have to be unique **within** a segment, so
both may be 1.

## Choosing deadband and interval

| the value | deadband | interval |
| --- | --- | --- |
| a temperature | 0.2–0.5 °C | 5000 ms |
| a tank level | 0.5 % | 2000 ms |
| a flow that matters | 0.1 | 1000 ms |
| a setpoint or command | 0.0 (every change) | 5000 ms |
| an on/off state | 0.0 | 5000 ms |

The deadband keeps noise off the network. The interval is what proves the link
is alive, so **never leave it at 0** on anything you will raise an alarm from —
without it, a value that simply stops changing looks identical to a link that
died.

Set the interval to about twice the slowest update you are willing to accept.

## What bites people

**Firing `REQ` every scan.** It is an edge. Every scan fills the queue.

**Forgetting `FAILSAFE := TRUE`** and wondering why `ON_LOSS` does nothing.

**`CONFIRMED := TRUE` with `BEEBUS_TP_PUBLISH_ALL`.** Nothing acknowledges a broadcast,
so it is refused with `BEEBUS_INVALID_ARGUMENT`. Confirmation needs a named
peer.

**Two nodes on one `NODE_ID`.** The second stands down and reports
`BEEBUS_DUPLICATE_NODE_ID`. Look for the code before you look at the wiring.

**Alarming on a number without checking its quality.** The frozen value is the
one that fools you.

**A topic name over 255 characters.** Refused rather than truncated, deliberately
— two long names cut to the same 255 would silently become one topic. While a
node with an older BeeBus is on the network, keep names to 31 characters: it
refuses longer ones.

**Blocks above the node block.** One scan of `BEEBUS_UNKNOWN_NODE`, then it
corrects itself. Harmless, but confusing when you are watching.
