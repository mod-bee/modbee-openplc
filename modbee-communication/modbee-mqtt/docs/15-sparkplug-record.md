# Record: a whole STRUCT by point list

`sp.Record` reports a STRUCT's members as Sparkplug metrics, each member by its
**class**, from one text: the point list. One call per record, every scan.

```st
eResult := sp.Record(anyData    := PUMP1,
                     anyPointList  := 'sts = now; tot = log, db = 0.1, u = h; cmd = cmd, pulse = 500',
                     sMetricNamePrefix    := 'pump1/',
                     nRecordMetrics => nPump1Metrics,
                     nFirstBadClause => nPump1Bad);
```

| Parameter | |
| --- | --- |
| `anyData` | the record: a STRUCT, nested STRUCTs and arrays included |
| `anyPointList` | its point list: a `STRING` variable of any length, or a literal |
| `sMetricNamePrefix` | put before every metric name, up to 32 characters. Empty for none |
| `nRecordMetrics` | metrics the record declared |
| `nFirstBadClause` | the first clause that cannot be used, counting from 1; `0` none; `-1` when `anyData` is not a STRUCT or `anyPointList` not a STRING; `-4` when another variable already records with the same name and `sMetricNamePrefix` |
| `nLostWriteCount` | host writes to `cmd` and `set` members dropped because four were already waiting |

A record is found by where it is, so two instances of one function block can each
record their own local. Give each its own `sMetricNamePrefix`: with the same prefix their
metric names would collide, and the second is refused (`InvalidArgument`,
`nFirstBadClause` `-4`).

It returns `Ok` while the node is born, `NotConnected` while it is not (the
record is kept and goes in the next birth), `InvalidArgument` for a bad clause
or a `log`/`live` class with `tLiveInterval := T#0s`, `QueueFull` when memory
ran out or a message it asked for could not be queued (it asks again), and
`WrongTask` outside the node's task. A failing record also shows on the node:
`bError`, and `sLastError` such as `Record PUMP1: clause 3`. The other clauses
still apply.

## The point list

Clauses split by `;`. Each clause is

```
<members> = <class> [, <option>]*
```

Spaces are ignored; class names and option keys are not case-sensitive.

```
sts.fault, sts.faultId = now;
tot.runHours           = log, db = 0.5, u = h, lo = 0, hi = 100000;
tot.level              = log, u = @uLevel;
det                    = live;
set                    = set:pump;
cmd                    = cmd, pulse = 300
```

### Members

`<members>` is a comma list of **paths** into the STRUCT - the same names BeeBus
uses:

| In the STRUCT | Path |
| --- | --- |
| `levelMm : REAL` | `levelMm` |
| `pump : S_PUMP` with `hours : REAL` | `pump.hours` |
| `spare : ARRAY[1..3] OF REAL` | `spare[1]`, `spare[2]`, `spare[3]` - from 1, whatever the bounds |

A path **covers** more than one value:

- **Everything below it.** `pump` is every value in `pump`.
- **Every element.** A name without an index - `spare` - covers `spare[1]` to
  `spare[n]`.
- **`*` is any one segment.** `*` alone is every member; `sts.*` everything
  in `sts`; `*.fault` the `fault` of every member that has one.

Case does not matter. **A member no clause covers is not reported** - not a
metric at all. That is how internal counters and spares are left out.

### Classes

The class says when a value goes, where, and whether SCADA may write it.

| Class | Goes | Where | SCADA writes it |
| --- | --- | --- | --- |
| `now` | at once, always | the node | no |
| `cmd` | at once, always | the node | while `bAllowHostWrites` |
| `view` | at once while someone views the node; otherwise held | the node | no |
| `log` | what moved past its deadband, every `tLogInterval`; every `tLiveInterval` while viewed | the node | no |
| `live` | what moved, every `tLiveInterval`, while a host demands it | device `live` | no |
| `set:<page>` | at once while a host demands it | device `cfg-<page>` | while `bAllowHostWrites` |
| `every:<time>` | all of them every `<time>` (`T#1m`, `30s`, `1h30m`), moved or not; a birth counts as a send | the node | no |
| `onreq` | all of them on a rising edge of Record's `bSendOnRequest` | the node | no |

