# FB_EventLog — Event log

The last events (trips, stops, end reasons) with their time, newest first, optionally kept over a power cut: "what happened overnight".

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `nCode` | `INT` |  | a code of your own (0 = none) |
| in | `eStop` | `E_StopReason` |  | a stop reason |
| in | `eFault` | `E_UtError` |  | an error |
| in | `bNew` | `BOOL` |  | rising edge: log the codes now |
| in | `nCount` | `UDINT` |  | optional counter: each change logs the codes |
| in | `nSrc` | `INT` | `1` | the source: the element of aSources this call uses |
| in | `dtClock` | `DT` | `DT#1970-01-01-00:00:00` | a real-time clock (optional); unwired: stamps stay blank |
| in | `refData` | `REFERENCE TO ST_EventLogData` |  | one rung each |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aBuffer` | `ARRAY[*] OF ST_Event` |  | the log, newest first: as many slots as declared |
| in-out | `aSources` | `ARRAY[*] OF ST_EventSrc` |  | what was last seen per source, index = nSrc |
| out | `nEvents` | `INT` |  | events in the log |
| out | `bNewEvent` | `BOOL` |  | on for the scan in which an event was logged |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_EventLogData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdClear` | `BOOL` |  | empty the log and the kept copy (cleared by the block) |

**Settings `set`** (`ST_EventLogSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bRetained` | `BOOL` | `TRUE` | keep the log over a power cut (up to 16 events) |
| `tSaveEvery` | `TIME` | `T#1h` | kept: copied at most this often (after a quiet spell: at once); 0 = not kept |
| `bLogPowerUp` | `BOOL` | `TRUE` | log a power-up event (source 0) at every power-up |

**Status `sts`** (`ST_EventLogSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stLast` | `ST_Event` |  | the newest event; fields below |
| `nEvents` | `INT` |  |  |
| `nLogged` | `UDINT` |  |  |
| `nLost` | `UDINT` |  |  |
| `bWrnConfig` | `BOOL` |  | aBuffer has no element, or more than 16 while kept |
| `bWrnSrc` | `BOOL` |  | a call this scan had an nSrc outside aSources (ignored) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

**`stLast`** (`ST_Event`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nSeq` | `UDINT` |  | running number of the event (0 = empty slot) |
| `dtStamp` | `DT` |  | when it happened (dtClock) |
| `nSrc` | `INT` |  | the source (0 = the log itself, power-up) |
| `nCode` | `INT` |  | your own code (0 = none) |
| `eStop` | `E_StopReason` |  |  |
| `eFault` | `E_UtError` |  |  |

## Rows `ST_EventSrc` (pin `aSources`)

`aSources` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_EventSrc`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCode` | `INT` |  |  |
| `eStop` | `E_StopReason` |  |  |
| `eFault` | `E_UtError` |  |  |
| `nCount` | `UDINT` |  | Count |
| `bNewPrev` | `BOOL` |  |  |
| `bSeen` | `BOOL` |  |  |

## How it works

The last N events (trips, stops, end reasons) with their time, newest first, for "what happened overnight"; optionally kept over a power cut.

Call it once per source per scan, all calls on the same instance, `aBuffer`, `aSources` and `refData` (one rung each): `fbLog`(`nCode` := 0, `eStop` := `fbPump1.eStopReason`, `nSrc` := 1, `aBuffer` := `aEvLog`, `aSources` := `aEvSrc`, `refData` := `stEvLog`); `fbLog`(`eFault` := `fbPump1.eErrorId`, `nCount` := `stPump1.tot`.nTrips, `nSrc` := 2, ...); An event is codes, not words: its stop reason (`E_StopReason`), its error (`E_UtError`) and a code of your own (INT); the HMI or SCADA shows the words. A call logs one event (`nCode`, `eStop`, `eFault`) when, for its source: `bNew` has a rising edge (any event pulse); `nCode` changes to a value other than 0, `eStop` to one other than None, or `eFault` to one other than None; or `nCount` changes (a counter such as a record's trips: every trip is logged, also the same one again). The calls share one instance, so the block sets its pins back to their defaults after each call (`nCode` 0, `eStop` None, `eFault` None, `bNew` FALSE, `nCount` 0, `nSrc` 1, `dtClock` unwired): a pin a call leaves unwired never carries another call's value. What a source shows at its first call after a power-up is its starting point, not an event; the power-up event (source 0) marks that moment. `aSources`[nSrc] keeps what was last seen from each source (the block writes it). `aBuffer` is the log, newest first (its first element is the newest event); a new one moves the others down, and the oldest falls off a full log (`sts.nLost`). Each event has its time (`dtClock`, optional; unwired: blank - the boards have no real-time clock), source, codes and a running number `nSeq` (0 = an empty slot). `set.bLogPowerUp` adds a power-up event (source 0, no codes) at every power-up.

Kept over a power cut (`set.bRetained`, the default, and `set.tSaveEvery` above 0): the block's own kept copy (up to 16 events). The first event after a quiet spell (no save for `tSaveEvery`) is copied at once, with any others of the same scan; later ones wait until `tSaveEvery` has passed since that copy, so a burst of events writes the controller's storage once. The power-up event is copied at once and does not start the wait. At power-up the log is read back from the kept copy. `bCmdClear` empties the log (and the kept copy at once). The newest event is in `sts.stLast`. One instance is called many times in a scan (TIME() is the same for the whole scan): `bNewEvent` stays on for the rest of the scan in which an event came; the command and the saving act once per scan.

## Example

The last 16 events of two pumps. Declare `aEv : ARRAY[1..16] OF ST_Event` and `aEvSrc : ARRAY[1..2] OF ST_EventSrc`.

| Pin | Wire |
| --- | --- |
| `eStop` | `stPump1.sts.eStopReason` |
| `eFault` | `fbPump1.eErrorId` |
| `nSrc` | 1 |
| `aBuffer` | `aEv` |
| `aSources` | `aEvSrc` |
| `refData` | `stEvLog` |

A second rung calls the same instance with pump 2's codes and `nSrc := 2`.

**Back to** [the index](../README.md).
