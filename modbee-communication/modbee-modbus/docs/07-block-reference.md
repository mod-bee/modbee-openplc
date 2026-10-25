# 07 - Block reference

Every block, every pin. For what they are *for*, see
[04 - Being a device](04-being-a-device.md) and
[05 - Reading and writing](05-reading-and-writing.md).

Eleven function blocks: three you will always use, five you will use often, and three you place only when a default is not what you want.

Every block but `MODBUS_NODE` and `MODBUS_BRIDGE` takes the node on a `NODE`
in-out pin and returns `ERROR` and `STATUS`. **The pin must be assigned at
every call — leaving it out is a compile error.**

`MODBUS_BRIDGE` stands alone and takes no node, because a bridge is not a
client or a server: it is both ends of a wire.

---

## `MODBUS_NODE`

The link. Call it first, in a fast task of its own. **Eleven pins are the whole
of an ordinary link** — everything else lives on the three optional blocks
below, so it costs you nothing until you want it.

| input | type | |
| --- | --- | --- |
| `TRANSPORT` | `MODBUS_TRANSPORT` | where the bytes go |
| `ROLE` | `MODBUS_ROLE` | ask, answer, or both |
| `TCP_HOST` | `STRING(48)` | the device to connect to. **Empty means be a server** |
| `TCP_PORT` | `UINT` | 0 for 502 |
| `SERIAL_DEVICE` | `STRING(48)` | serial device, e.g. `/dev/ttyUSB0`. Runtime only |
| `SERIAL_BAUD` | `DINT` | 0 for 19200 |
| `SERIAL_PARITY` | `MODBUS_PARITY` | `EVEN` is the Modbus default |
| `SERIAL_UNIT_ID` | `BYTE` | the address this node answers to on a serial line, 1..247. **Serial server only** — a TCP server answers whatever unit id is asked for |
| `RESET_STATS` | `BOOL` | rising edge zeroes the counters `MODBUS_STATUS` reports |
| `CONNECT` | `BOOL` | `TRUE` by default. Drop it to release the port |

**The prefix says which transport a pin belongs to**, and a pin for a transport
you are not using is ignored. `SERIAL_UNIT_ID` is the one people expect to need
on TCP and do not.

| output | type | |
| --- | --- | --- |
| `READY` | `BOOL` | the link is open |
| `CONNECTED` | `BOOL` | something is at the other end; for a server, that it is listening |
| `CLIENTS` | `INT` | clients connected. TCP server only |
| `ERROR` | `BOOL` | it did not open, or has since failed |
| `STATUS` | `MODBUS_RESULT` | why |
| `LAST_ERROR` | `STRING(64)` | the operating system's own words |

**The node waits one scan before opening**, so a helper below may sit anywhere
in the same program — above or below. That is one millisecond of a fast task,
and it removes a placement rule nobody would remember.

---

## `MODBUS_CONFIG` — optional

Tuning. Place it only where a default is not what you want.

| input | type | |
| --- | --- | --- |
| `FRAMING` | `MODBUS_FRAMING` | how frames are found. `AUTO` reads RTU on a serial line and MBAP on a socket. **The pin for a converter** |
| `TIMEOUT` | `DINT` | **0 measures it per device**, which is almost always better than a figure you pick |
| `RETRIES` | `BYTE` | attempts after the first. 0 takes the library's |
| `FAILSAFE` | `DINT` | silence that counts as losing the client. 0 disables. Needed before `MODBUS_MAP`'s `ON_LOSS` does anything |
| `MAX_CLIENTS` | `BYTE` | clients a TCP server holds at once. 0 for eight on the Runtime, two on a board. No ceiling of its own; too many for the board's memory stops the node with *"out of memory for MAX_CLIENTS connections"* |
| `QUEUE` | `UINT` | requests that may wait at once. 0 for 16 on a board, 64 on the Runtime |
| `QUEUE_BYTES` | `UINT` | bytes the waiting requests' values share. 0 for 1024 on a board, 16192 on the Runtime. Too much for the board stops the node with *"out of memory for the request queue"* |
| `IDLE` | `DINT` | close an unused connection. 0 for 60000, -1 never |
| `RECONNECT` | `DINT` | how often to retry a dropped link. **Already on** — 0 takes the library's two seconds; -1 turns recovery off |

