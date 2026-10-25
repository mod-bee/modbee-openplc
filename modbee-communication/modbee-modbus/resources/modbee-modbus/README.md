# ModBee Modbus

**Modbus that never blocks, and tells you the truth about what happened.**

RTU, ASCII and TCP. Client and server. Arduino, Linux, macOS and Windows, from
one source tree.

```cpp
#include <ModBeeModbus.h>

ModbusRTU mb;

void setup() {
    Serial1.begin(19200, SERIAL_8E1);
    mb.begin(&Serial1, 19200);
    mb.slave(17);                 // answer as unit 17
    mb.addHreg(40, &setpoint);    // this variable IS register 40
}

void loop() {
    mb.poll();                    // the whole contract
}
```

One object. One `poll()`. Your variables are the registers.

---

## Reading somebody else is the same object

```cpp
ModbusRTU mb;

uint16_t level    = 0;
uint16_t setpoint = 500;

void setup() {
    Serial1.begin(19200, SERIAL_8E1);
    mb.begin(&Serial1, 19200);
}

void loop() {
    mb.poll();

    mb.readIreg(17, 30, level);        // queues; `level` updates on a later poll
    mb.writeHreg(17, 40, setpoint);    // queues; only the value you settled on goes out
}
```

Call those every scan if you like. Nothing blocks, nothing stacks up, and
nothing is sent inside the call that made it.

---

## If you have used a Modbus library before

You know the shape. What is different is what happens between your call and the
wire.

| | Most libraries | ModBee |
| --- | --- | --- |
| A read | blocks until the answer or the timeout | queues and returns; the answer lands in your variable |
| The same read twice | two requests on the wire | the second is refused as `Duplicate` |
| A setpoint written every scan | a queue of every value you passed through | **only the value you settled on** — and whoever was waiting on a replaced write is *told* |
| A request that fails | returns an error, sometimes | **every accepted operation reaches exactly one conclusion** |
| A 32-bit float | you work out the word order | `mb.readFloat(17, 100, flow, ModbusOrder::CDAB)`, and `probeOrder()` when the data sheet does not say |
| A value that stops arriving | looks exactly like one that has not changed | `quality()` says `Good`, `Uncertain`, `Bad` or `Unknown` |
| RTU on Linux | splits frames, and nobody can say why | length framing by default; `framingReason()` explains the choice in a sentence |
| A gateway timing out | a timeout | **0x0A** "no route" or **0x0B** "the device is not there" — a client can tell them apart |

---

## Four objects, and that is the library

```cpp
ModbusRTU    mb;   // RS-485 or RS-232
ModbusASCII  mb;   // the same, for links that cannot hold RTU's timing
ModbusTCP    mb;   // Ethernet or WiFi, client or server
ModbusBridge b;    // TCP in front, a serial segment behind
```

Each is both roles at once if you want it to be — a device that answers a SCADA
system *and* reads three sensors of its own is one object, not two.

Nothing underneath is hidden. `mb.client()`, `mb.server()`, `mb.map()`,
`mb.link()` and `mb.poller()` stay public and reachable, so the day you need
something the short form does not offer, you reach past it without rewriting
what you already have.

---

## What it does for you

Between your call and the wire, with no configuration at all:

- **Stacks the work.** Operations queue as you make them. Nothing blocks and
  nothing is sent inside the call that made it.
- **Discards what is redundant.** Queue the same read twice and the second is
  refused. Write the same value twice and so is that.
- **Sends only the latest.** A control loop moving a setpoint faster than the
  bus can carry it sends the value it settled on. Whoever was waiting on the
  replaced write is told `Superseded`, not left hanging.
- **Concludes everything, exactly once.** Success, refusal, timeout, superseded,
  queue full — every accepted operation reaches one conclusion and one only.
  That is what lets you open a slot per request and never stall it.
- **Times itself.** The response timeout is measured per unit and includes the
  airtime the medium physically needs — so a slow VFD and a fast I/O block on
  one bus each get the timeout they deserve, and a 125-register read on a 9600
  line is not declared dead while it is still arriving.
