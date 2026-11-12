# Subscribing

Methods of the client. `Subscribe` for a value you act on, `Message` for
anything else, `SubscribeStruct` for a whole STRUCT, and `Request` and
`Response` for a question and its answer.

## A value you act on

```st
mqtt.Subscribe(anyValue := rSetpoint,
               sTopic   := 'plant/intake/cmd/level-setpoint',
               eQos     := E_MqttQos.AtLeastOnceDelivery,
               tExpect  := T#0s,
               eQuality => eSpQuality,
               bSeen    => bSpSeen);
```

Standing: call it every scan. It subscribes once and maintains itself.
Arriving text is read as `anyValue`'s declared type and lands in your variable
directly - nothing to copy, nothing to keep in step. `bNewValue` is TRUE on the
call that wrote it.

A payload that will not parse is counted on `nMalformed` and **the variable is
left alone**. A publisher sending `23,5` to a `REAL` is a real fault, and a
block that quietly wrote zero would hide it for a year.

`eQos` is the most the broker may use for this subscription. `bEnable := FALSE`
unsubscribes and keeps the record; TRUE again subscribes again.

## Quality is what makes it safe

`eQuality` is judged against `tExpect` - the interval *you* expect a value in -
not against some constant the library picked. A hard-coded "stale after five
seconds" is wrong for a temperature sampled hourly and wrong for a pressure
sampled ten times a second.

| `E_MqttQuality` | |
| --- | --- |
| `Unknown` | nothing has **ever** arrived |
| `Bad` | the link is down, or the value is more than twice overdue |
| `Uncertain` | overdue, but not by twice |
| `Good` | arrived inside the interval |

**Unknown and Bad are deliberately different**, and the difference is worth
protecting:

| | means | found |
| --- | --- | --- |
| **Unknown** | wrong filter, publisher never deployed, typo in a topic | at a desk, with a drawing |
| **Bad** | it was arriving and has stopped | in the plant, with a torch |

An alarm list that shows both as "no comms" throws that away.

**`bSeen` is that same distinction in a BOOL**, for a ladder rung, which cannot
compare an enumeration:

```
        bSeen = FALSE         nothing has ever arrived  - a desk fault
        tAge  > tExpect       it arrived and stopped    - a plant fault
```

`tAge` reads `T#0s` until the first value, which is the same as "arrived this
scan" - `bSeen` is what tells the two apart.

`tExpect := T#0s` means nothing was promised, so quality is Good as soon as
anything arrives and stays there while the link is up. That is right for a
setpoint that changes when an operator changes it and not otherwise. For a
measurement, set it to a little more than the publisher's own `tPeriod`.

Gate on it:

```st
IF eSpQuality >= E_MqttQuality.Uncertain THEN
  rWorkingSetpoint := rSetpoint;
ELSE
  rWorkingSetpoint := rSafeDefault;   (* or hold the last good value *)
END_IF;
```

A new `sTopic` on the same call is a new subscription: `Unknown` until it
speaks, never the previous topic's freshness.

## One honest limit

A connected broker will happily serve a **retained** message published by a
device that died last Tuesday, and nothing in MQTT marks it as old.

`eQuality` knows whether *we* are connected and how long since *we* last heard.
It cannot know the publisher is alive. Pair this with presence
(`stWillConfig`) at the publishing end and the question is answered properly -
subscribe to the publisher's status topic and you know.

## Wildcards

```
sTopic := 'plant/+/level'     (* one level: every line's level *)
sTopic := 'plant/line3/#'     (* the rest: everything under line 3 *)
```

One call can watch a group. The variable then holds whichever arrived last,
which is useful for an alarm count and useless for a specific tank - use
`Message` and its own topic per tank if you need to know which it came from.

A filter starting with a wildcard does not match a topic beginning `$`, which
is where brokers publish their own statistics.

## Raw messages

```st
mqtt.Message(anyPayload  := sCommand,
             sTopic      := 'plant/intake/command',
             eQos        := E_MqttQos.ExactlyOnceDelivery,
             bNewMessage => bNewCommand,
             nLen        => nCommandLen,
             bTruncated  => bCommandCut);

IF bNewCommand AND NOT bCommandCut THEN
  bOpen := sCommand = 'open';
END_IF;
```

