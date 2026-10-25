# 11 - Settings both ways: serve and bind

A panel shows a setting and lets the operator change it. The PLC decides
whether the new value is allowed. Whatever it decides, the panel must end up
showing what the PLC holds — never a value the PLC refused, never a value a
lost frame left behind.

That is two blocks, and nothing else in either program:

| | |
| --- | --- |
| `BEEBUS_TP_SERVE` | on the PLC: serves a `STRUCT`, one topic per member, and decides every change asked of it |
| `BEEBUS_TP_BIND` | on the panel (or SCADA, or another PLC): keeps a `STRUCT` of the same type equal to the PLC's, and asks for its changes |

No subscribe-and-write pair, no copy-back, no command flags cleared by the
program, no timers or retries. The protocol carries every change, waits for the
decision, and puts the owner's value back in the member.

New projects start here. The blocks of [05 - Topics](05-topics.md) are still
there underneath, for anything that needs them on their own.

## An example

The types, the same on both nodes:

```
TYPE
  PUMP_SET : STRUCT
    runTime  : TIME := T#10m;
    level    : REAL := 60.0;
    enabled  : BOOL := TRUE;
    name     : STRING(20) := 'Bore 1';
  END_STRUCT;

  PUMP_CMD : STRUCT
    start    : BOOL;
    stop     : BOOL;
    resetHrs : BOOL;
  END_STRUCT;
END_TYPE
```

The PLC, node 1:

```
set( NODE := node, VALUE := SET, TOPIC_ID := 300, WRITABLE := TRUE );
cmd( NODE := node, VALUE := CMD, TOPIC_ID := 400, WRITABLE := TRUE,
     COMMAND := TRUE, PULSE := T#500ms );

pump( RUN_TIME := SET.runTime, START := CMD.start, STOP := CMD.stop, ... );
```

The panel, node 2:

```
set( NODE := node, VALUE := SET, PEER := 1, TOPIC_ID := 300, RELIABLE := TRUE );
cmd( NODE := node, VALUE := CMD, PEER := 1, TOPIC_ID := 400, RELIABLE := TRUE );
```

The operator types 15 minutes into the panel's `SET.runTime`. The panel's bind
goes `PENDING`, the change reaches the PLC, `SET.runTime` there becomes
`T#15m`, the pump block runs with it, and the panel's bind goes back to
`IN_SYNC`. Nothing in either program did any of that.

## How the PLC decides

A change is put into the member at the start of the serve block's scan. The
program then runs — every block that reads the member sees the new value — and
after that scan (and `SETTLE`, if the block that judges it needs longer) the
member is read back:

- still holding what was asked: **ACCEPTED**;
- holding something else: **CHANGED**, and the panel is told the value kept.

So the rule that a setting must stay in range lives where it already does, in
the block that uses it. A block that refuses a value and puts its own back (as
the utilities blocks do) needs no extra rung to tell the panel; one that clamps
it is reported the same way. `REFUSED_COUNT` on the serve block counts them.

## Commands

`COMMAND := TRUE` makes every member a command: each change is one event for the
program, taken exactly once — not twice when an acknowledgement is lost and the
change is sent again, and not lost when the network drops a frame. A `BOOL`
command goes back to `FALSE` after `PULSE`, so the panel sees it go back too.

On the panel, setting `CMD.start := TRUE` is the whole button. The bind takes it
to the PLC, the PLC takes it once, and `start` comes back `FALSE` when the
pulse ends.

## RELIABLE, and when not

`RELIABLE := TRUE` on the bind is for setpoints, settings and configuration:
every change arrives, and one a lost frame took is sent again, as the current
value, within a rotation or two. It costs about two bytes a rotation while
values move, nothing while they do not.

Live values — levels, flows, speeds updated every scan — do not need it, and it
is off by default. Bind or subscribe them LIVE: best effort, newest wins, a
`DEADBAND` allowed.

## What the panel shows

`STATE` is the worst member. In a Ladder rung use the `BOOL`s, since a rung
cannot compare an enumeration:

| output | show |
| --- | --- |
| `IN_SYNC` | the values are the PLC's |
| `PENDING` | "sending..." — a change is with the PLC |
| `REFUSED` | "refused: kept *value*" — the member already holds the kept value; `REFUSED_NAME` says which member |
| `FAILED` | "not answered" — the member holds the PLC's last value |
| `STATE = BEEBUS_BIND_OFFLINE` | the PLC is not on the network |
| `STATE = BEEBUS_BIND_SYNCING` | waiting for the PLC's values (at start, and after it restarted) |

`REFUSED` and `FAILED` clear by themselves on the member's next change or the
PLC's next value.

## Restarts

A panel or a PLC that restarts — even one back before the other noticed it go —
is told apart from the instance before it, and the binds start again on their
own: `SYNCING`, then `IN_SYNC` with the PLC's values. Nothing in the program.

## One write, with its answer

For a single write that is not a bind — a value a sequence sets once —
`BEEBUS_TP_WRITE` with `WANT_RESULT := TRUE` waits for the owner's decision:
`DONE` then comes with `RESULT` (`BEEBUS_TP_ACCEPTED`, `BEEBUS_TP_CHANGED` ...),
`ACCEPTED`, `REFUSED` and `KEPT_VALUE`.

## What not to write any more

- A subscription of the PLC's settings plus a separate write block for changes.
- Copying a settings `STRUCT` into the blocks' `set` and back every scan to
  "bounce" a refused value.
- Command flags the program clears after acting (`TRUE` then `FALSE`, or `-1`
  for "no command").
- Timers on the panel that guess "refused" from what arrives.
- Subscribing a few topics at a time, and re-subscribing when the PLC comes
  back.

All of it is in the protocol now.
