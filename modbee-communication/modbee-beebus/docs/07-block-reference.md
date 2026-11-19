# Block reference

One block, `FB_BeeBusNode`: this PLC's place on one BeeBus segment. Everything it
owns, serves, subscribes, binds, reads or writes there is a **method** of it:
`node.Serve(...)`, `node.Subscribe(...)`, `node.ModbusRead(...)`. Call the block
itself once every scan, in the network task; call its methods after it. Two
segments are two instances.

Every method returns an `E_BeeBusResult`. A **request** (`Publish`, `Write`,
`ModbusRead`, `ModbusWrite`) starts on a rising edge of `bExecute`, returns
`Queued` while it runs and then holds its outcome until the next edge. A
**standing** method is called every scan while it is wanted and returns `Ok`
while its record is valid. A method's outputs are read with `=>`:
`ok := node.Subscribe(..., eQuality => q);`. An input left out takes its default.

| Block | What it does | Methods |
| --- | --- | --- |
| [`FB_BeeBusNode`](#fb_beebusnode) | A BeeBus node: this PLC's place on one segment, serial or UDP. | [`Topic`](#fb_beebusnodetopic), [`Publish`](#fb_beebusnodepublish), [`Subscribe`](#fb_beebusnodesubscribe), [`PublishStruct`](#fb_beebusnodepublishstruct), [`SubscribeStruct`](#fb_beebusnodesubscribestruct), [`Serve`](#fb_beebusnodeserve), [`Bind`](#fb_beebusnodebind), [`Write`](#fb_beebusnodewrite), [`Buffer`](#fb_beebusnodebuffer), [`ModbusMap`](#fb_beebusnodemodbusmap), [`ModbusRead`](#fb_beebusnodemodbusread), [`ModbusWrite`](#fb_beebusnodemodbuswrite), [`Statistics`](#fb_beebusnodestatistics), [`PeerStatus`](#fb_beebusnodepeerstatus) |

The option structures and enumerations are at the end: [Structures](#structures), [Enumerations](#enumerations).

---

## FB_BeeBusNode

```
A BeeBus node: this PLC's place on one segment, serial or UDP. Call it once
every scan, in the network task. Everything the PLC owns, serves, subscribes,
binds, reads or writes on that segment is a method of this block.
BeeBus passes a token round the nodes; a node in the ring is one taking
its turn, and only the node holding the token sends.

nNodeId     1..254, unique on the segment.
eTransport  which link. The target must have it; one it does not have is
           reported on bError and sLastError, never built.
             E_BeeBusTransport.RuntimeUdp       the Runtime's network, UDP
                                                multicast (default)
             E_BeeBusTransport.RuntimeSerial    a serial device on the
                                                Runtime, stSerialConfig.sDevice
             E_BeeBusTransport.ArduinoSerial    a board's hardware serial,
                                                stSerialConfig.nUart and pins
             E_BeeBusTransport.ArduinoWiFi      a board's Wi-Fi, UDP multicast
             E_BeeBusTransport.ArduinoEthernet  a board's Ethernet, UDP
                                                multicast. Needs
                                                BEEBUS_ENABLE_ETHERNET in the
                                                board's build flags
bConnect    be in the ring. TRUE (default) joins and stays. FALSE leaves:
           the node stops taking the token and its peers see it go, which is
           what a node that wakes, reports and sleeps again wants. Every
           binding survives the gap: nothing is registered again on waking,
           and a subscriber's stream picks up where it left off.
bApplySafeValueOnWriterLoss   apply each address's safe value (ModbusMap eActionOnWriterLoss) when the peer
           driving it goes silent.
nMaxPendingOperations how many requests (reads, writes, subscriptions) and how many
           answers can wait for the token at once, 1..255. 0 (default) is 16
           on a board and 50 on the Runtime. Past it a request is refused
           with E_BeeBusResult.QueueFull and asked again by its method on a
           later scan. Raise it on a node that keeps many requests in flight,
           and on the node that answers them. Each place costs about 300
           bytes of RAM, taken when the node starts; too many for the memory
           and the node does not start, sLastError saying so.
bDebugToConsole  print the protocol's own debug lines to the console.
stSerialConfig  ST_BeeBusSerialConfig, a serial link.
             sDevice   RuntimeSerial: the device, '/dev/ttyUSB0'
             nBaudRate  0 for the default, 115200
             nUart     ArduinoSerial: which hardware serial, 0 for the first
             nRxPin    ArduinoSerial on an ESP32: the receive pin, -1 for the
                       board's own
             nTxPin    the transmit pin, -1 for the board's own
stNetworkConfig  ST_BeeBusNetworkConfig, a UDP link.
             sMulticastAddress  the multicast group, empty for the protocol's
                             own (239.192.7.126)
             nUdpPort        0 for the protocol's own (7126)
             nMulticastHops  RuntimeUdp: multicast hops, 0 for 1 (this subnet)
             sInterfaceAddress  RuntimeUdp: the interface address to send from,
                             empty to let the host choose
             sSsid           ArduinoWiFi: the network to join
             sWiFiPassword   its password, up to 63 characters (WPA2)
             sMacAddress     ArduinoEthernet: six hex bytes,
                             'DE:AD:BE:EF:FE:ED'. Empty takes a built-in
                             default: fine for ONE device on a network
             sIpAddress      ArduinoEthernet: a fixed address, empty for DHCP.
                             Prefer a fixed address: DHCP blocks while it
                             asks, so each attempt is bounded to a second
           A member that does not apply to the target - sDevice on a board,
           sSsid on the Runtime - is reported on bError, never ignored.

bLinkOpen   the node started: its link is open.
bNetworkUp  the network under it is up: Wi-Fi joined, or the Ethernet cable
           in and an address held. The same as bLinkOpen on the Runtime and on
           a serial line.
bConnected  in the ring, holding a place in the rotation. THE ONE TO
           INTERLOCK ON.
bError      something failed: the link, a setting, or a method call.
eErrorId    why. E_BeeBusResult.Ok when fine.
             NotInitialised   the link is not open yet, retrying (sLastError says why)
             InvalidArgument  a setting is wrong, or a method's record was
                              refused
             DuplicateNodeId  another device on this segment transmits under
                              nNodeId, so this node takes no token, claims no
                              address and refuses every read and write.
                              Without it that reads exactly like a node still
                              starting up. It clears by itself once the other
                              device stops, or on a rising edge of bConnect
sLastError  what failed, in words: the operating system's ("could not open
           serial device: No such file or directory", "could not join
           multicast group: No such device"), a setting's ("nNodeId must be
           1..254", "no serial device named"), or the failing method call and
           its record ("Serve STS: topic 300 (limit) is already bound"). On a
           board it also tells the network faults apart: "joining the
           network", "Ethernet cable unplugged", "no address from DHCP yet",
           "no Ethernet controller found on SPI".
nLinkOpenAttemptCount  how many times the link has been opened, or tried.
tRetryTimeLeft  while a failed open waits to be tried again, how long until it
           is. T#0s otherwise.

METHODS

Each call is found again by what it is about: anyValue's (anyData's)
declared name and type, and the method. A literal has no name and is found
by its topic or address. So one variable is one record per method: to serve
one variable twice, give each call its own variable. A node holds up to 256
records; past that a method returns E_BeeBusResult.QueueFull. Every method
runs in this block's task and returns E_BeeBusResult.WrongTask in any other.
Before the node has started, a method returns NotInitialised and keeps its
record.

A REQUEST (Publish, Write, ModbusRead, ModbusWrite) starts on a rising edge
of bExecute and takes its inputs at that edge; changing them while it runs
has no effect. It returns E_BeeBusResult.Queued while it runs, then its
outcome, held until the next edge. A peer not in the ring at the edge:
E_BeeBusResult.UnknownNode at once, never queued for later.

A STANDING METHOD (Topic, Subscribe, PublishStruct, SubscribeStruct, Serve,
Bind, Buffer, ModbusMap) is called every scan while it is wanted, and
E_BeeBusResult.Ok means its record is valid. What a record is - its topic
ids, prefix, peer, table and address - is taken on the first call that
binds it; a later call that changes them returns InvalidArgument and the
record goes on as bound. The terms (deadband, period, reliability, pulse,
settle, depth) may change while it runs. A refused record is tried again
when what it is changes.

  node.Topic(anyValue, sTopic, nTopicId)
     A TOPIC THIS NODE OWNS, bound to the variable itself. Its declared type
     is the type on the wire: BOOL, SINT, USINT, BYTE, INT, UINT, WORD,
     DINT, UDINT, DWORD, LINT, ULINT, LWORD, REAL, LREAL, LTIME (LINT
     nanoseconds) or STRING. sTopic, up to 253 characters, is the identity:
     every peer addresses the topic by it. nTopicId, 1..32767, unique on
     this node; under 128 costs one byte on the wire. Once bound the node
     publishes on its own, to every subscriber on its own terms: move the
     variable and it goes out. Peers may read it, not write it. Ok,
     InvalidArgument (an empty or too long name, a type the wire cannot
     carry, an id already bound).

  node.Publish(anyValue, sTopic, nTopicId, ePublishMode, nPeerNodeId, bRequireAcknowledge,
               bExecute)
     A TOPIC THIS NODE OWNS, SENT ON A RISING EDGE of bExecute: an event
     that must go the moment something happened. ePublishMode
     E_BeeBusPublishMode.All: every node at once, one frame however many
     listen, applied by every node holding the topic; nothing acknowledges
     it, so bRequireAcknowledge is refused (InvalidArgument). ToPeer: nPeerNodeId only, on
     its counted stream; with bRequireAcknowledge the frame is retried until nPeerNodeId
     acknowledges it. Topic beside it, on the same variable, sTopic and
     nTopicId, also sends it on the subscribers' own terms. Queued while a
     confirmed publish waits, then Ok; unconfirmed, Ok at the edge.
     UnknownNode, Timeout, InvalidArgument.

  node.Subscribe(anyValue, nPeerNodeId, sTopic, nTopicId, fDeadband, tMaxSendInterval,
                 bDeliverEveryChange, eQuality =>, bValueEverReceived =>, tValueAge =>, bValueReceived =>,
                 nMissedUpdateCount =>)
     A PEER'S TOPIC, landing in anyValue, of the type the owner bound.
     fDeadband: sent again once it has moved this far, 0 every change.
     tMaxSendInterval: sent at least this often, moved or not, T#0s never.
     bDeliverEveryChange FALSE (Live): best effort, newest wins, for levels and
     speeds. TRUE: every change arrives, and one a lost frame took is sent
     again, as the current value, within a rotation or two; for a setpoint
     or a setting. eQuality Unknown before anything arrived, then Good,
     Uncertain or Bad as the value ages. bValueEverReceived: a value has arrived, for a
     ladder rung, which cannot compare an enumeration. tValueAge since the last
     value. bValueReceived: one arrived since the last call. nMissedUpdateCount: publishes
     the sequence says never arrived, a running total. Re-asked by itself
     whenever the peer rejoins. Ok, or the subscription's refusal.

  node.PublishStruct(anyData, nFirstTopicId, sTopicPrefix, bPeersMayWrite, tPulseLength, tAnswerDelay,
                     nMembers =>, bWrittenByPeer =>, nMembersWritten =>, sFirstWrittenMember =>,
                     nFirstWrittenIndex =>, nWrittenByNodeId =>, nDroppedWriteCount =>)
     A WHOLE STRUCT AS TOPICS THIS NODE OWNS, one per member: the member
     name is the topic name, nFirstTopicId + its position the id. An ARRAY of
     STRUCTs or of values works the same. bPeersMayWrite: peers may write the
     members; a write is held and taken in this call, one per member a
     scan, oldest first. tPulseLength: a BOOL member written TRUE drops back to
     FALSE this long after. tAnswerDelay: a write that asked for a result is
     answered after the program has run a scan with it, plus this long.
     bWrittenByPeer: writes were taken by this call; nMembersWritten how many,
     sFirstWrittenMember and nFirstWrittenIndex the first, nWrittenByNodeId the node that
     wrote it (held). nDroppedWriteCount: writes dropped, a member written more than 4
     times between two scans keeping its 4 newest. Ok, InvalidArgument.

  node.SubscribeStruct(anyData, nPeerNodeId, nFirstTopicId, sTopicPrefix, fDeadband,
                       tMaxSendInterval, bDeliverEveryChange, nMembers =>, eQuality =>,
                       bAllMembersEverReceived =>, tOldestMemberAge =>, nMembersReceived =>, sFirstReceivedMember =>,
                       nFirstReceivedIndex =>, nMissedUpdateCount =>)
     A PEER'S STRUCT INTO YOURS, of the same type, member by member.
     eQuality is the worst member's; bAllMembersEverReceived every member has arrived;
     tOldestMemberAge the oldest member's age; nMembersReceived the members that arrived
     since the last call, sFirstReceivedMember and nFirstReceivedIndex the first (held). Ok, or a
     refusal.

  node.Serve(anyData, nFirstTopicId, sTopicPrefix, bPeersMayChange, bMembersAreCommands, tPulseLength,
             tAnswerDelay, nOfflineBufferDepth, nMembers =>, bChangedByPeer =>, nMembersChanged =>,
             sFirstChangedMember =>, nFirstChangedIndex =>, nChangedByNodeId =>, nRefusedChangeCount =>,
             nDroppedChangeCount =>)
     A STRUCT THIS NODE SERVES AND DECIDES: the owner side of Bind. A change
     a peer asks for is put into the member in this call, the program runs
     with it, and after that scan (and tAnswerDelay) the member is read back:
     still holding what was asked, Accepted; holding something else
     because a block put its own value back, Changed, with the value kept.
     bMembersAreCommands: every member is a command, taken once and answered Accepted.
     nOfflineBufferDepth, 0..127: each member held in a ring of this many while the
     network is away. bChangedByPeer: changes taken by this call (nMembersChanged,
     sFirstChangedMember, nFirstChangedIndex, nChangedByNodeId held). nRefusedChangeCount: changes not
     kept as asked. Ok, InvalidArgument.

  node.Bind(anyData, nPeerNodeId, nFirstTopicId, sTopicPrefix, bDeliverEveryChange, fDeadband,
            nMembers =>, eBindState =>, bInSync =>, bChangePending =>,
            bSettingRefused =>, sFirstRefusedMember =>, nFirstRefusedIndex =>, bNoDecisionReceived =>,
            tOldestMemberAge =>, bValueReceived =>)
     A STRUCT BOUND TO ONE A PEER SERVES, both ways: the members hold the
     owner's values, and a member the program changes is asked of the
     owner, which decides; whatever it decides, the member ends with its
     value. eBindState, the worst member: Offline, Syncing, Failed,
     Refused, Pending, InSync. bSettingRefused: the owner kept another value for a
     member, which now holds it (sFirstRefusedMember, nFirstRefusedIndex). bNoDecisionReceived: no
     decision came back. Ok, InvalidArgument.

  node.Write(anyValue, nPeerNodeId, nTopicId, bRequireAcknowledge, bAskOwnerDecision, bExecute,
             eOwnerDecision =>, bOwnerAccepted =>, bOwnerKeptOtherValue =>, fOwnerKeptValue =>)
     ONE VALUE INTO A PEER'S WRITABLE TOPIC, on a rising edge of bExecute.
     bRequireAcknowledge: retried until acknowledged, applied once however often it
     was sent. bAskOwnerDecision: ask the owner what it did (makes it
     confirmed): eOwnerDecision Accepted, Changed (it kept another value), or
     Refused, with fOwnerKeptValue; NoAnswer until one came. Queued while it
     runs, then Ok. Refused (a read-only topic), TypeMismatch, Timeout (no
     decision came back), UnknownNode.

  node.Buffer(sTopic, nOfflineBufferDepth, nSamplesWaiting =>)
     STORE AND FORWARD for one of this node's topics (Topic, Publish): up to
     nOfflineBufferDepth samples, each with the age it was taken at, held while there
     is nowhere to send them, so a subscriber that comes back gets the
     history. 0 turns it off. nSamplesWaiting: samples waiting. A buffered topic
     goes out from its ring, change by change: a subscriber's tMaxSendInterval does
     not apply, and a new subscriber waits for the next change. Ok,
     NotMapped (no such topic on this node).

  node.ModbusMap(anyData, eTable, nStartAddress, eActionOnWriterLoss, nSafeValue,
                 nAddressesUsed =>, bWrittenByPeer =>, sFirstWrittenMember =>, nFirstWrittenIndex =>,
                 nFirstWrittenAddress =>, nMembersWritten =>, bSafeValueApplied =>)
     YOUR VARIABLE AT MODBUS ADDRESSES, so peers can read and write it: a
     value, an array or a whole STRUCT, laid out member by member from
     nStartAddress (a REAL two registers, high word first; a STRING(n) n/2 + 1).
     eTable: Coil, HoldingRegister (default), DiscreteInput or
     InputRegister; a coil or input table holds BOOLs only. eActionOnWriterLoss
     ResetToValue: a single number goes to nSafeValue, in its own type, when
     the peer writing it goes silent (bApplySafeValueOnWriterLoss). nAddressesUsed: addresses taken.
     bWrittenByPeer: a peer wrote some since the last call (sFirstWrittenMember,
     nFirstWrittenIndex, nFirstWrittenAddress, nMembersWritten held). bSafeValueApplied: the safe
     value was applied. Ok, InvalidArgument (refused whole, never a member
     skipped, which would move every address after it).

  node.ModbusRead(anyData, nPeerNodeId, eTable, nStartAddress, nQuantity, bExecute)
     A PEER'S ADDRESSES INTO YOUR VARIABLE, laid out as ModbusMap lays it
     out, on a rising edge of bExecute; one request for the whole range.
     nQuantity: how many values, every array element and member one; 0 all.
     The values land together when it ends, never half a value. Queued,
     then Ok. TypeMismatch (a register held a number its member cannot -
     300 for a USINT - and that member was left alone), InvalidArgument,
     UnknownNode, Timeout.

  node.ModbusWrite(anyData, nPeerNodeId, eTable, nStartAddress, nQuantity, bRequireAcknowledge,
                   bExecute)
     YOUR VARIABLE INTO A PEER'S ADDRESSES, on a rising edge of bExecute,
     the values as they were at the edge. Coil or HoldingRegister only.
     bRequireAcknowledge: Queued until the peer acknowledges, then Ok; unconfirmed,
     Ok at the edge. InvalidArgument (a read-only table, a value the table
     cannot hold), UnknownNode, Timeout, Refused.

  node.Statistics(nNodeIdInUse =>, nNodesInRing =>, tTokenRotationTime =>, nPendingOperations =>,
                  nChecksumErrorCount =>, nNoiseByteCount =>)
     THE NODE AND ITS SEGMENT, measured. nNodesInRing: nodes in the ring, this
     one included. tTokenRotationTime: how long the token takes to come round.
     nPendingOperations: operations queued and not finished. nChecksumErrorCount: frames
     that arrived corrupt; rising on a quiet bus is the number to judge a
     link by. nNoiseByteCount: bytes discarded hunting for a frame start;
     climbing steadily means a floating bus, a missing termination or a
     baud rate mismatch. Ok; NotInitialised before the node started.

  node.PeerStatus(nPeerNodeId, bInRing =>, bEverHeard =>, tSinceLastHeard =>, tTokenHopTime =>,
                  tTokenHopTimeout =>)
     ONE PEER, from this node. bInRing: in the ring. bEverHeard: heard at least
     once since the program started: FALSE is a peer never fitted or given
     the wrong id, TRUE with bInRing FALSE one that dropped off. tSinceLastHeard:
     since it was last heard. tTokenHopTime: how long it takes to accept the token;
     tTokenHopTimeout: what it is allowed. A hop time creeping towards its limit
     is a link about to drop a node. Ok, InvalidArgument (0 or 255).
```

**Inputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `nNodeId` | `BYTE` |  | 1..254, unique on the segment |
| `eTransport` | `E_BeeBusTransport` |  | RuntimeUdp (default), RuntimeSerial, ArduinoSerial, ArduinoWiFi, ArduinoEthernet |
| `bConnect` | `BOOL` | `TRUE` | TRUE joins the ring and stays; FALSE leaves it: peers see this node go, nothing is lost on rejoin |
| `bApplySafeValueOnWriterLoss` | `BOOL` |  | apply each address's safe value when the peer driving it goes silent |
| `nMaxPendingOperations` | `USINT` |  | requests and answers waiting for the token at once; 0 = 16 on a board, 50 on the Runtime |
| `bDebugToConsole` | `BOOL` |  | the protocol's debug lines on the console |
| `stSerialConfig` | `ST_BeeBusSerialConfig` |  | a serial link: the Runtime's device, a board's port and pins |
| `stNetworkConfig` | `ST_BeeBusNetworkConfig` |  | a UDP link: group, port, and a board's Wi-Fi or Ethernet |

**Outputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bLinkOpen` | `BOOL` |  | the node started: its link is open |
| `bNetworkUp` | `BOOL` |  | the network under it is up; bLinkOpen on the Runtime and on serial |
| `bConnected` | `BOOL` |  | in the ring: the one to interlock on |
| `bError` | `BOOL` |  | something failed: the link, a setting or a method call |
| `eErrorId` | `E_BeeBusResult` |  | why; Ok when fine |
| `sLastError` | `STRING(128)` |  | why, in words |
| `nLinkOpenAttemptCount` | `UDINT` |  | times the link has been opened, or tried |
| `tRetryTimeLeft` | `TIME` |  | until a failed open is tried again; T#0s otherwise |

### FB_BeeBusNode.Topic

```
result := node.Topic(anyValue := ..., sTopic := ..., nTopicId := ...);
```

Returns `E_BeeBusResult`.
Binds anyValue as a topic this node owns, named sTopic, id nTopicId. Called every scan; the node publishes it to each subscriber on its own terms. E_BeeBusResult.Ok while it is bound.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyValue` | `ANY` |  | the variable; its declared type is the type on the wire |
| `sTopic` | `STRING(254)` |  | up to 253 characters: every peer addresses the topic by it |
| `nTopicId` | `UINT` |  | 1..32767, unique on this node |

### FB_BeeBusNode.Publish

```
result := node.Publish(anyValue := ..., sTopic := ..., nTopicId := ...,
                       ePublishMode := ..., nPeerNodeId := ...,
                       bRequireAcknowledge := ..., bExecute := ...);
```

Returns `E_BeeBusResult`.
Sends anyValue, a topic this node owns, on a rising edge of bExecute: to every node, or to nPeerNodeId. Inputs are taken at the edge. E_BeeBusResult.Queued while a confirmed publish waits, then Ok or why not, until the next edge.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyValue` | `ANY` |  | the variable; its declared type is the type on the wire |
| `sTopic` | `STRING(254)` |  | the topic's name, up to 253 characters |
| `nTopicId` | `UINT` |  | 1..32767, unique on this node |
| `ePublishMode` | `E_BeeBusPublishMode` |  | All (default): every node, one frame; ToPeer: nPeerNodeId only |
| `nPeerNodeId` | `BYTE` |  | ToPeer: the node to send to |
| `bRequireAcknowledge` | `BOOL` |  | ToPeer: retried until nPeerNodeId acknowledges |
| `bExecute` | `BOOL` |  | rising edge sends |

### FB_BeeBusNode.Subscribe

```
result := node.Subscribe(anyValue := ..., nPeerNodeId := ..., sTopic := ...,
                         nTopicId := ..., fDeadband := ...,
                         tMaxSendInterval := ..., bDeliverEveryChange := ...,
                         eQuality => ..., bValueEverReceived => ...,
                         tValueAge => ..., bValueReceived => ...,
                         nMissedUpdateCount => ...);
```

Returns `E_BeeBusResult`.
Keeps anyValue up to date from nPeerNodeId's topic sTopic (nTopicId), called every scan. The subscription is asked again when the terms change and by itself when the peer rejoins.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyValue` | `ANY` |  | the variable the value lands in, of the owner's type |
| `nPeerNodeId` | `BYTE` |  | the node that owns the topic |
| `sTopic` | `STRING(254)` |  | its name on that node |
| `nTopicId` | `UINT` |  | its id on that node |
| `fDeadband` | `REAL` |  | sent again once it has moved this far; 0 = every change |
| `tMaxSendInterval` | `TIME` |  | sent at least this often, moved or not; T#0s = never |
| `bDeliverEveryChange` | `BOOL` |  | FALSE: newest wins (Live); TRUE: every change arrives |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `eQuality` | `E_BeeBusQuality` |  | Unknown before anything arrived, then Good, Uncertain, Bad |
| `bValueEverReceived` | `BOOL` |  | a value has arrived |
| `tValueAge` | `TIME` |  | since the last value; T#0s before the first |
| `bValueReceived` | `BOOL` |  | a value arrived since the last call |
| `nMissedUpdateCount` | `UDINT` |  | updates lost on the way: publishes that never arrived, running total |

### FB_BeeBusNode.PublishStruct

```
result := node.PublishStruct(anyData := ..., nFirstTopicId := ...,
                             sTopicPrefix := ..., bPeersMayWrite := ...,
                             tPulseLength := ..., tAnswerDelay := ...,
                             nMembers => ..., bWrittenByPeer => ...,
                             nMembersWritten => ...,
                             sFirstWrittenMember => ...,
                             nFirstWrittenIndex => ...,
                             nWrittenByNodeId => ...,
                             nDroppedWriteCount => ...);
```

Returns `E_BeeBusResult`.
Owns every member of anyData as a topic, nFirstTopicId + its position, named sTopicPrefix + its path. Called every scan. bPeersMayWrite: peers may write the members, taken here one per member a scan, oldest first.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a STRUCT, or an ARRAY of STRUCTs or values |
| `nFirstTopicId` | `UINT` |  | the first member's id |
| `sTopicPrefix` | `STRING(16)` |  | put before every member's name; names an ARRAY |
| `bPeersMayWrite` | `BOOL` |  | peers may write the members |
| `tPulseLength` | `TIME` |  | bPeersMayWrite: a BOOL written TRUE drops back after this; T#0s = kept |
| `tAnswerDelay` | `TIME` |  | bPeersMayWrite: extra wait after the scan that applied a write, before a result is answered |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nMembers` | `UINT` |  | members, and so topics |
| `bWrittenByPeer` | `BOOL` |  | writes were taken by this call |
| `nMembersWritten` | `UINT` |  | how many members (held) |
| `sFirstWrittenMember` | `STRING(64)` |  | the first of them, 'set.hiMm' (held) |
| `nFirstWrittenIndex` | `UINT` |  | its position from 1 (held) |
| `nWrittenByNodeId` | `BYTE` |  | the node that wrote it (held) |
| `nDroppedWriteCount` | `UDINT` |  | writes dropped, running total |

### FB_BeeBusNode.SubscribeStruct

```
result := node.SubscribeStruct(anyData := ..., nPeerNodeId := ...,
                               nFirstTopicId := ..., sTopicPrefix := ...,
                               fDeadband := ..., tMaxSendInterval := ...,
                               bDeliverEveryChange := ..., nMembers => ...,
                               eQuality => ...,
                               bAllMembersEverReceived => ...,
                               tOldestMemberAge => ...,
                               nMembersReceived => ...,
                               sFirstReceivedMember => ...,
                               nFirstReceivedIndex => ...,
                               nMissedUpdateCount => ...);
```

Returns `E_BeeBusResult`.
Keeps every member of anyData up to date from nPeerNodeId's PublishStruct of the same type at nFirstTopicId, sTopicPrefix. Called every scan. eQuality is the worst member's.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a STRUCT or ARRAY of the same type as the peer's |
| `nPeerNodeId` | `BYTE` |  | the node that owns the topics |
| `nFirstTopicId` | `UINT` |  | the peer's nFirstTopicId |
| `sTopicPrefix` | `STRING(16)` |  | the peer's sTopicPrefix |
| `fDeadband` | `REAL` |  | sent again once it has moved this far; 0 = every change |
| `tMaxSendInterval` | `TIME` |  | every member at least this often; T#0s = never |
| `bDeliverEveryChange` | `BOOL` |  | FALSE: newest wins (Live); TRUE: every change arrives |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nMembers` | `UINT` |  | members, and so topics |
| `eQuality` | `E_BeeBusQuality` |  | the worst member's |
| `bAllMembersEverReceived` | `BOOL` |  | every member has arrived |
| `tOldestMemberAge` | `TIME` |  | the oldest member's age |
| `nMembersReceived` | `UINT` |  | members that arrived since the last call |
| `sFirstReceivedMember` | `STRING(64)` |  | the first of them (held) |
| `nFirstReceivedIndex` | `UINT` |  | its position from 1 (held) |
| `nMissedUpdateCount` | `UDINT` |  | updates lost on the way, every member, running total |

### FB_BeeBusNode.Serve

```
result := node.Serve(anyData := ..., nFirstTopicId := ...,
                     sTopicPrefix := ..., bPeersMayChange := ...,
                     bMembersAreCommands := ..., tPulseLength := ...,
                     tAnswerDelay := ..., nOfflineBufferDepth := ...,
                     nMembers => ..., bChangedByPeer => ...,
                     nMembersChanged => ..., sFirstChangedMember => ...,
                     nFirstChangedIndex => ..., nChangedByNodeId => ...,
                     nRefusedChangeCount => ..., nDroppedChangeCount => ...);
```

Returns `E_BeeBusResult`.
Serves every member of anyData as a topic this node decides: a change a peer asks for is taken into the member here, the program runs with it, and the member is read back for the answer. Called every scan.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a STRUCT, or an ARRAY of STRUCTs or values |
| `nFirstTopicId` | `UINT` |  | the first member's id |
| `sTopicPrefix` | `STRING(16)` |  | put before every member's name |
| `bPeersMayChange` | `BOOL` |  | peers may ask to change the members; FALSE: ReadOnly |
| `bMembersAreCommands` | `BOOL` |  | every member is a command, taken once and answered Accepted |
| `tPulseLength` | `TIME` |  | a BOOL written TRUE drops back after this; T#0s = kept |
| `tAnswerDelay` | `TIME` |  | extra wait after the scan that applied a change, before the answer is sent |
| `nOfflineBufferDepth` | `USINT` |  | values of each member held while the network is away, 0..127 |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nMembers` | `UINT` |  | members, and so topics |
| `bChangedByPeer` | `BOOL` |  | changes were taken by this call |
| `nMembersChanged` | `UINT` |  | how many members (held) |
| `sFirstChangedMember` | `STRING(64)` |  | the first of them (held) |
| `nFirstChangedIndex` | `UINT` |  | its position from 1 (held) |
| `nChangedByNodeId` | `BYTE` |  | the node that asked (held) |
| `nRefusedChangeCount` | `UDINT` |  | changes not kept as asked, running total |
| `nDroppedChangeCount` | `UDINT` |  | changes dropped, running total |

### FB_BeeBusNode.Bind

```
result := node.Bind(anyData := ..., nPeerNodeId := ..., nFirstTopicId := ...,
                    sTopicPrefix := ..., bDeliverEveryChange := ...,
                    fDeadband := ..., nMembers => ..., eBindState => ...,
                    bInSync => ..., bChangePending => ...,
                    bSettingRefused => ..., sFirstRefusedMember => ...,
                    nFirstRefusedIndex => ..., bNoDecisionReceived => ...,
                    tOldestMemberAge => ..., bValueReceived => ...);
```

Returns `E_BeeBusResult`.
Binds every member of anyData to the one nPeerNodeId serves at nFirstTopicId, sTopicPrefix: the owner's values land in the members, and a member the program changes is asked of the owner. Called every scan.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a STRUCT or ARRAY declared the same as the owner's |
| `nPeerNodeId` | `BYTE` |  | the node that serves it |
| `nFirstTopicId` | `UINT` |  | the owner's nFirstTopicId |
| `sTopicPrefix` | `STRING(16)` |  | the owner's sTopicPrefix |
| `bDeliverEveryChange` | `BOOL` |  | TRUE for settings: every change arrives; FALSE: newest wins |
| `fDeadband` | `REAL` |  | Live only: sent again once it has moved this far |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nMembers` | `UINT` |  | members |
| `eBindState` | `E_BeeBusBindState` |  | the worst member's |
| `bInSync` | `BOOL` |  | every member holds the owner's value |
| `bChangePending` | `BOOL` |  | a change is with the owner |
| `bSettingRefused` | `BOOL` |  | the owner kept another value for a member |
| `sFirstRefusedMember` | `STRING(64)` |  | the first member refused (held) |
| `nFirstRefusedIndex` | `UINT` |  | its position from 1 (held) |
| `bNoDecisionReceived` | `BOOL` |  | no decision came back for a change |
| `tOldestMemberAge` | `TIME` |  | since the oldest member last had a value from the owner |
| `bValueReceived` | `BOOL` |  | a value arrived from the owner since the last call |

### FB_BeeBusNode.Write

```
result := node.Write(anyValue := ..., nPeerNodeId := ..., nTopicId := ...,
                     bRequireAcknowledge := ..., bAskOwnerDecision := ...,
                     bExecute := ..., eOwnerDecision => ...,
                     bOwnerAccepted => ..., bOwnerKeptOtherValue => ...,
                     fOwnerKeptValue => ...);
```

Returns `E_BeeBusResult`.
Writes anyValue into nPeerNodeId's writable topic nTopicId on a rising edge of bExecute. E_BeeBusResult.Queued while it waits for the acknowledgement or the owner's decision, then Ok or why not, until the next edge.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyValue` | `ANY` |  | one value of the member's type |
| `nPeerNodeId` | `BYTE` |  | the node that owns the topic |
| `nTopicId` | `UINT` |  | the topic's id on that node |
| `bRequireAcknowledge` | `BOOL` |  | retried until acknowledged |
| `bAskOwnerDecision` | `BOOL` |  | ask the owner what it did; makes it confirmed |
| `bExecute` | `BOOL` |  | rising edge writes |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `eOwnerDecision` | `E_BeeBusOutcome` |  | bAskOwnerDecision: the owner's decision; NoAnswer before one |
| `bOwnerAccepted` | `BOOL` |  | the decision was Accepted |
| `bOwnerKeptOtherValue` | `BOOL` |  | the owner kept another value: Changed or Refused |
| `fOwnerKeptValue` | `LREAL` |  | the owner's value with the decision |

### FB_BeeBusNode.Buffer

```
result := node.Buffer(sTopic := ..., nOfflineBufferDepth := ...,
                      nSamplesWaiting => ...);
```

Returns `E_BeeBusResult`.
Holds up to nOfflineBufferDepth samples of this node's topic sTopic while there is nowhere to send them, sent oldest first when there is. Called every scan.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sTopic` | `STRING(254)` |  | the topic, bound by Topic or Publish on this node |
| `nOfflineBufferDepth` | `USINT` |  | values held while the network is away; 0 turns it off |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nSamplesWaiting` | `UINT` |  | samples waiting to go out |

### FB_BeeBusNode.ModbusMap

```
result := node.ModbusMap(anyData := ..., eTable := ..., nStartAddress := ...,
                         eActionOnWriterLoss := ..., nSafeValue := ...,
                         nAddressesUsed => ..., bWrittenByPeer => ...,
                         sFirstWrittenMember => ...,
                         nFirstWrittenIndex => ...,
                         nFirstWrittenAddress => ..., nMembersWritten => ...,
                         bSafeValueApplied => ...);
```

Returns `E_BeeBusResult`.
Puts anyData at Modbus addresses from nStartAddress in eTable, so peers can read and write it. Called every scan; the variable is the register.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a value, a fixed-bounds array or a STRUCT |
| `eTable` | `E_BeeBusModbusTable` |  | Coil, HoldingRegister (default), DiscreteInput, InputRegister |
| `nStartAddress` | `UINT` |  | the first address |
| `eActionOnWriterLoss` | `E_BeeBusModbusFailsafe` |  | HoldLastValue (default) or ResetToValue when the writer goes silent |
| `nSafeValue` | `DINT` |  | ResetToValue: the value, in the variable's own type |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nAddressesUsed` | `UINT` |  | addresses taken: registers, or coils |
| `bWrittenByPeer` | `BOOL` |  | a peer wrote some since the last call |
| `sFirstWrittenMember` | `STRING(64)` |  | the first member written (held) |
| `nFirstWrittenIndex` | `UINT` |  | its position from 1 (held) |
| `nFirstWrittenAddress` | `UINT` |  | its first address (held) |
| `nMembersWritten` | `UINT` |  | members that write covered (held) |
| `bSafeValueApplied` | `BOOL` |  | the safe value was applied since the last call |

### FB_BeeBusNode.ModbusRead

```
result := node.ModbusRead(anyData := ..., nPeerNodeId := ..., eTable := ...,
                          nStartAddress := ..., nQuantity := ...,
                          bExecute := ...);
```

Returns `E_BeeBusResult`.
Reads nPeerNodeId's addresses into anyData on a rising edge of bExecute, laid out as ModbusMap lays it out. E_BeeBusResult.Queued while it runs, then Ok or why not, until the next edge.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a value, a fixed-bounds array or a STRUCT |
| `nPeerNodeId` | `BYTE` |  | the node to read from |
| `eTable` | `E_BeeBusModbusTable` |  | which of the peer's tables |
| `nStartAddress` | `UINT` |  | the first address on that node |
| `nQuantity` | `UINT` |  | values to read, each element and member one; 0 = all |
| `bExecute` | `BOOL` |  | rising edge reads |

### FB_BeeBusNode.ModbusWrite

```
result := node.ModbusWrite(anyData := ..., nPeerNodeId := ..., eTable := ...,
                           nStartAddress := ..., nQuantity := ...,
                           bRequireAcknowledge := ..., bExecute := ...);
```

Returns `E_BeeBusResult`.
Writes anyData into nPeerNodeId's addresses on a rising edge of bExecute, the values as they were at the edge. E_BeeBusResult.Queued while a confirmed write waits, then Ok or why not, until the next edge.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a value, a fixed-bounds array or a STRUCT |
| `nPeerNodeId` | `BYTE` |  | the node to write to |
| `eTable` | `E_BeeBusModbusTable` |  | Coil or HoldingRegister |
| `nStartAddress` | `UINT` |  | the first address on that node |
| `nQuantity` | `UINT` |  | values to write, each element and member one; 0 = all |
| `bRequireAcknowledge` | `BOOL` |  | wait for the peer to acknowledge |
| `bExecute` | `BOOL` |  | rising edge writes |

### FB_BeeBusNode.Statistics

```
result := node.Statistics(nNodeIdInUse => ..., nNodesInRing => ...,
                          tTokenRotationTime => ...,
                          nPendingOperations => ...,
                          nChecksumErrorCount => ..., nNoiseByteCount => ...);
```

Returns `E_BeeBusResult`.
This node and its segment, measured.

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nNodeIdInUse` | `BYTE` |  | the address this node holds, as opened |
| `nNodesInRing` | `BYTE` |  | nodes in the ring, this one included |
| `tTokenRotationTime` | `TIME` |  | how long the token takes to come round; T#0s until it has |
| `nPendingOperations` | `INT` |  | operations queued and not finished |
| `nChecksumErrorCount` | `DINT` |  | frames that arrived corrupt |
| `nNoiseByteCount` | `DINT` |  | bytes discarded hunting for a frame start |

### FB_BeeBusNode.PeerStatus

```
result := node.PeerStatus(nPeerNodeId := ..., bInRing => ...,
                          bEverHeard => ..., tSinceLastHeard => ...,
                          tTokenHopTime => ..., tTokenHopTimeout => ...);
```

Returns `E_BeeBusResult`.
How nPeerNodeId is doing, from this node.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nPeerNodeId` | `BYTE` |  | the peer, 1..254 |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bInRing` | `BOOL` |  | in the ring |
| `bEverHeard` | `BOOL` |  | heard at least once since the program started |
| `tSinceLastHeard` | `TIME` |  | since it was last heard; T#0s before |
| `tTokenHopTime` | `TIME` |  | how long it takes to accept the token |
| `tTokenHopTimeout` | `TIME` |  | what it is allowed before the token is presumed lost |

node(nNodeId := 10, eTransport := E_BeeBusTransport.RuntimeUdp);
  node.Serve(anyData := SET, nFirstTopicId := 300, bPeersMayChange := TRUE);
  node.Subscribe(anyValue := rLevel, nPeerNodeId := 2, sTopic := 'level', nTopicId := 100,
                 eQuality => eLevelQuality);

Call the block first in the scan and its methods after it: a method above it
acts one scan later, which costs a scan and corrects itself. Nothing here
configures timing: every protocol timeout is measured from the network.

A LINK THAT WILL NOT OPEN IS TRIED AGAIN. A USB adapter plugged in after
boot, a network that comes up after the PLC, a port another program is
holding: eErrorId reads NotInitialised, sLastError says why, and the open is
tried again 1 s later, then 2, 4, 8, 16, and every 30 s from then on.
tRetryTimeLeft counts down to the next try and nLinkOpenAttemptCount counts them. The moment
it opens, bError clears and bLinkOpen is set.

A WRONG SETTING IS NOT RETRIED, because trying again cannot fix it: a link
the target does not have, nNodeId 0 or 255, a serial link with no device, a
port the board has not got. eErrorId reads InvalidArgument and sLastError
names the setting. Correct it and the link opens, no restart.

ONE SCAN BEFORE OPENING. The link is built on the block's second scan, so
every method has been called once first, wherever it sits in the program.

SETTINGS MAY CHANGE WHILE IT RUNS. nNodeId, eTransport, bApplySafeValueOnWriterLoss,
nMaxPendingOperations and every member of the two option structures are read every
scan. A change leaves the ring and opens again with the new ones, on the
same node: every record the methods bound stays bound, and the node's peers
subscribe again when it returns under its new id.

ONE TASK. This block and its methods run in one task, the network task, at
a lower priority than the machine's. The machine's program trades values
with them through globals. Declare the instance in the network task's
program, never in a global list: a method called from another task returns
E_BeeBusResult.WrongTask and does nothing, rather than race the node from
another thread. See docs/10-scan-rate.md.

---

## Structures

Option structures are inputs of a block, set in the declaration or from an
HMI and read every scan. A member left at its default is the right answer
for most sites; `0` and `T#0s` mean the library's default.

### ST_BeeBusNetworkConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `sMulticastAddress` | `STRING(32)` |  | the multicast group every node joins; empty = 239.192.7.126 |
| `nUdpPort` | `UINT` |  | the port every node uses; 0 = 7126 |
| `nMulticastHops` | `BYTE` |  | RuntimeUdp: multicast hops; 0 = 1, this subnet |
| `sInterfaceAddress` | `STRING(32)` |  | RuntimeUdp: the interface address to send from; empty = the host's choice |
| `sSsid` | `STRING(32)` |  | E_BeeBusTransport.ArduinoWiFi: the network to join |
| `sWiFiPassword` | `STRING(63)` |  | its password, up to 63 characters (WPA2) |
| `sMacAddress` | `STRING(32)` |  | E_BeeBusTransport.ArduinoEthernet: this board's MAC, 'DE:AD:BE:EF:FE:ED' |
| `sIpAddress` | `STRING(32)` |  | ArduinoEthernet: a fixed address; empty = DHCP |

### ST_BeeBusSerialConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `sDevice` | `STRING(127)` |  | E_BeeBusTransport.RuntimeSerial: the device, '/dev/ttyUSB0' or a /dev/serial/by-id/ path |
| `nBaudRate` | `DINT` |  | 0 = the transport's default: 115200 |
| `nUart` | `BYTE` |  | E_BeeBusTransport.ArduinoSerial: the board's hardware serial, 0 = the first |
| `nRxPin` | `INT` | `-1` | ArduinoSerial on an ESP32: the receive pin; -1 = the board's own |
| `nTxPin` | `INT` | `-1` | ArduinoSerial on an ESP32: the transmit pin; -1 = the board's own |

## Enumerations

Each is `{attribute 'qualified_only'}`, so a value is always written with its type: `E_BeeBusModbusTable.Coil`, `E_BeeBusResult.Ok`. A bare `Ok` does not compile.

| Enumeration | Values, in order | Default |
| --- | --- | --- |
| `E_BeeBusBindState` | `Offline`, `Syncing`, `InSync`, `Pending`, `Refused`, `Failed` | `Offline` |
| `E_BeeBusModbusFailsafe` | `HoldLastValue`, `ResetToValue` | `HoldLastValue` |
| `E_BeeBusModbusTable` | `Coil`, `HoldingRegister`, `DiscreteInput`, `InputRegister` | `HoldingRegister` |
| `E_BeeBusOutcome` | `Accepted`, `Changed`, `Refused`, `ReadOnly`, `NoTopic`, `WrongType`, `Busy`, `NoAnswer` | `NoAnswer` |
| `E_BeeBusPublishMode` | `All`, `ToPeer` | `All` |
| `E_BeeBusQuality` | `Unknown`, `Good`, `Uncertain`, `Bad` | `Unknown` |
| `E_BeeBusResult` | `Queued`, `Ok`, `NotInitialised`, `InvalidArgument`, `UnknownNode`, `DuplicateNodeId`, `NotMapped`, `Duplicate`, `QueueFull`, `Timeout`, `NodeLost`, `Superseded`, `Cancelled`, `Refused`, `TypeMismatch`, `NotSubscribed`, `BufferFull`, `WrongTask` | `Ok` |
| `E_BeeBusTransport` | `RuntimeUdp`, `RuntimeSerial`, `ArduinoSerial`, `ArduinoWiFi`, `ArduinoEthernet` | `RuntimeUdp` |

[06 Diagnostics](06-diagnostics.md) explains every `E_BeeBusResult` value.

---

**Next:** [08 Patterns](08-patterns.md)
