# FB_EventLog — Event log

The last events (trips, stops, end reasons) with their time, newest first, optionally kept over a power cut: "what happened overnight".

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `nUserCode` | `INT` |  | a code of your own (0 = none) |
| in | `eStopReasonToLog` | `E_StopReason` |  | a stop reason |
| in | `eErrorToLog` | `E_UtError` |  | an error |
| in | `bLogNow` | `BOOL` |  | rising edge: log the codes now |
| in | `nCounter` | `UDINT` |  | optional counter: each change logs the codes |
| in | `nSource` | `INT` | `1` | the source: the element of aSources this call uses |
| in | `dtLocalTime` | `DT` | `DT#1970-01-01-00:00:00` | a real-time clock (optional); unwired: stamps stay blank |
| in | `refData` | `REFERENCE TO ST_EventLogData` |  | the block's record (one rung per source, all with the same record) |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aEvents` | `ARRAY[*] OF ST_Event` |  | the log, newest first: as many slots as declared |
| in-out | `aSources` | `ARRAY[*] OF ST_EventSrc` |  | what was last seen per source, index = nSource |
| out | `nEventsInLog` | `INT` |  | events in the log |
| out | `bEventLogged` | `BOOL` |  | on for the scan in which an event was logged |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_EventLogData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdClearLog` | `BOOL` |  | empty the log and the kept copy (cleared by the block) |

**Settings `set`** (`ST_EventLogSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bKeepOverPowerCut` | `BOOL` | `TRUE` | keep the log over a power cut (up to 16 events) |
| `tKeptCopyInterval` | `TIME` | `T#1h` | kept: copied at most this often (after a quiet spell: at once); 0 = not kept |
| `bLogPowerUp` | `BOOL` | `TRUE` | log a power-up event (source 0) at every power-up |

**Status `sts`** (`ST_EventLogSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stNewestEvent` | `ST_Event` |  | the newest event; fields below |
| `nEventsInLog` | `INT` |  | events in the log now |
| `nEventLoggedCount` | `UDINT` |  | events logged since power-up |
| `nEventLostCount` | `UDINT` |  | events that pushed an old one out of a full log |
| `bBufferSizeBad` | `BOOL` |  | aEvents has no element, or more than 16 while kept |
| `bSourceOutOfRange` | `BOOL` |  | a call this scan had an nSource outside aSources (ignored) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

**`stNewestEvent`** (`ST_Event`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nEventNumber` | `UDINT` |  | running number of the event (0 = empty slot) |
| `dtTimeStamp` | `DT` |  | when it happened (dtLocalTime) |
| `nSource` | `INT` |  | the source (0 = the log itself, power-up) |
| `nUserCode` | `INT` |  | your own code (0 = none) |
| `eStopReason` | `E_StopReason` |  | the stop reason logged |
| `eLoggedErrorId` | `E_UtError` |  | the error logged |

## Rows `ST_EventSrc` (pin `aSources`)

`aSources` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_EventSrc`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nLastUserCode` | `INT` |  | engine memory: the last code seen for this source |
| `eLastStopReason` | `E_StopReason` |  | engine memory: the last stop reason seen |
| `eLastErrorId` | `E_UtError` |  | engine memory: the last error seen |
| `nLastCounter` | `UDINT` |  | engine memory: the last counter value seen |
| `bLogNowLastScan` | `BOOL` |  | engine memory: bLogNow on the last scan |
| `bEverHeard` | `BOOL` |  | engine memory: this source has been seen |

## How it works

The last N events (trips, stops, end reasons) with their time, newest first, for "what happened overnight"; optionally kept over a power cut.

Call it once per source per scan, all calls on the same instance, `aEvents`, `aSources` and `refData` (one rung each). With `fbLog : FB_EventLog`, `fbPump1 : FB_Pump`, `stPump1 : ST_PumpData` (its record),
`stEvLog : ST_EventLogData`, `aEv : ARRAY[1..16] OF ST_Event` and `aEvSrc : ARRAY[1..2] OF ST_EventSrc`:

```
fbLog(nUserCode := 0, eStopReasonToLog := stPump1.sts.eStopReason, nSource := 1,
      aEvents := aEv, aSources := aEvSrc, refData := stEvLog);
fbLog(eErrorToLog := fbPump1.eErrorId, nCounter := stPump1.sts.stStartFailFault.nTripCount, nSource := 2,
      aEvents := aEv, aSources := aEvSrc, refData := stEvLog);
```

An event is codes, not words: its stop reason (`E_StopReason`), its error (`E_UtError`) and a code of your own (INT); the HMI or SCADA shows the words. A call logs one event (`nUserCode`, `eStopReasonToLog`, `eErrorToLog`) when, for its source: `bLogNow` has a rising edge (any event pulse); `nUserCode` changes to a value other than 0, `eStopReasonToLog` to one other than None, or `eErrorToLog` to one other than None; or `nCounter` changes (a counter such as a record's trips: every trip is logged, also the same one again). The calls share one instance, so the block sets its pins back to their defaults after each call (`nUserCode` 0, `eStopReasonToLog` None, `eErrorToLog` None, `bLogNow` FALSE, `nCounter` 0, `nSource` 1, `dtLocalTime` unwired): a pin a call leaves unwired never carries another call's value. What a source shows at its first call after a power-up is its starting point, not an event; the power-up event (source 0) marks that moment. `aSources`[nSource] keeps what was last seen from each source (the block writes it). `aEvents` is the log, newest first (its first element is the newest event); a new one moves the others down, and the oldest falls off a full log (`sts.nEventLostCount`). Each event has its time (`dtLocalTime`, optional; unwired: blank - the boards have no real-time clock), source, codes and a running number `nEventNumber` (0 = an empty slot). `set.bLogPowerUp` adds a power-up event (source 0, no codes) at every power-up.

Kept over a power cut (`set.bKeepOverPowerCut`, the default, and `set.tKeptCopyInterval` above 0): the block's own kept copy (up to 16 events). The first event after a quiet spell (no save for `tKeptCopyInterval`) is copied at once, with any others of the same scan; later ones wait until `tKeptCopyInterval` has passed since that copy, so a burst of events writes the controller's storage once. The power-up event is copied at once and does not start the wait. At power-up the log is read back from the kept copy. `bCmdClearLog` empties the log (and the kept copy at once). The newest event is in `sts.stNewestEvent`. One instance is called many times in a scan (TIME() is the same for the whole scan): `bEventLogged` stays on for the rest of the scan in which an event came; the command and the saving act once per scan.

## Example

The last 16 events of two pumps. Declare `aEv : ARRAY[1..16] OF ST_Event` and `aEvSrc : ARRAY[1..2] OF ST_EventSrc`.

| Pin | Wire |
| --- | --- |
| `eStopReasonToLog` | `stPump1.sts.eStopReason` |
| `eErrorToLog` | `fbPump1.eErrorId` |
| `nSource` | 1 |
| `aEvents` | `aEv` |
| `aSources` | `aEvSrc` |
| `refData` | `stEvLog` |

A second rung calls the same instance with pump 2's codes and `nSource := 2`.

**Back to** [the index](../README.md).
