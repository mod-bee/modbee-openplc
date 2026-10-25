# UT_MSG_QUEUE — Message ticker and site-status board

Puts the plant's status messages on one HMI text line. Every device block that can
stop equipment has a `statusCode` and a `faultId`; feed them all into one
UT_MSG_QUEUE and it shows them one at a time.

- **QUEUE** (the default): a message ticker. Each new or changed message is queued,
  shown for `showTime`, then dropped, in the order they came.
- **ACTIVE**: a site-status board, "what's wrong now". Each source has one slot
  holding its current message; when the source goes back to normal the slot goes.
  The display goes round the active ones every `showTime`.

A message is codes, not words: the source's status and fault. The block keeps only
the codes, and makes the words of the one message on display (`Message`, with
[UT_STATUS_TEXT](UT_STATUS_TEXT.md)); an HMI can show its own words from `MsgStatus`
and `MsgFault`. You size the storage: the block uses the `Buffer` and `Sources`
arrays you declare, so its RAM is what you give it.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Status` | UT_STATUS | UT_ST_IDLE | The source's status, e.g. `Pump1.statusCode` (from the record) |
| in | `Fault` | UT_FAULT | UT_F_NONE | Its fault, e.g. `Pump1.faultId` |
| in | `Src` | INT | 1 | Source number: the element of `Sources` this call uses |
| in | `Clock` | DT | | Optional real-time clock: each message is stamped with it |
| out | `Message` | STRING(30) | | The message on display in words, `UT_STATUS_TEXT(MsgStatus, MsgFault)` (`''` = none) |
| out | `Count` | INT | | Messages waiting, with the one shown (QUEUE), or active (ACTIVE) |
| out | `MsgSrc` | INT | | Source of the message on display (0 when none; check `Count`) |
| out | `MsgStatus` | UT_STATUS | | Its status (`UT_ST_IDLE` when none) |
| out | `MsgFault` | UT_FAULT | | Its fault (`UT_F_NONE` when none) |
| out | `NewMsg` | BOOL | | On for the scan in which a message came or changed (a beep, a log trigger) |
| inout | `Buffer` | ARRAY[*] OF UT_MSG | | The slots: as many as you declare |
| inout | `Sources` | ARRAY[*] OF UT_MSG_SRC | | One element per source: the last status and fault seen. The block writes it |
| inout | `Data` | UT_MSG_DATA | | Settings and status (below) |

## Record `UT_MSG_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `mode` | UT_MQ_MODE | UT_MQ_QUEUE | `UT_MQ_QUEUE` (0): each new message once, in turn. `UT_MQ_ACTIVE`: each source's current message. A change starts afresh |
| `showTime` | TIME | T#3s | Each message is on display this long (at least one scan; `T#0s` = one scan each) |
| `minKind` | UT_KIND | UT_KIND_HELD | Only statuses of this kind or worse are taken ([UT_STATUS_KIND](UT_STATUS_TEXT.md)). The order is normal, held, warning, fault, then configuration. `UT_KIND_HELD` = held / waiting, warnings, faults and configuration; `UT_KIND_WARNING` = warnings and worse; `UT_KIND_NORMAL` = every change (QUEUE: an event log, "Off" too). ACTIVE never shows `UT_ST_IDLE`, `UT_ST_OFF` or `UT_ST_OK` |
| `whenFull` | UT_MQ_FULL | UT_MQ_DROP_OLDEST | `UT_MQ_DROP_OLDEST` (0): make room by dropping the oldest (counted in `lost`). `UT_MQ_HOLD_NEW`: keep what is there; a new message waits until there is room (its source is tried again on every call) |
| `clearFullAfter` | TIME | T#0s | QUEUE: a buffer that stays full this long is emptied (counted in `lost`). `T#0s` = never |
| `cmdClear` | BOOL | | HMI: QUEUE empties the queue. ACTIVE builds the list again from the sources now |
| `cmdNext` | BOOL | | HMI: show the next message now (QUEUE drops the one on display) |
| `count` | INT | | Status: as `Count` |
| `full` | BOOL | | Status: every slot used |
| `lost` | UDINT | | Status: messages dropped to make room, or by `clearFullAfter` (since power-up) |
| `wrnConfig` | BOOL | | Status: a setting is invalid (a safe value is used), or `Buffer` or `Sources` is empty |
| `wrnSrc` | BOOL | | Status: a call this scan had a `Src` outside `Sources` (that call is ignored) |

## Slot `UT_MSG`
| Field | Type | Meaning |
| --- | --- | --- |
| `stamp` | DT | `Clock` when the message came (or changed) |
| `src` | INT | Source number |
| `status` | UT_STATUS | Its status |
| `fault` | UT_FAULT | Its fault |

