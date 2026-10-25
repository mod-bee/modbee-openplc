# 07 - Block reference

Every block, every pin. For what they are *for*, see
[04 - Registers](04-registers.md) and [05 - Topics](05-topics.md).

Thirteen function blocks.

Every block but `BEEBUS_NODE` itself takes the node on a `NODE` in-out pin and returns
`ERROR` and `STATUS`. The pin must be assigned at every call — leaving it out
is a compile error.

---

## `BEEBUS_NODE`

Starts the node. Call it before any other BeeBus block. `TRANSPORT` picks the
family, and pins the other family uses are ignored.

| input | type | |
| --- | --- | --- |
| `NODE_ID` | `BYTE` | 1..254, unique on the network |
| `TRANSPORT` | `BEEBUS_NODE_LINK` | which link, and which family |
| `FAILSAFE` | `BOOL` | enable safe states on this node |
| `CONNECT` | `BOOL` | `TRUE` by default. Drop it to leave the ring |
| `QUEUE` | `USINT` | requests (and answers) that can wait for the token at once, 1..255; 0 = 16 on a board, 50 on the Runtime. About 300 bytes of RAM each. Raise it on the answering node too: answers past its depth are lost |

Runtime transports — `BEEBUS_NODE_RUNTIME_UDP`, `BEEBUS_NODE_RUNTIME_SERIAL`:

| input | type | |
| --- | --- | --- |
| `DEVICE` | `STRING(32)` | serial device, e.g. `/dev/ttyUSB0` |
| `BAUD` | `DINT` | 0 for the transport's default |
| `GROUP` | `STRING(32)` | multicast group, empty for the protocol's own |
| `UDP_PORT` | `UINT` | 0 for the protocol's own |
| `TTL` | `BYTE` | multicast hops. 1 keeps it on this subnet |
| `IFACE` | `STRING(32)` | interface address to send from |