| output | type | |
| --- | --- | --- |
| `APPLIED` / `ERROR` / `STATUS` | | whether the settings reached the node |

**Automatic recovery is already on and needs no block.** A link that drops is
retried every two seconds until it returns, and every watched value is made due
the moment it does. `RECONNECT` only paces that differently, or turns it off.

**Assign `TIMEOUT` even when you want the default.** It is the first pin, and
the editor reports a block whose first input is never assigned. `TIMEOUT := 0`
says "I have thought about the timeout and I want the measured one", which is
worth saying on a tuning block.

---

## `MODBUS_IDENTITY` — optional

What this node answers function code 43 with.

| input | type | |
| --- | --- | --- |
| `VENDOR` / `PRODUCT` / `REVISION` | `STRING(32)` | its nameplate |

| output | type | |
| --- | --- | --- |
| `APPLIED` / `ERROR` / `STATUS` | | whether it reached the node |

Worth setting on anything somebody else will commission: six identical-looking
nodes on one segment are six nodes you can only tell apart by asking.

---

## `MODBUS_ARDUINO` — optional, boards only

The pins only a board has. On the Runtime it reports
`MODBUS_INVALID_ARGUMENT` rather than doing nothing quietly.

| input | type | |
| --- | --- | --- |
| `PORT` | `BYTE` | hardware serial port number |
| `RX_PIN` / `TX_PIN` | `INT` | -1 for the board's own. ESP32 only |
| `DE_PIN` | `INT` | RS-485 driver enable, -1 if the board wires it |
| `DE_HOLD` | `DINT` | hold after the last byte. 0 for two character times |
| `SSID` | `STRING(48)` | WiFi network |
| `PASSWORD` | `STRING(63)` | WiFi passphrase, up to 63 characters (the WPA2 maximum) |
| `MAC` | `STRING(32)` | Ethernet. Empty takes a built-in default — a collision the moment there are two |
| `IP` | `STRING(32)` | **required** on WiFi and Ethernet. `'dhcp'` asks a server instead |
| `GATEWAY` | `STRING(32)` | empty derives it from `IP`, ending `.1` |
| `SUBNET` | `STRING(32)` | empty uses `255.255.255.0` |

| output | type | |
| --- | --- | --- |
| `APPLIED` / `ERROR` / `STATUS` | | whether the settings reached the node |

---

---

## `MODBUS_MAP`

Your variables at Modbus addresses. No request pin: once bound, the variable
**is** the register.

| input | type | |
| --- | --- | --- |
| `TABLE` | `MODBUS_TABLE` | which of the four lists |
| `ADDRESS` | `UINT` | the first address |
| `ON_LOSS` | `MODBUS_FAILSAFE` | what a writable address does when the client stops. Needs `FAILSAFE` on the node |
| `SAFE_VALUE` | `DINT` | what `MODBUS_RESET_TO_VALUE` goes to. Single values only |
| `VALUE` | `ANY` | the variable to bind. Single value or fixed-bounds array |

| output | type | |
| --- | --- | --- |
| `BOUND` | `BOOL` | the addresses are live |
| `COUNT` | `UINT` | how many addresses were taken |
| `WRITTEN` | `BOOL` | one scan, when a client wrote any of them |
| `SAFE_APPLIED` | `BOOL` | one scan, when the safe state was applied |
| `ERROR` | `BOOL` | why not |
| `STATUS` | `MODBUS_RESULT` | why |

---

## `MODBUS_READ`

Reads a device, on a rising edge of `REQ`.

