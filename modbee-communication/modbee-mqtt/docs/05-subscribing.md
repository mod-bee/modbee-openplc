# Subscribing

Two blocks. `MQTT_SUBSCRIBE` for a number you act on, `MQTT_MESSAGE` for
anything else.

## A value you act on

```
sp( CLIENT := net,
    TOPIC := 'plant/intake/cmd/level-setpoint',
    VALUE := rSetpoint,
    EXPECT := T#0s,
    QOS := 1 );
```

The block subscribes once and maintains itself. Arriving text is read as
`VALUE`'s declared type and lands in your variable directly — nothing to copy,
nothing to keep in step.

A payload that will not parse is counted on `MALFORMED` and **the variable is
left alone**. A publisher sending `23,5` to a `REAL` is a real fault, and a
block that quietly wrote zero would hide it for a year.

## Quality is what makes it safe

`QUALITY` is judged against `EXPECT` — the interval *you* asked for —
not against some constant the library picked. A hard-coded "stale after five
seconds" is wrong for a temperature sampled hourly and wrong for a pressure
sampled ten times a second.

| | |
| --- | --- |
| `MQTT_QUALITY_UNKNOWN` | nothing has **ever** arrived |
| `MQTT_QUALITY_BAD` | the link is down, or the value is more than twice overdue |
| `MQTT_QUALITY_UNCERTAIN` | overdue, but not by much |
| `MQTT_QUALITY_GOOD` | arrived inside the interval |

**UNKNOWN and BAD are deliberately different**, and the difference is worth
protecting:

| | means | found |
| --- | --- | --- |
| **UNKNOWN** | wrong filter, publisher never deployed, typo in a topic | at a desk, with a drawing |
| **BAD** | it was arriving and has stopped | in the plant, with a torch |

An alarm list that shows both as "no comms" throws that away.

**`SEEN` is that same distinction in a BOOL**, and it exists because a ladder
cannot compare an enumeration — `EQ(QUALITY, MQTT_QUALITY_GOOD)` does not
compile, and neither does `TO_INT` of one. So a rung asks `SEEN` instead:

```
        SEEN = FALSE        nothing has ever arrived  - a desk fault
        AGE  > EXPECT       it arrived and stopped    - a plant fault
```

`AGE` reads `T#0s` until the first value, which is the same as "arrived this
scan" — `SEEN` is what tells the two apart. It used to be `AGE_MS = -1`, which
could not survive `TIME` being unsigned in CODESYS and said in a footnote what
a BOOL says in one word.

`EXPECT := T#0s` means nothing was promised, so quality is GOOD as soon
as anything arrives and stays there. That is right for a setpoint that changes
when an operator changes it and not otherwise. For a measurement, set it to a
little more than the publisher's own `PERIOD`.

Gate on it:

```
IF sp.QUALITY >= MQTT_QUALITY_UNCERTAIN THEN
  rWorkingSetpoint := rSetpoint;
ELSE
  (* hold the last good value, or fail safe *)
END_IF
```

## One honest limit

A connected broker will happily serve a **retained** message published by a
device that died last Tuesday, and nothing in MQTT marks it as old.

`QUALITY` knows whether *we* are connected and how long since *we* last heard.
It cannot know the publisher is alive. Pair this with `MQTT_PRESENCE` at the
publishing end and the question is answered properly — subscribe to the
publisher's status topic and you know.

## Wildcards

```
TOPIC := 'plant/+/level'     (* one level: every line's level *)
TOPIC := 'plant/line3/#'     (* the rest: everything under line 3 *)
```

One block can watch a group. The value pin then holds whichever arrived last,
which is useful for an alarm count and useless for a specific tank — use
`MQTT_MESSAGE` if you need to know which topic it came from.

A filter starting with a wildcard does not match a topic beginning `$`, which
is where brokers publish their own statistics.

## Raw messages

```
cmd( CLIENT := net, TOPIC := 'plant/intake/command', QOS := 2 );

IF cmd.NEW_MESSAGE THEN
  (* cmd.PAYLOAD holds the text *)
END_IF
```

For a JSON document you parse yourself, a state name, a command word, or
anything from a device that knows nothing about this library.

`NEW_MESSAGE` reports an **arrival**, not a change. The same value sent twice
is two messages, and for a command channel that is exactly right: "open" sent
again means open again, and a block that suppressed it would swallow an
instruction.

An **empty message is not nothing**. Publishing an empty payload with retain
is how MQTT deletes a retained value, so `LENGTH = 0` with `NEW_MESSAGE` is
being told the old value is withdrawn — different from having heard nothing.

`TRUNCATED` matters on JSON. A document cut in half parses as garbage or,
worse, as something plausible. Check it before you trust the text.

## Subscriptions survive a reconnect

A subscription is a **standing intent**, not a request. The library re-issues
every one after a reconnect where the broker did not keep the session, and
re-issues none where it did. Getting that backwards either loses every
subscription silently or duplicates them all; the block does neither, and you
do not have to arrange it.

## A whole STRUCT, one block

```
subAll( CLIENT := mqtt, BASE := 'plant/intake/cmd', DATA := stSetpoints,
        EXPECT := T#0s, QOS := 2 );
```

The mirror of `MQTT_STRUCT_PUBLISH`. Every member is subscribed as
`BASE/<MEMBER>` and arriving text lands in it directly.

**`QUALITY` is the WORST across the set**, deliberately. A recipe of twelve
setpoints where one is stale is not eleven-twelfths usable — it is a recipe you
should not run. `SEEN` is FALSE and `OLDEST` reads `T#0s` while *any* member
has never arrived, for
the same reason: "partly commissioned" is not a state worth reporting as an
age.

Where a member needs judging on its own, give it an `MQTT_SUBSCRIBE`.

**Each member costs a topic handle and a subscription.** The client's tables
grow with the program, on a board and the Runtime alike, so a struct may have
as many members as memory holds. Past that the block says so with
`MQTT_QUEUE_FULL` - and `MQTT_CLIENT`'s `LAST_ERROR` reads "out of memory for
topics or subscriptions" - rather than silently subscribing to some of them. More subscriptions than the client's queue holds at once is fine:
they go as it drains.

## One instance, many topics

Like publishing, state is keyed by the filter:

```
watch( CLIENT := net, TOPIC := 'plant/a/level', VALUE := rLevelA, ... );
watch( CLIENT := net, TOPIC := 'plant/b/level', VALUE := rLevelB, ... );
```

Two subscriptions, each with its own value, age and quality, on one block.

**Next:** [06 Diagnostics](06-diagnostics.md)
