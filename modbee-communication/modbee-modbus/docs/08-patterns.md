# 08 - Patterns

Worked examples, and the habits worth keeping.

## The two-task split

Every project should look like this, and it is the one piece of structure that
matters:

| task | interval | priority | holds |
| --- | --- | --- | --- |
| `APP_TASK` | `T#20ms` | `0` | the machine - no Modbus block at all |
| `NET_TASK` | `T#1ms` on the Runtime, `T#50ms` on a board to start | `20` | `MODBUS_NODE` and every block given it |

Values cross between them through globals, each written by one task.

```
PROGRAM net
VAR
    node : MODBUS_NODE;
END_VAR

node( TRANSPORT := MODBUS_RUNTIME_SERIAL,
      SERIAL_DEVICE    := '/dev/ttyUSB0', SERIAL_BAUD := 19200,
      ROLE      := MODBUS_ROLE_BOTH, SERIAL_UNIT_ID := 7 );

END_PROGRAM
```

The node is the only block that touches the wire, so its period is the floor on
how fast anything happens. Everything else just hands it work and reads pins.
[10 - Scan rate](10-scan-rate.md) has the numbers.

## Call the node before the blocks that use it

Within a scan, a block placed above the node acts on the previous scan's state.
It corrects itself and costs one scan — it is not fatal — but there is no
reason to have it happen.

## Keep the bus quiet for what matters

**This is the habit that separates a Modbus system that works from one that
nearly works.**

A Modbus segment carries one conversation at a time. Every read you issue is
time that a control word cannot have. So:

**Read on demand what is only needed on demand.** A nameplate, a serial number,
a configuration block, a recipe — read it once with `MODBUS_READ` on a rising
edge and keep it. It does not change.

**Watch only what genuinely has to stay fresh**, and at the rate the process
actually needs:

```
(* a tank level: seconds is plenty *)
level( NODE := node, UNIT := 1, FC := MODBUS_FC04_READ_INPUT_REGISTERS,
       ADDRESS := 30, EVERY := T#2s, VALUE := tankLevel );

(* a torque feedback in a closed loop: as fast as the bus will bear *)
torque( NODE := node, UNIT := 2, FC := MODBUS_FC04_READ_INPUT_REGISTERS,
        ADDRESS := 10, EVERY := T#100ms, VALUE := motorTorque );
```

**Stop watching what you are not using.** `ENABLE` stops and starts a watch in
place, with no second entry and no cost while it is off:

```
(* the dryer's sensors matter only while the dryer runs *)
dryerTemps( NODE := node, UNIT := 5, FC := MODBUS_FC04_READ_INPUT_REGISTERS,
            ADDRESS := 0, EVERY := T#500ms, ENABLE := dryerRunning,
            VALUE := temps );
```

**Write only when the value changed.** A write repeated every scan is a write
the bus has to carry every scan:

```
IF newSpeed <> lastSpeed THEN
    lastSpeed := newSpeed;
    sendSpeed := TRUE;
END_IF;

wr( NODE := node, REQ := sendSpeed, UNIT := 2, ADDRESS := 40, VALUE := newSpeed );

IF wr.DONE OR wr.ERROR THEN
    sendSpeed := FALSE;
END_IF;
```

**Read a range, not an address at a time.** One request for a hundred registers
is one frame. A hundred requests is a hundred frames and a hundred turnarounds:
at 19200 baud that is 126 ms against 1.3 seconds, for exactly the same data.

**It is safe to call a read or a write in the loop.** Nothing floods: a held
`REQ` reads once on the edge, a duplicate is refused, a superseded write is
replaced. The advice above is about the bus, not about safety.

## A device that must be there

```
VAR
    drive     : MODBUS_DEVICE;
    speedFb   : MODBUS_WATCH;
    feedback  : ARRAY [0..1] OF WORD;
    driveLost : BOOL;
    driveMissing : BOOL;
END_VAR

speedFb( NODE := node, UNIT := 2, FC := MODBUS_FC04_READ_INPUT_REGISTERS,
         ADDRESS := 10, EVERY := T#200ms, VALUE := feedback );

drive  ( NODE := node, UNIT := 2 );

(* Two different faults, two different alarms, two different engineers *)
driveMissing := (drive.SILENT < 0);       (* never answered: commissioning *)
driveLost    := NOT drive.ANSWERING AND (drive.SILENT >= 0);

(* Act on the value only while it is worth acting on *)
IF speedFb.QUALITY = MODBUS_QUALITY_GOOD THEN
    actualSpeed := feedback[0];
ELSE
    driveTrip := TRUE;
END_IF;
```

## Reading a float from a device