| input | type | |
| --- | --- | --- |
| `REQ` | `BOOL` | rising edge reads. Holding it high is safe |
| `UNIT` | `BYTE` | the device's address, 1..247 |
| `FC` | `MODBUS_READ_FC` | which read, named as the manual names it |
| `ADDRESS` | `UINT` | the first address on that device |
| `LENGTH` | `UINT` | **0 means "as many as are in the variable"**, which is almost always right |
| `ORDER` | `MODBUS_ORDER` | how a 32- or 64-bit value is laid out. Ignored for `BOOL` and `WORD` |
| `VALUE` | `ANY` | the variable to read into |

| output | type | |
| --- | --- | --- |
| `BUSY` | `BOOL` | a level: the request is outstanding |
| `DONE` | `BOOL` | one scan, when the answers arrived |
| `COUNT` | `UINT` | how many addresses were moved |
| `ERROR` | `BOOL` | one scan, when they did not |
| `STATUS` | `MODBUS_RESULT` | why |

---

## `MODBUS_WRITE`

Writes a device, on a rising edge of `REQ`.

| input | type | |
| --- | --- | --- |
| `REQ` | `BOOL` | rising edge writes |
| `UNIT` | `BYTE` | the device's address. **0 broadcasts**, and nobody answers |
| `FC` | `MODBUS_WRITE_FC` | `MODBUS_FC_AUTO` picks it from what you passed |
| `ADDRESS` | `UINT` | the first address |
| `LENGTH` | `UINT` | 0 means "as many as are in the variable" |
| `ORDER` | `MODBUS_ORDER` | word order for values wider than a register |
| `AND_MASK` / `OR_MASK` | `WORD` | for `MODBUS_FC22_MASK_WRITE_REGISTER` only |
| `VALUE` | `ANY` | the variable to write from |

| output | type | |
| --- | --- | --- |
| `BUSY` | `BOOL` | the request is outstanding |
| `DONE` | `BOOL` | one scan, when the device confirmed it |
| `COUNT` | `UINT` | how many addresses were written |
| `ERROR` | `BOOL` | one scan, when it did not |
| `STATUS` | `MODBUS_RESULT` | why |

---

## `MODBUS_WATCH`

A repeating read, with a quality. Never touches the wire itself.

| input | type | |
| --- | --- | --- |
| `UNIT` | `BYTE` | the device's address. May change while running |
| `FC` | `MODBUS_READ_FC` | which read. May change while running |
| `ADDRESS` | `UINT` | the first address. May change while running |
| `EVERY` | `TIME` | how often. `T#1s` if left at `T#0s`. **`QUALITY` is judged against this** |
| `LENGTH` | `UINT` | 0 means "as many as are in the variable". Fixed at the first call |
| `ORDER` | `MODBUS_ORDER` | word order. May change while running |
| `DEADBAND` | `UINT` | how far the value must move to count as a change |
| `ENABLE` | `BOOL` | `TRUE` by default. Stops and starts in place |
| `VALUE` | `ANY` | the variable to keep up to date. Fixed at the first call |

| output | type | |
| --- | --- | --- |
| `WATCHING` | `BOOL` | the watch is running |
| `COUNT` | `UINT` | how many addresses it covers |
| `QUALITY` | `MODBUS_QUALITY` | how much to believe `VALUE` right now |
| `SEEN` | `BOOL` | a value has arrived at least once |
| `AGE` | `TIME` | since it last arrived, `T#0s` if it never has (`SEEN` tells which) |
| `FAILURES` | `UINT` | reads that failed in a row |
| `ERROR` | `BOOL` | could not be set up, or its last read failed |
| `STATUS` | `MODBUS_RESULT` | why |

A new `UNIT`, `FC`, `ADDRESS` or `ORDER` re-aims the same watch: `QUALITY` goes
back to `UNKNOWN` and the next read goes to the new place.

## `MODBUS_POINT`

