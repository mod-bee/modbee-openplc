# Sparkplug: reporting to a SCADA system

Sparkplug B is MQTT with rules, and it is what SCADA systems and IoT platforms
(Ignition, a historian, a cloud SCADA) expect a remote site to speak. This page
is the Sparkplug node on a site: what to wire, what each method does, and what
to check when it does not report. The point list of `Record` is page 15.

| | What it is |
| --- | --- |
| `FB_MqttClient` | the connection - broker, TLS, login, Wi-Fi, Ethernet or cellular |
| `FB_SparkplugNode` | the Sparkplug node, a layer on that connection. One per client |
| `sp.Record` | a whole STRUCT as metrics, each member by its class - one call per record |
| `sp.Metric` | one value that is not in a record, or one under a device of your own |
| `sp.Command` | a write from SCADA that the program decides about |
| `sp.Device` | a device under the node that can go offline by itself |
| `sp.History` | events kept through an outage, sent afterwards flagged historical |
| `sp.DayTotals` | daily totals sent on every birth, so SCADA fills the gaps |
| `FB_MqttClock` | the controller's clock, so the timestamps are real |

## The pins that matter

**`FB_SparkplugNode`**

| Pin | Set it to |
| --- | --- |
| `sGroupId` | the site or customer, e.g. `'Plant1'` |
| `sEdgeNodeId` | this controller, e.g. `'pumps1'`. Group and node together must be unique |
| `fbClient` | the `FB_MqttClient` it rides on |
| `sPrimaryHostId` | the SCADA system's host ID. The node then sends nothing while SCADA is offline, and sends everything again when it comes back. Empty by default: births as soon as it connects |
| `stReportConfig` | how `Record`'s classes report: intervals, the log deadband, and `bAllowHostWrites` - whether SCADA may write |
| `bBirthSent` | TRUE when SCADA has the full metric list and data is flowing |
| `bClockSynced` | TRUE when the timestamps are real time |
| `sLastError` | what it is waiting for, in words |
| `bHostViewing`, `sDevicesDemanded` | Live Demand: someone views this node, and which devices they asked for |

**Everything about the connection is the client's** - `eTransport`, `sHostName`,
`eSecurity`, the login in `stSessionConfig`, the Wi-Fi in `stNetworkConfig`
or node-uio's `NETWORK`:

| `eTransport` | Where | Who brings the network up |
| --- | --- | --- |
| `E_MqttTransport.RuntimeTcp` | the OpenPLC Runtime. The default | the computer |
| `E_MqttTransport.ArduinoWiFi` | a board's Wi-Fi | `NETWORK` (node-uio), or `stNetworkConfig` |
| `E_MqttTransport.ArduinoEthernet` | a board's Ethernet | the client, from `stNetworkConfig` |
| `E_MqttTransport.Cellular` | the modem on the GSM HAT | `FB_GsmModemA7670` or `FB_GsmModemSim7070` (modbee-gsm) |
| `E_MqttTransport.External` | a transport wired to `nExternalLink` | whoever made it |

Moving a site from Wi-Fi to cellular is one pin on the client and one on the
clock. `eSecurity` does not change with it: on the Node every TLS setting works
on Wi-Fi, Ethernet and cellular alike, because the TLS runs on the controller
rather than in the modem (page 03, "TLS on a board").

**For a secure link to the site's own broker** use
`eSecurity := E_MqttSecurity.TlsPinned` with `bTrustFirstBrokerKey := TRUE` on the
client, and a login in `stSessionConfig`. Nothing to install or define: the
client learns the broker's key on its first connection, keeps it over power
cuts (turn on persistent storage), and refuses any other key after that.
`TlsVerify` is for a broker somebody signed for, such as a cloud platform, and
needs that CA in the board package.

## One connection for everything

Sparkplug runs over MQTT, and so does everything else a site says. The node is
a layer on the client's session, not a second connection: one radio, one
login, one session for Sparkplug, your own MQTT topics and firmware updates
(`FB_OtaNode`, modbee-ota) alike.

What Sparkplug needs of that session the node takes on every CONNECT:

