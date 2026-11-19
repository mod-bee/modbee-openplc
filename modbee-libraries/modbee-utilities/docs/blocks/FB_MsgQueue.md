# FB_MsgQueue — HMI message queue

A message ticker and site-status board for an HMI: each source's state and error code, queued or as a list of what is wrong now.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eSourceState` | `E_State` |  | the source's state (e.g. fbPump1.eState) |
| in | `eSourceErrorId` | `E_UtError` |  | its error (e.g. fbPump1.eErrorId) |
| in | `nSource` | `INT` | `1` | the source: the element of aSources this call uses |
| in | `dtLocalTime` | `DT` |  | optional real-time clock: stamped on each message |
| in | `refData` | `REFERENCE TO ST_MsgQueueData` |  | the block's record (one rung per source, all with the same record) |
| in | `ipSystem` | `I_SystemMode` |  | the system mode block; unwired: no system Auto / power-up hold / reset. An instance of a block that offers I_SystemMode (FB_SystemMode) *(from FB_Object)* |
| in-out | `aMessages` | `ARRAY[*] OF ST_Msg` |  | the slots: as many as declared |
| in-out | `aSources` | `ARRAY[*] OF ST_MsgSrc` |  | last state and error seen per source, index = nSource |
| out | `nMessages` | `INT` |  | messages waiting (Queue) or active (Active) |
| out | `nShownSource` | `INT` |  | the source of the message on display (0 when none) |
| out | `eShownState` | `E_State` |  | its state (Idle when none) |
| out | `eShownErrorId` | `E_UtError` |  | its error (None when none) |
| out | `bMessageReceived` | `BOOL` |  | on for the scan in which a message came (or changed) |
| out | `bError` | `BOOL` |  | TRUE while a trip or setting fault is active *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | which error: the first since the last reset, else the first warning; None when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | what it is doing now: Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MsgQueueData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdClearMessages` | `BOOL` |  | Queue empties it; Active builds it again (cleared by the block) |
| `bCmdNextMessage` | `BOOL` |  | the next message now (Queue drops the one on display) |

**Settings `set`** (`ST_MsgQueueSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eQueueMode` | `E_MsgMode` |  | Queue (each new message once) or Active (each source's current one) |
| `tDisplayTime` | `TIME` | `T#3s` | each message is on display this long |
| `eMinMessageKind` | `E_MsgKind` | `E_MsgKind.Held` | only messages of this kind or worse (Normal = every change) |
| `eWhenFull` | `E_MsgFull` |  | DropOldest, or HoldNew (new ones wait for room) |
| `tClearFullAfter` | `TIME` |  | Queue: a buffer full this long is emptied (0 = never) |

**Status `sts`** (`ST_MsgQueueSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nMessages` | `INT` |  | messages waiting (Queue) or active (Active) |
| `bBufferFull` | `BOOL` |  | the buffer is full |
| `nMessageLostCount` | `UDINT` |  | messages lost to a full buffer |
| `bBufferSizeBad` | `BOOL` |  | no slot or no source |
| `bSourceOutOfRange` | `BOOL` |  | a call this scan had an nSource outside aSources (ignored) |
| `bSettingRefused` | `BOOL` |  | a setting write was refused and the last good value put back (until a reset) |
| `eSettingRefusedErrorId` | `E_UtError` |  | why the last write was refused (cleared with bSettingRefused) |

## Rows `ST_Msg` (pin `aMessages`)

`aMessages` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_Msg`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `dtTimeStamp` | `DT` |  | dtLocalTime when it came (or changed) |
| `nSource` | `INT` |  | the source (0 = empty) |
| `eSourceState` | `E_State` |  | the source's state |
| `eSourceErrorId` | `E_UtError` |  | the source's error |

## Rows `ST_MsgSrc` (pin `aSources`)

`aSources` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_MsgSrc`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eLastState` | `E_State` |  | engine memory: the last state seen for this source |
| `eLastErrorId` | `E_UtError` |  | engine memory: the last error seen |
| `bEverHeard` | `BOOL` |  | FALSE: nothing seen yet (Active builds again) |

## Lists

- `E_MsgFull`: `DropOldest`, `HoldNew` (default `DropOldest`)
- `E_MsgKind`: `Normal`, `Held`, `Warning`, `Fault` (default `Normal`)
- `E_MsgMode`: `Queue`, `Active` (default `Queue`)

## How it works

Message ticker and site-status board for an HMI (messages are codes: the source's `eState` and `eErrorId`, the HMI shows the words).

Call it once per source per scan, all calls on the same instance, `aMessages`, `aSources` and `refData` (one rung each): `fbMsgs`(`eSourceState` := `fbPump1.eState`, `eSourceErrorId` := `fbPump1.eErrorId`, `nSource` := 1, `aMessages` := `aMsgBuf`, `aSources` := `aMsgSrc`, `refData` := `stMsgs`); `fbMsgs`(`eSourceState` := `fbPump2.eState`, `eSourceErrorId` := `fbPump2.eErrorId`, `nSource` := 2, ...); `aSources`[nSource] keeps the last state and error seen from that source, so a message is taken only when one of them changes. Its kind: Fault (`eSourceState` Fault), Warning (an `eSourceErrorId`, not Fault), Held (Held or Waiting), else Normal; only kinds of `set.eMinMessageKind` or worse are taken (default Held; Normal: every change).

```
  Queue   (the default) each new or changed message is queued, shown for set.tDisplayTime, then dropped, in the order
          they came.
  Active  one slot per source holds its current message; a kind below eMinMessageKind (or Idle, Off, Running with no
          error) removes it; the display goes round the active ones every tDisplayTime ("what's wrong now").
```

When the buffer is full: `set.eWhenFull` DropOldest makes room by dropping the oldest (`sts.nMessageLostCount`); HoldNew keeps what is there and new messages wait for room (their source is tried again on every call). Queue: a buffer that stays full for `set.tClearFullAfter` is emptied. `bCmdClearMessages`: Queue empties it; Active builds it again from the sources. `bCmdNextMessage`: the next message now (Queue drops the one on display).

RAM is what you declare: one `ST_Msg` per slot, one `ST_MsgSrc` per source. One instance is called many times in a scan (TIME() is the same for the whole scan): `bMessageReceived` stays on for the rest of the scan in which a message arrived, and the commands act once per scan.

## Example

A status ticker for two pumps. Declare `aMsg : ARRAY[1..8] OF ST_Msg` and `aMsgSrc : ARRAY[1..2] OF ST_MsgSrc`.

| Pin | Wire |
| --- | --- |
| `eSourceState` | `fbPump1.eState` |
| `eSourceErrorId` | `fbPump1.eErrorId` |
| `nSource` | 1 |
| `aMessages` | `aMsg` |
| `aSources` | `aMsgSrc` |
| `refData` | `stMsgs` |

A second rung calls the same instance with pump 2's codes and `nSource := 2`.

**Back to** [the index](../README.md).
