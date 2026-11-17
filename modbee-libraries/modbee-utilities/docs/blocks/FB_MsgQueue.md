# FB_MsgQueue — HMI message queue

A message ticker and site-status board for an HMI: each source's state and error code, queued or as a list of what is wrong now.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `eSrcState` | `E_State` |  | the source's state (e.g. fbPump1.eState) |
| in | `eSrcError` | `E_UtError` |  | its error (e.g. fbPump1.eErrorId) |
| in | `nSrc` | `INT` | `1` | the source: the element of aSources this call uses |
| in | `dtClock` | `DT` |  | optional real-time clock: stamped on each message |
| in | `refData` | `REFERENCE TO ST_MsgQueueData` |  | one rung each |
| in | `ipSystem` | `I_SystemMode` |  | The FB_SystemMode instance (optional): system Auto, the power-up hold and the plant reset *(from FB_Object)* |
| in-out | `aBuffer` | `ARRAY[*] OF ST_Msg` |  | the slots: as many as declared |
| in-out | `aSources` | `ARRAY[*] OF ST_MsgSrc` |  | last state and error seen per source, index = nSrc |
| out | `nCount` | `INT` |  | messages waiting (Queue) or active (Active) |
| out | `nMsgSrc` | `INT` |  | the source of the message on display (0 when none) |
| out | `eMsgState` | `E_State` |  | its state (Idle when none) |
| out | `eMsgError` | `E_UtError` |  | its error (None when none) |
| out | `bNewMsg` | `BOOL` |  | on for the scan in which a message came (or changed) |
| out | `bError` | `BOOL` |  | TRUE while a trip or a setting fault is active: a fault lamp, an alarm *(from FB_Object)* |
| out | `bWarning` | `BOOL` |  | TRUE while a warning is active (no trip) *(from FB_Object)* |
| out | `eErrorId` | `E_UtError` |  | Which error: the first since the last reset, else the first warning; `None` when all is well *(from FB_Object)* |
| out | `eState` | `E_State` |  | What it is doing now (Off, Idle, Waiting, Starting, Running, Stopping, Held, Fault) *(from FB_Object)* |

`bError`, `bWarning`, `eErrorId`, `eState` work as in every block: see [errors and state](../conventions.md#errors-and-state).

## Record `ST_MsgQueueData` (pin `refData`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `bCmdClear` | `BOOL` |  | Queue empties it; Active builds it again (cleared by the block) |
| `bCmdNext` | `BOOL` |  | the next message now (Queue drops the one on display) |

**Settings `set`** (`ST_MsgQueueSet`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eMode` | `E_MsgMode` |  | Queue (each new message once) or Active (each source's current one) |
| `tShowTime` | `TIME` | `T#3s` | each message is on display this long |
| `eMinKind` | `E_MsgKind` | `E_MsgKind.Held` | only messages of this kind or worse (Normal = every change) |
| `eWhenFull` | `E_MsgFull` |  | DropOldest, or HoldNew (new ones wait for room) |
| `tClearFullAfter` | `TIME` |  | Queue: a buffer full this long is emptied (0 = never) |

**Status `sts`** (`ST_MsgQueueSts`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `nCount` | `INT` |  | Count |
| `bFull` | `BOOL` |  |  |
| `nLost` | `UDINT` |  |  |
| `bWrnConfig` | `BOOL` |  | no slot or no source |
| `bWrnSrc` | `BOOL` |  | a call this scan had an nSrc outside aSources (ignored) |
| `bRefused` | `BOOL` |  | A setting write was refused and put back (until a reset) |

## Rows `ST_Msg` (pin `aBuffer`)

`aBuffer` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_Msg`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `dtStamp` | `DT` |  | dtClock when it came (or changed) |
| `nSrc` | `INT` |  | the source (0 = empty) |
| `eState` | `E_State` |  | What it is doing now (status) |
| `eError` | `E_UtError` |  |  |

## Rows `ST_MsgSrc` (pin `aSources`)

`aSources` is an array the project declares (any size, any lower bound): one row per item.

**One row** (`ST_MsgSrc`)

| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `eState` | `E_State` |  | What it is doing now (status) |
| `eError` | `E_UtError` |  |  |
| `bKnown` | `BOOL` |  | FALSE: nothing seen yet (Active builds again) |

## Lists

- `E_MsgFull`: `DropOldest`, `HoldNew` (default `DropOldest`)
- `E_MsgKind`: `Normal`, `Held`, `Warning`, `Fault` (default `Normal`)
- `E_MsgMode`: `Queue`, `Active` (default `Queue`)

## How it works

Message ticker and site-status board for an HMI.

Call it once per source per scan, all calls on the same instance, `aBuffer`, `aSources` and `refData` (one rung each): `fbMsgs`(`eSrcState` := `fbPump1.eState`, `eSrcError` := `fbPump1.eErrorId`, `nSrc` := 1, `aBuffer` := `aMsgBuf`, `aSources` := `aMsgSrc`, `refData` := `stMsgs`); `fbMsgs`(`eSrcState` := `fbPump2.eState`, `eSrcError` := `fbPump2.eErrorId`, `nSrc` := 2, ...); `aSources`[nSrc] keeps the last state and error seen from that source, so a message is taken only when one of them changes. Its kind: Fault (`eSrcState` Fault), Warning (an `eSrcError`, not Fault), Held (Held or Waiting), else Normal; only kinds of `set.eMinKind` or worse are taken (default Held; Normal: every change).

```
  Queue   (the default) each new or changed message is queued, shown for set.tShowTime, then dropped, in the order
          they came.
  Active  one slot per source holds its current message; a kind below eMinKind (or Idle, Off, Running with no
          error) removes it; the display goes round the active ones every tShowTime ("what's wrong now").
```

When the buffer is full: `set.eWhenFull` DropOldest makes room by dropping the oldest (`sts.nLost`); HoldNew keeps what is there and new messages wait for room (their source is tried again on every call). Queue: a buffer that stays full for `set.tClearFullAfter` is emptied. `bCmdClear`: Queue empties it; Active builds it again from the sources. `bCmdNext`: the next message now (Queue drops the one on display).

RAM is what you declare: one `ST_Msg` per slot, one `ST_MsgSrc` per source. One instance is called many times in a scan (TIME() is the same for the whole scan): `bNewMsg` stays on for the rest of the scan in which a message arrived, and the commands act once per scan.

## Example

A status ticker for two pumps. Declare `aMsg : ARRAY[1..8] OF ST_Msg` and `aMsgSrc : ARRAY[1..2] OF ST_MsgSrc`.

| Pin | Wire |
| --- | --- |
| `eSrcState` | `fbPump1.eState` |
| `eSrcError` | `fbPump1.eErrorId` |
| `nSrc` | 1 |
| `aBuffer` | `aMsg` |
| `aSources` | `aMsgSrc` |
| `refData` | `stMsgs` |

A second rung calls the same instance with pump 2's codes and `nSrc := 2`.

**Back to** [the index](../README.md).