The timing and remote control are the node's, in `stReportConfig`:

| `ST_SparkplugReportConfig` | default | |
| --- | --- | --- |
| `tLogInterval` | `T#15m` | how often `log` looks for what moved. At most `T#15m`; `T#0s` is refused |
| `tLiveInterval` | `T#30s` | how often `live` sends, and `log` while viewed. `T#0s` is refused - never every scan |
| `fLogDeadbandPct` | `0` | the `log` class's deadband in %, for a REAL or LREAL whose clause gives no `pct=` |
| `bAllowHostWrites` | `FALSE` | `cmd` and `set:` take writes. FALSE: a write is dropped at once and the member reported back unchanged |

What each is for:

- **`now`** - alarms, faults, states, running bits. Anything SCADA must see at
  once.
- **`cmd`** - commands and setpoints SCADA writes. Reported back after every
  write, which is how SCADA knows it took.
- **`view`** - values worth seeing on the node's own screen and not worth a
  message while nobody looks.
- **`log`** - what a historian keeps: totals, hours, slow analogues. On a
  metered link a value that sits still costs nothing, and one that moves costs
  one value every 15 minutes at most.
- **`live`** - a detail screen's fast values, on their own device so the host
  can ask for them by name.
- **`set:<page>`** - a settings page, one device per page (`cfg-pump`,
  `cfg-tank`), born only while a host has the page open. `<page>` is up to 43
  characters, without `+`, `/` or `#`.
- **`every:<time>`** - a set that must go whole on a clock, whether it moved
  or not: a status report a host checks for freshness.
- **`onreq`** - a set sent whole when the program says so:
  `sp.Record(anyData := DEV.batch, anyPointList := '* = onreq', bSendOnRequest := bBatchDone)`.

An **interval class** (`log`, `live`, `every:`, `onreq`) is held between its sends: its values
stay current in the node, so a birth carries them as they are, but they do not
ride along in another class's message. Every record with the same interval
looks in the same scan, so their changes go in one message.

### Which clause wins

A value takes **one node class** - from the **last** `now`, `cmd`, `view`,
`log`, `every:` or `onreq` clause that covers it (and, separately, one class
on each `dev=` device) - and may **also** be in `live` (the last `live`
clause covering it) and in any number of `set:` pages (the last clause of each
page). Each of those is a metric of its own on that device. So

```
* = view; sts.fault = now; det = live
```

makes every value `view` except `sts.fault`, which is `now`, and puts every
value in `det` on the `live` device as well. A value's options come from the
clause that gave it that class.

### Options

| Option | |
| --- | --- |
| `db=<n>` | deadband in the member's units: a move this size or less from the value last sent is not reported |
| `pct=<n>` | deadband in % of the value last sent. With `db=`, a move must clear both |
| `u=<text>` | engineering units, sent in the birth (`engUnit`). A TIME says `ms` by itself |
| `u=@<member>` | the units are the `STRING` member of the node's `anyUnits` STRUCT with that path |
| `lo=<n>`, `hi=<n>` | the range a SCADA gauge or trend should show (`engLow`, `engHigh`). Equal is none |
| `pulse=<ms>` | `cmd` and `set:` only: this many **milliseconds** after a write, the PLC puts the member back to 0, FALSE or `''`. For a command that acts on an edge, so writing it again acts again |
| `dev=<name>` | `now`, `cmd`, `view`, `log`, `every:` and `onreq`: the clause's members go under the program's own device `<name>` instead of the node - `'* = now, dev=skid2'`. The program brings it on and off line with `sp.Device(sDeviceId := 'skid2', bBringOnline := ...)`; Live Demand never touches it. Not `live` or `cfg-...` |

- A deadband is measured from the value **last sent**, so a slow drift still
  adds up.
- **A deadband on a BOOL or STRING freezes it**, so it is refused when the
  clause names that member **itself** (`sts.fault = now, db = 1` is a bad
  clause). Covered by a wider path, the BOOL simply reports every change.
- A value SCADA wrote is always reported back, whatever the deadband.
- Units and ranges go out in the birth, so a change shows at the next birth.