Arduino transports — `BEEBUS_NODE_ARDUINO_SERIAL`, `BEEBUS_NODE_ARDUINO_WIFI`,
`BEEBUS_NODE_ARDUINO_ETHERNET` — take `BAUD` and `GROUP` / `UDP_PORT` here, and
the board's own settings (port, pins, WiFi, Ethernet) on
[`BEEBUS_ARDUINO`](#beebus_arduino).

| output | type | |
| --- | --- | --- |
| `READY` | `BOOL` | the node started |
| `CONNECTED` | `BOOL` | in the ring with at least one other node |
| `LINK` | `BOOL` | WiFi or Ethernet link is up (Arduino transports) |
| `ERROR` | `BOOL` | did not start, or has stood down |
| `STATUS` | `BEEBUS_RESULT` | why |
| `LAST_ERROR` | `STRING(80)` | what failed, in the operating system's own words, or which setting is wrong |
| `ATTEMPTS` | `UDINT` | opens tried so far |
| `RETRY_IN` | `TIME` | while a failed open waits, how long until the next try |

A failed open (`BEEBUS_NOT_INITIALISED`) is tried again after 1 s, 2, 4, 8, 16,
then every 30 s, until it opens. A wrong setting (`BEEBUS_INVALID_ARGUMENT`) is
reported once and not retried.

---

## `BEEBUS_ARDUINO`

The settings only a board has. Optional, and ignored entirely on the Runtime.
Put it in the same program as the node, above or below it.

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `PORT` | `BYTE` | hardware serial port, 0 for the first (`Serial`), 1 for `Serial1` |
| `RX_PIN` / `TX_PIN` | `INT` | receive / transmit pin, -1 for the board's own. ESP32 only |
| `WIFI_SSID` | `STRING(32)` | the WiFi network (`BEEBUS_NODE_ARDUINO_WIFI`) |
| `PASSWORD` | `STRING(63)` | its passphrase, up to 63 characters (the WPA2 maximum) |
| `MAC` | `STRING(32)` | six hex bytes, e.g. `DE:AD:BE:EF:FE:ED` (Ethernet). Empty takes a built-in default: fine for one device on a network, a collision with two |
| `IP` | `STRING(32)` | a fixed address (Ethernet). Empty asks DHCP, which blocks while it waits |

| output | type | |
| --- | --- | --- |
| `APPLIED` | `BOOL` | the settings reached the node |
| `ERROR` / `STATUS` | | they did not, and why |

```
board( NODE := node, PORT := 1, RX_PIN := 18, TX_PIN := 17 );
wifi ( NODE := node, WIFI_SSID := 'plant', PASSWORD := 'secret' );
```

---

## `BEEBUS_NODE_STATUS`

This node and its segment. Nothing here is a setting.

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `DEBUG_ENABLE` | `BOOL` | print the protocol's debug lines. Read once at start-up. On a Node, only in a firmware built with `BEEBUS_ENABLE_DEBUG` |

| output | type | |
| --- | --- | --- |
| `CONNECTED` | `BOOL` | in a ring |
| `NODE_ID` | `BYTE` | its own address |
| `MEMBERS` | `BYTE` | nodes in the ring, including this one |
| `ROTATION` | `TIME` | measured time for a turn to come round, `T#0s` until it has |
| `PENDING_OPS` | `INT` | queued and unfinished |
| `CRC_ERRORS` | `DINT` | frames that arrived corrupt |
| `NOISE_BYTES` | `DINT` | bytes discarded hunting for a frame start |
| `ERROR` / `STATUS` | | no such node |

---

## `BEEBUS_NODE_PEER_STATUS`

One peer.

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `PEER` | `BYTE` | which peer |

| output | type | |
| --- | --- | --- |
| `ALIVE` | `BOOL` | in the ring and being heard from |
| `SEEN` | `BOOL` | heard from at least once since the program started. `SEEN` FALSE is a peer never fitted or given the wrong id; `SEEN` TRUE with `ALIVE` FALSE is one that has gone |
| `SILENT` | `TIME` | since it last said anything |
| `HOP` | `TIME` | measured time it takes to take its turn |
| `HOP_TIMEOUT` | `TIME` | how long it is allowed before its turn is presumed lost |
| `ERROR` / `STATUS` | | no such node |

---

## `BEEBUS_TP_TOPIC`

A topic this node owns. No request pin — the node publishes it on its own.

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `NAME` | `STRING(254)` | up to 253 characters, the identity |
| `TOPIC_ID` | `UINT` | 1..32767, unique on this node |
| `VALUE` | `ANY` | the variable. Its declared type is the wire type |

| output | type | |
| --- | --- | --- |
| `BOUND` | `BOOL` | registered on the node |
| `ERROR` / `STATUS` | | no such node, a type the wire cannot carry, or an ID already bound |

Types: `BOOL`, `SINT`, `USINT`, `BYTE`, `INT`, `UINT`, `WORD`, `DINT`, `UDINT`,
`DWORD`, `LINT`, `ULINT`, `LWORD`, `REAL`, `LREAL`, `LTIME` (`LINT` ns),
`STRING`. `WSTRING` is `BEEBUS_INVALID_ARGUMENT`.

---

## `BEEBUS_TP_SUBSCRIBE`

Binds a peer's topic and asks for a stream of it.

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `PEER` | `BYTE` | who owns the topic |
| `NAME` | `STRING(254)` | as the owner bound it |
| `TOPIC_ID` | `UINT` | as the owner bound it |
| `DEADBAND` | `REAL` | how far it must move to be sent. 0 = every change |
| `PERIOD` | `TIME` | longest gap even with no change |
| `RELIABLE` | `BOOL` | `TRUE` for a setting: every change, losses sent again. `FALSE` (default): LIVE |
| `VALUE` | `ANY` | where arriving values land |

| output | type | |
| --- | --- | --- |
| `QUALITY` | `BEEBUS_TP_QUALITY` | `BEEBUS_TP_GOOD` / `BEEBUS_TP_UNCERTAIN` / `BEEBUS_TP_BAD` / `BEEBUS_TP_UNKNOWN` |
| `SEEN` | `BOOL` | a value has arrived at least once |
| `AGE` | `TIME` | since the last one. `T#0s` until one ever arrives |
| `NEW_VALUE` | `BOOL` | one scan, when one arrived |
| `MISSED` | `UDINT` | running total of updates that went astray |
| `ERROR` / `STATUS` | | |

---

## `BEEBUS_TP_STRUCT`

A whole `STRUCT` as topics this node owns, one per member. No request pin.

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `VALUE` | `ANY` | the `STRUCT`, or an `ARRAY` of `STRUCT`s or simple values |
| `TOPIC_ID` | `UINT` | the first member's id; member *k* (from 0) is `TOPIC_ID` + *k* |
| `PREFIX` | `STRING(16)` | in front of every member's name. Empty for none; names an `ARRAY` |
| `WRITABLE` | `BOOL` | peers may write the members (settings, commands); taken on the first scan |
| `PULSE` | `TIME` | `WRITABLE` only: a `BOOL` member written TRUE goes back to FALSE this long after. `T#0s`: kept |
| `SETTLE` | `TIME` | `WRITABLE` only: a write that asks for a result is read back after one scan plus this long |

| output | type | |
| --- | --- | --- |
| `BOUND` | `BOOL` | every member is registered |
| `COUNT` | `UINT` | how many topics |
| `WRITTEN` | `BOOL` | one scan, when peers' writes were taken |
| `WRITTEN_COUNT` | `UINT` | how many members that scan (held) |
| `WRITTEN_NAME` | `STRING(64)` | the first of them (held) |
| `WRITTEN_INDEX` | `UINT` | its position from 1 (held) |
| `WRITTEN_BY` | `BYTE` | the node that wrote it (held) |
| `LOST` | `UDINT` | writes dropped (a member written more than 4 times between two scans) |
| `ERROR` / `STATUS` | | |
| `LAST_ERROR` | `STRING(80)` | which member was refused, and why |

With `WRITABLE` a peer's write is queued by the node and taken in this block's
scan, one per member a scan, oldest first (as Sparkplug `WRITABLE`). The queue
is sized from the program: a waiting write for every `WRITABLE` member at once
(at least 32). Any number of `WRITABLE` `STRUCT`s, on any number of nodes; every
`BOOL` member can be a momentary command (`PULSE`) at the same time.

Names: the member path, `hmi.systemMode`, `spare[1]` (position from 1), at
most 255 characters, `PREFIX` included. An `ARRAY` on `VALUE` is named from the
element on: `PREFIX` `'alarms'` gives `alarms[3].set.prot.delay`. Types as `BEEBUS_TP_TOPIC`, plus `TIME`/`TOD` (`DINT` ms)
and `DT`/`DATE` (`UDINT` seconds since 1970).

---

## `BEEBUS_TP_STRUCT_SUBSCRIBE`

A peer's `BEEBUS_TP_STRUCT`, into a `STRUCT` of the same type.

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `VALUE` | `ANY` | your `STRUCT` (or `ARRAY`), the same type as the peer's |
| `PEER` | `BYTE` | who owns the topics |
| `TOPIC_ID` | `UINT` | as the owner gave it |
| `PREFIX` | `STRING(16)` | as the owner gave it |
| `DEADBAND` | `REAL` | 0 = every change (right for mixed members) |
| `PERIOD` | `TIME` | longest gap even with no change |
| `RELIABLE` | `BOOL` | `TRUE` for settings: every change of every member, losses sent again. `FALSE` (default): LIVE |

| output | type | |
| --- | --- | --- |
| `COUNT` | `UINT` | how many members |
| `QUALITY` | `BEEBUS_TP_QUALITY` | the worst member; `BEEBUS_TP_UNKNOWN` while any has never arrived |
| `SEEN` | `BOOL` | every member has arrived |
| `AGE` | `TIME` | since the oldest member's last value |
| `NEW_VALUE` | `BOOL` | one scan, when members arrived |
| `NEW_COUNT` | `UINT` | how many on that scan |
| `NEW_NAME` | `STRING(64)` | the first of them (held) |
| `NEW_INDEX` | `UINT` | its position, from 1 (held) |
| `MISSED` | `UDINT` | running total, all members |
| `ERROR` / `STATUS` | | |
| `LAST_ERROR` | `STRING(80)` | which member was refused, and why |

---

## `BEEBUS_TP_WRITE`

Writes one value into a topic a peer owns (a `WRITABLE` member), on a rising
edge of `REQ`.

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `REQ` | `BOOL` | rising edge writes |
| `PEER` | `BYTE` | the node that owns the topic |
| `TOPIC_ID` | `UINT` | the topic's id on that node |
| `CONFIRMED` | `BOOL` | retry until acknowledged; applied once (RELIABLE for a one-off write) |
| `WANT_RESULT` | `BOOL` | wait for the owner's decision; makes it `CONFIRMED` |
| `VALUE` | `ANY` | one value of the member's type (a `TIME` member takes `DINT` milliseconds) |

| output | type | |
| --- | --- | --- |
| `BUSY` | `BOOL` | waiting on the acknowledgement (and the decision) |
| `DONE` | `BOOL` | one scan, when it went / was acknowledged / was decided |
| `ERROR` / `STATUS` | | `BEEBUS_REFUSED`: the topic is read only; `BEEBUS_TIMEOUT`: no decision came back |
| `RESULT` | `BEEBUS_TP_OUTCOME` | the decision (held) |
| `ACCEPTED` | `BOOL` | kept as written (held) |
| `REFUSED` | `BOOL` | the owner kept another value: `CHANGED` or `REFUSED` (held) |
| `KEPT_VALUE` | `LREAL` | the owner's value with the decision (held) |

---

## `BEEBUS_TP_PUBLISH`

Owns a topic and sends it on a rising edge of `REQ`.

| input | type | |
| --- | --- | --- |
| `REQ` | `BOOL` | rising edge sends |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `NAME` | `STRING(254)` | up to 253 characters |
| `TOPIC_ID` | `UINT` | |
| `MODE` | `BEEBUS_TP_SEND` | `BEEBUS_TP_PUBLISH_ALL` or `BEEBUS_TP_PUBLISH_TO` |
| `PEER` | `BYTE` | the node to send to, when `BEEBUS_TP_PUBLISH_TO` |
| `CONFIRMED` | `BOOL` | retry until acknowledged. Only with `BEEBUS_TP_PUBLISH_TO` |
| `VALUE` | `ANY` | the variable |

| output | type | |
| --- | --- | --- |
| `BOUND` | `BOOL` | the topic is registered |
| `BUSY` | `BOOL` | waiting on the acknowledgement. Always `FALSE` unconfirmed |
| `DONE` | `BOOL` | one scan, when it went |
| `ERROR` / `STATUS` | | |

---

## `BEEBUS_TP_BUFFER`

Holds samples of one owned topic while there is nowhere to send them.

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `NAME` | `STRING(254)` | the topic, as bound by `BEEBUS_TP_TOPIC` or `BEEBUS_TP_PUBLISH` |
| `DEPTH` | `BYTE` | samples to hold. 0 turns buffering off |

| output | type | |
| --- | --- | --- |
| `HELD` | `UINT` | samples waiting to go out |
| `ERROR` / `STATUS` | | no such node, or no such topic on it |

---

## `BEEBUS_TP_SERVE`

A whole `STRUCT` served by this node, which decides every change a peer asks
for; the owner side of `BEEBUS_TP_BIND`. See
[11 - Settings both ways](11-bidirectional-binding.md).

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `VALUE` | `ANY` | the `STRUCT`, or an `ARRAY` of `STRUCT`s or simple values |
| `TOPIC_ID` | `UINT` | the first member's id |
| `PREFIX` | `STRING(16)` | in front of every member's name. Empty for none |
| `WRITABLE` | `BOOL` | peers may change the members; `FALSE`: a change is refused `READ_ONLY` |
| `COMMAND` | `BOOL` | every member is a command: each change taken once, answered when taken |
| `PULSE` | `TIME` | a `BOOL` member written TRUE goes back to FALSE this long after |
| `SETTLE` | `TIME` | a change is read back after one scan plus this long |
| `DEPTH` | `USINT` | store and forward: each member held in a ring this deep while the network is away. 0 for none |

| output | type | |
| --- | --- | --- |
| `BOUND` | `BOOL` | every member is served |
| `COUNT` | `UINT` | how many topics |
| `CHANGED` | `BOOL` | one scan, when peers' changes were taken |
| `CHANGED_COUNT` / `CHANGED_NAME` / `CHANGED_INDEX` / `CHANGED_BY` | | that scan's changes (held), as `WRITTEN_*` on `BEEBUS_TP_STRUCT` |
| `REFUSED_COUNT` | `UDINT` | changes the program did not keep as asked, running total |
| `LOST` | `UDINT` | changes dropped (a member changed more than 4 times between two scans) |
| `ERROR` / `STATUS` | | |
| `LAST_ERROR` | `STRING(80)` | which member was refused, and why |

---

## `BEEBUS_TP_BIND`

A `STRUCT` kept equal to the one a peer serves. Change a member and the owner
is asked; whatever it decides, the member ends with its value.

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `VALUE` | `ANY` | your `STRUCT` (or `ARRAY`), the same type as the owner's |
| `PEER` | `BYTE` | the node that serves it |
| `TOPIC_ID` | `UINT` | as the owner gave it |
| `PREFIX` | `STRING(16)` | as the owner gave it |
| `RELIABLE` | `BOOL` | `TRUE` for setpoints, settings, configuration. `FALSE` (default): LIVE |
| `DEADBAND` | `REAL` | LIVE only. 0 = every change |

| output | type | |
| --- | --- | --- |
| `COUNT` | `UINT` | how many members |
| `STATE` | `BEEBUS_TP_BIND_STATE` | the worst member |
| `IN_SYNC` | `BOOL` | every member holds the owner's value |
| `PENDING` | `BOOL` | a change is with the owner |
| `REFUSED` | `BOOL` | the owner kept another value for a member, now in the member |
| `REFUSED_NAME` / `REFUSED_INDEX` | | the first member refused (held) |
| `FAILED` | `BOOL` | no decision came back; the member holds the owner's last value |
| `AGE` | `TIME` | since the oldest member last had a value from the owner |
| `NEW_VALUE` | `BOOL` | a value arrived from the owner since the last scan |
| `ERROR` / `STATUS` | | |
| `LAST_ERROR` | `STRING(80)` | which member was refused, and why |

---

## `BEEBUS_MB_MAP`

Puts your variables at Modbus addresses. No request pin — the variable **is**
the register.

| input | type | |
| --- | --- | --- |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `TABLE` | `BEEBUS_MB_TABLE` | which of the four lists |
| `ADDRESS` | `UINT` | the first address |
| `ON_LOSS` | `BEEBUS_MB_FAILSAFE` | `BEEBUS_MB_HOLD_LAST_VALUE` or `BEEBUS_MB_RESET_TO_VALUE` |
| `SAFE_VALUE` | `DINT` | what `BEEBUS_MB_RESET_TO_VALUE` goes to |
| `VALUE` | `ANY` | the variable to bind: one value, a fixed-bounds array or a `STRUCT` |

| output | type | |
| --- | --- | --- |
| `BOUND` | `BOOL` | the addresses are live |
| `COUNT` | `UINT` | how many addresses were taken |
| `WRITTEN` | `BOOL` | one scan, when a peer wrote any of them |
| `WRITTEN_NAME` | `STRING(64)` | which member (the first, if several); held |
| `WRITTEN_INDEX` | `UINT` | its position, from 1; held |
| `WRITTEN_ADDRESS` | `UINT` | its first address; held |
| `WRITTEN_COUNT` | `UINT` | how many members that write covered; held |
| `SAFE_APPLIED` | `BOOL` | one scan, when the safe state was applied |
| `ERROR` / `STATUS` | | |
| `LAST_ERROR` | `STRING(80)` | which member was refused, and why |

`ON_LOSS` needs `FAILSAFE := TRUE` on the node block, and applies to a single
writable number — not a range, a `STRUCT` or a string. `SAFE_VALUE` is in the
number's own type: 5 on a `REAL` is 5.0.

---

## `BEEBUS_MB_READ`

Reads a peer's registers or coils.

| input | type | |
| --- | --- | --- |
| `REQ` | `BOOL` | rising edge reads |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `PEER` | `BYTE` | the node to read from |
| `TABLE` | `BEEBUS_MB_TABLE` | which list |
| `ADDRESS` | `UINT` | the first address on that node |
| `LENGTH` | `UINT` | how many values (members, elements). 0 uses all of what was passed |
| `VALUE` | `ANY` | where the answer lands: one value, a fixed-bounds array or a `STRUCT` |

| output | type | |
| --- | --- | --- |
| `BUSY` | `BOOL` | outstanding |
| `DONE` | `BOOL` | one scan, when it landed |
| `ERROR` / `STATUS` | | |

---

## `BEEBUS_MB_WRITE`

Writes to a peer.

| input | type | |
| --- | --- | --- |
| `REQ` | `BOOL` | rising edge writes |
| `NODE` | `BEEBUS_NODE` | the node, as an in-out. Must be wired |
| `PEER` | `BYTE` | the node to write to |
| `TABLE` | `BEEBUS_MB_TABLE` | `BEEBUS_MB_COIL` or `BEEBUS_MB_HOLDING_REG` — the only writable lists |
| `ADDRESS` | `UINT` | the first address on that node |
| `CONFIRMED` | `BOOL` | wait for the peer to acknowledge |
| `LENGTH` | `UINT` | how many values (members, elements). 0 uses all of what was passed |
| `VALUE` | `ANY` | the variable to send: one value, a fixed-bounds array or a `STRUCT` |

| output | type | |
| --- | --- | --- |
| `BUSY` | `BOOL` | outstanding |
| `DONE` | `BOOL` | one scan, when it landed |
| `ERROR` / `STATUS` | | |

---

## The `VALUE` pin

`BEEBUS_MB_MAP`, `BEEBUS_MB_READ` and `BEEBUS_MB_WRITE` all take the variable itself:

```
VALUE := iSetpoint        (* one address *)
VALUE := aTrend           (* ARRAY [0..99] OF WORD — a range of registers *)
VALUE := aValves          (* ARRAY [0..7] OF BOOL  — a range of coils *)
VALUE := CFG              (* a STRUCT — its members, one after the other *)
```

`TABLE` says whether the addresses are bits or registers, so the variable does
not have to. An array must have **fixed bounds** — `ARRAY [*]` is a view rather
than a variable and cannot ride a generic pin. A literal has nothing to point
at and is refused.

Each value takes its own width: `BOOL`, `SINT`, `USINT`, `BYTE`, `INT`, `UINT`,
`WORD` one register; `DINT`, `UDINT`, `DWORD`, `REAL`, `TIME`, `TOD`, `DT`,
`DATE` two, `LINT`, `ULINT`, `LWORD`, `LREAL`, `LTIME` four, **high word
first**; `STRING(n)` n/2 + 1. A bit list takes `BOOL`s only. `WSTRING` is
`BEEBUS_INVALID_ARGUMENT`. See [04 - Registers](04-registers.md).

---

## The enumerations

| type | values |
| --- | --- |
| `BEEBUS_MB_TABLE` | `BEEBUS_MB_COIL`, `BEEBUS_MB_HOLDING_REG`, `BEEBUS_MB_DISCRETE_INPUT`, `BEEBUS_MB_INPUT_REG` |
| `BEEBUS_MB_FAILSAFE` | `BEEBUS_MB_HOLD_LAST_VALUE`, `BEEBUS_MB_RESET_TO_VALUE` |
| `BEEBUS_TP_SEND` | `BEEBUS_TP_PUBLISH_ALL`, `BEEBUS_TP_PUBLISH_TO` |
| `BEEBUS_TP_QUALITY` | `BEEBUS_TP_UNKNOWN`, `BEEBUS_TP_GOOD`, `BEEBUS_TP_UNCERTAIN`, `BEEBUS_TP_BAD` |
| `BEEBUS_TP_OUTCOME` | `BEEBUS_TP_ACCEPTED`, `BEEBUS_TP_CHANGED`, `BEEBUS_TP_REFUSED`, `BEEBUS_TP_READ_ONLY`, `BEEBUS_TP_NO_TOPIC`, `BEEBUS_TP_WRONG_TYPE`, `BEEBUS_TP_BUSY`, `BEEBUS_TP_NO_ANSWER` |
| `BEEBUS_TP_BIND_STATE` | `BEEBUS_BIND_OFFLINE`, `BEEBUS_BIND_SYNCING`, `BEEBUS_BIND_IN_SYNC`, `BEEBUS_BIND_PENDING`, `BEEBUS_BIND_REFUSED`, `BEEBUS_BIND_FAILED` |
| `BEEBUS_NODE_LINK` | `BEEBUS_NODE_RUNTIME_SERIAL`, `BEEBUS_NODE_RUNTIME_UDP` |
| `BEEBUS_NODE_LINK` | `BEEBUS_NODE_ARDUINO_SERIAL`, `BEEBUS_NODE_ARDUINO_WIFI`, `BEEBUS_NODE_ARDUINO_ETHERNET` |
| `BEEBUS_RESULT` | see [06 - Diagnostics](06-diagnostics.md) |
