# Sparkplug: reporting to a SCADA system

Sparkplug B is MQTT with rules, and it is what SCADA systems and IoT platforms
(Ignition, a historian, a cloud SCADA) expect a remote site to speak. This page
is the Sparkplug blocks on a site: what to wire, what each pin does, and what to
check when it does not report.

| Block | What it is |
| --- | --- |
| `MQTT_CLIENT` | the connection - broker, TLS, login, Wi-Fi, Ethernet or cellular |
| `SPARKPLUG_NODE` | the Sparkplug node, a layer on that connection. One per client |
| `SPARKPLUG_STRUCT` | a whole STRUCT as metrics - one per group of values |
| `SPARKPLUG_METRIC` | one value that is not in a struct |
| `SPARKPLUG_COMMAND` | a write from SCADA that the program decides about |
| `SPARKPLUG_DEVICE` | a device under the node that can go offline by itself |
| `MQTT_CLOCK` | the controller's clock, so the timestamps are real |

## The pins that matter

**`SPARKPLUG_NODE`**

| Pin | Set it to |
| --- | --- |
| `GROUP` | the site or customer, e.g. `'Plant1'` |
| `NODE` | this controller, e.g. `'pumps1'`. GROUP + NODE must be unique |
| `CLIENT` | the `MQTT_CLIENT` it rides on |
| `PRIMARY_HOST` | the SCADA system's host ID. The node then sends nothing while SCADA is offline, and sends everything again when it comes back |
| `BORN` | TRUE when SCADA has the full metric list and data is flowing |
| `CLOCK_SET` | TRUE when the timestamps are real time |
| `LAST_ERROR` | what it is waiting for, in words |

**Everything about the connection is `MQTT_CLIENT`'s** - `TRANSPORT`, `HOST`,
`SECURITY`, the login on `MQTT_CONFIG`, the Wi-Fi on `MQTT_ARDUINO` or
`NETWORK`:

| `TRANSPORT` | Where | Who brings the network up |
| --- | --- | --- |
| `MQTT_RUNTIME_TCP` | the OpenPLC Runtime. The default | the computer |
| `MQTT_ARDUINO_WIFI` | a board's Wi-Fi | `NETWORK` (node-uio), or `MQTT_ARDUINO` |
| `MQTT_ARDUINO_ETHERNET` | a board's Ethernet | `MQTT_CLIENT` with `MQTT_ARDUINO` |
| `MQTT_CELLULAR` | the modem on the GSM HAT | `GSM_MODEM` (modbee-gsm) |
| `MQTT_LINK_EXTERNAL` | a transport wired to `EXTERNAL_LINK` | whoever made it |

Moving a site from Wi-Fi to cellular is one pin on `MQTT_CLIENT` and one on
the clock. `SECURITY` does not change with it: on the Node every TLS setting
works on Wi-Fi, Ethernet and cellular alike, because the TLS runs on the
controller rather than in the modem (page 03, "TLS on a board").

**For a secure link to the site's own broker** use `SECURITY := MQTT_TLS_PINNED`
with `TRUST_NEW := TRUE` on `MQTT_CLIENT`, and a login on `MQTT_CONFIG`.
Nothing to install or define: the client learns the broker's key on its first
connection, keeps it over power cuts (turn on persistent storage), and refuses
any other key after that. `MQTT_TLS_VERIFY` is for a broker somebody signed
for, such as a cloud platform, and needs that CA in the board package.

## One connection for everything

Sparkplug runs over MQTT, and so does everything else a site says. The node is
a layer on the client's session, not a second connection: one radio, one
login, one session for Sparkplug, your own MQTT topics and firmware updates
(`OTA_NODE`, modbee-ota) alike.

What Sparkplug needs of that session the node takes on every CONNECT:

- **the Will is its NDEATH.** A connection carries one Will, so there is no
  `MQTT_PRESENCE` on a client with a Sparkplug node (it says `MQTT_REFUSED`):
  the birth and death certificates are the presence. And one node per client -
  a second node needs a second `MQTT_CLIENT`.
- **the session is always clean**, whatever `MQTT_CONFIG` says.
- **the transmit buffer holds the birth certificate.**