One value on a device, defined entirely by settings: read and re-read from its
pins every scan. See [11 - Points from settings](11-points-from-settings.md).

| input | type | |
| --- | --- | --- |
| `UNIT` | `BYTE` | the device's address |
| `FC` | `MODBUS_PT_FC` | FC01..FC04 to read, FC05 / FC06 / FC16 to write |
| `ADDRESS` | `UINT` | the register or coil |
| `DTYPE` | `MODBUS_PT_TYPE` | `BIT`, `INT16`, `UINT16`, `INT32`, `UINT32`, `FLOAT32`, `REG_BIT` |
| `ORDER` | `MODBUS_ORDER` | word order of a 32-bit value |
| `BIT` | `USINT` | `REG_BIT` only: which bit, 0..15 |
| `SCALE` | `REAL` | value = raw × `SCALE` + `OFFSET`. 1.0 by default |
| `OFFSET` | `REAL` | |
| `EVERY` | `TIME` | how often to read, or to send a write again. `T#1s` if `T#0s` |
| `STALE` | `TIME` | no good answer this long = lost (`BAD`). `T#0s`: 3 × `EVERY` |
| `TIMEOUT` | `TIME` | this device's answer time limit (radio: a few seconds). `T#0s`: measured |
| `WRITE_VALUE` | `REAL` | write points: the value, in engineering units |
| `ENABLE` | `BOOL` | `TRUE` by default. `FALSE` = not fitted: never asked, never ok |

| output | type | |
| --- | --- | --- |
| `VALUE` | `REAL` | engineering units. The last good value is held while not ok |
| `Q` | `BOOL` | `VALUE <> 0`, for a bit |
| `OK` | `BOOL` | good or a little late. `FALSE` before the first answer and once lost |
| `QUALITY` | `MODBUS_QUALITY` | `UNKNOWN` never answered, `GOOD`, `UNCERTAIN` late, `BAD` lost |
| `AGE` | `TIME` | since the last good answer |
| `FAILURES` | `UINT` | failed attempts in a row |
| `ERROR` | `BOOL` | the last attempt failed, or the settings cannot work |
| `STATUS` | `MODBUS_RESULT` | why. `MODBUS_INVALID_ARGUMENT` for settings that cannot work |

## `MODBUS_POINTS`

The same, as a table: one block for every point on the bus.

| in-out | type | |
| --- | --- | --- |
| `NODE` | `MODBUS_NODE` | which node |
| `SETTINGS` | `ARRAY OF MODBUS_PT_CFG` | one row a point. Retain it |
| `POINTS` | `ARRAY OF MODBUS_PT_STS` | what each row is doing. Do not retain it |

| input | type | |
| --- | --- | --- |
| `RUN` | `BOOL` | `TRUE` by default. `FALSE` stops asking |

| output | type | |
| --- | --- | --- |
| `GOOD_COUNT` | `INT` | enabled rows that are ok |
| `LOST_COUNT` | `INT` | enabled rows that are not |
| `FIRST_LOST` | `INT` | the first such row, 0 when none |
| `ERROR` | `BOOL` | `LOST_COUNT > 0` |
| `STATUS` | `MODBUS_RESULT` | the first lost row's result |
| `STATUS_TEXT` | `STRING(30)` | `pt 3 unit 5 lost`, `pt 2 unit 9 no answer`, `pt 4 bad settings` |

`MODBUS_PT_CFG` (settings): `unit`, `fc`, `address`, `dtype`, `order`, `bit`,
`scale` (1.0), `offset`, `every` (`T#1s`), `stale`, `timeout`, `enable` (TRUE).

`MODBUS_PT_STS`: `w` (your logic: the value to write), and the status `v`, `q`,
`ok`, `quality`, `age`, `failures`, `result`.

---

## `MODBUS_STATUS`

How the link is doing. **No inputs**: it reports and changes nothing.

