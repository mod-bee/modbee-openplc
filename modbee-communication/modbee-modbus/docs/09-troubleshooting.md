# 09 - Troubleshooting

Arranged by what you are seeing, not by what is wrong.

## The node will not start

**`READY` is `FALSE` and `ERROR` is `TRUE`.**

Read `LAST_ERROR` first. It carries the operating system's own words, which say
far more than a code can:

| `LAST_ERROR` | |
| --- | --- |
| *"No such file or directory"* | the `DEVICE` path is wrong. Check what actually appeared: `ls /dev/ttyUSB*` |
| *"Permission denied"* | the runtime user cannot open the port. On Linux, add it to the `dialout` group |
| *"Address already in use"* | another program has the TCP port. Often a second copy of this one still running |
| *"no serial device named"* | `DEVICE` was left empty on a serial transport |
| *"a serial server needs UNIT_ID, 1 to 247"* | `ROLE` is server or both, and `SERIAL_UNIT_ID` is 0 |
| *"a TCP client needs HOST; leave it empty to be a server"* | `ROLE` is client on TCP with no `HOST` |
| *"that transport needs a board, not the Runtime"* | `TRANSPORT` is a `MODBUS_ARDUINO_*` value on the Runtime. Use a `MODBUS_RUNTIME_*` one |
| *"MBAP framing has no meaning on a serial line"* | `FRAMING := MODBUS_FRAMING_TCP` on a serial transport |
| *"ASCII inside a TCP stream is not a Modbus transport"* | `FRAMING := MODBUS_FRAMING_ASCII` on a network transport |
| *"TRANSPORT and FRAMING cannot change once started"* | something is writing those pins while the program runs |
| *"out of memory for MAX_CLIENTS connections"* | the board cannot hold that many TCP clients. Lower `MODBUS_CONFIG`'s (or `MODBUS_BRIDGE`'s) `MAX_CLIENTS` |
| *"out of memory for the request queue"* | the board cannot hold the queue `MODBUS_CONFIG`'s `QUEUE` / `QUEUE_BYTES` ask for. Lower them |

The node retries every two seconds, so a fault you fix is picked up without a
restart.

## Nothing answers

**`STATUS` is `MODBUS_TIMEOUT` on every request.**

Work down this list. It is in the order that finds faults fastest.

**1. Look at `MODBUS_STATUS`.** If `CHECKSUM_ERRORS`, `FRAMING_ERRORS` and
`NOISE_BYTES` are **all flat** while `SENT` climbs, no bytes are arriving at
all. That is wiring, not protocol: wrong port, A and B swapped, transmit and
receive swapped, or the device is off. Stop reading this list and check the
wiring.

If any of them is climbing, bytes *are* arriving and you have a protocol or
signal-quality problem. Carry on.

**2. Baud rate and parity.** A mismatch produces a steady stream of
`CHECKSUM_ERRORS` — the bytes arrive, the maths does not agree. Note that
`MODBUS_PARITY_NONE` means **8N2**, which is what the specification requires
when parity is off. A device set to 8N1 needs `MODBUS_PARITY_NONE_8N1`.

**3. Unit id.** The commonest single mistake. Check `MODBUS_DEVICE.SILENT`:
**-1 means that unit id has never answered anything**, which is a wrong address
rather than a dead device.

**4. Termination and bias.** `NOISE_BYTES` climbing steadily on an idle bus is
a floating line. 120 Ω at each far end, and bias resistors somewhere.

**5. Is it RTU over TCP?** If you are on TCP and getting silence, it is very
likely a terminal server. Set `FRAMING := MODBUS_FRAMING_RTU`. See
[03 - The node block](03-the-node-block.md).

## The device answers but says no

**`STATUS` is `MODBUS_REFUSED`.**

**This is good news.** Frames are going out, arriving, being understood and
being answered. Everything below the application layer works. You are arguing
about an address or a function code.

| likely cause | |
| --- | --- |
| **the address is not in that device** | check the manual's map |
| **off-by-one** | many manuals number registers from 1 and the wire numbers them from 0. "Register 40001" is usually address 0 in the holding registers |
| **the wrong list** | address 40 in the holding registers is not address 40 in the input registers |
| **the function code is not supported** | an older device may implement FC 06 and not FC 16. Name `MODBUS_FC06_WRITE_SINGLE_REGISTER` |
| **too many at once** | some devices accept fewer than the specification's 125 registers. Read a smaller range |

## The values are nonsense

**A float reads `4.6e-41`, or `1.7e38`, or a huge negative number.**

The address is right and the word order is wrong. Try `MODBUS_ORDER_CDAB` if
you were on `ABCD`, or the other way round. See
[05 - Reading and writing](05-reading-and-writing.md).

**A number is right but a thousand times out.** The device is publishing in
different units, or with an implied decimal point. That is in its manual, not
on the wire.

**A signed value reads as a huge positive number.** A `WORD` holds 0 to 65535.
Use `WORD_TO_INT` for a signed one.

**Half the array is right and half is untouched.** A length mistake. Check
`COUNT` against what you expected — that pin exists for exactly this.

## Requests are refused before they go out