## Source `UT_MSG_SRC` (written by the block)
| Field | Type | Meaning |
| --- | --- | --- |
| `status` | UT_STATUS | The last status seen from this source |
| `fault` | UT_FAULT | The last fault seen from this source |
| `known` | BOOL | FALSE: nothing seen yet (ACTIVE builds again) |

**RAM.** A slot holds no text, only the time stamp and three small codes, and a
source two codes and a flag, so a large buffer costs little. Size the buffer for
the messages you want to keep, not for every device: in ACTIVE mode a site rarely
has more than a handful of things wrong at once.

## How it works
- **Call it once per source per scan**, all calls on the same instance, `Buffer`,
  `Sources` and `Data`. Give each call its own `Src`. The order of the calls is
  the order of messages that arrive in the same scan.
- `Sources[Src]` keeps the last status and fault seen from that source. Nothing is
  taken until one of them changes, so 20 sources cost a few number compares each a
  scan. A countdown is not a change: the time left is in the device's record
  (`timeLeft`), not in the message.
- A status below `minKind` is not taken; in ACTIVE mode it (or `UT_ST_IDLE`,
  `UT_ST_OFF`, `UT_ST_OK`) removes that source's slot and the rest move up.
- ACTIVE: a new fault with the same status (one protection taking over from
  another) updates the source's slot in place; if it is on display, `Message`
  changes at once.
- QUEUE: a source that changes status or fault again before its first message is
  shown gets a second message. Use ACTIVE when only the latest matters.
- `NewMsg` stays on for the rest of the scan in which a message came, whichever
  call took it; `cmdClear` and `cmdNext` act once per scan. (`TIME()` is the same
  for the whole scan, which is how the block knows a new scan has started.)
- `MsgSrc` and `Src` count however you number your `Sources` array:
  `ARRAY[1..20] OF UT_MSG_SRC` takes sources 1..20, `ARRAY[0..9] OF UT_MSG_SRC`
  sources 0..9.
  `Buffer` can start at any index too. An empty `Buffer` keeps nothing.
- Every loop is bounded by the arrays you declare; there are no WHILE loops.
- Nothing is retained: after a power cut the buffer starts empty, and every source
  with a status of `minKind` or worse comes back in on its first call.

## Using it
```iecst
VAR
  Msgs : UT_MSG_QUEUE;
  MsgBuf : ARRAY[1..8] OF UT_MSG;          (* 8 messages at a time *)
  MsgSrc : ARRAY[1..6] OF UT_MSG_SRC;      (* sources 1..6 *)
  MsgCfg : UT_MSG_DATA := (mode := UT_MQ_ACTIVE, showTime := T#4s);
  HmiLine : STRING(30);
END_VAR

Msgs(Status := Pump1Data.statusCode, Fault := Pump1Data.faultId, Src := 1, Clock := SiteClock,
     Buffer := MsgBuf, Sources := MsgSrc, Data := MsgCfg);
Msgs(Status := Pump2Data.statusCode, Fault := Pump2Data.faultId, Src := 2, Clock := SiteClock,
     Buffer := MsgBuf, Sources := MsgSrc, Data := MsgCfg);
Msgs(Status := StationData.statusCode, Fault := StationData.faultId, Src := 3, Clock := SiteClock,
     Buffer := MsgBuf, Sources := MsgSrc, Data := MsgCfg);
Msgs(Status := DoseData.statusCode, Fault := DoseData.faultId, Src := 4, Clock := SiteClock,
     Buffer := MsgBuf, Sources := MsgSrc, Data := MsgCfg);
(* a plain condition with no status record: give it a status of its own *)
Msgs(Status := SEL(HighLevelFloat, UT_ST_IDLE, UT_ST_WARNING), Fault := UT_F_HIGH,
     Src := 5, Buffer := MsgBuf, Sources := MsgSrc, Data := MsgCfg);
HmiLine := Msgs.Message;    (* or the HMI's own words for Msgs.MsgStatus / MsgFault *)
```
In Ladder or FBD, give each call its own unconditional rung (see
[ladder-rules.md](../ladder-rules.md)); the calls share the instance.

For a ticker of events, leave `mode` at QUEUE.
For a "what's wrong now" board next to an overview screen, use ACTIVE.

## Bad settings
A negative `showTime` acts as 3 s, an unknown `minKind` as `UT_KIND_HELD`, a negative
`clearFullAfter` as `T#0s`, an unknown `mode` as QUEUE and an unknown `whenFull`
as DROP_OLDEST; each sets `wrnConfig`. An empty `Buffer` or `Sources` also sets
`wrnConfig`.