For a JSON document you parse yourself, a state name, a command word, or
anything from a device that knows nothing about this library. `anyPayload` must
be a `STRING` variable; it takes one message per call, so a burst is
presented one scan at a time and none is folded into another.

`bNewMessage` reports an **arrival**, not a change. The same value sent twice
is two messages, and for a command channel that is exactly right: "open" sent
again means open again, and a block that suppressed it would swallow an
instruction.

An **empty message is not nothing**. Publishing an empty payload with retain
is how MQTT deletes a retained value, so `nLen = 0` with `bNewMessage` is being
told the old value is withdrawn - different from having heard nothing.

`bTruncated` matters on JSON: the message was longer than `anyPayload` or the
client's buffer (`stSessionConfig.nMaxMsgIn`). A document cut in half parses
as garbage or, worse, as something plausible. Check it before you trust the
text.

## Subscriptions survive a reconnect

A subscription is a **standing intent**, not a request. Every one is made
again after a reconnect where the broker did not keep the session, and none
where it did. Getting that backwards either loses every subscription silently
or duplicates them all; the methods do neither, and you do not have to arrange
it.

## A whole STRUCT, one call

```st
mqtt.SubscribeStruct(anyData  := stSetpoints,
                     sBase    := 'plant/intake/cmd',
                     eQos     := E_MqttQos.ExactlyOnceDelivery,
                     eQuality => eRecipeQuality,
                     bSeen    => bRecipeSeen);
```

The mirror of `PublishStruct`. Every member is subscribed as
`sBase/<member>` and arriving text lands in it directly.

**`eQuality` is the WORST across the set**, deliberately. A recipe of twelve
setpoints where one is stale is not eleven-twelfths usable - it is a recipe you
should not run. `bSeen` is FALSE and `tOldest` reads `T#0s` while *any* member
has never arrived, for the same reason: "partly commissioned" is not a state
worth reporting as an age. With the link down the quality is `Bad`.

Where a member needs judging on its own, give it a `Subscribe` of its own.

**Each member costs a topic and a subscription.** The client's tables grow
with the program, on a board and the Runtime alike, so a struct may have as
many members as memory holds. Past that the call returns `QueueFull` - and the
client's `sLastError` reads "out of memory for topics or subscriptions" -
rather than silently subscribing to some of them. A member the wire cannot
carry is counted on `nSkipped` and the call returns `InvalidArgument`.

## A question and its answer

MQTT 5 can carry a request: a message with a **Response Topic** and
**Correlation Data**, answered on that topic. Both ends are here.

**Asking:**

```st
eAskResult := mqtt.Request(anyValue    := 'level?',
                           sTopic      := 'plant/well/ask',
                           sReplyTopic := 'plant/intake/reply',
                           tTimeout    := T#5s,
                           bExecute    := bAsk,
                           sReply      => sAnswer);
```

A request, like `Publish`. The rising edge of `bExecute` clears `sReply` and
sends; `sReplyTopic` is subscribed beforehand, so the answer cannot arrive
before anyone listens. `Queued` until the answer (`Ok`, its text in `sReply`,
up to 254 characters) or `tTimeout` (`KeepAliveTimeout`; `T#0s` is five
seconds). Give each requester its own `sReplyTopic`.

On a 3.1.1 connection it returns `NotSupportedByProtocol` rather than sending
a request with nowhere to answer.

**Answering:**

```st
mqtt.Response(anyRequest  := sQuestion,
              sTopic      := 'plant/well/ask',
              anyReply    := rWellLevel,
              bExecute    := bNewQuestion,
              bNewRequest => bNewQuestion);
```

Standing. A request arriving on `sTopic` is written into `anyRequest` as its
declared type, and `bNewRequest` is TRUE on that call. A rising edge of
`bExecute` sends `anyReply` to the request's Response Topic, quoting its
Correlation Data - once per request. Wiring `bNewRequest` back to `bExecute`
answers every question on the scan after it arrives. `bAwaitingReply` says
the last request is waiting for its answer.

**MQTT is a noticeboard.** If most of your traffic is questions and answers,
you want Modbus.

**Next:** [06 Diagnostics](06-diagnostics.md)
