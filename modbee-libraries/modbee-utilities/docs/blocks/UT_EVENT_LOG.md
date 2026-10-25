# UT_EVENT_LOG — Event log: what happened, and when

Keeps the last N events (trips, stops, end reasons) with their time, newest
first, so a technician can read "what happened overnight" on the HMI or over SCADA,
also for the hours the comms were down. Feed it the records' `stopReason`,
`lastFault` and `trips`, or any event pulse of your own. It can keep the log over a
power cut.

An event is codes, not words: its stop reason (`UT_STOP`), its fault (`UT_FAULT`)
and a code of your own (INT). The HMI or SCADA shows the words
([UT_STOP_TEXT](UT_STOP_TEXT.md) and [UT_STATUS_TEXT](UT_STATUS_TEXT.md) give them for
a simple display). You size the storage: the block uses the `Buffer` and `Sources`
arrays you declare.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Code` | INT | 0 | A code of your own (0 = none) |
| in | `Stop` | UT_STOP | UT_STOP_NONE | A stop reason, e.g. `Pump1.stopReason` |
| in | `Fault` | UT_FAULT | UT_F_NONE | A fault, e.g. `Pump1.lastFault` |
| in | `New` | BOOL | FALSE | Rising edge: log (`Code`, `Stop`, `Fault`) now (any event pulse) |
| in | `Count` | UDINT | 0 | Optional counter, e.g. `Pump1.trips`: each change logs (`Code`, `Stop`, `Fault`) |
| in | `Src` | INT | 1 | Source number: the element of `Sources` this call uses |
| in | `Clock` | DT | unwired | Real-time clock for the time stamps (e.g. [UT_SCHEDULE](UT_SCHEDULE.md)'s `Data.localTime`); unwired = the controller clock (UTC) |
| out | `Events` | INT | | Events in the log |
| out | `NewEvent` | BOOL | | On for the scan in which an event was logged (a beep, a report trigger) |
| inout | `Buffer` | ARRAY[*] OF UT_EVENT | | The log, newest first: as many slots as you declare |
| inout | `Sources` | ARRAY[*] OF UT_EVENT_SRC | | One element per source: what was last seen from it. The block writes it |
| inout | `Saved` | ARRAY[*] OF UT_EVENT | | The kept copy: declare it `RETAIN`, the same size as `Buffer`. Not used when the log is not kept (pass any one-element array) |
| inout | `Data` | UT_EVENT_LOG_DATA | | Settings and status (below) |

## Record `UT_EVENT_LOG_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `retained` | BOOL | FALSE | Keep the log over a power cut (in `Saved`) |
| `saveEvery` | TIME | T#12h | Kept: copy the log to `Saved` at most this often (the first event after a quiet spell at once). `T#0s` = not kept |
| `logPowerUp` | BOOL | TRUE | Log a power-up event (source 0, no codes) at every power-up |
| `cmdClear` | BOOL | | HMI: empty the log (and `Saved`, at once). Acts once, on its rising edge |
| `count` | INT | | Status: as `Events` |
| `logged` | UDINT | | Status: events logged since power-up |
| `lost` | UDINT | | Status: events pushed out of a full log since power-up |
| `wrnConfig` | BOOL | | Status: `Buffer` has no element, a negative `saveEvery`, or `Saved` smaller than `Buffer` while kept |
| `wrnSrc` | BOOL | | Status: a call this scan had a `Src` outside `Sources` (that call is ignored) |

## Slot `UT_EVENT`
| Field | Type | Meaning |
| --- | --- | --- |
| `seq` | UDINT | Running number of the event (0 = an empty slot). Carries on over a power cut when the log is kept |
| `stamp` | DT | When it happened (`Clock`) |
| `src` | INT | The source (the `Src` of the call; 0 = the log itself: the power-up event) |
| `code` | INT | Your own code (the `Code` pin; 0 = none) |
| `stop` | UT_STOP | The stop reason (the `Stop` pin) |
| `fault` | UT_FAULT | The fault (the `Fault` pin) |

`UT_EVENT_SRC` (`code`, `stop`, `fault`, `count`, `newPrev`, `seen`) is the block's
memory of each source; don't write it.

## How it works
- **Call it once per source per scan**, all calls on the same instance, `Buffer`,
  `Sources`, `Saved` and `Data`, each with its own `Src` (as
  [UT_MSG_QUEUE](UT_MSG_QUEUE.md)). Give each call its own unconditional rung in
  Ladder or FBD. The order of the calls is the order of events that come in the same
  scan.
- A call logs one event when, for its source:
  - `New` has a rising edge, or
  - `Code` changes to a value other than 0, `Stop` to a reason other than
    `UT_STOP_NONE`, or `Fault` to a fault other than `UT_F_NONE`, or
  - `Count` changes (a trip counter: every trip is logged, also the same one again).
- One of these in a call gives one event, with the call's `Code`, `Stop` and `Fault`.
- A pin a call leaves unwired never takes another call's value: the block sets its
  pins back to their defaults after each call.
- What a source shows at its first call after a power-up is its starting point,
  not an event (as a command never acts on the first scan). The power-up event
  (source 0, no codes) marks that moment.
- **Newest first**: the first element of `Buffer` is the newest event; a new one
  moves the others down, and a full log drops the oldest (counted in `lost`).
- **Kept over a power cut** (`retained` TRUE and `saveEvery` above 0): `Saved` gets
  a copy of the log. The first event after a quiet spell (no copy for `saveEvery`) is
  copied at once, with any others of the same scan; later ones wait until
  `saveEvery` has passed since that copy, so a burst of events writes the
  controller's storage once. The power-up event is copied at once and starts no
  wait (one copy per power-up), so the first trip after a power cut is kept at once
  too. At power-up the log is read back from `Saved`, with a new power-up event on top,
  and the running numbers carry on. With the default 12 h an event after the first
  of a busy spell can be lost by a power cut within 12 h; a shorter `saveEvery` keeps
  more but writes the storage more often (see
  [conventions](../conventions.md#retained-data)).
- Not kept (the default, or `saveEvery` `T#0s`): the log starts empty at every
  power-up (with the power-up event if `logPowerUp`), and `Saved` is not touched.
- `cmdClear` empties the log and, when kept, `Saved` at once.
- The block is called many times a scan; `NewEvent` stays on for the rest of the
  scan in which an event came, and `cmdClear` and the copy act once per scan.

## Using it
```iecst
(* Saved is declared RETAIN, the same size as Log *)
Ev(Code := 0, Stop := Pump1.stopReason, Src := 1, Clock := Sched.Data.localTime,
   Buffer := Log, Sources := EvSrc, Saved := LogSaved, Data := EvCfg);
Ev(Fault := Pump1.lastFault, Count := Pump1.trips, Src := 2, Clock := Sched.Data.localTime,
   Buffer := Log, Sources := EvSrc, Saved := LogSaved, Data := EvCfg);
Ev(Stop := Valve1.stopReason, Src := 3, Clock := Sched.Data.localTime,
   Buffer := Log, Sources := EvSrc, Saved := LogSaved, Data := EvCfg);
```
with `Log : ARRAY[1..20] OF UT_EVENT; EvSrc : ARRAY[1..3] OF UT_EVENT_SRC;
EvCfg : UT_EVENT_LOG_DATA := (retained := TRUE);` and
`VAR RETAIN LogSaved : ARRAY[1..20] OF UT_EVENT; END_VAR`. Wire `Code` in at least
one call (0 when you have no code of your own): the editor's check wants a
block's first input assigned.
