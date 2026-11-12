# 09 - Troubleshooting

Arranged by what you are seeing, not by what is wrong.

## The node will not start

**`bLinkUp` is `FALSE` and `bError` is `TRUE`.**

Read `sLastError` first. It carries the operating system's own words, which say
far more than a code can:

| `sLastError` | |
| --- | --- |
| *"No such file or directory"* | `stSerialConfig.sDevice` is wrong. Check what actually appeared: `ls /dev/ttyUSB*` |
| *"Permission denied"* | the runtime user cannot open the port. On Linux, add it to the `dialout` group |
| *"Address already in use"* | another program has the TCP port. Often a second copy of this one still running |
| *"no stSerialConfig.sDevice named"* | `sDevice` was left empty on a serial transport |
| *"a serial server needs stSerialConfig.nUnitId, 1 to 247"* | `eRole` is `Server` or `Both`, and `nUnitId` is 0 |
| *"a server needs a Map call"* | `eRole` is `Server` or `Both`, and no `node.Map` is called |
| *"a TCP client needs sHost; leave it empty to be a server"* | `eRole` is `Client` on TCP with no `sHost` |
| *"that eTransport needs a board, not the Runtime"* | `eTransport` is an `Arduino...` value on the Runtime. Use a `Runtime...` one |
| *"eFraming Tcp (MBAP) has no meaning on a serial line"* | `stTimingConfig.eFraming := E_ModbusFraming.Tcp` on a serial transport |
| *"eFraming Ascii inside a TCP stream is not a Modbus transport"* | `eFraming := E_ModbusFraming.Ascii` on a network transport |
| *"eTransport and eFraming cannot change once started"* | something is writing those while the program runs |
| *"out of memory for nMaxClients connections"* | the board cannot hold that many TCP clients. Lower `stTimingConfig.nMaxClients` (or the bridge's `nMaxClients`) |
| *"out of memory for the request queue"* | the board cannot hold the queue `nMaxPending` / `nMaxPendingBytes` ask for. Lower them |

The node retries every two seconds, so a fault you fix is picked up without a
restart.

**`bLinkUp` is `TRUE` but `bConnected` is `FALSE`, `eErrorId` `LinkDown`.**
A TCP client whose device is not there - nothing listening on that address
and port. `sLastError` says *"not connected"*; the node keeps trying on its
own.

## Nothing answers

**Every request returns `Timeout`.**

Work down this list. It is in the order that finds faults fastest.

**1. Look at `node.Statistics`.** If `nChecksumErrors`, `nFramingErrors` and
`nNoiseBytes` are **all flat** while `nSent` climbs, no bytes are arriving at
all. That is wiring, not protocol: wrong port, A and B swapped, transmit and
receive swapped, or the device is off. Stop reading this list and check the
wiring.

If any of them is climbing, bytes *are* arriving and you have a protocol or
signal-quality problem. Carry on.

**2. Baud rate and parity.** A mismatch produces a steady stream of
`nChecksumErrors` - the bytes arrive, the maths does not agree, and the request
waiting for them times out. Note that `E_ModbusParity.None` means **8N2**,
which is what the specification requires when parity is off. A device set to
8N1 needs `E_ModbusParity.None8N1`.

**3. Unit id.** The commonest single mistake. Check `node.Device`'s `bSeen`:
**`FALSE` means that unit id has never answered anything**, which is a wrong
address rather than a dead device.

**4. Termination and bias.** `nNoiseBytes` climbing steadily on an idle bus is
a floating line. 120 ohm at each far end, and bias resistors somewhere.

**5. Is it RTU over TCP?** If you are on TCP and getting silence, it is very
likely a terminal server. Set `stTimingConfig.eFraming := E_ModbusFraming.Rtu`.
See [03 - The node block](03-the-node-block.md).

## The device answers but says no

**The result is `Refused`, `NotMapped` or `InvalidArgument` after a round
trip.**

**This is good news.** Frames are going out, arriving, being understood and
being answered. Everything below the application layer works. You are arguing
about an address or a function code.

| likely cause | |
| --- | --- |
| **the address is not in that device** (`NotMapped`) | check the manual's map |
| **off-by-one** | many manuals number registers from 1 and the wire numbers them from 0. "Register 40001" is usually address 0 in the holding registers |
| **the wrong table** | address 40 in the holding registers is not address 40 in the input registers |
| **the function code is not supported** (`Refused`) | an older device may implement FC 06 and not FC 16: use `WriteSingleRegister` instead of `WriteMultipleRegisters` |
| **too many at once** | some devices accept fewer than the specification's 125 registers. Read a smaller range |

A device that answers an address it does not have with an empty or malformed
reply instead of an exception comes back as `ProtocolError`.

## The values are nonsense

**A float reads `4.6e-41`, or `1.7e38`, or a huge negative number.**

The address is right and the word order is wrong. Try `E_ModbusOrder.CDAB` if
you were on `ABCD`, or the other way round. See
[05 - Reading and writing](05-reading-and-writing.md).

**A number is right but a thousand times out.** The device is publishing in
different units, or with an implied decimal point. That is in its manual, not
on the wire. `Point`'s `fScale` and `fOffset` are made for this.

**A signed value reads as a huge positive number.** A `WORD` holds 0 to 65535.
Use `WORD_TO_INT` for a signed one, or read into an `INT`.

**Half the array is right and half is untouched.** A length mistake: check
`nQuantity`, which should usually be left at 0.

## A request never seems to finish, or finishes twice

**The result stays `Queued`, or a read repeats on its own.** Two calls of the
same method share one variable, so they share one record and fight over its
`bExecute` edge. Give each call its own variable - see
[05 - Reading and writing](05-reading-and-writing.md#a-request).

## Requests are refused before they go out

| result | |
| --- | --- |
| `InvalidArgument` | a zero count, an `nQuantity` past the end of the variable, a quantity past what one request may carry (2000 bits or 125 registers for a read), or a `BOOL` aimed at a register table |
| `Duplicate` | an identical request from another variable is already outstanding |
| `Superseded` | a newer write to the same address replaced this one. **Not an error** |
| `QueueFull` | you are asking faster than the bus can answer. Watch fewer things, or less often - or raise `stTimingConfig.nMaxPending` / `nMaxPendingBytes` if the bursts are expected |
| `LinkDown` | the link is not open, or a TCP client's device is not connected. Check `node.bLinkUp`, `bConnected` and `sLastError` |
| `WrongTask` | see the last section |

## Frames go missing on RS-485

**`nFramingErrors` climbing, or reads that work intermittently.**

Read `sFramingReason` from `node.Statistics`. It says which rule the link is
using and why, in a sentence.

RTU ends a frame with three and a half character times of silence, and several
ordinary things destroy that silence:

- a **USB-to-RS-485 adapter**, which delivers bytes in clumps on its own
  schedule;
- a **virtual serial port**, which has no timing at all;
- a **busy PLC scan**, if the node's task is not fast enough.

If the node is not in a fast task of its own, put it there first - see
[10 - Scan rate](10-scan-rate.md). If the link genuinely cannot hold the timing,
`E_ModbusFraming.Ascii` removes the requirement entirely at the cost of twice
the bytes.

## A watched value stopped updating

**`eQuality` is `Bad`.**

It was arriving and has stopped. Check `nFailures` - one is a hiccup, ten is a
device that has gone - and `node.Device`'s `tSilent` for how long.

Note the backoff: a device that stops answering is retried progressively less
often, down to one attempt in sixteen, so that one dead unit does not consume
the segment. It will pick itself up when the device returns; it just will not
do it instantly.

**`eQuality` is `Unknown` and stays there.**

It has **never** arrived. That is not a running fault - it is a wrong address,
a wrong unit id, a wrong table, or a device that was never fitted. The
method's result says which.

**`eQuality` flickers to `Uncertain`.**

The value is arriving late. Either `tPeriod` is shorter than the bus can
manage, or the node's task is too slow, or there are too many watches. All
three are in [10 - Scan rate](10-scan-rate.md).

## A client cannot read my PLC

**`eRole`** must be `E_ModbusRole.Server` or `Both`.

**`stSerialConfig.nUnitId`** must match what the client is asking for - on
serial. On TCP the unit id does not matter.

**`node.Map` must return `Ok`.** `InvalidArgument` means the variable and the
table disagree: a `BOOL` in a register table, a number in a coil table, a
`REAL`, an unwired `anyData`, or the same variable mapped again somewhere else.
`LinkDown` means the node is not open yet.

**The addresses** are where you said, from the array's lower bound.

## The failsafe never fires

`eOnLoss` needs **`stTimingConfig.tFailsafe`** on the node. Without a silence
to measure there is no loss to act on, and `Map` cannot tell you that because
nothing is wrong with it.

`ResetToValue` applies to a **single value only** - a range has no one safe
value. Map the few addresses that need a safe state individually.

Test it by pulling the cable and watching `bSafeApplied`.

## It works on the Runtime and not on the board

**The node reports *"stNetworkConfig is for a board; the Runtime uses its
machine's network"* on the Runtime** (or the same for `nUart` and the pins).
Every such member describes hardware a board has and a Linux runtime does not.
The link still runs; the message says the setting does nothing.

**`ArduinoEthernet` says *"define MODBUS_ENABLE_ETHERNET to build Ethernet
in"*.** Installing the Arduino Ethernet library is not enough on its own: the
Arduino builder adds a user library to the include path only when it **sees** a
plain `#include` for it, and a header behind a conditional is invisible to that
scanner. Add `MODBUS_ENABLE_ETHERNET` to the project's build flags and it
compiles in.

**The node will not start and says *"set stNetworkConfig.sIp, or 'dhcp' to ask
for one"*.** A fixed address is required on Wi-Fi and on Ethernet - see
[03 - The node block](03-the-node-block.md). Write `sIp := 'dhcp'` if you
genuinely want a server-assigned one.

**Ethernet says *"no Ethernet controller found on SPI"*.** The shield or module
is not answering - usually the chip select pin, or it is not seated.

**Ethernet says *"Ethernet cable unplugged"*.** The controller is there and the
link is not.

**Serial goes nowhere on an ESP32-S3.** With USB CDC on boot, `Serial` is the
USB device and not a UART. `nUart := 0` is `Serial0`, which is UART0. Use
`nUart := 1` or `2` with `nRxPin` and `nTxPin` for a real port.

## A method returns WrongTask

The call is in a different task from its node. It does nothing until it is
moved: OpenPLC runs each task on a thread of its own, and a call from another
task would be inside the node while the node's own scan is. Move it into the
node's program, and hand your application the value through a global - see
[10 - Scan rate](10-scan-rate.md#the-one-rule).

**Next:** [10 - Scan rate](10-scan-rate.md)
