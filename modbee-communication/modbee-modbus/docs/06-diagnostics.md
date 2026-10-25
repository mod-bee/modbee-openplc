# 06 - Diagnostics

Two blocks, and neither of them puts anything extra on the bus except when you
ask it to.

## MODBUS_STATUS — how the link is doing

```
health( NODE := node );
```

No inputs at all. It reports and changes nothing, which is why it is safe to
drop onto a diagnostic page anywhere.

### The three error counters, and what each one means

This is the part worth putting on a screen, because **the difference between
them says which fault you have**, and none of them looks any different from the
application's point of view:

| climbing | means |
| --- | --- |
| `CHECKSUM_ERRORS` | the bytes arrive and the maths does not agree. Noise, a baud rate mismatch, or a missing termination resistor |
| `NOISE_BYTES` | bytes discarded while hunting for the start of a frame. A **floating bus** — nothing is holding the line at idle. Fit the bias resistors |
| `FRAMING_ERRORS` | structurally impossible frames. Something on the bus is speaking a different protocol, or frames are being split — read `FRAMING_REASON` |

**All three flat while a device does not answer means the bytes are not
arriving at all**: wrong port, wrong wires, transmit and receive swapped, or the
device is off. That is a useful negative result and it takes two seconds to
check.

`SENT` and `RECEIVED` are frames, both directions. On a healthy client they
track each other. `SENT` climbing while `RECEIVED` stays put is nobody
answering.

`PENDING` is requests queued and not yet concluded. It should hover near zero
and come back down. One that climbs steadily is a program issuing requests
faster than the bus can carry them — see [10 - Scan rate](10-scan-rate.md).

To zero the counters, pulse `RESET_STATS` on the node that owns the link.

### FRAMING_REASON

The first thing to read when frames go missing, and the answer to the commonest
question asked of any Modbus library: **why is my RTU splitting frames.**

RTU marks the end of a frame with silence — three and a half character times of
it. A USB adapter, a virtual serial port or a busy PLC scan can all destroy
that silence by delivering bytes in clumps. So the library measures the line and
picks a rule, and this pin says which rule and why, in a sentence you can read
off the screen.

On a TCP link it says so and stops there — the header carries the length, so
there is nothing to predict and nothing to measure. On an **RTU-over-TCP** link
it reports the RTU rule instead, which is how you tell from one pin which of
the two a terminal server actually gave you.

## MODBUS_DEVICE — how one device is doing

```
drive( NODE := node, UNIT := 2, IDENTIFY := askOnce );
```

**`ANSWERING`, `SILENT` and `ROUND_TRIP` are read off traffic you are
already making.** With `POLL` at 0 this block sends nothing at all, so a
screen showing thirty devices you already read costs not one extra frame.

**Which means a device nobody asks anything reads as not answering.** That is
literally true and thoroughly unhelpful — the device may be in perfect health
and simply have nothing to say, because nothing has spoken to it. If this block
is the only thing pointed at a device, give it a `POLL`:

```
standby( NODE := node, UNIT := 5, POLL := T#2s );
```

It sends the standard link test, function code 8: whatever goes out comes back
unchanged, and no register is touched. A device that does not implement FC 8
answers with an **exception** — which still proves it is alive and still counts
as answering, because a unit that is transmitting is a unit that is there. So
the check works even on devices that refuse it.

### SILENT = -1 is not a long silence

It means this device has **never answered at all**, which is a different fault
from one that has gone quiet — and the two send an engineer to opposite ends of
the site:

| | |
| --- | --- |
| **never answered** | the unit id is wrong, the device was never fitted, or it is set to a different address. A **commissioning fault**, found at the desk with a wiring drawing |
| **gone quiet** | it was answering and has stopped. A cable, a power supply, a failed device. A **running fault**, found in the plant |

An alarm list that shows both as "no comms" throws that away. Keep them apart:

```
deviceMissing := (drive.SILENT < 0);              (* never there *)
deviceLost    := (drive.SILENT > 5000);           (* was, is not *)
```