| `STATUS` | |
| --- | --- |
| `MODBUS_INVALID_ARGUMENT` | a zero count, a `LENGTH` past the end of the variable, a quantity past what one request may carry (2000 bits or 125 registers for a read), or a `BOOL` aimed at a register list |
| `MODBUS_DUPLICATE` | an identical request is already outstanding. **Not an error** — this is what stops a held `REQ` flooding the bus |
| `MODBUS_SUPERSEDED` | a newer write to the same address replaced this one. **Not an error** |
| `MODBUS_QUEUE_FULL` | you are asking faster than the bus can answer. Watch fewer things, or less often - or raise `MODBUS_CONFIG`'s `QUEUE` / `QUEUE_BYTES` if the bursts are expected |
| `MODBUS_LINK_DOWN` | on a block other than the node, the `NODE` pin has no started node behind it. Check `node.READY` and that the node is called first |

## Frames go missing on RS-485

**`FRAMING_ERRORS` climbing, or reads that work intermittently.**

Read `MODBUS_STATUS.FRAMING_REASON`. It says which rule the link is using and
why, in a sentence.

RTU ends a frame with three and a half character times of silence, and several
ordinary things destroy that silence:

- a **USB-to-RS-485 adapter**, which delivers bytes in clumps on its own
  schedule;
- a **virtual serial port**, which has no timing at all;
- a **busy PLC scan**, if the node's task is not fast enough.

If the node is not in a fast task of its own, put it there first — see
[10 - Scan rate](10-scan-rate.md). If the link genuinely cannot hold the timing,
`MODBUS_FRAMING_ASCII` removes the requirement entirely at the cost of twice
the bytes.

## A watched value stopped updating

**`QUALITY` is `MODBUS_QUALITY_BAD`.**

It was arriving and has stopped. Check `FAILURES` — one is a hiccup, ten is a
device that has gone — and `MODBUS_DEVICE.SILENT` for how long.

Note the backoff: a device that stops answering is retried progressively less
often, down to one attempt in sixteen, so that one dead unit does not consume
the segment. It will pick itself up when the device returns; it just will not
do it instantly.

**`QUALITY` is `MODBUS_QUALITY_UNKNOWN` and stays there.**

It has **never** arrived. That is not a running fault — it is a wrong address,
a wrong unit id, a wrong list, or a device that was never fitted. Check
`STATUS` on the watch block for which.

**`QUALITY` flickers to `MODBUS_QUALITY_UNCERTAIN`.**

The value is arriving late. Either `EVERY` is shorter than the bus can
manage, or the node's task is too slow, or there are too many watches. All
three are in [10 - Scan rate](10-scan-rate.md).

## A client cannot read my PLC

**`ROLE`** must be `MODBUS_ROLE_SERVER` or `MODBUS_ROLE_BOTH`.

**`SERIAL_UNIT_ID`** must match what the client is asking for — on serial. On TCP the
unit id does not matter.

**`MODBUS_MAP.BOUND`** must be `TRUE`. If it is `FALSE` with
`MODBUS_INVALID_ARGUMENT`, the variable and the list disagree: a `BOOL` in a
register list, a number in a coil list, an unwired `VALUE` pin, or an
`ARRAY [*]`, which is a view rather than a variable.

**The addresses** are where you said, from the array's lower bound. Check
`COUNT`.

## The failsafe never fires

`ON_LOSS` needs **`FAILSAFE` on a `MODBUS_CONFIG` block**. Without a silence to measure
there is no loss to act on, and the map block cannot tell you that because
nothing is wrong with it.

`MODBUS_RESET_TO_VALUE` applies to a **single value only** — a range has no one
safe value. Bind the few addresses that need a safe state individually.

Test it by pulling the cable and watching `SAFE_APPLIED`.

## It works on the Runtime and not on the board

**An `ANY` pin fed from a Global Variable List does not compile for a board.**
Move the variable into the POU that calls the block. See
[08 - Patterns](08-patterns.md).

**`MODBUS_ARDUINO` reports `MODBUS_INVALID_ARGUMENT` on the Runtime.** Every
pin on it describes hardware a board has and a Linux runtime does not. It says
so rather than doing nothing quietly.

**`MODBUS_ARDUINO_ETHERNET` says *"define MODBUS_ENABLE_ETHERNET to build
Ethernet in"*.** Installing the Arduino Ethernet library is not enough on its
own: the Arduino builder adds a user library to the include path only when it
**sees** a plain `#include` for it, and a header behind a conditional is
invisible to that scanner. Add `MODBUS_ENABLE_ETHERNET` to the project's build
flags and it compiles in.

**The node will not start and says *"set IP, or 'dhcp' to ask for one"*.** A
fixed address is required on WiFi and on Ethernet — see
[03 - The node block](03-the-node-block.md). Write `IP := 'dhcp'` if you
genuinely want a server-assigned one.

**Ethernet says *"no Ethernet controller found on SPI"*.** The shield or module
is not answering — usually the chip select pin, or it is not seated.

**Ethernet says *"Ethernet cable unplugged"*.** The controller is there and the
link is not. Ethernet is behind a build flag, because
compiling it in unconditionally breaks the link step on boards that have no
Ethernet at all.

**Serial goes nowhere on an ESP32-S3.** With USB CDC on boot, `Serial` is the
USB device and not a UART. The node falls back to `Serial0`, which is UART0.
Use `PORT := 1` or `PORT := 2` with `RX_PIN` and `TX_PIN` on a `MODBUS_ARDUINO`
block for a real port.

**Next:** [10 - Scan rate](10-scan-rate.md)

## STATUS says MODBUS_WRONG_TASK

The block is in a different task from its node. It does nothing until it is
moved: OpenPLC runs each task on a thread of its own, and a block in another
task would be inside the node while the node's own scan is. Move it into the
node's program, and hand your application the value through a global — see
[10 - Scan rate](10-scan-rate.md#the-one-rule).