| output | type | |
| --- | --- | --- |
| `CONNECTED` | `BOOL` | there is something at the other end |
| `CLIENTS` | `INT` | clients connected, for a server |
| `PENDING` | `INT` | requests queued and not yet concluded |
| `SENT` / `RECEIVED` | `DINT` | frames, both directions |
| `CHECKSUM_ERRORS` | `DINT` | the bytes arrived and the maths did not agree |
| `FRAMING_ERRORS` | `DINT` | structurally impossible frames |
| `NOISE_BYTES` | `DINT` | discarded while hunting for a frame start |
| `FRAMING_REASON` | `STRING(160)` | how this link finds frames, and why, in a sentence |
| `ERROR` | `BOOL` | no such node |
| `STATUS` | `MODBUS_RESULT` | why |

---

## `MODBUS_DEVICE`

How one device is doing. Free while `POLL` is 0 — it reads the traffic your
program already makes and sends nothing. **Which means a device nobody asks
anything reads as not answering**: give `POLL` to a device this block is the
only thing pointed at.

| input | type | |
| --- | --- | --- |
| `UNIT` | `BYTE` | the device's address |
| `IDENTIFY` | `BOOL` | rising edge asks for its nameplate. Once is enough |
| `POLL` | `DINT` | ask this device whether it is alive, this often. **0 watches only the traffic you already make** — which answers nothing about a device nobody talks to |
| `GONE` | `DINT` | silence before `ANSWERING` drops. 0 uses 5000 |

| output | type | |
| --- | --- | --- |
| `ANSWERING` | `BOOL` | it has answered within `GONE` |
| `SILENT` | `DINT` | since it last answered, or **-1 if it never has** |
| `ROUND_TRIP` | `DINT` | how long it takes to reply, measured |
| `VENDOR` / `PRODUCT` / `REVISION` | `STRING(32)` | its nameplate |
| `IDENTIFIED` | `BOOL` | one scan, when the nameplate arrived |
| `ERROR` | `BOOL` | no such node, or the nameplate could not be read |
| `STATUS` | `MODBUS_RESULT` | why |

---

## `MODBUS_BRIDGE`

TCP clients in front, a serial segment behind. Takes no `NODE`; put it in the
fast task a node would go in.

| input | type | |
| --- | --- | --- |
| `SERIAL_DEVICE` | `STRING(48)` | the serial device behind. Runtime only |
| `SERIAL_BAUD` | `DINT` | 0 for 19200 |
| `SERIAL_PARITY` | `MODBUS_PARITY` | `EVEN` is the Modbus default |
| `PORT` / `RX_PIN` / `TX_PIN` | `BYTE` / `INT` | board only |
| `DE_PIN` / `DE_HOLD` | `INT` / `DINT` | RS-485 driver enable |
| `TCP_PORT` | `UINT` | the port clients connect to. 0 for 502 |
| `FIRST_UNIT` / `LAST_UNIT` | `BYTE` | the unit ids out on the segment |
| `MAX_CLIENTS` | `BYTE` | clients at once. 0 for eight on the Runtime, two on a board. No ceiling of its own |
| `MAX_PENDING` | `BYTE` | transactions outstanding on the serial bus. 0 for 8 |
| `PASS_OTHERS` | `BOOL` | forward anything not routed, instead of refusing it |
| `CONNECT` | `BOOL` | `TRUE` by default |

| output | type | |
| --- | --- | --- |
| `READY` | `BOOL` | both ends are open |
| `CLIENTS` | `INT` | clients connected |
| `FORWARDED` | `DINT` | requests sent to the serial segment |
| `NO_PATH` | `DINT` | refused: we have no route. **Our** problem |
| `NO_DEVICE` | `DINT` | refused: the device did not answer. **Its** problem |
| `FRAMING_REASON` | `STRING(160)` | how the serial segment finds frames |
| `ERROR` | `BOOL` | it did not open |
| `STATUS` | `MODBUS_RESULT` | why |
| `LAST_ERROR` | `STRING(64)` | in words |