`ANSWERING` is the simple form: `TRUE` while the device has answered within
`GONE`, which defaults to five seconds.

### ROUND_TRIP

The number to quote when somebody asks whether a device is slow or the bus is.
It is measured, not configured.

A drive answering in 45 ms on a bus whose other devices answer in 6 ms is **a
slow drive**, and no amount of changing the baud rate will help. A bus where
everything answers slowly is a bus problem. Without this number the two
arguments go round for an afternoon.

### IDENTIFY — the device's own nameplate

A rising edge asks the device who it is, using function code 43 — the same
information a handheld tool shows:

```
drive( NODE := node, UNIT := 2, IDENTIFY := askOnce );

IF drive.IDENTIFIED THEN
    (* one scan, when the nameplate arrived *)
    logLine := CONCAT(drive.VENDOR, drive.PRODUCT);
    askOnce := FALSE;
END_IF;
```

**Ask once at start-up and keep what comes back.** It does not change.

Not every device implements it. One that does not answers with an exception,
which arrives as `MODBUS_REFUSED` — that is a normal answer, not a fault worth
alarming on.

## Every status code

`STATUS` is on every block. `MODBUS_OK` when fine.

### Accepted

| | |
| --- | --- |
| `MODBUS_QUEUED` | accepted; the outcome arrives on a later scan |
| `MODBUS_OK` | it completed. This is what success looks like |

### Refused before anything reached the wire

These are your program's mistakes, and being told immediately is the point —
you can fix a bad request, and you cannot tell a bad request from an absent
device once it has timed out.

| | |
| --- | --- |
| `MODBUS_NOT_INITIALISED` | the link is not open. Check `node.READY` and `node.LAST_ERROR` |
| `MODBUS_INVALID_ARGUMENT` | a zero count, a length past the end of the variable, a quantity Modbus disallows, or a `BOOL` aimed at a register list |
| `MODBUS_NOT_MAPPED` | a local address with nothing bound to it |
| `MODBUS_DUPLICATE` | an identical request is already outstanding. Not an error — this is what stops a held `REQ` flooding the bus |
| `MODBUS_QUEUE_FULL` | more outstanding requests than the queue holds. You are asking faster than the bus can answer - or, if the bursts are expected, `MODBUS_CONFIG`'s `QUEUE` / `QUEUE_BYTES` are too small |
| `MODBUS_UNKNOWN_UNIT` | the destination is not reachable |
| `MODBUS_SUPERSEDED` | a newer write to the same address replaced this one before it went out. Not an error |
| `MODBUS_CANCELLED` | discarded by a restart |

### Concluded on the wire

| | |
| --- | --- |
| `MODBUS_TIMEOUT` | nothing answered, after every retry. The device is off, unplugged, at a different address, or on a different baud rate |
| `MODBUS_REFUSED` | the device answered and said no. **The wiring works** — the address or the function code is wrong for that device |
| `MODBUS_ACKNOWLEDGED` | the device took the job and is still doing it. **Poll, do not retry** — retrying sends a second copy of a command already running |
| `MODBUS_BUSY` | the device is busy. Retry later |
| `MODBUS_GATEWAY_PATH_UNAVAILABLE` | a bridge has no route to that unit. A problem with the **bridge** |
| `MODBUS_GATEWAY_TARGET_FAILED` | the route exists and the device did not answer. A problem with the **device** |

### Link faults

| | |
| --- | --- |
| `MODBUS_LINK_DOWN` | the transport is not usable. On a block other than the node, this also means the `NODE` pin has no started node behind it |
| `MODBUS_CHECKSUM_ERROR` | a reply arrived corrupt |
| `MODBUS_PROTOCOL_ERROR` | a reply arrived and made no sense |

**`MODBUS_REFUSED` is the most encouraging failure on this list.** It means
frames are going out, arriving, being understood and being answered. Everything
below the application layer works, and you are arguing about an address.

**Next:** [07 - Block reference](07-block-reference.md)
