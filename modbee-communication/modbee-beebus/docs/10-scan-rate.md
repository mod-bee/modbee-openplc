# 10 - Scan rate, and the node's own task

Everything in this library is quick. The thing that decides how quick your
network feels is not the library at all — it is how often OpenPLC runs the task
the node block sits in.

This page explains why, and what to do about it. The short version:

> **Put the node block, and every block given it, in a fast task of their own.
> Your application stays on the task it was written for, and trades values with
> them through globals.**

A six-node plant measured **485 ms** to get a value round the ring on a 20 ms
task. The same six nodes, same code, with the node block moved to a 1 ms task:
**80 ms.**

## Why the scan rate is the price

BeeBus has no master. The right to transmit moves around the ring as a **token**
— a small frame handed from one node to the next. Hold the token and it is your
turn: you send what you owe and pass it on. That is the whole arrangement, and
it is what makes the network deterministic and collision-free with nobody in
charge.

The catch is what "hand it to the next node" means when the next node is a PLC.

A PLC does not listen continuously. It runs a scan, and between scans it is not
looking at the network at all. So the token does not arrive at a node — it waits
at the node's door until the node's next scan comes round and notices it. Then
the node takes its turn and passes the token on, and the *next* node waits at
*its* door for *its* next scan.

**Every hop costs a scan.** Not a millisecond of network time — a scan.

Measured on real runtimes, a hop costs roughly **four scans**, because the two
nodes' scans are not synchronised with each other and the receiving node needs
one look to notice the token and another to act on it. So:

```
one rotation  ≈  4.5  ×  nodes  ×  scan period
```

That holds while the scan is the largest cost, which is the case at the
intervals a PLC normally runs. Push the interval low enough and the network's
own costs — the wire, the sockets, the OS — become the floor instead, and the
rotation stops improving; the measurements below flatten out well before 1 ms
for that reason.

At 20 ms, six nodes: about half a second for the token to get all the way round.
And **every read, every write and every publish waits for its turn**, so half a
second is what a value can take to move.

The network is not slow. The scan is.

## Only the node block needs the fast rate

Here is the useful part. Look at what each block actually does:

| | |
| --- | --- |
| `BEEBUS_NODE` | **services the protocol** — receives, takes the turn, passes the token |
| everything else | hands the node a job, or reads a result off a pin |

`BEEBUS_MB_READ` does not talk to the network. It puts a job on the node's queue and
returns. The node does the work on its next turn, and `BEEBUS_MB_READ` picks up the
answer whenever it is next called. Whether that is one scan later or fifty makes
no difference to the answer — it only changes how soon you *see* it.

So the node block is the only one that benefits from running often. **But every
block given the node runs in the node's task.** OpenPLC runs each task on a
thread of its own, and the library underneath is single-threaded: a block in
another task would be inside the node while the node's own scan is - one thread
adding to its queue while the other walks it. So each block checks it is in its
node's task, and in any other it does nothing and says `BEEBUS_WRONG_TASK`. It
never races and never waits: a lock that waited would hold your application
back by the node's scan.

## The pattern

The node and its blocks live in one program on a fast task. Your application
runs on its own, and the two trade values through a **Global Variable List**.

### The list

**Declare the node in the network program, never in a global list.** OpenPLC
locks every access to a shared global, and a block instance is one: a machine
task that so much as names a global `BEEBUS_NODE` waits for the network task to finish
with it - before the block's own task check has run. Measured on a Node UIO with
the client global and one block of it in the 20 ms task: the broker went away,
the network task's scans stretched while it reconnected, the machine task sat
199 ms behind it and OpenPLC stopped the PLC. `BEEBUS_WRONG_TASK` stops a race; only
keeping the instance out of the global list stops the wait. Plain values in the
list are fine - each access is a copy.

Add a list — call it `NET` — holding the values that cross between the tasks,
**each written by one task only**:

| name | type | written by |
| --- | --- | --- |
| `rTemp` | `REAL` | `netrun` - what arrived |
| `bAwake` | `BOOL` | `main` - what your logic decided |

### The node's program

The node and every block given it:

```
PROGRAM netrun
  VAR
    node   : BEEBUS_NODE;
    status : BEEBUS_NODE_STATUS;
    subTemp: BEEBUS_TP_SUBSCRIBE;
  END_VAR

node   ( NODE_ID := 10, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP, FAILSAFE := TRUE,
         CONNECT := NET.bAwake );
status ( NODE := node );
subTemp( NODE := node, PEER := 4, NAME := 'temp', TOPIC_ID := 1,
         VALUE := NET.rTemp );
END_PROGRAM
```

`NODE` is an in-out pin carrying the node itself, so it must be assigned —
leaving it out is a compile error rather than a node that goes missing at run
time.

