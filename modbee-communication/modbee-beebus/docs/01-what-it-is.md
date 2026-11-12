# 01 - What it is

BeeBus lets several PLCs share values with each other directly. No master, no
SCADA in the middle, no one node that everything depends on.

If you have wired Modbus before, the mental model transfers almost completely.
What changes is the one thing that usually causes the trouble: **there is no
master**.

## The problem it solves

With Modbus, one device asks and the others answer. That works, and it has two
costs you have probably paid.

The master is a single point of failure - stop it and the network stops. And
every value arrives because somebody asked for it, so a change is only as fresh
as the next poll, and most polls carry a number that has not moved.

BeeBus turns that round. Every node is equal. Each takes a turn to speak, says
what it has to say, and hands on. Nothing polls, and no node is in charge.

## The ring

A **token** goes round the nodes. Holding it is your turn to transmit; when you
are done you pass it to the next node. That is the whole idea.

You do not have to do anything about this. The node block runs it for you: it
finds the other nodes, joins the ring, takes its turn, and if a node is
unplugged the rest close the gap and carry on. If it comes back it rejoins.

Two things are worth knowing because you will see them on a pin:

**Every node needs a different id.** 1 to 254. Two nodes on one id is the most
common commissioning mistake there is, and the protocol detects it - the second
node stands down and says `E_BeeBusResult.DuplicateNodeId` rather than fighting
for the address. Unplug the wrong one and the other rejoins on its own.

**Timing measures itself.** How long a turn takes, how long to wait for a peer
- all of it is taken from the network as it runs, so a slow radio link and a
fast wired one need no different settings. There is nothing to tune.

## Two ways to share a value

This is the one real choice you make, so it is worth getting right.

### Registers - `ModbusMap`, `ModbusRead`, `ModbusWrite`

Your variable sits at a numbered Modbus address. A peer reads address 40 and
gets it; writes address 40 and changes it.

```
node.ModbusMap(anyData := rTankLevel, eTable := E_BeeBusModbusTable.HoldingRegister,
               nAddress := 40);
```

Use registers when:

- something else on the network already speaks Modbus and needs to reach it
- you are replacing an existing Modbus layout and want to keep the addresses
- you want a peer to be able to **write** into your PLC by address

The cost is that addresses are numbers. Nothing on the wire says address 40 is
a tank level, so the meaning lives in a spreadsheet somewhere.

### Topics - `Topic`, `Subscribe`, `PublishStruct` and the rest

Your variable has a **name** and a type. Peers subscribe to it, and the value
arrives on its own when it changes.

```
node.Topic(anyValue := rTankLevel, sName := 'tank_level', nTopicId := 1);
```

Use topics when:

- you want values to arrive by themselves rather than be asked for
- you care whether a value is fresh, or whether an update went missing
- the value should keep flowing while a listener is switched off
- you would rather read `'tank_level'` than remember what 40 was

Topics carry their type, so a `REAL` arrives as a `REAL` rather than as two
registers you have to reassemble. They also carry **quality** and **age**, so a
subscriber can tell a value that stopped updating from one that simply is not
changing - which is the failure Modbus hides, because a stale register looks
exactly like a healthy one.

### Which one

If in doubt, **topics**. Registers exist for compatibility; topics are what the
protocol is built around.

Use both in one program if it suits. They are independent and a node can do
either or both.

## What a node looks like in ST

Every program follows the same shape:

```
PROGRAM main
VAR
    node       : FB_BeeBusNode;
    rTankLevel : REAL;
END_VAR

(* 1. The node, first, every scan. *)
node(nNodeId := 10, eTransport := E_BeeBusTransport.RuntimeUdp);

(* 2. What this node shares: method calls on it, every scan. *)
node.Topic(anyValue := rTankLevel, sName := 'tank_level', nTopicId := 1);

(* 3. Your program, as normal. *)
rTankLevel := rTankLevel + 0.1;
END_PROGRAM
```

`node` is the node itself. Everything it does on the segment is a method of
it, so there is no second block to declare and nothing to wire between blocks:
the method's instance **is** the node. A method call copies nothing into an
instance of its own, and the node keeps what each call needs between scans in
a record of its own, found again each scan by the variable the call is about
(its declared name and type).

A segment is one node. Two segments - a serial line and a UDP network, say -
are two instances, each with its own methods.

## When not to use it

**You need hard determinism.** A turn on the ring comes round in a measured
time, not a guaranteed one. For a motion loop, use something built for that.

**You have one master and it works.** If a Modbus master already does the job
and nothing about it hurts, BeeBus is not solving a problem you have.

**Very small boards.** A node needs roughly 10 KB of RAM before your own data.
An ESP32 is comfortable; an 8-bit Uno or Nano is not.

---

Next: [02 - Getting started](02-getting-started.md) builds a working pair.
