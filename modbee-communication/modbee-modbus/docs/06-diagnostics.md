# 06 - Diagnostics

What a link and a device are doing: the node's own error pins, `Statistics`,
`Device` and `ReadDeviceIdentification`. None of them puts anything extra on
the bus unless you ask it to.

## The node's error pins

`bError`, `eErrorId` and `sLastError` on `FB_ModbusNode` say what is wrong, in
this order:

1. **The link would not open** - `sLastError` in the operating system's words:
   *"No such file or directory"*, *"Permission denied"*, *"Address already in
   use"*. `bLinkUp` stays `FALSE` and the node tries again every two seconds.
2. **The link is open with nobody at the other end** - a TCP client whose
   device refused or dropped the connection: `eErrorId` is `LinkDown`,
   `sLastError` says *"not connected"*, and the node keeps trying.
3. **A method call failed** - named by method and variable, *"ReadHoldingRegisters
   aRegs: Timeout"*, until that same call succeeds. The last failing call is
   the one shown.
4. **An input the target does not use** - a board's network settings on the
   Runtime, say.

A program that wants one alarm per link wires `bError`; one that wants to know
which call failed reads the call's own result.

## node.Statistics - how the link is doing

```
node.Statistics(nSent => nSent, nReceived => nReceived,
                nChecksumErrors => nCrc, nNoiseBytes => nNoise,
                nFramingErrors => nFraming, sFramingReason => sWhy);
```

It reports and changes nothing - except that a rising edge of `bReset` zeroes
the counters - which is why it is safe to call from a diagnostic page anywhere
in the node's task. It counts across outages: `nReconnects` is worth reading
most while the link is down.

### The three error counters, and what each one means

This is the part worth putting on a screen, because **the difference between
them says which fault you have**, and none of them looks any different from the
application's point of view:

| climbing | means |
| --- | --- |
| `nChecksumErrors` | the bytes arrive and the maths does not agree. Noise, a baud rate mismatch, or a missing termination resistor |
| `nNoiseBytes` | bytes discarded while hunting for the start of a frame. A **floating bus** - nothing is holding the line at idle. Fit the bias resistors |
| `nFramingErrors` | structurally impossible frames. Something on the bus is speaking a different protocol, or frames are being split - read `sFramingReason` |

**All three flat while a device does not answer means the bytes are not
arriving at all**: wrong port, wrong wires, transmit and receive swapped, or the
device is off. That is a useful negative result and it takes two seconds to
check.

A corrupt reply is discarded and counted, never matched to a request: the
request that was waiting for it times out (`Timeout`), and `nChecksumErrors`
is where the corruption shows.

`nSent` and `nReceived` are frames, both directions. On a healthy client they
track each other. `nSent` climbing while `nReceived` stays put is nobody
answering.

`nPending` is requests queued and not yet concluded. It should hover near zero
and come back down. One that climbs steadily is a program issuing requests
faster than the bus can carry them - see [10 - Scan rate](10-scan-rate.md).

`nReconnects` counts the times the link dropped and came back on its own. A
link that works but reconnects nightly is a different problem from one that has
never worked.

### sFramingReason

The first thing to read when frames go missing, and the answer to the commonest
question asked of any Modbus library: **why is my RTU splitting frames.**

RTU marks the end of a frame with silence - three and a half character times of
it. A USB adapter, a virtual serial port or a busy PLC scan can all destroy
that silence by delivering bytes in clumps. So the library measures the line and
picks a rule, and `sFramingReason` says which rule and why, in a sentence you
can read off the screen.

On a TCP link it says so and stops there - the header carries the length, so
there is nothing to predict and nothing to measure. On an **RTU-over-TCP** link
it reports the RTU rule instead, which is how you tell from one output which of
the two a terminal server actually gave you.

## node.Device - how one device is doing

```
node.Device(nUnitId := 2, bAnswering => bDriveAnswering, bSeen => bDriveSeen,
            tSilent => tDriveSilent, tRoundTrip => tDriveRtt);
```

A standing method: call it every scan. **`bAnswering`, `tSilent` and
`tRoundTrip` are read off traffic you are already making.** With `tPoll` at
`T#0s` it sends nothing at all, so a screen showing thirty devices you already
read costs not one extra frame.

**Which means a device nobody asks anything reads as not answering.** That is
literally true and thoroughly unhelpful - the device may be in perfect health
and simply have nothing to say, because nothing has spoken to it. If this is
the only call pointed at a device, give it a `tPoll`:

```
node.Device(nUnitId := 5, tPoll := T#2s, bAnswering => bStandbyAnswering);
```

It sends the standard link test, function code 8: whatever goes out comes back
unchanged, and no register is touched. A device that does not implement FC 8
answers with an **exception** - which still proves it is alive and still counts
as answering, because a unit that is transmitting is a unit that is there. So
the check works even on devices that refuse it.