A node started on a session that is already up reconnects it once, so the next
CONNECT carries the NDEATH - every other block on the client sees one reconnect.
The same happens when the primary host goes offline, which Sparkplug requires.
A deliberate goodbye from `MQTT_CLIENT` - `CONNECT := FALSE`, or a new broker
address - publishes the NDEATH too. `ENABLE := FALSE` on the node sends the
NDEATH and leaves the connection to everything else on it.

**One task.** The client, the node and every `SPARKPLUG_*` block run in the
network task (page 10). In any other task a block says `MQTT_WRONG_TASK` and
does nothing.

## A ModBee Node, Wi-Fi now

```
wifi ( ENABLE := TRUE, SSID := CFG.wifiSsid, PASSWORD := CFG.wifiKey );
clock( TRANSPORT := MQTT_LINK#MQTT_ARDUINO_WIFI );
mqtt ( TRANSPORT := MQTT_LINK#MQTT_ARDUINO_WIFI, HOST := CFG.scadaBroker,
       CLIENT_ID := 'plant1-pumps' );
sp   ( CLIENT := mqtt, GROUP := 'Plant1', NODE := 'pumps1',
       PRIMARY_HOST := 'scada' );
core ( NODE := sp, DATA := STS, DEADBAND := 0.01 );
sets ( NODE := sp, DATA := CMD, WRITABLE := TRUE );
```

## The same Node, cellular later

```
modem( CONNECT := TRUE, APN := CFG.gsmApn );
clock( TRANSPORT := MQTT_LINK#MQTT_CELLULAR );
mqtt ( TRANSPORT := MQTT_LINK#MQTT_CELLULAR, HOST := CFG.scadaBroker,
       CLIENT_ID := 'plant1-pumps' );
```

Nothing else changes - `sp` and every struct block stay as they were. The
modbee-gsm library being in the project is what switches cellular on; there is
no build setting.

## Firmware updates, from SCADA

`OTA_SPARKPLUG` (modbee-ota) puts an `OTA_NODE`'s updates on this node as
metrics - `Firmware/Version`, `Firmware/State`, `Firmware/Progress`,
`Firmware/Offered`, `Firmware/Status` - and takes `Node Control/Firmware Accept`,
`Apply`, `Confirm` and the rest as commands, so an update can be run from the
SCADA screens. The image itself travels on the OTA node's own topics, over the
same connection.

```
ota  ( CLIENT := mqtt, BASE := 'plant1/pumps1/ota', VERSION := '1.4.0',
       AUTO_APPLY := FALSE );
otasp( NODE := ota, SPARKPLUG := sp );
```

Put every MQTT and Sparkplug block in the network task, not the logic task
(page 10). On an ESP32 opening the socket and the TLS handshake run on a task
of their own and hold neither; on a board without threads opening the socket
holds the block's task, over cellular for a second or two.

## How many metrics

| Controller | Metrics per node (node and devices together) | Devices |
| --- | --- | --- |
| a board (ModBee Node UIO, any ESP32) | as many as memory holds | as many as memory holds |
| OpenPLC Runtime | as many as memory holds | as many as memory holds |

Nothing is reserved up front. The node's tables grow with what the blocks
declare, and its buffers are sized to its own birth certificate when it first
connects - in PSRAM on a board that has it, so a hundred metrics cost the
internal RAM nothing. On a board a metric takes 320 bytes there (32 of them
what each scan reads: one cache line), a STRING 280 more, and a writable one
80 for the writes waiting on it (624 for a STRING). A `SPARKPLUG_STRUCT` keeps
12 bytes per declared member
in internal RAM - what each scan walks - and nothing for a member `SKIP` leaves
out or the node refuses. A metric memory cannot hold is refused: the declaring
block's `ERROR` (or `SKIPPED` on a STRUCT) says so, and `SPARKPLUG_NODE`'s
`LAST_ERROR` reads "out of memory for metrics or devices".

A `SPARKPLUG_HOST` likewise tracks as many nodes, and metrics per node, as
memory holds, on a board and the Runtime alike, and its LAST_ERROR says when
memory ran out.

A `SPARKPLUG_STRUCT` takes every value in its STRUCT - nested STRUCTs and
arrays included.

## One struct block, not a block per value

Every value in a `SPARKPLUG_STRUCT` is its own metric, named by its **path** -
the same names BeeBus uses:

| In the STRUCT | Metric name |
| --- | --- |
| `levelMm : REAL` | `levelMm` |
| `pump : S_PUMP` with `hours : REAL` | `pump.hours` |
| `spare : ARRAY[1..3] OF REAL` | `spare[1]`, `spare[2]`, `spare[3]` (from 1, whatever the bounds) |

`PREFIX` goes in front of every name: `PREFIX := 'Cmd/'` turns `systemMode`
into the metric `Cmd/systemMode`. Use it to keep two structs' names apart, or to
put a group in its own folder at the SCADA end.

**Per-member settings.** A member that needs its own units, deadband or display
range gets an entry in `SETTINGS`, an `ARRAY OF SPARKPLUG_MEMBER`:

| `SPARKPLUG_MEMBER` | |
| --- | --- |
| `NAME` | the member's path, without PREFIX. Case does not matter. An array or nested STRUCT by name (`spare`, `pump`) covers every value in it |
| `UNITS` | engineering units, sent in the birth (`engUnit`) |
| `DEADBAND` | its own deadband, in its units. 0 = every change |
| `DEADBAND_PCT` | its own deadband as a % of the value last sent |
| `LOW`, `HIGH` | the range a SCADA gauge or trend should show (`engLow`, `engHigh`). Equal = none |
| `PULSE` | for a command: the PLC puts the member back to 0 this long after a write. `T#0s` = keep it |
| `SKIP` | TRUE leaves the member out - not a metric at all (an internal counter, the spares). FALSE puts back one an earlier entry left out, with this entry's numbers. Read once, when the metrics are declared |

```
VAR
  sp      : SPARKPLUG_NODE;
  core    : SPARKPLUG_STRUCT;
  coreSet : ARRAY[1..3] OF SPARKPLUG_MEMBER := [
              (NAME := 'levelMm', UNITS := 'mm', DEADBAND := 10.0,
               LOW := 0.0, HIGH := 3000.0),
              (NAME := 'pressureBar', UNITS := 'bar', DEADBAND := 0.02),
              (NAME := 'pumpHours', UNITS := 'h', DEADBAND := 0.1)];
END_VAR

coreSet[1].DEADBAND := CFG.levelDeadband;   // a setting may follow CFG
core(NODE := sp, DATA := CORE, SETTINGS := coreSet);
```

- A member with an entry takes **its** deadband; one without takes the block's
  `DEADBAND`/`DEADBAND_PCT` (REAL and LREAL members only).
- Entries apply in order: one for `spare` and then one for `spare[2]` gives
  `spare[2]` the second's settings and the rest of the array the first's.
  `SKIP` too: `[(NAME := 'sts', SKIP := TRUE), (NAME := 'sts.value',
  SKIP := FALSE, DEADBAND := 10.0)]` leaves out all of `sts` but `sts.value`,
  which takes the second entry's deadband.
- The settings are read again whenever they change, so they may be written from
  CFG on every scan. Units and ranges go out in the birth, so a change to them
  shows at the next birth.
- `BAD_SETTING` names the first entry that could not be used, counting from 1 -
  a `NAME` that is no member, a negative number, a deadband on a BOOL or STRING -
  and `ERROR` stays on until it is fixed. The other entries still apply.
- A TIME member says `ms` by itself.

## Report by exception, and deadbands

Sparkplug sends a value only when it changes. A level transmitter that jitters
by a few millimetres would still send every scan - over a metered cellular link
that is most of the bill. A deadband says how much a value must move before it
is worth a message:

| Block | Pins | Applies to |
| --- | --- | --- |
| `SPARKPLUG_STRUCT` | `DEADBAND` (in the members' units), `DEADBAND_PCT` (% of the value) | REAL and LREAL members only |
| `SPARKPLUG_METRIC` | `DEADBAND` (in VALUE's units) | a numeric VALUE |

- The move is measured from the value **last sent**, not the last scan, so a
  slow drift still adds up and is reported.
- The block's `DEADBAND` covers REAL and LREAL members only. BOOLs and STRINGs
  always report every change - a deadband would freeze a bit, a FAULT
  included. An integer, or an analog that needs its own number, gets a
  `SETTINGS` entry.
- A value SCADA **wrote** is always reported back, whatever the deadband - SCADA
  watches for that echo to know the write took.
- With both `DEADBAND` and `DEADBAND_PCT` set, a move must clear both.
- A birth, and a STRUCT's `PERIOD` heartbeat, always carry every value as it
  is.

## When a STRUCT sends

| `MODE` | Sends | Its members otherwise |
| --- | --- | --- |
| `MQTT_ON_CHANGE` | what moved, past its deadband; all of them every `PERIOD` (if set) | go with any report |
| `MQTT_ON_INTERVAL` | all of them, every `PERIOD` | **held**: never with other blocks' reports |
| `MQTT_ON_REQUEST` | all of them on `REQ`'s rising edge | **held** |
| `MQTT_CHANGED_EVERY` | what moved past its deadband since it was last sent, together, every `PERIOD` on the node's clock (every set with the same `PERIOD` in one message); nothing when none moved | **held** |

- "All of them" is the block's own members, never the rest of the node.
- **One message a scan, for every block.** A STRUCT (or a `SPARKPLUG_METRIC`)
  does not send: it marks what is to go and asks, and `SPARKPLUG_NODE` sends
  ONE NDATA - and one DDATA for each online device with something to say - on
  its next scan, carrying everything on the node that moved. The values are
  the ones the blocks set; the message's timestamp is when the node sends it.
  A STRUCT's `SENT` counts the message on the scan after it asked, and its
  `ERROR`/`MQTT_QUEUE_FULL` then says one could not be queued (it asks again).
- The **birth** carries every member: a device coming online sends the whole
  set in its DBIRTH, and `PERIOD` counts from that birth. `ENABLE` going TRUE
  sends an `MQTT_ON_INTERVAL` set at once, and an `MQTT_CHANGED_EVERY` set's
  changes at once. Nothing is sent for a device that is offline.
- **A held set switched off** (`ENABLE` FALSE) still keeps its values current
  in the node, so a birth carries them as they are; nothing is sent for it.
- **`MQTT_CHANGED_EVERY` is for a metered link.** A logged value checked every
  15 minutes goes only when it has moved past its deadband; one that sits still
  costs nothing. The same mode with a short `PERIOD` (10 s) and `ENABLE` wired
  to "someone is viewing" streams a screen's values without sending the ones
  that did not move. Alarms that must reach SCADA at once stay `MQTT_ON_CHANGE`.

## Writes from SCADA

- `WRITABLE := TRUE` on a STRUCT lets SCADA write its members. The value lands
  in the STRUCT, and the next message reports it back - that is how SCADA sees
  the write took.
- Under a `DEVICE` the writes are DCMDs instead of NCMDs, and they land the
  same way.
- **No write is lost.** Every write to a metric waits its turn: the block
  takes one a scan, oldest first, so SCADA writing 1 and then 0 in one go
  leaves the member 1 for a scan and then 0, and the program sees both. Up to
  four writes wait per metric. A fifth that arrives before the program has
  taken any drops the oldest - the newest is always kept - and is counted on
  the block's `LOST` output. `LOST` above 0 means SCADA is writing that metric
  faster than the program scans.
- **Commands are a writable struct too**, each member its own metric, written
  one at a time:

  ```
  cmds(NODE := sp, DATA := CMD.remote, PREFIX := 'Cmd/', WRITABLE := TRUE,
       SETTINGS := cmdSet);
  ```

  - A **held** signal (a run request) and a **mode** stay as written. With
    `UT_CMD` a mode acts when it changes; to ask for the same mode again, write
    -1 first.
  - A **momentary** command - a bit that acts on its rising edge, as `UT_CMD`'s
    command bits do - must go back to 0 before the next one. Either SCADA
    writes the bit and then 0 (both are seen, however close together), or the
    member gets `PULSE` in `SETTINGS` (`T#500ms`, longer than the slowest task
    that reads it): SCADA writes the bits once, the PLC clears them, and
    writing the same command again acts again.
- For a write the program must decide about by itself, declare it with
  `SPARKPLUG_METRIC` (`WRITABLE := TRUE`) and watch it with
  `SPARKPLUG_COMMAND`, called **before** the metric block. Set
  `SPARKPLUG_COMMAND.DEVICE` when the metric is under a device.
- A write to a metric that is not writable, does not exist, or is the wrong
  type is refused and counted (`REFUSED`), never applied.
- `WRITABLE` may go FALSE while running - remote control switched off. A write
  that arrives then is dropped at once (counted on a STRUCT's `REFUSED`) and
  the member is reported back unchanged, so SCADA sees the write did not take.
  It is never kept: `WRITABLE` coming back on does not apply an old command.

## Types on the wire

Each metric's Sparkplug datatype is its IEC type: BOOL is Boolean, INT is
Int16, DINT is Int32, REAL is Float, STRING is String, and so on.

A **TIME** goes as an **Int64 of milliseconds**, both ways. Sparkplug has no
duration type. `T#10s` is reported as 10000, and SCADA writing 90000 sets
`T#90s`. A negative write is refused. A STRUCT member that is a TIME says
`ms` in the birth by itself.

An array or a nested STRUCT inside a `SPARKPLUG_STRUCT` is not one value: each
of its values is a metric of its own (see "One struct block"). An enumeration
goes as the unsigned integer it is stored as (UInt8 / UInt16 / UInt32 by its
size), both ways: the value's code, so modes and a protection's response are
visible and writable from the host. DATE and TIME_OF_DAY have no Sparkplug
type: a STRUCT member of one of those is refused and counted (`SKIPPED`), never
left out quietly.

## Time

`MQTT_CLOCK` sets the controller's clock from the network: NTP over Wi-Fi or
Ethernet, the mobile network's own time over cellular, or a time wired to
`UTC_IN` (an RTC, `GSM_TIME`). Once it is set, Sparkplug's timestamps and
`CURRENT_DT` are real time, and `SYNCED` and the node's `CLOCK_SET` are TRUE.

Until then a board counts from when it started, so its timestamps are dates in
January 1970 - plainly not real. Set the SCADA historian to stamp a value with
the time it arrived when its timestamp is that old. The data is still good;
only the time is missing.

On the Runtime the computer keeps the time, and `MQTT_CLOCK` only reports it.

## Changing settings while it runs

`BROKER`, `PORT`, `SECURITY`, `TRANSPORT`, `USER`, `PASSWORD`, `GROUP`, `NODE`,
`PRIMARY_HOST`, `PROTOCOL` and `KEEP_ALIVE` are read every scan. A change from
an HMI settings page needs no restart: the node leaves on the old settings (the
host sees its NDEATH), and births again on the new ones with the next bdSeq.
Every metric declaration, alias and device stays, so nothing else in the
program notices. The medium is rebuilt only when what it is made from changed.

A pinned key stays pinned: a different broker is refused until `TRUST_NEW` is
switched off and on, as for a replaced one.

## Outages: `SPARKPLUG_HISTORY`

Sparkplug has no store-and-forward of its own. While the node is not born - no
coverage, the broker away, the host offline - nothing is sent, and after the
next birth the host sees only the values as they are then. What happened in
between, and when, is gone.

`SPARKPLUG_HISTORY` keeps **events** while the node cannot publish and sends
them after it births again, with Sparkplug's `is_historical` flag: the host
files each at its own time and does not overwrite the live tag with it.

| Pin | | |
| --- | --- | --- |
| `NODE` | in-out | the node |
| `ADD` | in, BOOL | TRUE records one event on this call - wire a one-scan pulse |
| `SOURCE` | in, UINT | what it is about: a pump, an alarm number, a zone |
| `CODE` | in, UINT | what happened: a status, fault or stop code |
| `VALUE` | in, REAL | a number that goes with it |
| `NAME` | in, STRING(24) | the metrics' prefix, `'Event'` |
| `DEPTH` | in, UINT | events kept while away, `256`. Fixed at the first call |
| `BATCH` | in, UINT | events per message when catching up, `20` |
| `PERIOD` | in, TIME | between catch-up messages, `T#1s` |
| `STORED` | out, UINT | events waiting |
| `LOST` | out, UDINT | dropped because the buffer was full (the oldest go) |
| `SENT` | out, UDINT | sent since the program started |
| `REPLAYING` | out, BOOL | catching up |
| `ERROR`, `STATUS` | out | no memory, or the metrics could not be declared |

```
history(NODE := sp, ADD := pumpStopped, SOURCE := 1, CODE := pump1.StopCode, VALUE := level);
history(NODE := sp, ADD := alarmRaised, SOURCE := 100 + alarmNo, CODE := 1, VALUE := 0.0);
```

Each event is one row of four metrics with the same timestamp:
`Event/source`, `Event/code`, `Event/value` and `Event/seq` (a count from 1
since the program started, so the host sees any gap), plus `Event/lost`. While
the node is born an event goes at once as live data; recorded while it is not,
it waits and goes historical, oldest first, `BATCH` at a time every `PERIOD`.

- **Events, not analogs.** A level that moves every scan would fill any
  buffer. Keep the reasons, stops, alarms and day totals; counters that only go
  up reconcile the rest by themselves.
- **256 events** is about a week of a normal site, 6 KB of PSRAM (24 bytes an
  event), allocated on the first scan. Nothing of the internal heap but the
  block's own few bytes.
- **Not retained.** A power cut during an outage loses the waiting events; the
  counters and the day totals still reconcile.
- **Sent at least once.** Data messages are QoS 0 by the specification, so an
  event is forgotten only after the node has stayed born for half a second on
  the same birth; a link that drops in that moment sends the batch again. The
  host may see an event twice (same timestamp, same seq), never not at all.
- **The clock.** An event recorded before `MQTT_CLOCK` has set the clock is
  kept against the board's uptime and placed on the clock once it is set.
  Events wait for the clock up to five minutes after a birth, then go with
  what they have.

## Daily totals: `SPARKPLUG_DAY_TOTALS`

| Pin | | |
| --- | --- | --- |
| `NODE` | in-out | the node |
| `TABLE` | in-out, ARRAY OF SPARKPLUG_DAY | `DAY : DATE`, `TOTAL : REAL`. Retain it. Row 0 is today; the rest are closed days, newest first |
| `NAME` | in, STRING(32) | the metric, `'pumpedDay'` |
| `VALUE` | in, REAL | today's running total, from your totaliser |
| `CLOCK` | in, DT | local date and time - the clock your totaliser rolls its day on |
| `DAYS` | out, INT | closed days held |
| `SENT` | out, UDINT | day values sent |
| `ERROR`, `STATUS` | out | the metric could not be declared, or `TABLE` has fewer than two rows |

```
VAR_GLOBAL RETAIN  PUMPED_DAYS : ARRAY[0..31] OF SPARKPLUG_DAY;  END_VAR
days(NODE := sp, TABLE := PUMPED_DAYS, NAME := 'pumpedDay', VALUE := pumped.today, CLOCK := localNow);
```

When the date on `CLOCK` changes the day just ended is closed - its total is
the value `VALUE` had on the scan before - and moves into the table as the
newest closed day; the oldest falls off. A day that ends during a power cut is
closed when the PLC comes back, from the retained table. Nothing happens while
the clock is not set.

**On every birth every closed day goes as a historical value** of `NAME`,
stamped 00:00 of its date (the date as `CLOCK` has it, written as UTC: read
the date, not the hour). So a host that missed days while the link was down
fills them in, and sending a day twice lands on the same timestamp. The live
value of `NAME` is the last closed day.

## When it does not report

| `LAST_ERROR` | What it means |
| --- | --- |
| `waiting for Wi-Fi - is NETWORK enabled?` | the radio is not joined yet |
| `no STATE from primary host 'scada'` | SCADA has never connected to this broker - or `PRIMARY_HOST` is spelt differently from SCADA's host ID |
| `offline STATE from primary host 'scada'` | SCADA is down. The node waits, as it should |
| `MQTT_CELLULAR needs the modbee-gsm library and a GSM_MODEM` | add the GSM library and a `GSM_MODEM` |
| `a board needs the CA in MQTT_CA_CERT_PEM` | `MQTT_TLS_VERIFY` with no CA defined: use `MQTT_TLS_PINNED` with `TRUST_NEW` for the site's own broker, or add the CA to the board package |
| `no pinned key yet - set TRUST_NEW once to learn it` | `MQTT_TLS_PINNED` on a node that has never connected |
| `on a board, set TRANSPORT - MQTT_ARDUINO_WIFI, ...` | `TRANSPORT` was left at the Runtime's default |

**Next:** [07 Block reference](07-block-reference.md) for every pin.