### Units from a settings page

```st
VAR
  UNITS : S_UNITS;     (* uLevel : STRING(8) := 'mm'; uFlow : STRING(8) := 'm3/h' *)
END_VAR

sp(fbClient := mqtt, sGroupId := 'Plant1', sEdgeNodeId := 'pumps1', anyUnits := UNITS);
sp.Record(anyData := TANK, anyPointList := 'level = log, u = @uLevel; flow = log, u = @uFlow');
```

`anyUnits` is optional: a STRUCT of STRINGs the point lists name with
`u=@<member>`. An HMI may change a unit there; it shows at the next birth.
`u=@` naming a member that is not there is a bad clause.

## Metric names

The metric name is `sMetricNamePrefix` and the path:

| `sMetricNamePrefix` | path | class | metric | on |
| --- | --- | --- | --- | --- |
| `'pump1/'` | `sts.fault` | `now` | `pump1/sts.fault` | the node |
| `'pump1/'` | `spare[2]` | `log` | `pump1/spare[2]` | the node |
| `'pump1/'` | `det.rate` | `live` | `pump1/rate` | device `live` |
| `'pump1/'` | `set.onLevel` | `set:pump` | `pump1/onLevel` | device `cfg-pump` |

**`live` drops a leading `det.`, and a set page a leading `set.`** - the usual
shape of a record is `sts`, `det`, `set`, `cmd`, and on its own device the
group name says nothing. Only a leading `det.` or `set.` is dropped, and only
for those classes.

Use `sMetricNamePrefix` to keep two records' names apart - `'pump1/'`, `'pump2/'` - or
to put a group in its own folder at the SCADA end. A name already taken on the
node or device is refused, and that clause is reported on `nFirstBadClause`.

**The member name IS the metric name**, so the STRUCT declaration is the tag
list. Rename a member and you rename a tag.

## Types

Each metric's datatype is its IEC type (BOOL Boolean, INT Int16, REAL Float,
STRING String...). A TIME goes as Int64 milliseconds, both ways. An enumeration
goes as the unsigned integer it is stored as, both ways. DATE and TIME_OF_DAY
have no Sparkplug type and are left out; a clause that covers nothing else is
reported on `nFirstBadClause`.

## When the point list is read

- **Membership is read at the first call.** Which members, and which class each
  has, are fixed then: the birth has described them. A record is found again
  by its declared name and type, and `sMetricNamePrefix` - the same STRUCT with two
  prefixes is two records.
- **Options follow the text.** Change a `db=`, a `u=`, a range or a pulse while
  it runs - from an HMI, by writing the STRING - and it applies at once; units
  and ranges show at the next birth. A change of `anyUnits` or of
  `fLogDeadbandPct` is applied the same way.
- **Adding or removing a clause later is refused**: the clauses would not line
  up with the members read at the first call, and `nFirstBadClause` reports it
  (the first clause past the shorter list). Change membership with a restart.
- **A record first called after the birth makes the node birth again**, so the
  host has a birth for every name. Call every `Record` from the first scan.

## What makes a clause bad

`nFirstBadClause` names the first; the others still apply.

- no `=`, an empty member, or an unknown class or option key;
- an option value that is not a number, or a negative `db=`, `pct=` or `pulse=`;
- `pulse=` on a class SCADA does not write (`now`, `view`, `log`, `live`);
- `set:` with an empty page, one over 43 characters, or one with `+ / #`;
- a clause that covers no member;
- a member name already taken on the node or the device, or out of memory;
- a deadband on a BOOL or STRING the clause names itself;
- `u=@` naming no STRING member of `anyUnits`;
- the number of clauses changed since the first call.

## Live Demand

A record with a `view`, `log`, `live` or `set:` class makes the node offer
Live Demand: a writable metric `Node Control/Live Demand` that a host writes
while someone views the node. Then `view` sends, `log` speeds up to
`tLiveInterval`, and the `live` and `cfg-...` devices the host asks for are
born. Page 14 has the contract - the offer, the demand, the lease.

**Next:** [07 Block reference](07-block-reference.md) for every pin.