---

## The enumerations

| type | values |
| --- | --- |
| `MODBUS_TRANSPORT` | `MODBUS_RUNTIME_SERIAL`, `MODBUS_RUNTIME_TCP`, `MODBUS_ARDUINO_SERIAL`, `MODBUS_ARDUINO_WIFI`, `MODBUS_ARDUINO_ETHERNET` |
| `MODBUS_FRAMING` | `MODBUS_FRAMING_AUTO`, `MODBUS_FRAMING_RTU`, `MODBUS_FRAMING_ASCII`, `MODBUS_FRAMING_TCP` |
| `MODBUS_ROLE` | `MODBUS_ROLE_CLIENT`, `MODBUS_ROLE_SERVER`, `MODBUS_ROLE_BOTH` |
| `MODBUS_PARITY` | `MODBUS_PARITY_EVEN`, `MODBUS_PARITY_ODD`, `MODBUS_PARITY_NONE` (8N2), `MODBUS_PARITY_NONE_8N1` |
| `MODBUS_TABLE` | `MODBUS_COILS`, `MODBUS_DISCRETE_INPUTS`, `MODBUS_HOLDING_REGISTERS`, `MODBUS_INPUT_REGISTERS` |
| `MODBUS_READ_FC` | `MODBUS_FC01_READ_COILS`, `MODBUS_FC02_READ_DISCRETE_INPUTS`, `MODBUS_FC03_READ_HOLDING_REGISTERS`, `MODBUS_FC04_READ_INPUT_REGISTERS` |
| `MODBUS_WRITE_FC` | `MODBUS_FC_AUTO`, `MODBUS_FC05_WRITE_SINGLE_COIL`, `MODBUS_FC06_WRITE_SINGLE_REGISTER`, `MODBUS_FC15_WRITE_MULTIPLE_COILS`, `MODBUS_FC16_WRITE_MULTIPLE_REGISTERS`, `MODBUS_FC22_MASK_WRITE_REGISTER` |
| `MODBUS_ORDER` | `MODBUS_ORDER_ABCD`, `MODBUS_ORDER_CDAB`, `MODBUS_ORDER_BADC`, `MODBUS_ORDER_DCBA` |
| `MODBUS_QUALITY` | `MODBUS_QUALITY_UNKNOWN`, `MODBUS_QUALITY_GOOD`, `MODBUS_QUALITY_UNCERTAIN`, `MODBUS_QUALITY_BAD` |
| `MODBUS_FAILSAFE` | `MODBUS_HOLD_LAST_VALUE`, `MODBUS_RESET_TO_VALUE` |
| `MODBUS_PT_FC` | `MODBUS_PT_FC01_READ_COILS`, `MODBUS_PT_FC02_READ_DISCRETE_INPUTS`, `MODBUS_PT_FC03_READ_HOLDING_REGISTERS`, `MODBUS_PT_FC04_READ_INPUT_REGISTERS`, `MODBUS_PT_FC05_WRITE_COIL`, `MODBUS_PT_FC06_WRITE_REGISTER`, `MODBUS_PT_FC16_WRITE_REGISTERS` |
| `MODBUS_PT_TYPE` | `MODBUS_PT_BIT`, `MODBUS_PT_INT16`, `MODBUS_PT_UINT16`, `MODBUS_PT_INT32`, `MODBUS_PT_UINT32`, `MODBUS_PT_FLOAT32`, `MODBUS_PT_REG_BIT` |
| `MODBUS_RESULT` | see [06 - Diagnostics](06-diagnostics.md) |

## Not in this version

**FC 23, read/write multiple registers.** It needs a second buffer and a second
address, which would leave four pins dead on every ordinary write. Use a write
followed by a read.

**FC 43 as a general call.** It appears as the identity outputs on
`MODBUS_DEVICE` instead, which is what anybody actually wants from it.

**Next:** [08 - Patterns](08-patterns.md)