- **Retries and reports.** With backoff and jitter, so two masters on one bus do
  not stay in step.

There is nothing to tune. `mb.timeout()` and `mb.retries()` exist so you *can*
pin something a segment demonstrably needs; an object opened with no
configuration at all is a fully working one.

---

## Knowing whether to believe a reading

A variable holding `1234` tells you nothing about whether `1234` is still true.
On a bus where one device has quietly failed, its last reading looks identical
to a healthy one.

```cpp
const size_t levelWatch = mb.watchIreg(17, 30, &level, 1, 500);   // said once

void loop() {
    mb.poll();

    if (mb.quality(levelWatch) == ModbusQuality::Good) control(level);
    else                                               holdSafeState();
}
```

`Unknown` (never read at all — a commissioning problem) and `Bad` (read once and
now stale — a running fault) are deliberately different answers. An alarm list
that conflates them sends somebody to the wrong end of the plant.

---

## Every common function code

| | | | |
| --- | --- | --- | --- |
| 0x01 Read Coils | 0x02 Read Discrete Inputs | 0x03 Read Holding Registers | 0x04 Read Input Registers |
| 0x05 Write Single Coil | 0x06 Write Single Register | 0x0F Write Multiple Coils | 0x10 Write Multiple Registers |
| 0x16 Mask Write Register | 0x17 Read/Write Multiple | 0x2B/0x0E Device Identification | 0x07 Read Exception Status |
| 0x08 Diagnostics | 0x0B Comm Event Counter | 0x0C Comm Event Log | 0x11 Report Server ID |

Every exception code too, including the two most libraries skip: **0x05
Acknowledge** ("accepted, poll — do not retry") and **0x06 Busy** ("retry
later"), which are different instructions and are reported as different results.

**0x16 Mask Write** is worth calling out: it is the only atomic
read-modify-write Modbus has. Without it, two clients setting different bits of
one register erase each other's.

---

## Install

**Arduino** — copy this repository into your `libraries` folder, or add it as a
ZIP library.

```cpp
#include <ModBeeModbus.h>
```

Needs a 32-bit board: ESP32, ESP8266, SAMD21, STM32, RP2040. A link costs about
2 KB of RAM before your own data, so the 8-bit AVR boards are out of reach.

**CMake**

```cmake
add_subdirectory(modbee-modbus)
target_link_libraries(my_app PRIVATE ModBee::modbus)
```

**Try it with no hardware**

```bash
cmake -S . -B build && cmake --build build -j
./build/examples/cpp/modbee_tcp_server 1502 &
./build/examples/cpp/modbee_tcp_client 127.0.0.1 1502
```

---

## Documentation

| | |
| --- | --- |
| [Getting started](docs/getting-started.md) | From nothing to a working device, in order |
| [Best practices](docs/best-practices.md) | How to keep a bus healthy, and why it matters |
| [Recipes](docs/recipes.md) | RTU over TCP, bridges, VFDs, control words, and the rest |
| [API](docs/api.md) | Every call, grouped by what you are trying to do |
| [Architecture](docs/ARCHITECTURE.md) | The five layers, and why each boundary is where it is |

## Examples

| | |
| --- | --- |
| `examples/arduino/RTU_Server` | A slave on RS-485, with failsafe |
| `examples/arduino/RTU_Client` | A master on RS-485 |
| `examples/arduino/TCP_Server` | An ESP32 serving several clients at once |
| `examples/arduino/TCP_Client` | An ESP32 reading a device |
| `examples/arduino/Polling_With_Quality` | Four sensors, and which readings to believe |
| `examples/cpp/tcp_server`, `tcp_client` | Host, TCP |
| `examples/cpp/rtu_server`, `rtu_client` | Host, serial |
| `examples/cpp/gateway` | TCP in front, a serial segment behind |

---

## Not for

Modbus TCP Security. Networks where you need more than 247 serial units.
Anything expecting Modbus to be real-time: it is a polled protocol and this
library does not pretend otherwise.

## Licence

See [LICENSE](LICENSE).

---

**Ask for the value. Get on with the application. Be told what happened.**