```
VAR
    flow     : MODBUS_WATCH;
    flowRate : REAL;
END_VAR

flow( NODE := node, UNIT := 3, FC := MODBUS_FC04_READ_INPUT_REGISTERS,
      ADDRESS := 30, EVERY := T#1s,
      ORDER := MODBUS_ORDER_CDAB, VALUE := flowRate );
```

If it reads `4.6e-41` instead of `1234.5`, the address is right and `ORDER` is
wrong. Try `MODBUS_ORDER_CDAB` first if you were on `ABCD`, and the other way
round. See [05 - Reading and writing](05-reading-and-writing.md).

## A PLC that is also a device

```
PROGRAM net
VAR
    node : MODBUS_NODE;
    cfg  : MODBUS_CONFIG;
    name : MODBUS_IDENTITY;
END_VAR
node( TRANSPORT := MODBUS_RUNTIME_SERIAL,
      SERIAL_DEVICE    := '/dev/ttyUSB0', SERIAL_BAUD := 19200,
      ROLE      := MODBUS_ROLE_BOTH, SERIAL_UNIT_ID := 7 );

(* Optional, and here only because this node wants a failsafe *)
cfg ( NODE := node, TIMEOUT := T#0s, FAILSAFE := T#5s );
name( NODE := node, VENDOR := 'Example Co', PRODUCT := 'Pump House' );
END_PROGRAM
```

```
PROGRAM app
VAR
    node     : MODBUS_NODE;
    measured : MODBUS_MAP;
    commands : MODBUS_MAP;
    readings : ARRAY [0..15] OF WORD;
    setpoints: ARRAY [0..3] OF WORD;
END_VAR

(* Read-only to anyone outside: the list has no write function code *)
measured( NODE := node, TABLE := MODBUS_INPUT_REGISTERS,
          ADDRESS := 0, VALUE := readings );

(* Writable, and therefore validated *)
commands( NODE := node, TABLE := MODBUS_HOLDING_REGISTERS,
          ADDRESS := 100, VALUE := setpoints );

IF commands.WRITTEN THEN
    IF setpoints[0] > 1500 THEN setpoints[0] := 1500; END_IF;
    acceptSetpoint := TRUE;
END_IF;
END_PROGRAM
```

## A terminal server

A serial-to-Ethernet converter with three RS-485 ports is three nodes, one per
TCP port:

```
segmentA( TRANSPORT := MODBUS_RUNTIME_TCP, FRAMING := MODBUS_FRAMING_RTU,
          TCP_HOST := '192.168.1.50', TCP_PORT := 4001 );
segmentB( TRANSPORT := MODBUS_RUNTIME_TCP, FRAMING := MODBUS_FRAMING_RTU,
          TCP_HOST := '192.168.1.50', TCP_PORT := 4002 );
```

Both in the fast task. Two nodes are two independent buses, which is exactly
what they are physically.

## A gateway

Several SCADA clients sharing one RS-485 segment:

```
PROGRAM gateway
VAR
    bridge : MODBUS_BRIDGE;
END_VAR

bridge( SERIAL_DEVICE := '/dev/ttyUSB0', SERIAL_BAUD := 19200,
        TCP_PORT := 502, FIRST_UNIT := 1, LAST_UNIT := 32 );

(* Two alarms, because they send you to different places *)
gatewayFault := bridge.NO_PATH > 0;      (* our routing is wrong *)
fieldFault   := bridge.NO_DEVICE > 0;    (* a device is not answering *)
END_PROGRAM
```

## Habits worth keeping

**Interlock on `QUALITY`, never on a value alone.** A stale register looks
exactly like a steady process.

**Give `UNKNOWN` and `BAD` separate alarms.** One is a commissioning fault, the
other is a running fault.

**Read `LAST_ERROR` before anything else when a node will not start.** It
carries the operating system's own words.

**Put anything a client must not change in a read-only list.** It is not a
permission somebody can alter later.

**Validate what a client writes.** The register is your variable, so the check
belongs in your program.

**Test the failsafe by pulling the cable**, on commissioning, and watch
`SAFE_APPLIED`. A failsafe nobody has seen fire is a failsafe nobody knows
works.

**Use `WORD` for registers, not `INT`.** `WORD` is what you can mask, shift and
take a bit of.

## One limitation on Arduino targets

**An `ANY` pin fed from a Global Variable List does not compile on a board.**
The generated code needs a newer C++ standard than the ESP32 core builds with.
`check` passes either way, so it only appears at board build time.

Until that is fixed upstream, **`VALUE` pins take POU locals on Arduino
targets** — which is why every example above keeps the variable and the block
in the same program. On the Runtime there is no such limit.

**Next:** [09 - Troubleshooting](09-troubleshooting.md)