### Your program

No BeeBus block at all - it reads and writes the list:

```
PROGRAM main
  IF NET.rTemp > 80.0 THEN
    alarm := TRUE;
  END_IF;
  NET.bAwake := NOT sleeping;
END_PROGRAM
```

### The tasks

| task | interval | priority | program |
| --- | --- | --- | --- |
| `TASK_APP` | `T#20ms` | `0` | `main` |
| `TASK_NET` | `T#1ms` on the Runtime | `20` | `netrun` |

The node services the protocol every millisecond. Your logic runs at 20 ms, or
at whatever it was written for, at the higher priority (IEC priority 0 is the
highest).

**On a board, measure before going fast.** OpenPLC stops the PLC when a task is
still in one scan after 10 of its intervals, so a `T#1ms` task needs every scan
of the node under 10 ms. Bringing Wi-Fi or Ethernet up is not that - DHCP alone
waits up to a second - so a node on a network link starts at `T#50ms`. Check the
task's longest scan with `openplc-cli debug stats` on your own link before
going faster.

## One task also works

A single task holding the node, its blocks and your logic is one less thing in
the project, and it is the right choice when nothing is waiting on an answer.
Put the node block first and give every other block the local instance:

```
PROGRAM main
  VAR
    node   : BEEBUS_NODE;
    status : BEEBUS_NODE_STATUS;
  END_VAR

node  ( NODE_ID := 10, TRANSPORT := BEEBUS_NODE_RUNTIME_UDP, FAILSAFE := TRUE );
status( NODE := node );
END_PROGRAM
```

The cost is that your application logic runs at the node's rate. Where that
matters, put the heavy work behind a divider:

```
divider := divider + 1;
IF divider >= 20 THEN     (* 1ms task, so this is every 20ms *)
  divider := 0;
  (* the heavy work *)
END_IF;
```

**In a container, check the log before relying on priorities.** Setting a
real-time priority needs `CAP_SYS_NICE`, which Docker does not grant by
default, and the runtime says so and carries on:

```
[task TASK0] SCHED_FIFO(1) failed: Operation not permitted — running default scheduling
```

Add `--cap-add=SYS_NICE` to the container if you want them honoured.

## What you get

Measured on nine OpenPLC runtimes in containers, reading `ROTATION` off
`BEEBUS_NODE_STATUS`:

| | 3-node ring | 6-node plant |
| --- | --- | --- |
| one 20 ms task | 199–238 ms | 485 ms |
| one 5 ms task | 69–84 ms | — |
| one 1 ms task | 41–48 ms | 77–98 ms |
| **node 1 ms, logic 20 ms** | **44–49 ms** | **70–102 ms** |

The last two rows are the point. Splitting gets the same rotation as running
everything at 1 ms, while the application logic runs at 20 ms instead — the
network speed without the scan rate.

A sleeping node's rejoin improved in the same proportion — 460 ms down to
160 ms — because rejoining is also paced by how often the node looks at the bus.

## Watch it, do not guess it

`BEEBUS_NODE_STATUS` reports the real figure:

```
status( NODE := node );     (* in netrun, beside the node *)
(* status.ROTATION — measured, not estimated *)
```

Divide it by your node count and you have the cost of a hop. If that number is
close to four times your scan period, the scan is what you are paying for and
this page applies. If it is much larger, something else is wrong — start at
[09 - Troubleshooting](09-troubleshooting.md).

## Things worth knowing

**Only the node's program goes on the fast task** - the node and its blocks.
Anything of your application's put there runs a thousand times a second for no
benefit.

**Read the node's outputs from the instance**, in its own program -
`node.CONNECTED` - and hand your application what it needs through the list.

**Two nodes?** Declare both in the node's program, give each its own `NODE_ID`
and transport, and give every other block the one it belongs to — see
[03 - The node block](03-the-node-block.md#more-than-one-node-in-a-program).

## When not to bother

**One task is fine when nothing is waiting on the answer.** A plant logging
tank levels every few seconds does not care whether the value is 80 ms or 500 ms
old, and a single 20 ms task is one less thing in the project.

Reach for the split when:

- the ring has **more than a handful of nodes** — the cost is per hop, so it
  grows with every node you add
- something **commands** something else and wants the acknowledgement back
  promptly
- a node **sleeps and wakes** often, and each rejoin is costing you

And if you simply want it faster with no restructuring, **lowering the one task
you have works too** — 20 ms to 5 ms measured about 3× on a real ring. The split
is better because it does not make your application logic run twenty times as
often to get there.

---

Next: [08 - Patterns](08-patterns.md), or back to
[03 - The node block](03-the-node-block.md).