- **the Will is its NDEATH.** A connection carries one Will, so there is no
  `stWill` on a client with a Sparkplug node (the client says
  `E_MqttResult.Refused`): the birth and death certificates are the presence.
  And one node per client - a second node needs a second `FB_MqttClient`.
- **the session is always clean**, whatever `stSessionConfig` says.
- **the transmit buffer holds the birth certificate.**

A node started on a session that is already up reconnects it once, so the next
CONNECT carries the NDEATH - every other call on the client sees one
reconnect. The same happens when the primary host goes offline, which
Sparkplug requires. A deliberate goodbye from the client - `bConnect := FALSE`,
or a new broker address - publishes the NDEATH too. `bEnable := FALSE` on the
node sends the NDEATH and leaves the connection to everything else on it.

**One task.** The client, the node and their methods run in the network task
(page 10). In any other task a method returns `E_MqttResult.WrongTask` and does
nothing.

## A ModBee Node, Wi-Fi now

```st
VAR
  clock : FB_MqttClock;
  mqtt  : FB_MqttClient;
  sp    : FB_SparkplugNode;
  stReport : ST_SparkplugReportConfig;
END_VAR

clock(eTimeSource := E_MqttTransport.ArduinoWiFi);
mqtt(eTransport := E_MqttTransport.ArduinoWiFi, sHostName := CFG.sScadaBroker,
     sClientId := 'plant1-pumps');
stReport.bAllowHostWrites := CFG.bRemote;
sp(fbClient := mqtt, sGroupId := 'Plant1', sEdgeNodeId := 'pumps1',
   sPrimaryHostId := 'scada', stReportConfig := stReport);
sp.Record(anyData := STS, anyPointList := '* = now, db = 0.01');
sp.Record(anyData := CMD, anyPointList := '* = cmd', sMetricNamePrefix := 'Cmd/');
```

The Wi-Fi itself is node-uio's `NETWORK` block, joined from the site's
settings; the client waits for it.

## The same Node, cellular later

```st
clock(eTimeSource := E_MqttTransport.Cellular);
mqtt(eTransport := E_MqttTransport.Cellular, sHostName := CFG.sScadaBroker,
     sClientId := 'plant1-pumps');
```

Nothing else changes - `sp` and every `Record` stay as they were, beside a
`FB_GsmModemA7670` or `FB_GsmModemSim7070` from modbee-gsm. The library being in the project is what switches
cellular on; there is no build setting.

## Firmware updates, from SCADA

`FB_OtaNode` (modbee-ota) runs firmware updates on the same client, and its
`Sparkplug` method puts them on this node as metrics - `Firmware/Version`,
`Firmware/State`, `Firmware/Progress` and the rest - and takes
`Node Control/Firmware Accept`, `Apply`, `Confirm` and the others as commands,
so an update can be run from the SCADA screens. The image itself travels on
the OTA node's own topics, over the same connection.

```st
VAR
  ota : FB_OtaNode;
END_VAR

ota(fbClient := mqtt, sBaseTopic := 'plant1/pumps1/ota', sFirmwareVersion := '1.4.0',
    bAutoApply := FALSE);
ota.Sparkplug(fbNode := sp);
```

Put every MQTT and Sparkplug call in the network task, not the logic task
(page 10). On an ESP32 opening the socket and the TLS handshake run on a task
of their own and hold neither; on a board without threads opening the socket
holds the block's task, over cellular for a second or two.

## A birth carries every metric

The metric set is **closed**: the birth certificate carries every metric the
node will publish, and a write to an undeclared name is refused rather than
invented. So call every `Record`, `Metric`, `History` and `DayTotals` from the
first scan. The node waits up to two seconds for the first declaration before
it births, and births with everything declared by then.

A metric declared **after** the birth - a `Record` first called later, a
`Metric` behind an `IF` - makes the node **birth again**, so the host never
receives data for a name it has no birth for. It costs one NBIRTH; on a
metered link keep the calls unconditional.

## How many metrics

| Controller | Metrics per node (node and devices together) | Devices |
| --- | --- | --- |
| a board (ModBee Node UIO, any ESP32) | as many as memory holds | as many as memory holds |
| OpenPLC Runtime | as many as memory holds | as many as memory holds |