### Never answered is not a long silence

`bSeen` `FALSE` means this device has **never answered at all**, which is a
different fault from one that has gone quiet - and the two send an engineer to
opposite ends of the site:

| | |
| --- | --- |
| **never answered** (`bSeen` `FALSE`) | the unit id is wrong, the device was never fitted, or it is set to a different address. A **commissioning fault**, found at the desk with a wiring drawing |
| **gone quiet** (`bSeen`, not `bAnswering`) | it was answering and has stopped. A cable, a power supply, a failed device. A **running fault**, found in the plant |

An alarm list that shows both as "no comms" throws that away. Keep them apart:

```
bDeviceMissing := NOT bDriveSeen;                       (* never there *)
bDeviceLost    := bDriveSeen AND NOT bDriveAnswering;   (* was, is not *)
```

`bAnswering` is `TRUE` while the device has answered within `tGone`, which
defaults to five seconds. Give it room for at least two `tPoll` periods.

### tRoundTrip

The number to quote when somebody asks whether a device is slow or the bus is.
It is measured, not configured.

A drive answering in 45 ms on a bus whose other devices answer in 6 ms is **a
slow drive**, and no amount of changing the baud rate will help. A bus where
everything answers slowly is a bus problem. Without this number the two
arguments go round for an afternoon.

## node.ReadDeviceIdentification - the device's own nameplate

A request: a rising edge asks the device who it is, using function code 43 -
the same information a handheld tool shows:

```
eIdent := node.ReadDeviceIdentification(nUnitId := 2, bExecute := bAskOnce,
                                        sVendor => sVendor, sProduct => sProduct,
                                        sRevision => sRevision);
IF eIdent = E_ModbusResult.Ok THEN
    sLogLine := CONCAT(sVendor, sProduct);
END_IF;
```

**Ask once at start-up and keep what comes back.** It does not change.

Not every device implements it. One that does not answers with an exception,
which arrives as `Refused` - that is a normal answer, not a fault worth
alarming on.

## Every result

Every method returns an `E_ModbusResult`, and the node's `eErrorId` carries
one. `Ok` when fine.

### Accepted

| | |
| --- | --- |
| `Queued` | accepted; the outcome arrives on a later scan |
| `Ok` | it completed. This is what success looks like. A standing method returns it while its record is valid |

### Refused before anything reached the wire

These are your program's mistakes, and being told immediately is the point -
you can fix a bad request, and you cannot tell a bad request from an absent
device once it has timed out.

| | |
| --- | --- |
| `NotInitialised` | on the node: the link would not open. Read `sLastError` |
| `InvalidArgument` | a zero count, a length past the end of the variable, a quantity Modbus disallows, a `BOOL` aimed at a register table, a `REAL` given to `Map`, or settings that cannot work. Also the device's exception 03 |
| `Duplicate` | an identical request from another variable is already outstanding |
| `QueueFull` | more outstanding requests than the queue holds - you are asking faster than the bus can answer, or `stTimingConfig.nMaxPending` / `nMaxPendingBytes` are too small for expected bursts. Also: more than 256 records on one node |
| `Superseded` | a newer write to the same address replaced this one before it went out. Not an error |
| `Cancelled` | the link was closed (`bConnect` `FALSE`) while it was out |
| `WrongTask` | called from a task other than the node's. Nothing was done |

### Concluded on the wire

| | |
| --- | --- |
| `Timeout` | nothing answered, after every retry. The device is off, unplugged, at a different address, or on a different baud rate - or its reply arrived corrupt (see `nChecksumErrors`) |
| `Refused` | the device answered and said no (exception 01, 04 and others). **The wiring works** - the function code is wrong for that device |
| `NotMapped` | the device has nothing at that address (exception 02) |
| `Acknowledged` | the device took the job and is still doing it (exception 05). **Poll, do not retry** - retrying sends a second copy of a command already running |
| `Busy` | the device is busy (exception 06). Retry later |
| `GatewayPathUnavailable` | a bridge has no route to that unit (exception 0A). A problem with the **bridge** |
| `GatewayTargetFailed` | the route exists and the device did not answer (exception 0B). A problem with the **device** |
| `ProtocolError` | a reply arrived and made no sense |

### Link faults

| | |
| --- | --- |
| `LinkDown` | the link is not open, or a TCP client's device is not connected. A request is refused at once; a standing method keeps its record |

`UnknownUnit` and `ChecksumError` are in the enumeration because it mirrors the
protocol library's result list value for value; no method returns them today.

**`Refused` is the most encouraging failure on this list.** It means frames
are going out, arriving, being understood and being answered. Everything below
the application layer works, and you are arguing about a function code.

**Next:** [07 - Block reference](07-block-reference.md)