Nothing is reserved up front. The node's tables grow with what is declared,
and its buffers are sized to its own birth certificate when it first connects -
in PSRAM on a board that has it, so a hundred metrics cost the internal RAM
nothing. On a board a metric takes 320 bytes there (32 of them what each scan
reads: one cache line), a STRING 280 more, and a writable one 80 for the
writes waiting on it (624 for a STRING). A `Record` keeps 16 bytes per
declared member in internal RAM - what each scan walks - and nothing for a
member no clause covers. A metric memory cannot hold is refused, and the
node's `sLastError` reads "out of memory for metrics or devices". A node holds
up to 1024 `Metric`, `Device`, `Command`, `History` and `DayTotals` calls.

An `FB_SparkplugHost` likewise tracks as many nodes, and metrics per node, as
memory holds, and its `sLastError` says when memory ran out.

## A record, not a block per value

```st
sp.Record(anyData := PUMP1, sMetricNamePrefix := 'pump1/',
          anyPointList := 'sts = now; tot = log, db = 0.1, u = h; cmd = cmd, pulse = 500',
          nRecordMetrics => nPump1Metrics, nFirstBadClause => nPump1Bad);
```

Every value in the STRUCT that a clause covers is its own metric, named by its
**path** after `sMetricNamePrefix` - `pump1/sts.running`, `pump1/tot.runHours`,
`pump1/cmd.start`. Each clause gives its members a **class**: when they go,
whether on a device, whether SCADA may write them:

| Class | Sends | Writable |
| --- | --- | --- |
| `now` | at once, always | no |
| `cmd` | at once, always | while `stReportConfig.bAllowHostWrites` |
| `view` | at once while someone views the node (Live Demand) | no |
| `log` | what moved past its deadband, every `tLogInterval` (`T#15m`); every `tLiveInterval` while viewed | no |
| `live` | on device `live`: what moved, every `tLiveInterval` (`T#30s`), while demanded | no |
| `set:<page>` | on device `cfg-<page>`: at once while demanded | while `bAllowHostWrites` |

and options - `db=` and `pct=` deadbands, `u=` units, `lo=`/`hi=` ranges,
`pulse=` for a momentary command. [15 Record](15-sparkplug-record.md) is the
whole grammar.

## Report by exception, and deadbands

Sparkplug sends a value only when it changes. A level transmitter that jitters
by a few millimetres would still send every scan - over a metered cellular link
that is most of the bill. A deadband says how much a value must move before it
is worth a message:

| Where | How | Applies to |
| --- | --- | --- |
| a `Record` clause | `db=` (in the member's units), `pct=` (% of the value) | numbers |
| `stReportConfig.fLogDeadbandPct` | the log class's % where a clause gives no `pct=` | REAL and LREAL members of the log class |
| `sp.Metric` | `fDeadband` (in `anyValue`'s units) | a numeric value |

- The move is measured from the value **last sent**, not the last scan, so a
  slow drift still adds up and is reported.
- BOOLs and STRINGs always report every change - a deadband would freeze a
  bit, a FAULT included. A clause that names a BOOL itself with `db=` is an
  error (`nFirstBadClause`); a wider path simply reports its BOOLs on change.
- A value SCADA **wrote** is always reported back, whatever the deadband -
  SCADA watches for that echo to know the write took.
- With both `db=` and `pct=` set, a move must clear both.
- A birth always carries every value as it is.

## One message a scan

A method does not send: it marks what is to go and asks, and the node sends
**one** NDATA - and one DDATA for each online device with something to say -
on its next scan, carrying everything that moved, however many calls asked.
The values are the ones the calls set; the message's timestamp is when the
node sends it. The interval classes (`log`, `live`) look on the node's clock,
so every record with the same interval goes in the same message. Births,
deaths and `History`'s events go when they happen.

## Writes from SCADA

- A `cmd` or `set:<page>` member is written by SCADA while
  `stReportConfig.bAllowHostWrites` is TRUE. The value lands in the STRUCT, and
  the next message reports it back - that is how SCADA sees the write took.
- **Remote control off**: a write is dropped at once and the member reported
  back unchanged, so SCADA sees the write did not take. It is never kept:
  `bAllowHostWrites` coming back on does not apply an old command.
- **No write is lost.** Every write to a metric waits its turn: one is taken a
  scan, oldest first, so SCADA writing 1 and then 0 in one go leaves the
  member 1 for a scan and then 0, and the program sees both. Up to four writes
  wait per metric; a fifth that arrives before the program has taken any drops
  the oldest - the newest is always kept.
- A **held** signal (a run request) and a **mode** stay as written. A
  **momentary** command - a bit that acts on its rising edge - must go back to
  0 before the next one: SCADA writes the bit and then 0, or the clause gives
  `pulse=500` (milliseconds, longer than the slowest task that reads it) and
  the PLC clears it. Then writing the same command again acts again.
- A write to a metric that is not writable, does not exist, or is the wrong
  type is refused by the node, never applied.

### A write the program decides about

```st
sp.Command(sMetricName := 'Cmd/reset', bTakeCommand := bResetTaken,
           bCommandWaiting => bResetPending, bValue => bResetValue);
bResetTaken := bResetPending AND bResetAllowed;
sp.Metric(anyValue := bResetCmd, sMetricName := 'Cmd/reset', bHostCanWrite := TRUE);
```

`Metric` with `bHostCanWrite` declares a writable metric and writes the host's
value into `anyValue`. `Command`, called **before** it, shows the oldest write
waiting (`bCommandWaiting`, with `fValue`, `bValue` and `sText`) without taking it, so
a rung can look before it decides; a rising edge of `bTakeCommand` takes it, so two
rungs cannot both act on one command. Give `sDeviceId` on both when the metric
is under a device.

## Devices of your own

```st
sp.Device(sDeviceId := 'skid2', bBringOnline := bSkid2Healthy, bDeviceBirthSent => bSkid2Born);
sp.Metric(anyValue := rSkid2Flow, sMetricName := 'flow', sDeviceId := 'skid2',
          sUnits := 'm3/h', fDeadband := 0.5);
```

A device is something that can be lost while the node is fine - a pump skid, a
remote I/O drop. `Device` acts on a **change** of `bBringOnline` (a DBIRTH, or a
DDEATH), never every scan, and births the device again after every node birth.
Its metrics are `Metric` calls with its `sDeviceId`; a `Metric` naming a device
no `Device` call made adds it and brings it online itself.

`live` and every `cfg-...` name are the node's own, brought on and off line by
Live Demand: `Device` and `Metric` refuse them.

## Live Demand

A screen that shows a node's detail wants it fast while somebody is looking,
and not at all otherwise - on a metered link the difference is most of the
bill. Live Demand is that contract between the node and the host.

**The offer.** A record with a `view`, `log`, `live` or `set:` class makes the
node declare one more metric, `Node Control/Live Demand`, a String whose value
says what can be demanded:

```
{"devices":["live","cfg-pump"],"required":false}
```

**The demand.** A host that opens the node's screen writes it:

```
{"demand":true,"leaseS":120,"devices":["live","cfg-pump"]}
```

For `leaseS` seconds (120 when missing, or outside 1 to 86399) the node is
**viewed**: `bHostViewing` is TRUE, the `view` class sends its changes, the `log`
class goes every `tLiveInterval` instead of every `tLogInterval`, and every
device listed is born (DBIRTH) and sends; a device not listed dies (DDEATH).
`sDevicesDemanded` lists the devices demanded now, `'live,cfg-pump'`.

**The lease.** The host writes again before the lease ends to keep it - each
write replaces the demand and starts the lease again. `{"demand":false}` ends
it at once. When the lease runs out with no write, the node stops by itself:
a host that crashed with the screen open costs two minutes, not a month.

- A write without `"demand"`, or longer than 200 characters, is ignored.
- After every write the node puts the offer back, so the metric always says
  what can be demanded.
- A device in the demand that the offer does not name is ignored.
- `bHostViewing` and `sDevicesDemanded` are outputs the program may use too - a panel lamp
  "SCADA is watching", or a faster scan of a sensor while someone looks.

## Types on the wire

Each metric's Sparkplug datatype is its IEC type: BOOL is Boolean, INT is
Int16, DINT is Int32, REAL is Float, STRING is String, and so on.

A **TIME** goes as an **Int64 of milliseconds**, both ways. Sparkplug has no
duration type. `T#10s` is reported as 10000, and SCADA writing 90000 sets
`T#90s`. A negative write is refused. A TIME member says `ms` in the birth by
itself.

An array or a nested STRUCT in a record is not one value: each of its values
is a metric of its own (page 15). An enumeration goes as the unsigned integer
it is stored as (UInt8 / UInt16 / UInt32 by its size), both ways: the value's
code, so modes are visible and writable from the host. DATE and TIME_OF_DAY
have no Sparkplug type: a record leaves such a member out, and a clause that
covers nothing else is reported on `nFirstBadClause`.

## Time

`FB_MqttClock` sets the controller's clock from the network: NTP over Wi-Fi or
Ethernet, the mobile network's own time over cellular, or a time wired to
`dtExternalUtc` (an RTC, the modem's `NetworkTime`). Once it is set, Sparkplug's timestamps and
`CURRENT_DT` are real time, and the clock's `bClockSynced` and the node's
`bClockSynced` are TRUE.

Until then a board counts from when it started, so its timestamps are dates in
January 1970 - plainly not real. Set the SCADA historian to stamp a value with
the time it arrived when its timestamp is that old. The data is still good;
only the time is missing.

On the Runtime the computer keeps the time, and `FB_MqttClock` only reports it.

## Changing settings while it runs

The client's `sHostName`, `nHostPort`, `eSecurity`, `eTransport`, `eProtocol`, login and
keep-alive, and the node's `sGroupId`, `sEdgeNodeId` and `sPrimaryHostId`, are
read every scan. A change from an HMI settings page needs no restart: the node
leaves on the old settings (the host sees its NDEATH), and births again on the
new ones with the next bdSeq. Every declaration, alias and device stays, so
nothing else in the program notices. The medium is rebuilt only when what it is
made from changed.

A pinned key stays pinned: a different broker is refused until `bTrustFirstBrokerKey` is
switched off and on, as for a replaced one.

## Outages: `sp.History`

Sparkplug has no store-and-forward of its own. While the node is not born - no
coverage, the broker away, the host offline - nothing is sent, and after the
next birth the host sees only the values as they are then. What happened in
between, and when, is gone.

`History` keeps **events** while the node cannot publish and sends them after
it births again, with Sparkplug's `is_historical` flag: the host files each at
its own time and does not overwrite the live tag with it.

```st
sp.History(bRecordEvent := bPumpStopped, nEventSource := 1, nEventCode := nPump1StopCode, fValue := rLevel);
sp.History(bRecordEvent := bAlarmRaised, nEventSource := 100 + nAlarmNo, nEventCode := 1, fValue := 0.0);
```

| Parameter | | |
| --- | --- | --- |
| `bRecordEvent` | BOOL | TRUE records one event on this call - wire a one-scan pulse |
| `nEventSource` | UINT | what it is about: a pump, an alarm number, a zone |
| `nEventCode` | UINT | what happened: a status, fault or stop code |
| `fValue` | REAL | a number that goes with it |
| `sMetricPrefix` | STRING(24) | the metrics' prefix, `'Event'`. Calls with one prefix share one buffer |
| `nMaxEventsKept` | UINT | events kept while away, `256`. Fixed at the first call |
| `nEventsPerMessage` | UINT | events per message when catching up, `20`, at most 64. Fixed at the first call |
| `tCatchUpInterval` | TIME | between catch-up messages, `T#1s` |
| `nEventsWaiting` | out | events waiting |
| `nLostEventCount` | out | dropped because the buffer was full (the oldest go) |
| `nSentEventCount` | out | sent since the program started |
| `bCatchingUp` | out | catching up |

Each event is one row of four metrics with the same timestamp:
`Event/source`, `Event/code`, `Event/value` and `Event/seq` (a count from 1
since the program started, so the host sees any gap), plus `Event/lost`. While
the node is born an event goes at once as live data; recorded while it is not,
it waits and goes historical, oldest first, `nEventsPerMessage` at a time every `tCatchUpInterval`.

- **Events, not analogs.** A level that moves every scan would fill any
  buffer. Keep the reasons, stops, alarms and day totals; counters that only go
  up reconcile the rest by themselves.
- **256 events** is about a week of a normal site, 6 KB of PSRAM (24 bytes an
  event), allocated on the first call.
- **Not retained.** A power cut during an outage loses the waiting events; the
  counters and the day totals still reconcile.
- **Sent at least once.** Data messages are QoS 0 by the specification, so an
  event is forgotten only after the node has stayed born for half a second on
  the same **node** birth; a device's birth - Live Demand's, often - does not
  count. A link that drops in that moment sends the batch again. The host may
  see an event twice (same timestamp, same seq), never not at all.
- **The clock.** An event recorded before `FB_MqttClock` has set the clock is
  kept against the board's uptime and placed on the clock once it is set.
  Events wait for the clock up to five minutes after a birth, then go with
  what they have.

## Daily totals: `sp.DayTotals`

```st
VAR RETAIN
  PUMPED_DAYS : ARRAY[0..31] OF ST_SparkplugDay;
END_VAR

sp.DayTotals(anyDays := PUMPED_DAYS, sMetricName := 'pumpedDay',
             fTodayTotal := rPumpedToday, dtLocalTime := dtLocalNow);
```

| Parameter | | |
| --- | --- | --- |
| `anyDays` | ARRAY OF ST_SparkplugDay | `dDay : DATE`, `fTotal : REAL`, two rows or more. **Retain it.** The first row is today; the rest are closed days, newest first |
| `sMetricName` | STRING(32) | the metric |
| `fTodayTotal` | REAL | today's running total, from your totaliser |
| `dtLocalTime` | DT | local date and time - the clock your totaliser rolls its day on |
| `tSaveInterval` | TIME | how often today's total is written into the table, `T#1h`; `T#0s` every call |
| `nClosedDays` | out | closed days held |
| `nSentDayCount` | out | day values sent |

When the date on `dtLocalTime` changes the day just ended is closed - its total is
the value `fTodayTotal` had on the call before - and moves into the table as the
newest closed day; the oldest falls off. A day that ends during a power cut is
closed when the PLC comes back, from the total last saved. Nothing happens
while the clock is not set.

**On every node birth every closed day goes as a historical value** of
`sMetricName`, stamped 00:00 of its date (the date as `dtLocalTime` has it, written
as UTC: read the date, not the hour). So a host that missed days while the link
was down fills them in, and sending a day twice lands on the same timestamp. A
device's birth does not send them. The live value of `sMetricName` is the last
closed day.

## When it does not report

| `sLastError` | What it means |
| --- | --- |
| `joining the WiFi network` (on the client) | the radio is not joined yet |
| `set SSID on MQTT_ARDUINO` (on the client) | no `stNetworkConfig.sSsid` and no node-uio `NETWORK` has joined the radio (the message still names the 0.1 block) |
| `no STATE from primary host 'scada'` | SCADA has never connected to this broker - or `sPrimaryHostId` is spelt differently from SCADA's host ID |
| `offline STATE from primary host 'scada'` | SCADA is down. The node waits, as it should |
| `Record PUMP1: clause 3` | that record's point list: clause 3 cannot be used. `nFirstBadClause` on the call says the same (page 15) |
| `Record PUMP1: tLiveInterval is T#0s` | a `log` or `live` class with no interval to go on |
| `another layer owns the client's Will` | an `FB_SparkplugHost` or a second node on the same client |
| `out of memory for metrics or devices` | memory ran out for a declaration |
| `E_MqttTransport.Cellular needs a modbee-gsm modem block` (on the client) | add the modbee-gsm library and a `FB_GsmModemA7670` or `FB_GsmModemSim7070` |
| `a board needs the CA in MQTT_CA_CERT_PEM` (on the client) | `TlsVerify` with no CA defined: use `TlsPinned` with `bTrustFirstBrokerKey` for the site's own broker, or add the CA to the board package |
| `no pinned key yet - set bTrustFirstBrokerKey once to learn it` (on the client) | `TlsPinned` on a client that has never connected |

**Next:** [15 Record](15-sparkplug-record.md), the point list in full.
