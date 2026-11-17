(* A BeeBus node: this PLC's place on one segment, serial or UDP. Call it once
every scan, in the network task. Everything the PLC owns, serves, subscribes,
binds, reads or writes on that segment is a method of this block.

nNodeId     1..254, unique on the segment.
eTransport  which link. The target must have it; one it does not have is
           reported on bError and sLastError, never built.
             E_BeeBusTransport.RuntimeUdp       the Runtime's network, UDP
                                                multicast (default)
             E_BeeBusTransport.RuntimeSerial    a serial device on the
                                                Runtime, stSerialConfig.sDevice
             E_BeeBusTransport.ArduinoSerial    a board's hardware serial,
                                                stSerialConfig.nPort and pins
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
bFailsafe   apply each address's safe value (ModbusMap eOnLoss) when the peer
           driving it goes silent.
nMaxPending how many requests (reads, writes, subscriptions) and how many
           answers can wait for the token at once, 1..255. 0 (default) is 16
           on a board and 50 on the Runtime. Past it a request is refused
           with E_BeeBusResult.QueueFull and asked again by its method on a
           later scan. Raise it on a node that keeps many requests in flight,
           and on the node that answers them. Each place costs about 300
           bytes of RAM, taken when the node starts; too many for the memory
           and the node does not start, sLastError saying so.
bDebug      print the protocol's own debug lines to the console.
stSerialConfig  ST_BeeBusSerialConfig, a serial link.
             sDevice   RuntimeSerial: the device, '/dev/ttyUSB0'
             nBaud     0 for the default, 115200
             nPort     ArduinoSerial: which hardware serial, 0 for the first
             nRxPin    ArduinoSerial on an ESP32: the receive pin, -1 for the
                       board's own
             nTxPin    the transmit pin, -1 for the board's own
stNetworkConfig  ST_BeeBusNetworkConfig, a UDP link.
             sGroupAddr      the multicast group, empty for the protocol's
                             own (239.192.7.126)
             nUdpPort        0 for the protocol's own (7126)
             nTtl            RuntimeUdp: multicast hops, 0 for 1 (this subnet)
             sInterfaceAddr  RuntimeUdp: the interface address to send from,
                             empty to let the host choose
             sSsid           ArduinoWiFi: the network to join
             sWiFiPassword   its password, up to 63 characters (WPA2)
             sMac            ArduinoEthernet: six hex bytes,
                             'DE:AD:BE:EF:FE:ED'. Empty takes a built-in
                             default: fine for ONE device on a network
             sIp             ArduinoEthernet: a fixed address, empty for DHCP.
                             Prefer a fixed address: DHCP blocks while it
                             asks, so each attempt is bounded to a second
           A member that does not apply to the target - sDevice on a board,
           sSsid on the Runtime - is reported on bError, never ignored.

bReady      the node started: its link is open.
bLinkUp     the network under it is up: Wi-Fi joined, or the Ethernet cable
           in and an address held. The same as bReady on the Runtime and on
           a serial line.
bConnected  in the ring, holding a place in the rotation. THE ONE TO
           INTERLOCK ON.
bError      something failed: the link, a setting, or a method call.
eErrorId    why. E_BeeBusResult.Ok when fine.
             NotInitialised   the link did not open; tried again, below
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
nAttempts   how many times the link has been opened, or tried.
tRetryIn    while a failed open waits to be tried again, how long until it
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

  node.Topic(anyValue, sName, nTopicId)
     A TOPIC THIS NODE OWNS, bound to the variable itself. Its declared type
     is the type on the wire: BOOL, SINT, USINT, BYTE, INT, UINT, WORD,
     DINT, UDINT, DWORD, LINT, ULINT, LWORD, REAL, LREAL, LTIME (LINT
     nanoseconds) or STRING. sName, up to 253 characters, is the identity:
     every peer addresses the topic by it. nTopicId, 1..32767, unique on
     this node; under 128 costs one byte on the wire. Once bound the node
     publishes on its own, to every subscriber on its own terms: move the
     variable and it goes out. Peers may read it, not write it. Ok,
     InvalidArgument (an empty or too long name, a type the wire cannot
     carry, an id already bound).

  node.Publish(anyValue, sName, nTopicId, ePublishMode, nPeer, bConfirmed,
               bExecute)
     A TOPIC THIS NODE OWNS, SENT ON A RISING EDGE of bExecute: an event
     that must go the moment something happened. ePublishMode
     E_BeeBusPublishMode.All: every node at once, one frame however many
     listen, applied by every node holding the topic; nothing acknowledges
     it, so bConfirmed is refused (InvalidArgument). ToPeer: nPeer only, on
     its counted stream; with bConfirmed the frame is retried until nPeer
     acknowledges it. Topic beside it, on the same variable, sName and
     nTopicId, also sends it on the subscribers' own terms. Queued while a
     confirmed publish waits, then Ok; unconfirmed, Ok at the edge.
     UnknownNode, Timeout, InvalidArgument.

  node.Subscribe(anyValue, nPeer, sName, nTopicId, fDeadband, tPeriod,
                 bReliable, eQuality =>, bSeen =>, tAge =>, bNewValue =>,
                 nMissed =>)
     A PEER'S TOPIC, landing in anyValue, of the type the owner bound.
     fDeadband: sent again once it has moved this far, 0 every change.
     tPeriod: sent at least this often, moved or not, T#0s never.
     bReliable FALSE (Live): best effort, newest wins, for levels and
     speeds. TRUE: every change arrives, and one a lost frame took is sent
     again, as the current value, within a rotation or two; for a setpoint
     or a setting. eQuality Unknown before anything arrived, then Good,
     Uncertain or Bad as the value ages. bSeen: a value has arrived, for a
     ladder rung, which cannot compare an enumeration. tAge since the last
     value. bNewValue: one arrived since the last call. nMissed: publishes
     the sequence says never arrived, a running total. Re-asked by itself
     whenever the peer rejoins. Ok, or the subscription's refusal.

  node.PublishStruct(anyData, nTopicId, sPrefix, bWritable, tPulse, tSettle,
                     nMembers =>, bWritten =>, nWritten =>, sWrittenName =>,
                     nWrittenIndex =>, nWrittenBy =>, nLost =>)
     A WHOLE STRUCT AS TOPICS THIS NODE OWNS, one per member: the member
     name is the topic name, nTopicId + its position the id. An ARRAY of
     STRUCTs or of values works the same. bWritable: peers may write the
     members; a write is held and taken in this call, one per member a
     scan, oldest first. tPulse: a BOOL member written TRUE drops back to
     FALSE this long after. tSettle: a write that asked for a result is
     answered after the program has run a scan with it, plus this long.
     bWritten: writes were taken by this call; nWritten how many,
     sWrittenName and nWrittenIndex the first, nWrittenBy the node that
     wrote it (held). nLost: writes dropped, a member written more than 4
     times between two scans keeping its 4 newest. Ok, InvalidArgument.

  node.SubscribeStruct(anyData, nPeer, nTopicId, sPrefix, fDeadband,
                       tPeriod, bReliable, nMembers =>, eQuality =>,
                       bSeen =>, tOldest =>, nNewValues =>, sNewName =>,
                       nNewIndex =>, nMissed =>)
     A PEER'S STRUCT INTO YOURS, of the same type, member by member.
     eQuality is the worst member's; bSeen every member has arrived;
     tOldest the oldest member's age; nNewValues the members that arrived
     since the last call, sNewName and nNewIndex the first (held). Ok, or a
     refusal.

  node.Serve(anyData, nTopicId, sPrefix, bWritable, bCommand, tPulse,
             tSettle, nDepth, nMembers =>, bChanged =>, nChanged =>,
             sChangedName =>, nChangedIndex =>, nChangedBy =>, nRefused =>,
             nLost =>)
     A STRUCT THIS NODE SERVES AND DECIDES: the owner side of Bind. A change
     a peer asks for is put into the member in this call, the program runs
     with it, and after that scan (and tSettle) the member is read back:
     still holding what was asked, Accepted; holding something else
     because a block put its own value back, Changed, with the value kept.
     bCommand: every member is a command, taken once and answered Accepted.
     nDepth, 0..127: each member held in a ring of this many while the
     network is away. bChanged: changes taken by this call (nChanged,
     sChangedName, nChangedIndex, nChangedBy held). nRefused: changes not
     kept as asked. Ok, InvalidArgument.

  node.Bind(anyData, nPeer, nTopicId, sPrefix, bReliable, fDeadband,
            nMembers =>, eBindState =>, bInSync =>, bPending =>,
            bRefused =>, sRefusedName =>, nRefusedIndex =>, bFailed =>,
            tOldest =>, bNewValue =>)
     A STRUCT BOUND TO ONE A PEER SERVES, both ways: the members hold the
     owner's values, and a member the program changes is asked of the
     owner, which decides; whatever it decides, the member ends with its
     value. eBindState, the worst member: Offline, Syncing, Failed,
     Refused, Pending, InSync. bRefused: the owner kept another value for a
     member, which now holds it (sRefusedName, nRefusedIndex). bFailed: no
     decision came back. Ok, InvalidArgument.

  node.Write(anyValue, nPeer, nTopicId, bConfirmed, bWantResult, bExecute,
             eOutcome =>, bAccepted =>, bRefused =>, fKeptValue =>)
     ONE VALUE INTO A PEER'S WRITABLE TOPIC, on a rising edge of bExecute.
     bConfirmed: retried until acknowledged, applied once however often it
     was sent. bWantResult: ask the owner what it did (makes it
     confirmed): eOutcome Accepted, Changed (it kept another value), or
     Refused, with fKeptValue; NoAnswer until one came. Queued while it
     runs, then Ok. Refused (a read-only topic), TypeMismatch, Timeout (no
     decision came back), UnknownNode.

  node.Buffer(sName, nDepth, nHeld =>)
     STORE AND FORWARD for one of this node's topics (Topic, Publish): up to
     nDepth samples, each with the age it was taken at, held while there
     is nowhere to send them, so a subscriber that comes back gets the
     history. 0 turns it off. nHeld: samples waiting. A buffered topic
     goes out from its ring, change by change: a subscriber's tPeriod does
     not apply, and a new subscriber waits for the next change. Ok,
     NotMapped (no such topic on this node).

  node.ModbusMap(anyData, eTable, nAddress, eOnLoss, nSafeValue,
                 nCount =>, bWritten =>, sWrittenName =>, nWrittenIndex =>,
                 nWrittenAddr =>, nWritten =>, bSafeApplied =>)
     YOUR VARIABLE AT MODBUS ADDRESSES, so peers can read and write it: a
     value, an array or a whole STRUCT, laid out member by member from
     nAddress (a REAL two registers, high word first; a STRING(n) n/2 + 1).
     eTable: Coil, HoldingRegister (default), DiscreteInput or
     InputRegister; a coil or input table holds BOOLs only. eOnLoss
     ResetToValue: a single number goes to nSafeValue, in its own type, when
     the peer writing it goes silent (bFailsafe). nCount: addresses taken.
     bWritten: a peer wrote some since the last call (sWrittenName,
     nWrittenIndex, nWrittenAddr, nWritten held). bSafeApplied: the safe
     value was applied. Ok, InvalidArgument (refused whole, never a member
     skipped, which would move every address after it).

  node.ModbusRead(anyData, nPeer, eTable, nAddress, nLength, bExecute)
     A PEER'S ADDRESSES INTO YOUR VARIABLE, laid out as ModbusMap lays it
     out, on a rising edge of bExecute; one request for the whole range.
     nLength: how many values, every array element and member one; 0 all.
     The values land together when it ends, never half a value. Queued,
     then Ok. TypeMismatch (a register held a number its member cannot -
     300 for a USINT - and that member was left alone), InvalidArgument,
     UnknownNode, Timeout.

  node.ModbusWrite(anyData, nPeer, eTable, nAddress, nLength, bConfirmed,
                   bExecute)
     YOUR VARIABLE INTO A PEER'S ADDRESSES, on a rising edge of bExecute,
     the values as they were at the edge. Coil or HoldingRegister only.
     bConfirmed: Queued until the peer acknowledges, then Ok; unconfirmed,
     Ok at the edge. InvalidArgument (a read-only table, a value the table
     cannot hold), UnknownNode, Timeout, Refused.

  node.Statistics(nIdInUse =>, nMembers =>, tRotation =>, nPendingOps =>,
                  nCrcErrors =>, nNoiseBytes =>)
     THE NODE AND ITS SEGMENT, measured. nMembers: nodes in the ring, this
     one included. tRotation: how long the token takes to come round.
     nPendingOps: operations queued and not finished. nCrcErrors: frames
     that arrived corrupt; rising on a quiet bus is the number to judge a
     link by. nNoiseBytes: bytes discarded hunting for a frame start;
     climbing steadily means a floating bus, a missing termination or a
     baud rate mismatch. Ok; NotInitialised before the node started.

  node.PeerStatus(nPeer, bAlive =>, bSeen =>, tSilent =>, tHop =>,
                  tHopTimeout =>)
     ONE PEER, from this node. bAlive: in the ring. bSeen: heard at least
     once since the program started: FALSE is a peer never fitted or given
     the wrong id, TRUE with bAlive FALSE one that dropped off. tSilent:
     since it was last heard. tHop: how long it takes to accept the token;
     tHopTimeout: what it is allowed. A hop time creeping towards its limit
     is a link about to drop a node. Ok, InvalidArgument (0 or 255).

---

  node(nNodeId := 10, eTransport := E_BeeBusTransport.RuntimeUdp);
  node.Serve(anyData := SET, nTopicId := 300, bWritable := TRUE);
  node.Subscribe(anyValue := rLevel, nPeer := 2, sName := 'level', nTopicId := 100,
                 eQuality => eLevelQuality);

Call the block first in the scan and its methods after it: a method above it
acts one scan later, which costs a scan and corrects itself. Nothing here
configures timing: every protocol timeout is measured from the network.

A LINK THAT WILL NOT OPEN IS TRIED AGAIN. A USB adapter plugged in after
boot, a network that comes up after the PLC, a port another program is
holding: eErrorId reads NotInitialised, sLastError says why, and the open is
tried again 1 s later, then 2, 4, 8, 16, and every 30 s from then on.
tRetryIn counts down to the next try and nAttempts counts them. The moment
it opens, bError clears and bReady is set.

A WRONG SETTING IS NOT RETRIED, because trying again cannot fix it: a link
the target does not have, nNodeId 0 or 255, a serial link with no device, a
port the board has not got. eErrorId reads InvalidArgument and sLastError
names the setting. Correct it and the link opens, no restart.

ONE SCAN BEFORE OPENING. The link is built on the block's second scan, so
every method has been called once first, wherever it sits in the program.

SETTINGS MAY CHANGE WHILE IT RUNS. nNodeId, eTransport, bFailsafe,
nMaxPending and every member of the two option structures are read every
scan. A change leaves the ring and opens again with the new ones, on the
same node: every record the methods bound stays bound, and the node's peers
subscribe again when it returns under its new id.

ONE TASK. This block and its methods run in one task, the network task, at
a lower priority than the machine's. The machine's program trades values
with them through globals. Declare the instance in the network task's
program, never in a global list: a method called from another task returns
E_BeeBusResult.WrongTask and does nothing, rather than race the node from
another thread. See docs/10-scan-rate.md. *)

FUNCTION_BLOCK FB_BeeBusNode
  VAR_INPUT
    nNodeId : BYTE;                          (* 1..254, unique on the segment *)
    eTransport : E_BeeBusTransport;          (* RuntimeUdp (default), RuntimeSerial, ArduinoSerial, ArduinoWiFi, ArduinoEthernet *)
    bConnect : BOOL := TRUE;                 (* TRUE joins the ring and stays; FALSE leaves it, every binding kept *)
    bFailsafe : BOOL;                        (* apply each address's safe value when the peer driving it goes silent *)
    nMaxPending : USINT;                     (* requests and answers waiting for the token at once; 0 = 16 on a board, 50 on the Runtime *)
    bDebug : BOOL;                           (* the protocol's debug lines on the console *)
    stSerialConfig : ST_BeeBusSerialConfig;  (* a serial link: the Runtime's device, a board's port and pins *)
    stNetworkConfig : ST_BeeBusNetworkConfig;  (* a UDP link: group, port, and a board's Wi-Fi or Ethernet *)
  END_VAR
  VAR_OUTPUT
    bReady : BOOL;               (* the node started: its link is open *)
    bLinkUp : BOOL;              (* the network under it is up; bReady on the Runtime and on serial *)
    bConnected : BOOL;           (* in the ring: the one to interlock on *)
    bError : BOOL;               (* something failed: the link, a setting or a method call *)
    eErrorId : E_BeeBusResult;   (* why; Ok when fine *)
    sLastError : STRING(128);    (* why, in words *)
    nAttempts : UDINT;           (* times the link has been opened, or tried *)
    tRetryIn : TIME;             (* until a failed open is tried again; T#0s otherwise *)
  END_VAR
  VAR
    (* The node, its link and every method's records, made on first use. *)
    nState : __XWORD;
  END_VAR


(* Binds anyValue as a topic this node owns, named sName, id nTopicId. Called
   every scan; the node publishes it to each subscriber on its own terms.
   E_BeeBusResult.Ok while it is bound. *)
METHOD PUBLIC Topic : E_BeeBusResult
  VAR_INPUT
    anyValue : ANY;              (* the variable; its declared type is the type on the wire *)
    sName : STRING(254);         (* up to 253 characters: every peer addresses the topic by it *)
    nTopicId : UINT;             (* 1..32767, unique on this node *)
  END_VAR
END_METHOD

(* Sends anyValue, a topic this node owns, on a rising edge of bExecute: to
   every node, or to nPeer. Inputs are taken at the edge.
   E_BeeBusResult.Queued while a confirmed publish waits, then Ok or why not,
   until the next edge. *)
METHOD PUBLIC Publish : E_BeeBusResult
  VAR_INPUT
    anyValue : ANY;              (* the variable; its declared type is the type on the wire *)
    sName : STRING(254);         (* the topic's name, up to 253 characters *)
    nTopicId : UINT;             (* 1..32767, unique on this node *)
    ePublishMode : E_BeeBusPublishMode;  (* All (default): every node, one frame; ToPeer: nPeer only *)
    nPeer : BYTE;                (* ToPeer: the node to send to *)
    bConfirmed : BOOL;           (* ToPeer: retried until nPeer acknowledges *)
    bExecute : BOOL;             (* rising edge sends *)
  END_VAR
END_METHOD

(* Keeps anyValue up to date from nPeer's topic sName (nTopicId), called every
   scan. The subscription is asked again when the terms change and by itself
   when the peer rejoins. *)
METHOD PUBLIC Subscribe : E_BeeBusResult
  VAR_INPUT
    anyValue : ANY;              (* the variable the value lands in, of the owner's type *)
    nPeer : BYTE;                (* the node that owns the topic *)
    sName : STRING(254);         (* its name on that node *)
    nTopicId : UINT;             (* its id on that node *)
    fDeadband : REAL;            (* sent again once it has moved this far; 0 = every change *)
    tPeriod : TIME;              (* sent at least this often, moved or not; T#0s = never *)
    bReliable : BOOL;            (* FALSE: newest wins (Live); TRUE: every change arrives *)
  END_VAR
  VAR_OUTPUT
    eQuality : E_BeeBusQuality;  (* Unknown before anything arrived, then Good, Uncertain, Bad *)
    bSeen : BOOL;                (* a value has arrived *)
    tAge : TIME;                 (* since the last value; T#0s before the first *)
    bNewValue : BOOL;            (* a value arrived since the last call *)
    nMissed : UDINT;             (* publishes that never arrived, running total *)
  END_VAR
END_METHOD

(* Owns every member of anyData as a topic, nTopicId + its position, named
   sPrefix + its path. Called every scan. bWritable: peers may write the
   members, taken here one per member a scan, oldest first. *)
METHOD PUBLIC PublishStruct : E_BeeBusResult
  VAR_INPUT
    anyData : ANY;               (* a STRUCT, or an ARRAY of STRUCTs or values *)
    nTopicId : UINT;             (* the first member's id *)
    sPrefix : STRING(16);        (* put before every member's name; names an ARRAY *)
    bWritable : BOOL;            (* peers may write the members *)
    tPulse : TIME;               (* bWritable: a BOOL written TRUE drops back after this; T#0s = kept *)
    tSettle : TIME;              (* bWritable: a write asking for a result is answered one scan and this after *)
  END_VAR
  VAR_OUTPUT
    nMembers : UINT;             (* members, and so topics *)
    bWritten : BOOL;             (* writes were taken by this call *)
    nWritten : UINT;             (* how many members (held) *)
    sWrittenName : STRING(64);   (* the first of them, 'set.hiMm' (held) *)
    nWrittenIndex : UINT;        (* its position from 1 (held) *)
    nWrittenBy : BYTE;           (* the node that wrote it (held) *)
    nLost : UDINT;               (* writes dropped, running total *)
  END_VAR
END_METHOD

(* Keeps every member of anyData up to date from nPeer's PublishStruct of the
   same type at nTopicId, sPrefix. Called every scan. eQuality is the worst
   member's. *)
METHOD PUBLIC SubscribeStruct : E_BeeBusResult
  VAR_INPUT
    anyData : ANY;               (* a STRUCT or ARRAY of the same type as the peer's *)
    nPeer : BYTE;                (* the node that owns the topics *)
    nTopicId : UINT;             (* the peer's nTopicId *)
    sPrefix : STRING(16);        (* the peer's sPrefix *)
    fDeadband : REAL;            (* sent again once it has moved this far; 0 = every change *)
    tPeriod : TIME;              (* every member at least this often; T#0s = never *)
    bReliable : BOOL;            (* FALSE: newest wins (Live); TRUE: every change arrives *)
  END_VAR
  VAR_OUTPUT
    nMembers : UINT;             (* members, and so topics *)
    eQuality : E_BeeBusQuality;  (* the worst member's *)
    bSeen : BOOL;                (* every member has arrived *)
    tOldest : TIME;              (* the oldest member's age *)
    nNewValues : UINT;           (* members that arrived since the last call *)
    sNewName : STRING(64);       (* the first of them (held) *)
    nNewIndex : UINT;            (* its position from 1 (held) *)
    nMissed : UDINT;             (* publishes that never arrived, every member, running total *)
  END_VAR
END_METHOD

(* Serves every member of anyData as a topic this node decides: a change a
   peer asks for is taken into the member here, the program runs with it,
   and the member is read back for the answer. Called every scan. *)
METHOD PUBLIC Serve : E_BeeBusResult
  VAR_INPUT
    anyData : ANY;               (* a STRUCT, or an ARRAY of STRUCTs or values *)
    nTopicId : UINT;             (* the first member's id *)
    sPrefix : STRING(16);        (* put before every member's name *)
    bWritable : BOOL;            (* peers may ask to change the members; FALSE: ReadOnly *)
    bCommand : BOOL;             (* every member is a command, taken once and answered Accepted *)
    tPulse : TIME;               (* a BOOL written TRUE drops back after this; T#0s = kept *)
    tSettle : TIME;              (* a change is answered one scan and this after *)
    nDepth : USINT;              (* each member held in a ring of this many while the network is away, 0..127 *)
  END_VAR
  VAR_OUTPUT
    nMembers : UINT;             (* members, and so topics *)
    bChanged : BOOL;             (* changes were taken by this call *)
    nChanged : UINT;             (* how many members (held) *)
    sChangedName : STRING(64);   (* the first of them (held) *)
    nChangedIndex : UINT;        (* its position from 1 (held) *)
    nChangedBy : BYTE;           (* the node that asked (held) *)
    nRefused : UDINT;            (* changes not kept as asked, running total *)
    nLost : UDINT;               (* changes dropped, running total *)
  END_VAR
END_METHOD

(* Binds every member of anyData to the one nPeer serves at nTopicId,
   sPrefix: the owner's values land in the members, and a member the program
   changes is asked of the owner. Called every scan. *)
METHOD PUBLIC Bind : E_BeeBusResult
  VAR_INPUT
    anyData : ANY;               (* a STRUCT or ARRAY declared the same as the owner's *)
    nPeer : BYTE;                (* the node that serves it *)
    nTopicId : UINT;             (* the owner's nTopicId *)
    sPrefix : STRING(16);        (* the owner's sPrefix *)
    bReliable : BOOL;            (* TRUE for settings: every change arrives; FALSE: newest wins *)
    fDeadband : REAL;            (* Live only: sent again once it has moved this far *)
  END_VAR
  VAR_OUTPUT
    nMembers : UINT;             (* members *)
    eBindState : E_BeeBusBindState;  (* the worst member's *)
    bInSync : BOOL;              (* every member holds the owner's value *)
    bPending : BOOL;             (* a change is with the owner *)
    bRefused : BOOL;             (* the owner kept another value for a member *)
    sRefusedName : STRING(64);   (* the first member refused (held) *)
    nRefusedIndex : UINT;        (* its position from 1 (held) *)
    bFailed : BOOL;              (* no decision came back for a change *)
    tOldest : TIME;              (* since the oldest member last had a value from the owner *)
    bNewValue : BOOL;            (* a value arrived from the owner since the last call *)
  END_VAR
END_METHOD

(* Writes anyValue into nPeer's writable topic nTopicId on a rising edge of
   bExecute. E_BeeBusResult.Queued while it waits for the acknowledgement or
   the owner's decision, then Ok or why not, until the next edge. *)
METHOD PUBLIC Write : E_BeeBusResult
  VAR_INPUT
    anyValue : ANY;              (* one value of the member's type *)
    nPeer : BYTE;                (* the node that owns the topic *)
    nTopicId : UINT;             (* the topic's id on that node *)
    bConfirmed : BOOL;           (* retried until acknowledged *)
    bWantResult : BOOL;          (* ask the owner what it did; makes it confirmed *)
    bExecute : BOOL;             (* rising edge writes *)
  END_VAR
  VAR_OUTPUT
    eOutcome : E_BeeBusOutcome;  (* bWantResult: the owner's decision; NoAnswer before one *)
    bAccepted : BOOL;            (* the decision was Accepted *)
    bRefused : BOOL;             (* the owner kept another value: Changed or Refused *)
    fKeptValue : LREAL;          (* the owner's value with the decision *)
  END_VAR
END_METHOD

(* Holds up to nDepth samples of this node's topic sName while there is
   nowhere to send them, sent oldest first when there is. Called every scan. *)
METHOD PUBLIC Buffer : E_BeeBusResult
  VAR_INPUT
    sName : STRING(254);         (* the topic, bound by Topic or Publish on this node *)
    nDepth : USINT;              (* samples to hold; 0 turns it off *)
  END_VAR
  VAR_OUTPUT
    nHeld : UINT;                (* samples waiting to go out *)
  END_VAR
END_METHOD

(* Puts anyData at Modbus addresses from nAddress in eTable, so peers can read
   and write it. Called every scan; the variable is the register. *)
METHOD PUBLIC ModbusMap : E_BeeBusResult
  VAR_INPUT
    anyData : ANY;               (* a value, a fixed-bounds array or a STRUCT *)
    eTable : E_BeeBusModbusTable;  (* Coil, HoldingRegister (default), DiscreteInput, InputRegister *)
    nAddress : UINT;             (* the first address *)
    eOnLoss : E_BeeBusModbusFailsafe;  (* HoldLastValue (default) or ResetToValue when the writer goes silent *)
    nSafeValue : DINT;           (* ResetToValue: the value, in the variable's own type *)
  END_VAR
  VAR_OUTPUT
    nCount : UINT;               (* addresses taken: registers, or coils *)
    bWritten : BOOL;             (* a peer wrote some since the last call *)
    sWrittenName : STRING(64);   (* the first member written (held) *)
    nWrittenIndex : UINT;        (* its position from 1 (held) *)
    nWrittenAddr : UINT;         (* its first address (held) *)
    nWritten : UINT;             (* members that write covered (held) *)
    bSafeApplied : BOOL;         (* the safe value was applied since the last call *)
  END_VAR
END_METHOD

(* Reads nPeer's addresses into anyData on a rising edge of bExecute, laid out
   as ModbusMap lays it out. E_BeeBusResult.Queued while it runs, then Ok or
   why not, until the next edge. *)
METHOD PUBLIC ModbusRead : E_BeeBusResult
  VAR_INPUT
    anyData : ANY;               (* a value, a fixed-bounds array or a STRUCT *)
    nPeer : BYTE;                (* the node to read from *)
    eTable : E_BeeBusModbusTable;  (* which of the peer's tables *)
    nAddress : UINT;             (* the first address on that node *)
    nLength : UINT;              (* values to read, each element and member one; 0 = all *)
    bExecute : BOOL;             (* rising edge reads *)
  END_VAR
END_METHOD

(* Writes anyData into nPeer's addresses on a rising edge of bExecute, the
   values as they were at the edge. E_BeeBusResult.Queued while a confirmed
   write waits, then Ok or why not, until the next edge. *)
METHOD PUBLIC ModbusWrite : E_BeeBusResult
  VAR_INPUT
    anyData : ANY;               (* a value, a fixed-bounds array or a STRUCT *)
    nPeer : BYTE;                (* the node to write to *)
    eTable : E_BeeBusModbusTable;  (* Coil or HoldingRegister *)
    nAddress : UINT;             (* the first address on that node *)
    nLength : UINT;              (* values to write, each element and member one; 0 = all *)
    bConfirmed : BOOL;           (* wait for the peer to acknowledge *)
    bExecute : BOOL;             (* rising edge writes *)
  END_VAR
END_METHOD

(* This node and its segment, measured. *)
METHOD PUBLIC Statistics : E_BeeBusResult
  VAR_OUTPUT
    nIdInUse : BYTE;             (* the address this node holds, as opened *)
    nMembers : BYTE;             (* nodes in the ring, this one included *)
    tRotation : TIME;            (* how long the token takes to come round; T#0s until it has *)
    nPendingOps : INT;           (* operations queued and not finished *)
    nCrcErrors : DINT;           (* frames that arrived corrupt *)
    nNoiseBytes : DINT;          (* bytes discarded hunting for a frame start *)
  END_VAR
END_METHOD

(* How nPeer is doing, from this node. *)
METHOD PUBLIC PeerStatus : E_BeeBusResult
  VAR_INPUT
    nPeer : BYTE;                (* the peer, 1..254 *)
  END_VAR
  VAR_OUTPUT
    bAlive : BOOL;               (* in the ring *)
    bSeen : BOOL;                (* heard at least once since the program started *)
    tSilent : TIME;              (* since it was last heard; T#0s before *)
    tHop : TIME;                 (* how long it takes to accept the token *)
    tHopTimeout : TIME;          (* what it is allowed before the token is presumed lost *)
  END_VAR
END_METHOD

#include <BeeBusAPI.h>
#include <atomic>
#include <new>

#if defined(BEEBUS_PLATFORM_HOST)
#include <transport/BeeBusHostSerialTransport.h>
#include <transport/BeeBusHostUdpTransport.h>
#endif

#if defined(BEEBUS_PLATFORM_ARDUINO)
#include <Arduino.h>

// WiFi is detected: it ships inside the ESP32 core, so its header is already
// on the include path and __has_include can answer honestly. BEEBUS_NO_WIFI
// forces it off for a board that has none.
#if !defined(BEEBUS_NO_WIFI) && defined(__has_include)
#if __has_include(<WiFi.h>)
#define BEEBUS_HAS_WIFI 1
#include <WiFi.h>
#include <WiFiUdp.h>
#endif
#endif

// Ethernet is opt-in, and cannot be detected the same way. arduino-cli finds a
// user library by compiling, failing on the missing header, and then searching
// for whatever provides it -- so the include has to be one the compiler will
// actually try. Behind __has_include there is no failure to react to, the path
// is never added, and the header stays invisible however installed it is.
//
// Add BEEBUS_ENABLE_ETHERNET to the project's build flags to use it.
#if defined(BEEBUS_ENABLE_ETHERNET)
#define BEEBUS_HAS_ETHERNET 1
#include <Ethernet.h>
#include <EthernetUdp.h>
#endif

#include <transport/BeeBusArduinoUdpTransport.h>

#if defined(BEEBUS_HAS_ETHERNET)
// Six hex bytes with any separator, into the array Ethernet.begin takes.
static bool bbParseMac(const char* text, uint8_t out[6])
{
  if (!text) return false;
  int byteIndex = 0;
  unsigned value = 0;
  int digits = 0;
  for (const char* p = text; ; p++) {
    const char c = *p;
    const bool separator = (c == ':' || c == '-' || c == '\0');
    if (separator) {
      if (digits == 0 || byteIndex > 5) return false;
      out[byteIndex++] = (uint8_t)value;
      value = 0;
      digits = 0;
      if (c == '\0') break;
      continue;
    }
    int nibble;
    if (c >= '0' && c <= '9') nibble = c - '0';
    else if (c >= 'a' && c <= 'f') nibble = c - 'a' + 10;
    else if (c >= 'A' && c <= 'F') nibble = c - 'A' + 10;
    else return false;
    if (++digits > 2) return false;
    value = (value << 4) | (unsigned)nibble;
  }
  return byteIndex == 6;
}
#endif

// The board's hardware serials, by the number the PORT pin gives. Not every
// board has all of them, which is why this is a switch and not an array. A
// number the board does not have is refused (nullptr), never quietly opened on
// UART0: on the ModBee Node UART0 is the HAT port, where a modem sits.
static HardwareSerial* bbSerialPort(uint8_t port)
{
  switch (port) {
    case 0:
#if defined(ARDUINO_ARCH_ESP32) && defined(ARDUINO_USB_CDC_ON_BOOT) && ARDUINO_USB_CDC_ON_BOOT
      // This core boots Serial as the USB CDC device rather than a UART, so it
      // is not a HardwareSerial at all. Serial0 is UART0 and is always declared.
      return &Serial0;
#else
      return &Serial;
#endif
#if defined(SERIAL_PORT_HARDWARE_OPEN) || defined(HAVE_HWSERIAL1) || defined(ARDUINO_ARCH_ESP32)
    case 1: return &Serial1;
#endif
#if defined(HAVE_HWSERIAL2) || defined(ARDUINO_ARCH_ESP32)
    case 2: return &Serial2;
#endif
    default: return nullptr;
  }
}
#endif

#include <string>
#include <vector>
#include <stdio.h>
#include <string.h>

// =============================================================================
// ONE TASK PER NODE
// =============================================================================
//
// OpenPLC runs every task on a thread of its own - on the Runtime, and on a
// board in RTOS mode - and the BeeBus library is single-threaded by design. A
// method called from another task would be inside the node while the node's
// own scan is. A lock is the wrong answer: a machine task waiting for the
// network task's scan is held back by it, and OpenPLC stops a PLC whose task
// overruns. So the node and its methods run in one task, and the machine's
// program trades values with them through globals. The block notes its task
// every scan; a method in another task does nothing and returns
// E_BeeBusResult.WrongTask - it never races, never waits.
//
// The task is 0 until the block's first scan: a method that runs before it,
// in the same scan, is let through.
#if defined(ESP_PLATFORM)
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
static strucpp::XWORD_t bb_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)xTaskGetCurrentTaskHandle();
}
#elif !defined(ARDUINO)
#include <pthread.h>
static strucpp::XWORD_t bb_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)pthread_self();
}
#else
// One task and nothing else: every call is in it.
static strucpp::XWORD_t bb_currentTask() { return 1; }
#endif

static bool bb_inTask(strucpp::XWORD_t owner) {
    return owner == 0 || owner == bb_currentTask();
}


// --- reading and writing a TIME pin --------------------------------------
//
// Every duration on every block is a TIME, so that T#500ms on one of these
// reads the same as T#500ms on a TON beside it. TIME is signed nanoseconds
// here and unsigned milliseconds in CODESYS, so nothing relies on a negative:
// below zero is treated as none at all. Rounded UP, because 0 means "the
// sensible default" on these pins and a value somebody set must not vanish.
int32_t bb_millisOf(const strucpp::IEC_TIME& t)
{
    const int64_t ns = t.get();
    if (ns <= 0) return 0;
    const int64_t ms = (ns + 999999LL) / 1000000LL;
    return ms > 2147483647LL ? 2147483647 : (int32_t)ms;
}

// And the way back, for an age or a hop time reported on a pin. A negative
// count - which here means "it has never happened" - comes out as T#0s,
// because TIME is unsigned in CODESYS and a pin showing a negative duration
// would be a lie about a type. The pin beside it says which zero it is:
// bSeen, or eQuality reading Unknown.
strucpp::IEC_TIME bb_timeOf(int32_t milliseconds)
{
    if (milliseconds <= 0) return strucpp::IEC_TIME((strucpp::TIME_t)0);
    return strucpp::IEC_TIME((strucpp::TIME_t)milliseconds * strucpp::NS_PER_MS);
}

// The wire type an IEC type class names, or BEEBUS_T_COUNT for one the wire
// does not carry. Defined here rather than in the protocol, which knows nothing
// about a toolchain.
uint8_t bb_wireTypeOfClass(uint32_t typeClass)
{
  switch (typeClass) {
    case strucpp::TYPE_CLASS::TYPE_BOOL:   return BEEBUS_T_BOOL;
    case strucpp::TYPE_CLASS::TYPE_SINT:   return BEEBUS_T_I8;
    case strucpp::TYPE_CLASS::TYPE_BYTE:
    case strucpp::TYPE_CLASS::TYPE_USINT:  return BEEBUS_T_U8;
    case strucpp::TYPE_CLASS::TYPE_INT:    return BEEBUS_T_I16;
    case strucpp::TYPE_CLASS::TYPE_WORD:
    case strucpp::TYPE_CLASS::TYPE_UINT:   return BEEBUS_T_U16;
    case strucpp::TYPE_CLASS::TYPE_DINT:   return BEEBUS_T_I32;
    case strucpp::TYPE_CLASS::TYPE_DWORD:
    case strucpp::TYPE_CLASS::TYPE_UDINT:  return BEEBUS_T_U32;
    case strucpp::TYPE_CLASS::TYPE_REAL:   return BEEBUS_T_F32;
    case strucpp::TYPE_CLASS::TYPE_STRING: return BEEBUS_T_STRING;
    // The 64-bit types, bound in place. LTIME is IEC 61131-3's signed 64-bit
    // count of nanoseconds (2013, table 10 note m), which is what it holds.
    case strucpp::TYPE_CLASS::TYPE_LINT:
    case strucpp::TYPE_CLASS::TYPE_LTIME:  return BEEBUS_T_I64;
    case strucpp::TYPE_CLASS::TYPE_LWORD:
    case strucpp::TYPE_CLASS::TYPE_ULINT:  return BEEBUS_T_U64;
    case strucpp::TYPE_CLASS::TYPE_LREAL:  return BEEBUS_T_F64;
    default: break;
  }
  return BEEBUS_T_COUNT;
}


// E_BEEBUSRESULT mirrors BeeBusResult member for member (Immediate is Ok), so
// a method casts rather than translates. A member added on one side without
// the other is a build error here, not a wrong reason on a panel; the order is
// checked by internal/check-enums.py.
static_assert((int)E_BEEBUSRESULT::BUFFERFULL + 1 == BEEBUS_RESULT_COUNT,
              "E_BEEBUSRESULT must mirror BeeBusResult member for member");
static_assert((int)E_BEEBUSRESULT::QUEUED == (int)BeeBusResult::Queued &&
              (int)E_BEEBUSRESULT::OK == (int)BeeBusResult::Immediate &&
              (int)E_BEEBUSRESULT::TIMEOUT == (int)BeeBusResult::Timeout &&
              (int)E_BEEBUSRESULT::BUFFERFULL == (int)BeeBusResult::BufferFull,
              "E_BEEBUSRESULT must mirror BeeBusResult member for member");
static_assert((int)E_BEEBUSQUALITY::BAD == (int)BeeBusQuality::Bad &&
              (int)E_BEEBUSBINDSTATE::FAILED == (int)BeeBusBindState::Failed &&
              (int)E_BEEBUSMODBUSTABLE::INPUTREGISTER == (int)MB_INPUT_REGISTER &&
              (int)E_BEEBUSOUTCOME::NOANSWER == BEEBUS_OUTCOME_COUNT,
              "the enumerations must mirror the library's");

// =============================================================================
// A VARIABLE AS A LIST OF VALUES - under every method that takes a STRUCT, an
// array or a single value on its anyData.
// =============================================================================
//
// A STRUCT arrives on an ANY pin as an address and a layout (TYPEDESC, which
// STruC++ emits beside every STRUCT type). The layout names each member, its
// offset and its type, nested STRUCTs and arrays included. Walking it gives a
// flat list of values in declaration order, and that list is the whole design:
//
//   - its ORDER is the register order and the topic order,
//   - each value's PATH ("hmi.systemMode", "spareReal[3]") is its name,
//   - each value's TYPE fixes its width on the wire.
//
// The list is held in "runs": a scalar member is a run of one, an array of a
// simple type is one run of all its elements, and an array of STRUCTs is
// unrolled element by element. A 1000-element WORD array is therefore one
// entry, not a thousand.
//
// Names number array elements by POSITION, counting from 1, whatever the
// declared bounds: the layout carries the element count but not the bounds.
// ARRAY[1..n], the usual declaration, reads exactly as declared.

#include <new>
#include <utility>

namespace {

// How a value reaches the wire when it is not already a wire type.
enum BbConv : uint8_t {
  BB_CONV_NONE = 0,   // bound in place
  BB_CONV_MS,         // TIME, TOD: nanoseconds <-> DINT milliseconds
  BB_CONV_DT,         // DT: nanoseconds since 1970 <-> UDINT seconds since 1970
  BB_CONV_DATE,       // DATE: days since 1970 <-> UDINT seconds since 1970
};

// A path is as long as this at most ("pumps[2].motor.fault"): one character
// past the longest topic name, so a path cut short here is always refused as a
// topic name too long, never carried cut. Only a diagnostic name shows it.
static const size_t BB_PATH_MAX = BEEBUS_TOPIC_NAME_MAX + 1;

struct BbRun {
  uint32_t path = 0;         // its path in BbPlan::paths, e.g. "hmi.systemMode"
  bool array = false;        // elements are named path[k], k from 1
  uint8_t* base = nullptr;   // the first element's payload
  uint32_t stride = 0;       // bytes from one element to the next
  uint32_t count = 1;        // elements
  uint32_t iecClass = 0;     // strucpp::TYPE_CLASS of an element
  uint8_t wire = 0;          // BEEBUS_T_*
  uint8_t conv = BB_CONV_NONE;
  uint16_t cap = 0;          // STRING(n): n
  uint16_t regsEach = 1;     // registers (or bits) one element takes
  uint32_t firstLeaf = 0;    // number of element 0 in the whole list, from 0
  uint32_t firstReg = 0;     // its register offset from nAddress
  // A converted type is bound to a copy in its wire type, held in the plan's
  // shadow array from here on. `synced` (after the shadows) is what each copy
  // held when it was last brought into line with the variable, so a change in
  // it that the program did not make is a peer's.
  uint32_t shadow = 0;
};

// Everything a plan holds is taken when it is built or bound, never while it
// serves: the runs and their paths in one pass over the layout once they are
// counted, the topic names and counters when the topics are bound, the peer
// buffers on the first read or write.
struct BbPlan {
  BbRun* runs = nullptr;
  uint32_t runCount = 0;
  char* paths = nullptr;     // every run's path, NUL separated; "" is the root
  int32_t* shadows = nullptr;   // converted copies, then their synced values
  uint32_t shadowCount = 0;
  uint32_t leaves = 0;       // values in the list
  uint32_t regs = 0;         // registers (or bits) they take
  uint8_t* root = nullptr;   // the variable's address when the plan was made
  const char* rootName = "VALUE";   // the variable's own name, for a single value
  bool rootArray = false;           // anyData is an ARRAY: topics named from "[i]" on
  bool bits = false;         // laid out for a coil or discrete-input table

  // Registers this node holds (ModbusMap)
  bool bound = false;
  BeeBusRegisterType table = MB_HOLDING_REGISTER;
  uint16_t address = 0;
  uint32_t since = 0;        // registerWritesSince cursor

  // Topics (PublishStruct, SubscribeStruct)
  bool topics = false;
  bool remote = false;
  uint8_t peer = 0;
  uint16_t topicId = 0;
  char* names = nullptr;     // every value's name, NUL separated, never moved
  uint8_t* state = nullptr;  // per value: BB_ISSUED, BB_ARRIVED
  uint16_t* seen = nullptr;  // per value: received, then missed

  // A peer's registers, read or written (ModbusRead, ModbusWrite)
  int16_t* regBuf = nullptr;
  uint8_t* bitBuf = nullptr; // bool-sized, so a bool* can walk it
  uint32_t ioLeaves = 0;     // values the outstanding request covers

  // Writes taken from the node's queue (PublishStruct bWritable)
  void* wq = nullptr;        // the node's BbWq
  uint16_t wqRange = 0;      // this STRUCT's place in it
  // Momentary commands waiting to drop back to FALSE: room for every BOOL
  // member, taken when the writes are queued.
  uint32_t* pulseLeaf = nullptr;
  uint32_t* pulseAt = nullptr;
  uint32_t pulseCap = 0;
  uint32_t pulses = 0;
  // Writes taken this scan, told to the node once the queue's lock is let go
  // (topicApplied), so a write that asked for a result is read back. Room for
  // every member, taken when the writes are queued.
  uint16_t* appliedIds = nullptr;
  uint8_t* appliedCmd = nullptr;
  uint16_t settleMs = 0;     // the read-back's delay after the next scan
  bool command = false;      // every member is a command: answered once taken

  // Binds (Bind): the bound members' last states
  bool binds = false;

  ~BbPlan() {
    delete[] runs;
    delete[] paths;
    delete[] shadows;
    delete[] names;
    delete[] state;
    delete[] seen;
    delete[] regBuf;
    delete[] bitBuf;
    delete[] pulseLeaf;
    delete[] pulseAt;
    delete[] appliedIds;
    delete[] appliedCmd;
  }
};

enum : uint8_t { BB_ISSUED = 0x01, BB_ARRIVED = 0x02 };

const char* bbClassName(uint32_t cls)
{
  switch (cls) {
    case strucpp::TYPE_CLASS::TYPE_WSTRING: return "WSTRING";
    case strucpp::TYPE_CLASS::TYPE_POINTER: return "a POINTER";
    case strucpp::TYPE_CLASS::TYPE_REFERENCE: return "a REFERENCE";
    case strucpp::TYPE_CLASS::TYPE_ARRAY: return "an array of arrays";
    default: return "a type";
  }
}

// The wire type a value of this class travels as, and how it is converted.
bool bbLeafType(uint32_t cls, uint32_t bytes, uint8_t& wire, uint8_t& conv)
{
  conv = BB_CONV_NONE;
  switch (cls) {
    case strucpp::TYPE_CLASS::TYPE_BOOL:   wire = BEEBUS_T_BOOL; return true;
    case strucpp::TYPE_CLASS::TYPE_SINT:   wire = BEEBUS_T_I8;   return true;
    case strucpp::TYPE_CLASS::TYPE_BYTE:
    case strucpp::TYPE_CLASS::TYPE_USINT:  wire = BEEBUS_T_U8;   return true;
    case strucpp::TYPE_CLASS::TYPE_INT:    wire = BEEBUS_T_I16;  return true;
    case strucpp::TYPE_CLASS::TYPE_WORD:
    case strucpp::TYPE_CLASS::TYPE_UINT:   wire = BEEBUS_T_U16;  return true;
    case strucpp::TYPE_CLASS::TYPE_DINT:   wire = BEEBUS_T_I32;  return true;
    case strucpp::TYPE_CLASS::TYPE_DWORD:
    case strucpp::TYPE_CLASS::TYPE_UDINT:  wire = BEEBUS_T_U32;  return true;
    case strucpp::TYPE_CLASS::TYPE_REAL:   wire = BEEBUS_T_F32;  return true;
    case strucpp::TYPE_CLASS::TYPE_STRING: wire = BEEBUS_T_STRING; return true;
    case strucpp::TYPE_CLASS::TYPE_LINT:   wire = BEEBUS_T_I64;  return true;
    case strucpp::TYPE_CLASS::TYPE_LWORD:
    case strucpp::TYPE_CLASS::TYPE_ULINT:  wire = BEEBUS_T_U64;  return true;
    case strucpp::TYPE_CLASS::TYPE_LREAL:  wire = BEEBUS_T_F64;  return true;
    // IEC 61131-3 (2013, table 10 note m): a signed 64-bit count of
    // nanoseconds, which is what STruC++ stores, so it is bound in place.
    case strucpp::TYPE_CLASS::TYPE_LTIME:  wire = BEEBUS_T_I64;  return true;
    case strucpp::TYPE_CLASS::TYPE_TIME:
    case strucpp::TYPE_CLASS::TYPE_TIMEOFDAY:
      wire = BEEBUS_T_I32; conv = BB_CONV_MS; return true;
    case strucpp::TYPE_CLASS::TYPE_DATEANDTIME:
      wire = BEEBUS_T_U32; conv = BB_CONV_DT; return true;
    case strucpp::TYPE_CLASS::TYPE_DATE:
      wire = BEEBUS_T_U32; conv = BB_CONV_DATE; return true;
    case strucpp::TYPE_CLASS::TYPE_ENUM:
      // An enumeration travels as the integer it is stored as.
      if (bytes == 1) { wire = BEEBUS_T_I8;  return true; }
      if (bytes == 2) { wire = BEEBUS_T_I16; return true; }
      if (bytes == 4) { wire = BEEBUS_T_I32; return true; }
      if (bytes == 8) { wire = BEEBUS_T_I64; return true; }
      return false;
    default:
      return false;
  }
}

// The path being walked, one segment per level, and what the walk produces.
// The layout is walked twice: once to count the runs and the bytes their paths
// need (and to find any member that cannot be carried), then to fill storage
// taken once.
struct BbWalk {
  BbPlan& p;
  bool fill;                 // the second pass
  char path[BB_PATH_MAX];
  size_t len = 0;
  uint32_t runs = 0;
  uint32_t pathBytes = 0;
  uint32_t shadows = 0;
  char* err;
  size_t errCap;
  BbWalk(BbPlan& plan, bool second, char* e, size_t cap)
      : p(plan), fill(second), err(e), errCap(cap) { path[0] = '\0'; }

  // Appends text to the path; returns where it was, to put back.
  size_t push(const char* text) {
    const size_t mark = len;
    const int n = snprintf(path + len, sizeof(path) - len, "%s", text);
    if (n > 0) len = (len + (size_t)n < sizeof(path)) ? len + (size_t)n : sizeof(path) - 1;
    return mark;
  }
  size_t pushIndex(uint32_t position) {
    char index[16];
    snprintf(index, sizeof(index), "[%lu]", (unsigned long)position);
    return push(index);
  }
  void pop(size_t mark) { len = mark; path[len] = '\0'; }
  // The name to show for the path walked so far.
  const char* shown() const { return len ? path : p.rootName; }
};

// A path that ends in "." while a STRUCT is being entered.
bool bbAddRun(BbWalk& w, bool array, uint8_t* base, uint32_t stride, uint32_t count,
              uint32_t cls, uint32_t bytes, uint16_t cap)
{
  BbPlan& p = w.p;
  uint8_t wire = 0, conv = BB_CONV_NONE;
  if (!bbLeafType(cls, bytes, wire, conv)) {
    snprintf(w.err, w.errCap, "%s is %s, which BeeBus does not carry", w.shown(),
             bbClassName(cls));
    return false;
  }
  if (p.bits && wire != BEEBUS_T_BOOL) {
    snprintf(w.err, w.errCap, "%s is not a BOOL; a coil or input table holds BOOLs only",
             w.shown());
    return false;
  }
  uint16_t regsEach;
  if (wire == BEEBUS_T_STRING) {
    if (cap == 0) {
      snprintf(w.err, w.errCap, "%s: an ARRAY OF STRING needs a STRUCT around it", w.shown());
      return false;
    }
    regsEach = (uint16_t)(cap / 2 + 1);   // n characters and the terminator
  } else {
    regsEach = p.bits ? 1 : bb_registersOf(wire);
  }

  if (w.fill) {
    BbRun& r = p.runs[w.runs];
    r.path = w.pathBytes;
    memcpy(p.paths + w.pathBytes, w.path, w.len + 1);
    r.array = array;
    r.base = base;
    r.stride = stride;
    r.count = count;
    r.iecClass = cls;
    r.wire = wire;
    r.conv = conv;
    r.cap = cap;
    r.regsEach = regsEach;
    r.firstLeaf = p.leaves;
    r.firstReg = p.regs;
    r.shadow = w.shadows;
  }
  w.runs++;
  w.pathBytes += (uint32_t)w.len + 1;
  if (conv != BB_CONV_NONE) w.shadows += count;
  p.leaves += count;
  p.regs += count * regsEach;
  return true;
}

bool bbWalkStruct(BbWalk& w, const strucpp::TypeDesc* d, uint8_t* base, int depth)
{
  if (!d) {
    snprintf(w.err, w.errCap, "%s: no layout for this STRUCT", w.shown());
    return false;
  }
  if (depth > 8) {
    snprintf(w.err, w.errCap, "%s: STRUCTs nested deeper than 8", w.path);
    return false;
  }
  for (uint16_t i = 0; i < d->MEMBERCOUNT; i++) {
    const strucpp::MemberDesc& m = d->MEMBERS[i];
    const size_t mark = w.push(m.NAME ? m.NAME : "?");
    uint8_t* at = base + m.BYTEOFFSET;
    bool ok;

    if (m.TYPECLASS == strucpp::TYPE_CLASS::TYPE_USERDEF) {
      const size_t dot = w.push(".");
      ok = bbWalkStruct(w, m.NESTED, at, depth + 1);
      w.pop(dot);
    } else if (m.TYPECLASS == strucpp::TYPE_CLASS::TYPE_ARRAY) {
      if (m.BASETYPECLASS == strucpp::TYPE_CLASS::TYPE_USERDEF) {
        ok = true;
        for (uint32_t e = 0; ok && e < m.NUMELEMENTS; e++) {
          const size_t element = w.pushIndex(e + 1);
          w.push(".");
          ok = bbWalkStruct(w, m.NESTED, at + (size_t)e * m.STRIDE, depth + 1);
          w.pop(element);
        }
      } else {
        ok = bbAddRun(w, true, at, m.STRIDE, m.NUMELEMENTS, m.BASETYPECLASS,
                      m.ELEMBITSIZE / 8, m.CAP);
      }
    } else {
      ok = bbAddRun(w, false, at, m.STRIDE, 1, m.TYPECLASS, m.BITSIZE / 8, m.CAP);
    }
    w.pop(mark);
    if (!ok) return false;
  }
  return true;
}

// One pass over whatever is on anyData.
bool bbWalkValue(BbWalk& w, const strucpp::IEC_ANY& v)
{
  if (v.TYPECLASS == strucpp::TYPE_CLASS::TYPE_USERDEF) {
    return bbWalkStruct(w, v.TYPEDESC, v.PVALUE, 0);
  }
  if (v.TYPECLASS == strucpp::TYPE_CLASS::TYPE_ARRAY) {
    if (v.ELEMCLASS == strucpp::TYPE_CLASS::TYPE_USERDEF) {
      for (int32_t e = 0; e < v.DICOUNT; e++) {
        const size_t mark = w.push(w.p.rootName);
        w.pushIndex((uint32_t)e + 1);
        w.push(".");
        const bool ok = bbWalkStruct(w, v.TYPEDESC, v.PVALUE + (size_t)e * (size_t)v.DISTRIDE, 0);
        w.pop(mark);
        if (!ok) return false;
      }
      return true;
    }
    const uint32_t bytes = (uint32_t)(v.DISIZE / v.DICOUNT);
    return bbAddRun(w, true, v.PVALUE, (uint32_t)v.DISTRIDE, (uint32_t)v.DICOUNT,
                    v.ELEMCLASS, bytes, 0);
  }
  // A STRING's DISIZE is its buffer, the capacity and the terminator.
  const uint16_t cap = (v.TYPECLASS == strucpp::TYPE_CLASS::TYPE_STRING && v.DISIZE > 1)
      ? (uint16_t)(v.DISIZE - 1) : 0;
  return bbAddRun(w, false, v.PVALUE, (uint32_t)v.DISTRIDE, 1, v.TYPECLASS,
                  (uint32_t)v.DISIZE, cap);
}

BbRun* bbRunOf(BbPlan& p, uint32_t leaf, uint32_t& element)
{
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    if (leaf >= r.firstLeaf && leaf < r.firstLeaf + r.count) {
      element = leaf - r.firstLeaf;
      return &r;
    }
  }
  return nullptr;
}

// A value's name, written into `out`: its path, numbered from 1 in an array.
// As a topic (`topic`), an anyData that is itself an ARRAY is named from the
// element on - "[3].set.delay", "[3]" - without the variable's own name:
// sPrefix names the array, so the subscriber's variable need not be spelled as
// the owner's. Registers keep the variable's name, which only diagnostics show.
void bbLeafName(const BbPlan& p, const BbRun& r, uint32_t element, const char* prefix,
                bool topic, char* out, size_t cap)
{
  if (!out || cap == 0) return;
  const char* path = p.paths[r.path] ? p.paths + r.path : p.rootName;
  if (topic && p.rootArray) {
    const size_t root = strlen(p.rootName);
    if (strncmp(path, p.rootName, root) == 0) path += root;
  }
  if (r.array) {
    snprintf(out, cap, "%s%s[%lu]", prefix ? prefix : "", path, (unsigned long)(element + 1));
  } else {
    snprintf(out, cap, "%s%s", prefix ? prefix : "", path);
  }
}

uint8_t* bbElem(const BbRun& r, uint32_t e) { return r.base + (size_t)e * r.stride; }

int32_t& bbShadow(BbPlan& p, const BbRun& r, uint32_t e) { return p.shadows[r.shadow + e]; }
int32_t& bbSynced(BbPlan& p, const BbRun& r, uint32_t e)
{
  return p.shadows[p.shadowCount + r.shadow + e];
}

// The variable's value in its wire form, for a converted type.
int32_t bbToWire(const BbRun& r, uint32_t e)
{
  int64_t v;
  memcpy(&v, bbElem(r, e), 8);
  switch (r.conv) {
    case BB_CONV_MS: {
      // Rounded to the nearest millisecond and held inside a DINT.
      const int64_t ms = v >= 0 ? (v + 500000LL) / 1000000LL : -((-v + 500000LL) / 1000000LL);
      if (ms > 2147483647LL) return 2147483647;
      if (ms < -2147483647LL - 1) return (int32_t)(-2147483647LL - 1);
      return (int32_t)ms;
    }
    case BB_CONV_DT: {
      const int64_t s = v / 1000000000LL;
      return (int32_t)(uint32_t)(s < 0 ? 0 : (s > 0xFFFFFFFFLL ? 0xFFFFFFFFLL : s));
    }
    case BB_CONV_DATE: {
      const int64_t s = v * 86400LL;
      return (int32_t)(uint32_t)(s < 0 ? 0 : (s > 0xFFFFFFFFLL ? 0xFFFFFFFFLL : s));
    }
  }
  return 0;
}

void bbFromWire(const BbRun& r, uint32_t e, int32_t wire)
{
  int64_t v = 0;
  switch (r.conv) {
    case BB_CONV_MS:   v = (int64_t)wire * 1000000LL; break;
    case BB_CONV_DT:   v = (int64_t)(uint32_t)wire * 1000000000LL; break;
    case BB_CONV_DATE: v = (int64_t)((uint32_t)wire / 86400u); break;
    default: return;
  }
  memcpy(bbElem(r, e), &v, 8);
}

// Brings each converted copy into line with its variable. `peerWins`: a copy
// that moved since the last sync was written by a peer, and is taken into
// the variable; otherwise the variable is the truth and the copy follows.
void bbSyncShadows(BbPlan& p, bool peerWins)
{
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    if (r.conv == BB_CONV_NONE) continue;
    for (uint32_t e = 0; e < r.count; e++) {
      int32_t& shadow = bbShadow(p, r, e);
      int32_t& synced = bbSynced(p, r, e);
      if (peerWins && shadow != synced) {
        bbFromWire(r, e, shadow);
      } else {
        shadow = bbToWire(r, e);
      }
      synced = shadow;
    }
  }
}

void* bbBindingOf(BbPlan& p, BbRun& r, uint32_t e)
{
  if (r.conv != BB_CONV_NONE) return (void*)&bbShadow(p, r, e);
  return (void*)bbElem(r, e);
}

// One value's register image, written into `out` (r.regsEach registers).
void bbEncode(BbPlan& p, BbRun& r, uint32_t e, int16_t* out)
{
  if (r.wire == BEEBUS_T_STRING) {
    const char* text = (const char*)bbElem(r, e);
    const uint32_t bytes = (uint32_t)r.regsEach * 2;
    for (uint32_t k = 0; k < bytes; k += 2) {
      // The buffer is cap + 1 bytes and NUL terminated; nothing past the
      // terminator is sent, so a shorter text leaves no tail of a longer one.
      const uint8_t hi = (k < r.cap) ? (uint8_t)text[k] : 0;
      const uint8_t lo = (k + 1 < r.cap) ? (uint8_t)text[k + 1] : 0;
      out[k / 2] = (int16_t)(((uint16_t)hi << 8) | lo);
    }
    // Stop at the terminator.
    bool ended = false;
    for (uint32_t k = 0; k < bytes; k++) {
      uint16_t reg = (uint16_t)out[k / 2];
      uint8_t ch = (k % 2 == 0) ? (uint8_t)(reg >> 8) : (uint8_t)(reg & 0xFF);
      if (ch == 0) ended = true;
      if (ended) {
        reg = (k % 2 == 0) ? (uint16_t)(reg & 0x00FF) : (uint16_t)(reg & 0xFF00);
        out[k / 2] = (int16_t)reg;
      }
    }
    return;
  }
  if (r.conv != BB_CONV_NONE) bbShadow(p, r, e) = bbToWire(r, e);
  const void* v = bbBindingOf(p, r, e);
  for (uint16_t w = 0; w < r.regsEach; w++) {
    out[w] = (int16_t)bb_valueRegister(v, r.wire, (uint8_t)w);
  }
}

// The way back. False if a register holds a number the type cannot.
bool bbDecode(BbPlan& p, BbRun& r, uint32_t e, const int16_t* in)
{
  if (r.wire == BEEBUS_T_STRING) {
    char* text = (char*)bbElem(r, e);
    uint32_t k = 0;
    for (; k < r.cap; k++) {
      const uint16_t reg = (uint16_t)in[k / 2];
      const char ch = (char)((k % 2 == 0) ? (reg >> 8) : (reg & 0xFF));
      text[k] = ch;
      if (ch == '\0') break;
    }
    if (k >= r.cap) text[r.cap] = '\0';
    return true;
  }
  void* v = bbBindingOf(p, r, e);
  // Built in a scratch copy and stored only once every register fits, so a
  // refused value is left whole.
  const size_t width = bb_topicTypeSize(r.wire);
  uint8_t scratch[8];
  memcpy(scratch, v, width);
  for (uint16_t w = 0; w < r.regsEach; w++) {
    if (!bb_setValueRegister(scratch, r.wire, (uint8_t)w, (uint16_t)in[w], nullptr)) return false;
  }
  memcpy(v, scratch, width);
  if (r.conv != BB_CONV_NONE) {
    bbFromWire(r, e, bbShadow(p, r, e));
    bbSynced(p, r, e) = bbShadow(p, r, e);
  }
  return true;
}

int bbQualityRank(uint8_t q)
{
  switch ((BeeBusQuality)q) {
    case BeeBusQuality::Good:      return 0;
    case BeeBusQuality::Unknown:   return 1;
    case BeeBusQuality::Uncertain: return 2;
    case BeeBusQuality::Bad:       return 3;
  }
  return 3;
}

// The peer buffers, taken on the first read or write at the plan's full size.
bool bbPeerBuffers(BbPlan& p, bool bits)
{
  if (bits && !p.bitBuf) p.bitBuf = new (std::nothrow) uint8_t[p.regs ? p.regs : 1];
  if (!bits && !p.regBuf) p.regBuf = new (std::nothrow) int16_t[p.regs ? p.regs : 1];
  return bits ? p.bitBuf != nullptr : p.regBuf != nullptr;
}

}  // namespace

// ---- The functions the blocks call --------------------------------------

// Builds the list for whatever is on anyData. nullptr, with the reason in
// `err`, for a variable that cannot be carried: the whole variable is refused
// rather than the member skipped, because a missing member would move every
// address and topic id after it.
void* bb_planBuild(const strucpp::IEC_ANY& v, bool bits, char* err, size_t errCap)
{
  BbPlan* p = new (std::nothrow) BbPlan();
  if (!p) {
    snprintf(err, errCap, "no memory for the list");
    return nullptr;
  }
  p->bits = bits;
  p->root = v.PVALUE;
  p->rootName = v.NAME ? v.NAME : "VALUE";
  p->rootArray = v.TYPECLASS == strucpp::TYPE_CLASS::TYPE_ARRAY;

  if (!v.PVALUE || v.DICOUNT <= 0) {
    snprintf(err, errCap, "anyData is not wired");
    delete p;
    return nullptr;
  }

  // Counted first, so the runs, their paths and the copies are taken once.
  BbWalk count(*p, false, err, errCap);
  if (!bbWalkValue(count, v)) {
    delete p;
    return nullptr;
  }
  if (p->leaves == 0) {
    snprintf(err, errCap, "%s has no members", p->rootName);
    delete p;
    return nullptr;
  }
  p->runs = new (std::nothrow) BbRun[count.runs];
  p->paths = new (std::nothrow) char[count.pathBytes ? count.pathBytes : 1];
  p->shadowCount = count.shadows;
  p->shadows = count.shadows ? new (std::nothrow) int32_t[2 * count.shadows]() : nullptr;
  if (!p->runs || !p->paths || (count.shadows && !p->shadows)) {
    snprintf(err, errCap, "no memory for the list");
    delete p;
    return nullptr;
  }
  p->runCount = count.runs;
  p->leaves = 0;
  p->regs = 0;
  BbWalk fill(*p, true, err, errCap);
  bbWalkValue(fill, v);

  bbSyncShadows(*p, false);
  return p;
}

uint32_t bb_planLeaves(void* plan) { return plan ? ((BbPlan*)plan)->leaves : 0; }
uint32_t bb_planRegisters(void* plan) { return plan ? ((BbPlan*)plan)->regs : 0; }
bool bb_planMoved(void* plan, const strucpp::IEC_ANY& v)
{
  return plan && ((BbPlan*)plan)->root != v.PVALUE;
}

// A value's name and its register offset, by its number in the list (from 0).
bool bb_planLeafInfo(void* plan, uint32_t leaf, char* name, size_t cap, uint32_t* regOffset)
{
  if (!plan) return false;
  BbPlan& p = *(BbPlan*)plan;
  uint32_t e = 0;
  BbRun* r = bbRunOf(p, leaf, e);
  if (!r) return false;
  bbLeafName(p, *r, e, "", p.topics, name, cap);
  if (regOffset) *regOffset = r->firstReg + e * r->regsEach;
  return true;
}

// The value whose registers include this offset from nAddress, from 0.
bool bb_planLeafAt(void* plan, uint32_t regOffset, uint32_t* leaf)
{
  if (!plan) return false;
  BbPlan& p = *(BbPlan*)plan;
  for (uint32_t i = 0; i < p.runCount; i++) {
    const BbRun& r = p.runs[i];
    const uint32_t span = r.count * r.regsEach;
    if (regOffset >= r.firstReg && regOffset < r.firstReg + span) {
      *leaf = r.firstLeaf + (regOffset - r.firstReg) / r.regsEach;
      return true;
    }
  }
  return false;
}

// A single number (not a string, not a list), and its wire type: the one case
// with a safe value to state.
bool bb_planSingle(void* plan, uint8_t* wire)
{
  if (!plan) return false;
  BbPlan& p = *(BbPlan*)plan;
  if (p.leaves != 1 || p.runCount != 1 || p.runs[0].wire == BEEBUS_T_STRING) return false;
  if (wire) *wire = p.runs[0].wire;
  return true;
}

// ---- Registers this node holds (ModbusMap) ----

bool bb_planBindRegisters(void* plan, BeeBusAPI* node, BeeBusRegisterType table,
                          uint16_t address, char* err, size_t errCap)
{
  BbPlan& p = *(BbPlan*)plan;
  if ((uint32_t)address + p.regs > 0x10000u) {
    snprintf(err, errCap, "the registers would run past address 65535");
    return false;
  }
  bbSyncShadows(p, false);
  uint32_t done = 0;   // leaves bound, for an undo
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++) {
      const uint16_t at = (uint16_t)(address + r.firstReg + e * r.regsEach);
      bool ok;
      if (r.wire == BEEBUS_T_STRING) {
        // The buffer is cap + 1 bytes: n characters and the terminator.
        char* text = (char*)bbElem(r, e);
        ok = (table == MB_HOLDING_REGISTER)
            ? node->addString(at, text, (uint16_t)(r.cap + 1))
            : (table == MB_INPUT_REGISTER)
                ? node->addInputString(at, text, (uint16_t)(r.cap + 1))
                : false;
      } else {
        ok = node->addRegister(table, at, bbBindingOf(p, r, e), r.wire);
      }
      if (!ok) {
        // Undo what was bound, so a refused STRUCT leaves nothing behind.
        uint32_t left = done;
        for (uint32_t j = 0; j <= i && left > 0; j++) {
          BbRun& u = p.runs[j];
          for (uint32_t f = 0; f < u.count && left > 0; f++, left--) {
            const uint16_t back = (uint16_t)(address + u.firstReg + f * u.regsEach);
            if (u.wire == BEEBUS_T_STRING) {
              if (table == MB_HOLDING_REGISTER) node->removeString(back);
              else node->removeInputString(back);
            } else {
              node->removeRegister(table, back);
            }
          }
        }
        char leafName[BB_PATH_MAX];
        bbLeafName(p, r, e, "", false, leafName, sizeof(leafName));
        snprintf(err, errCap, "address %u (%s) is already taken", (unsigned)at, leafName);
        return false;
      }
      done++;
    }
  }
  p.bound = true;
  p.table = table;
  p.address = address;
  p.since = 0;
  node->registerWritesSince(table, address, (uint16_t)(p.regs > 0xFFFF ? 0xFFFF : p.regs), p.since);
  return true;
}

// Once a scan: takes what peers wrote into converted values, and brings the
// rest of the copies up to date. Returns how many values peers wrote since the
// last call, and the first of them (by number from 0) in `firstLeaf`.
uint16_t bb_planServe(void* plan, BeeBusAPI* node, uint32_t* firstLeaf)
{
  BbPlan& p = *(BbPlan*)plan;
  bbSyncShadows(p, bb_tableIsWritable(p.table));
  uint16_t first = 0;
  const uint16_t written = node->registerWritesSince(
      p.table, p.address, (uint16_t)(p.regs > 0xFFFF ? 0xFFFF : p.regs), p.since, &first);
  if (written > 0 && firstLeaf) {
    uint32_t leaf = 0;
    if (bb_planLeafAt(plan, (uint32_t)(uint16_t)(first - p.address), &leaf)) *firstLeaf = leaf;
  }
  return written;
}

// ---- A peer's registers (ModbusRead / ModbusWrite) ----

// Registers covering the first `leaves` values (all of them for 0), or 0 if
// that is more than were passed.
uint32_t bb_planRegsFor(void* plan, uint32_t leaves)
{
  BbPlan& p = *(BbPlan*)plan;
  if (leaves == 0 || leaves == p.leaves) return p.regs;
  if (leaves > p.leaves) return 0;
  uint32_t e = 0;
  BbRun* r = bbRunOf(p, leaves, e);
  return r ? r->firstReg + e * r->regsEach : 0;
}

BeeBusResult bb_planWritePeer(void* plan, BeeBusAPI* node, uint8_t peer,
                              BeeBusRegisterType table, uint16_t address,
                              uint32_t leaves, BeeBusDelivery delivery)
{
  BbPlan& p = *(BbPlan*)plan;
  if (leaves == 0) leaves = p.leaves;
  const uint32_t regs = bb_planRegsFor(plan, leaves);
  if (regs == 0 || regs > 0xFFFF) return BeeBusResult::InvalidArgument;

  if (bb_tableIsBits(table)) {
    if (!bbPeerBuffers(p, true)) return BeeBusResult::QueueFull;
    memset(p.bitBuf, 0, regs);
    uint32_t k = 0;
    for (uint32_t i = 0; i < p.runCount && k < regs; i++) {
      BbRun& r = p.runs[i];
      for (uint32_t e = 0; e < r.count && k < regs; e++, k++) {
        p.bitBuf[k] = (*(const bool*)bbElem(r, e)) ? 1 : 0;
      }
    }
    return node->writeCoilManual(peer, address, (const bool*)p.bitBuf, (uint16_t)regs,
                                 delivery, (uint16_t)sizeof(uint8_t));
  }

  if (!bbPeerBuffers(p, false)) return BeeBusResult::QueueFull;
  memset(p.regBuf, 0, regs * sizeof(int16_t));
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++) {
      const uint32_t at = r.firstReg + e * r.regsEach;
      if (at + r.regsEach > regs) break;
      bbEncode(p, r, e, &p.regBuf[at]);
    }
  }
  return node->writeHregManual(peer, address, p.regBuf, (uint16_t)regs, delivery,
                               (uint16_t)sizeof(int16_t));
}

BeeBusResult bb_planReadPeer(void* plan, BeeBusAPI* node, uint8_t peer,
                             BeeBusRegisterType table, uint16_t address, uint32_t leaves)
{
  BbPlan& p = *(BbPlan*)plan;
  if (leaves == 0) leaves = p.leaves;
  const uint32_t regs = bb_planRegsFor(plan, leaves);
  if (regs == 0 || regs > 0xFFFF) return BeeBusResult::InvalidArgument;
  p.ioLeaves = leaves;
  if (bb_tableIsBits(table)) {
    if (!bbPeerBuffers(p, true)) return BeeBusResult::QueueFull;
    memset(p.bitBuf, 0, regs);
    bool* into = (bool*)p.bitBuf;
    return (table == MB_OUTPUT_COIL)
        ? node->readCoilManual(peer, address, into, (uint16_t)regs, 0, (uint16_t)sizeof(uint8_t))
        : node->readIstsManual(peer, address, into, (uint16_t)regs, 0, (uint16_t)sizeof(uint8_t));
  }
  if (!bbPeerBuffers(p, false)) return BeeBusResult::QueueFull;
  memset(p.regBuf, 0, regs * sizeof(int16_t));
  return (table == MB_HOLDING_REGISTER)
      ? node->readHregManual(peer, address, p.regBuf, (uint16_t)regs, 0, (uint16_t)sizeof(int16_t))
      : node->readIregManual(peer, address, p.regBuf, (uint16_t)regs, 0, (uint16_t)sizeof(int16_t));
}

// Unpacks a finished read into the variable. False if a register held a number
// a member's type cannot (that member is left as it was).
bool bb_planReadDone(void* plan, bool bits)
{
  BbPlan& p = *(BbPlan*)plan;
  if ((bits && !p.bitBuf) || (!bits && !p.regBuf)) return false;
  bool allOk = true;
  uint32_t k = 0;
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++, k++) {
      if (k >= p.ioLeaves) return allOk;
      if (bits) {
        *(bool*)bbElem(r, e) = p.bitBuf[r.firstReg + e] != 0;
      } else if (!bbDecode(p, r, e, &p.regBuf[r.firstReg + e * r.regsEach])) {
        allOk = false;
      }
    }
  }
  return allOk;
}

// ---- Topics (PublishStruct, SubscribeStruct) ----

// Binds every value as a topic: this node's own (`remote` false) or `peer`'s.
// Names are sPrefix + path, ids nTopicId + the value's number from 0. A STRING
// member is bound to its own buffer, n characters and the terminator.
// writable (owner only): peers may write the members (PublishStruct bWritable).
bool bb_planBindTopicsEx(void* plan, BeeBusAPI* node, bool remote, uint8_t peer,
                         uint16_t topicId, const char* prefix, bool writable,
                         char* err, size_t errCap)
{
  BbPlan& p = *(BbPlan*)plan;
  const char* pre = prefix ? prefix : "";

  if (topicId < BEEBUS_TOPIC_ID_MIN ||
      (uint32_t)topicId + p.leaves - 1 > (uint32_t)BEEBUS_TOPIC_ID_MAX) {
    snprintf(err, errCap, "nTopicId + members runs past 32767, or nTopicId is 0");
    return false;
  }

  // Every name is checked, and its bytes counted, before anything is bound.
  // The node keeps a pointer to each name, so they are held here, packed end
  // to end at their own length: a 10-character name costs 11 bytes, not a
  // fixed BEEBUS_TOPIC_NAME_MAX.
  char name[BB_PATH_MAX];
  size_t nameBytes = 0;
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++) {
      bbLeafName(p, r, e, pre, true, name, sizeof(name));
      const size_t length = strlen(name);
      if (length >= BEEBUS_TOPIC_NAME_MAX) {
        // The lengths first: sLastError is shorter than the longest name.
        snprintf(err, errCap, "name too long (%u > %u): %s", (unsigned)length,
                 (unsigned)(BEEBUS_TOPIC_NAME_MAX - 1), name);
        return false;
      }
      nameBytes += length + 1;
    }
  }
  // Taken once: the node points into it from the first bind on.
  if (!p.names) p.names = new (std::nothrow) char[nameBytes];
  if (!p.names) {
    snprintf(err, errCap, "no memory for the topic names");
    return false;
  }

  if (remote && (!p.state || !p.seen)) {
    delete[] p.state;
    delete[] p.seen;
    p.state = new (std::nothrow) uint8_t[p.leaves]();
    p.seen = new (std::nothrow) uint16_t[2 * (size_t)p.leaves]();
    if (!p.state || !p.seen) {
      snprintf(err, errCap, "no memory for the topic records");
      return false;
    }
  }

  bbSyncShadows(p, false);
  uint32_t done = 0;
  char* nm = p.names;
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++, nm += strlen(nm) + 1) {
      const uint32_t leaf = r.firstLeaf + e;
      const uint16_t id = (uint16_t)(topicId + leaf);
      bbLeafName(p, r, e, pre, true, nm, BEEBUS_TOPIC_NAME_MAX);
      const bool isText = r.wire == BEEBUS_T_STRING;
      void* where = isText ? (void*)bbElem(r, e) : bbBindingOf(p, r, e);
      const uint16_t textCap = isText ? (uint16_t)(r.cap + 1) : 0;
      const bool ok = remote
          ? node->registerTopicRaw(peer, id, r.wire, where, nm, textCap)
          : node->addTopicRaw(id, r.wire, where, writable, nm, textCap);
      if (!ok) {
        // Undo, so a refused STRUCT leaves no half of itself on the node.
        for (uint32_t k = 0; k < done; k++) {
          const uint16_t back = (uint16_t)(topicId + k);
          if (remote) node->unregisterTopic(peer, back);
          else node->removeTopic(back);
        }
        snprintf(err, errCap, "topic %u (%s) is already bound", (unsigned)id, nm);
        return false;
      }
      done++;
    }
  }
  p.topics = true;
  p.remote = remote;
  p.peer = peer;
  p.topicId = topicId;
  return true;
}

// Owner, once a scan: the copies follow the variable, so the node publishes
// what the program holds. A string is bound in place and needs nothing.
void bb_planPublishSync(void* plan)
{
  BbPlan& p = *(BbPlan*)plan;
  bbSyncShadows(p, false);
}

// The read-only form every other block declares.
bool bb_planBindTopics(void* plan, BeeBusAPI* node, bool remote, uint8_t peer,
                       uint16_t topicId, const char* prefix, char* err, size_t errCap)
{
  return bb_planBindTopicsEx(plan, node, remote, peer, topicId, prefix, false, err, errCap);
}

// ---- Queued writes: PublishStruct and Serve with bWritable ------------------------
// A peer's write to a writable STRUCT member is not stored by the node (the
// topic is queued, BeeBusAPI::setTopicQueued): the node's written handlers put
// it in this node's queue, from the node's task, and the STRUCT block
// that owns the member takes it in its own scan — one write per member a scan,
// oldest first, as a Sparkplug writable metric does — so a command written 1 then 0
// between two scans is seen as both. A spinlock keeps the two tasks apart;
// nothing in it allocates or blocks for longer than a copy.
//
// Every node and every writable STRUCT gets a queue; only memory limits them.
// It is sized by what the program declares, as each writable STRUCT binds
// (start-up, never while serving): a waiting write for every writable member
// at once (at least 32), a text slot for every writable STRING member (at
// least 4) as long as the longest of them, and a count of dropped writes for
// each STRUCT.
static const uint16_t BB_WQ_SIZE = 32;      // waiting writes, at least
static const uint16_t BB_WQ_TEXTS = 4;      // text slots, at least, once there is a STRING
static const uint8_t BB_WQ_PER_TOPIC = 4;   // a fifth write to one member drops its oldest
static const uint16_t BB_WQ_NO_TEXT = 0xFFFF;

struct BbWqEntry {
  uint16_t id;
  uint16_t text;   // text slot, or BB_WQ_NO_TEXT for a number
  uint8_t by;      // the writing node
  BeeBusScalar value;
};

struct BbWqRange {
  uint16_t first;     // a writable STRUCT's topics
  uint16_t count;
  uint32_t dropped;   // its writes dropped, not yet counted by its block
  uint32_t refused;   // writes the node answered CHANGED or REFUSED, not yet counted
};

struct BbWq {
  std::atomic_flag lock = ATOMIC_FLAG_INIT;
  BeeBusAPI* node = nullptr;
  BbWq* next = nullptr;          // the next node's queue
  BbWqEntry* e = nullptr;        // `size` long, `count` waiting
  uint16_t* taken = nullptr;     // bb_planTakeWrites' scratch, `size` long
  uint16_t size = 0;
  uint16_t count = 0;
  char* text = nullptr;          // `texts` slots of `textCap` bytes
  uint16_t* textLen = nullptr;   // per slot, BB_WQ_NO_TEXT when free
  uint16_t texts = 0;
  uint16_t textCap = 0;
  BbWqRange* range = nullptr;    // one per writable STRUCT
  uint16_t ranges = 0;
  uint32_t members = 0;          // writable members, every STRUCT
  uint32_t strings = 0;          // STRINGs among them
};

static BbWq* bbWqs = nullptr;    // one per node, linked

struct BbWqLock {
  BbWq& q;
  explicit BbWqLock(BbWq& queue) : q(queue) {
    while (q.lock.test_and_set(std::memory_order_acquire)) {}
  }
  ~BbWqLock() { q.lock.clear(std::memory_order_release); }
};

// The writable STRUCT a member belongs to, or q.ranges for none.
static uint16_t bbWqRangeOf(const BbWq& q, uint16_t id)
{
  uint16_t r = 0;
  while (r < q.ranges && !(id >= q.range[r].first &&
                           (uint32_t)id < (uint32_t)q.range[r].first + q.range[r].count)) {
    r++;
  }
  return r;
}

static void bbWqRemove(BbWq& q, uint16_t i)
{
  if (q.e[i].text != BB_WQ_NO_TEXT) q.textLen[q.e[i].text] = BB_WQ_NO_TEXT;
  for (uint16_t k = i; k + 1 < q.count; k++) q.e[k] = q.e[k + 1];
  q.count--;
}

static void bbWqDropped(BbWq& q, uint16_t id)
{
  const uint16_t r = bbWqRangeOf(q, id);
  if (r < q.ranges) q.range[r].dropped++;
}

// The node's task: a peer wrote a queued member.
static void bbWqPush(BbWq& q, uint8_t by, uint16_t id, const BeeBusScalar* value,
                     const char* text, uint16_t length)
{
  BbWqLock guard(q);
  if (q.size == 0 || bbWqRangeOf(q, id) == q.ranges) return;
  uint16_t same = 0, oldest = 0;
  for (uint16_t i = 0; i < q.count; i++) {
    if (q.e[i].id != id) continue;
    if (same++ == 0) oldest = i;
  }
  if (same >= BB_WQ_PER_TOPIC) { bbWqRemove(q, oldest); bbWqDropped(q, id); }
  if (q.count == q.size) { bbWqDropped(q, q.e[0].id); bbWqRemove(q, 0); }
  BbWqEntry n{};
  n.id = id;
  n.by = by;
  n.text = BB_WQ_NO_TEXT;
  if (text) {
    uint16_t slot = 0;
    while (slot < q.texts && q.textLen[slot] != BB_WQ_NO_TEXT) slot++;
    if (slot == q.texts) { bbWqDropped(q, id); return; }
    // The longest writable STRING fits whole; the member takes its own n.
    const uint16_t keep = length < q.textCap - 1 ? length : (uint16_t)(q.textCap - 1);
    char* at = q.text + (size_t)slot * q.textCap;
    memcpy(at, text, keep);
    at[keep] = '\0';
    q.textLen[slot] = keep;
    n.text = slot;
  } else if (value) {
    n.value = *value;
  }
  q.e[q.count++] = n;
}

// The queue of a node, made (and its handlers registered) the first time a
// writable STRUCT binds on it.
static BbWq* bbWqOf(BeeBusAPI* node)
{
  for (BbWq* q = bbWqs; q; q = q->next) {
    if (q->node == node) return q;
  }
  BbWq* q = new (std::nothrow) BbWq();
  if (!q) return nullptr;
  q->node = node;
  q->next = bbWqs;
  bbWqs = q;
  node->onTopicWritten([q](uint8_t by, uint16_t id, const BeeBusScalar& value) {
    if (bb_topicTypeIsString(value.type)) return;   // the string handler takes it
    bbWqPush(*q, by, id, &value, nullptr, 0);
  });
  node->onTopicStringWritten([q](uint8_t by, uint16_t id, const char* text, uint16_t length) {
    bbWqPush(*q, by, id, nullptr, text ? text : "", text ? length : 0);
  });
  // A write that asked for a result and was not kept as written: counted for
  // the STRUCT it belongs to.
  node->onTopicDecided([q](uint8_t, uint16_t id, uint8_t outcome) {
    if (outcome != BEEBUS_OUTCOME_CHANGED && outcome != BEEBUS_OUTCOME_REFUSED) return;
    BbWqLock guard(*q);
    const uint16_t r = bbWqRangeOf(*q, id);
    if (r < q->ranges) q->range[r].refused++;
  });
  return q;
}

// Owner, once after a bWritable bind: every member is queued on the node, and
// the node's queue grows to hold this STRUCT's members too. The new storage is
// taken aside and swapped in under the lock, what is waiting copied across.
bool bb_planQueueWrites(void* plan, BeeBusAPI* node, char* err, size_t errCap)
{
  BbPlan& p = *(BbPlan*)plan;
  uint32_t strings = 0, bools = 0;
  uint16_t longest = 0;
  for (uint32_t i = 0; i < p.runCount; i++) {
    const BbRun& r = p.runs[i];
    if (r.wire == BEEBUS_T_STRING) {
      strings += r.count;
      if (r.cap + 1u > longest) longest = (uint16_t)(r.cap + 1u);
    } else if (r.wire == BEEBUS_T_BOOL) {
      bools += r.count;
    }
  }
  if (bools > 0 && !p.pulseLeaf) {
    p.pulseLeaf = new (std::nothrow) uint32_t[bools];
    p.pulseAt = new (std::nothrow) uint32_t[bools];
    if (!p.pulseLeaf || !p.pulseAt) {
      snprintf(err, errCap, "no memory for the momentary commands");
      return false;
    }
    p.pulseCap = bools;
  }
  if (!p.appliedIds) {
    p.appliedIds = new (std::nothrow) uint16_t[p.leaves];
    p.appliedCmd = new (std::nothrow) uint8_t[p.leaves];
    if (!p.appliedIds || !p.appliedCmd) {
      snprintf(err, errCap, "no memory for the write results");
      return false;
    }
  }

  BbWq* q = bbWqOf(node);
  const uint32_t members = (q ? q->members : 0) + p.leaves;
  const uint32_t allStrings = (q ? q->strings : 0) + strings;
  const uint32_t size = members > BB_WQ_SIZE ? members : BB_WQ_SIZE;
  const uint32_t texts = allStrings == 0 ? 0 : (allStrings > BB_WQ_TEXTS ? allStrings : BB_WQ_TEXTS);
  BbWqEntry* e = nullptr;
  uint16_t* taken = nullptr;
  char* text = nullptr;
  uint16_t* textLen = nullptr;
  BbWqRange* range = nullptr;
  uint16_t textCap = 0;
  bool ok = q != nullptr;
  if (ok) {
    textCap = longest > q->textCap ? longest : q->textCap;
    if (size > q->size) {
      e = new (std::nothrow) BbWqEntry[size];
      taken = new (std::nothrow) uint16_t[size];
      ok = e && taken;
    }
    if (ok && (texts > q->texts || textCap > q->textCap)) {
      text = new (std::nothrow) char[(size_t)texts * textCap];
      textLen = new (std::nothrow) uint16_t[texts];
      ok = text && textLen;
    }
    if (ok) {
      range = new (std::nothrow) BbWqRange[q->ranges + 1u];
      ok = range != nullptr;
    }
  }
  if (!ok) {
    delete[] e;
    delete[] taken;
    delete[] text;
    delete[] textLen;
    snprintf(err, errCap, "no memory for the write queue (%lu writable members)",
             (unsigned long)members);
    return false;
  }
  {
    BbWqLock guard(*q);
    if (e) {
      for (uint16_t i = 0; i < q->count; i++) e[i] = q->e[i];
      std::swap(e, q->e);
      std::swap(taken, q->taken);
      q->size = (uint16_t)size;
    }
    if (text) {
      for (uint32_t s = 0; s < texts; s++) textLen[s] = BB_WQ_NO_TEXT;
      for (uint16_t s = 0; s < q->texts; s++) {
        if (q->textLen[s] == BB_WQ_NO_TEXT) continue;
        memcpy(text + (size_t)s * textCap, q->text + (size_t)s * q->textCap, q->textLen[s] + 1u);
        textLen[s] = q->textLen[s];
      }
      std::swap(text, q->text);
      std::swap(textLen, q->textLen);
      q->texts = (uint16_t)texts;
      q->textCap = textCap;
    }
    for (uint16_t r = 0; r < q->ranges; r++) range[r] = q->range[r];
    range[q->ranges] = BbWqRange{p.topicId, (uint16_t)p.leaves, 0, 0};
    std::swap(range, q->range);
    p.wqRange = q->ranges;
    q->ranges++;
    q->members = members;
    q->strings = allStrings;
  }
  // What was swapped out.
  delete[] e;
  delete[] taken;
  delete[] text;
  delete[] textLen;
  delete[] range;
  for (uint32_t k = 0; k < p.leaves; k++) node->setTopicQueued((uint16_t)(p.topicId + k), true);
  p.wq = q;
  return true;
}

static bool bbLeafRun(BbPlan& p, uint32_t leaf, BbRun*& run, uint32_t& e)
{
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    if (leaf >= r.firstLeaf && leaf < r.firstLeaf + r.count) { run = &r; e = leaf - r.firstLeaf; return true; }
  }
  return false;
}

// A taken write into the program's variable (and its wire copy, if converted).
static void bbApplyWrite(BbPlan& p, BbWq& q, const BbWqEntry& w, uint32_t pulseMs)
{
  const uint32_t leaf = (uint32_t)(w.id - p.topicId);
  BbRun* r = nullptr;
  uint32_t e = 0;
  if (!bbLeafRun(p, leaf, r, e)) return;
  if (r->wire == BEEBUS_T_STRING) {
    if (w.text == BB_WQ_NO_TEXT) return;
    char* to = (char*)bbElem(*r, e);
    const uint16_t keep = q.textLen[w.text] < r->cap ? q.textLen[w.text] : r->cap;
    memcpy(to, q.text + (size_t)w.text * q.textCap, keep);
    to[keep] = '\0';
    return;
  }
  if (r->conv != BB_CONV_NONE) {
    int32_t wire = 0;
    bb_scalarStore(w.value, &wire);
    bbFromWire(*r, e, wire);
    bbShadow(p, *r, e) = wire;
    bbSynced(p, *r, e) = wire;
    return;
  }
  bb_scalarStore(w.value, bbElem(*r, e));
  // A momentary command: a BOOL written TRUE goes back to FALSE after tPulse.
  // There is a place for every BOOL member, so none is ever cut short.
  if (pulseMs > 0 && r->wire == BEEBUS_T_BOOL && *(bool*)bbElem(*r, e)) {
    uint32_t slot = 0;
    while (slot < p.pulses && p.pulseLeaf[slot] != leaf) slot++;
    if (slot == p.pulses) {
      if (p.pulses == p.pulseCap) return;
      p.pulses++;
    }
    p.pulseLeaf[slot] = leaf;
    p.pulseAt[slot] = (uint32_t)bb_millis();
  }
}

// Owner, once a scan: one waiting write per member, oldest first, into the
// variable. Returns how many were taken; `firstLeaf` / `by` describe the first
// of them, `lost` adds the writes dropped since the last call (a member written
// more than 4 times between two scans, or a full queue).
uint32_t bb_planTakeWrites(void* plan, uint32_t pulseMs, uint32_t* firstLeaf, uint8_t* by,
                           uint32_t* lost)
{
  BbPlan& p = *(BbPlan*)plan;
  // Momentary commands whose pulse is over go back to FALSE.
  const uint32_t now = (uint32_t)bb_millis();
  for (uint32_t s = 0; s < p.pulses;) {
    if (pulseMs == 0 || now - p.pulseAt[s] >= pulseMs) {
      BbRun* r = nullptr;
      uint32_t e = 0;
      if (bbLeafRun(p, p.pulseLeaf[s], r, e)) *(bool*)bbElem(*r, e) = false;
      p.pulseLeaf[s] = p.pulseLeaf[p.pulses - 1];
      p.pulseAt[s] = p.pulseAt[p.pulses - 1];
      p.pulses--;
    } else {
      s++;
    }
  }
  BbWq* q = (BbWq*)p.wq;
  if (!q) return 0;
  uint32_t taken = 0;
  {
    BbWqLock guard(*q);
    uint16_t* takenIds = q->taken;
    for (uint16_t i = 0; i < q->count;) {
      const BbWqEntry w = q->e[i];
      const bool mine = w.id >= p.topicId && (uint32_t)w.id < (uint32_t)p.topicId + p.leaves;
      bool already = false;
      for (uint32_t k = 0; k < taken && !already; k++) already = takenIds[k] == w.id;
      if (!mine || already) { i++; continue; }
      bbApplyWrite(p, *q, w, pulseMs);
      if (taken == 0) {
        if (firstLeaf) *firstLeaf = (uint32_t)(w.id - p.topicId);
        if (by) *by = w.by;
      }
      // A momentary BOOL is a command: answered once taken, not read back,
      // since it drops back to FALSE on its own.
      BbRun* r = nullptr;
      uint32_t e = 0;
      const bool momentary = pulseMs > 0 && bbLeafRun(p, (uint32_t)(w.id - p.topicId), r, e) &&
                             r->wire == BEEBUS_T_BOOL;
      if (p.appliedIds) {
        p.appliedIds[taken] = w.id;
        p.appliedCmd[taken] = (uint8_t)(p.command || momentary);
      }
      takenIds[taken++] = w.id;
      bbWqRemove(*q, i);
    }
    BbWqRange& mine = q->range[p.wqRange];
    if (lost) *lost += mine.dropped;
    mine.dropped = 0;
  }
  // Outside the queue's lock: the node's task takes that lock inside its own,
  // so taking the node's here, under it, could stop both.
  if (p.appliedIds) {
    for (uint32_t k = 0; k < taken; k++) {
      q->node->topicApplied(p.appliedIds[k], p.settleMs, p.appliedCmd[k] != 0);
    }
  }
  return taken;
}

// Owner: the read-back's delay and whether every member is a command
// (Serve, PublishStruct's tSettle).
void bb_planServeTerms(void* plan, uint32_t settleMs, bool command)
{
  BbPlan& p = *(BbPlan*)plan;
  p.settleMs = (uint16_t)(settleMs > 0xFFFFu ? 0xFFFFu : settleMs);
  p.command = command;
}

// Owner, once a scan: writes the node answered CHANGED or REFUSED since the
// last call.
uint32_t bb_planTakeRefused(void* plan)
{
  BbPlan& p = *(BbPlan*)plan;
  BbWq* q = (BbWq*)p.wq;
  if (!q) return 0;
  BbWqLock guard(*q);
  BbWqRange& mine = q->range[p.wqRange];
  const uint32_t refused = mine.refused;
  mine.refused = 0;
  return refused;
}

// Owner: every member held in a ring of `depth` while the network is away
// (store and forward). 0 leaves them unbuffered.
bool bb_planBuffer(void* plan, BeeBusAPI* node, uint8_t depth, char* err, size_t errCap)
{
  BbPlan& p = *(BbPlan*)plan;
  if (depth == 0) return true;
  for (uint32_t k = 0; k < p.leaves; k++) {
    if (!node->bufferTopic((uint16_t)(p.topicId + k), depth)) {
      snprintf(err, errCap, "no ring of %u for topic %u", (unsigned)depth,
               (unsigned)(p.topicId + k));
      return false;
    }
  }
  return true;
}

// Subscriber: asks for every topic not yet asked for, stopping at the first
// refusal the queue gives (QueueFull: the rest go next scan). `again` re-asks
// every one, for new terms. Returns the values still not asked for.
uint32_t bb_planSubscribe(void* plan, BeeBusAPI* node, float deadband, int32_t intervalMs,
                          bool again, BeeBusResult* last, bool reliable)
{
  BbPlan& p = *(BbPlan*)plan;
  if (!p.state) {
    if (last) *last = BeeBusResult::InvalidArgument;
    return p.leaves;
  }
  if (again) {
    for (uint32_t k = 0; k < p.leaves; k++) p.state[k] = (uint8_t)(p.state[k] & ~BB_ISSUED);
  }
  uint32_t pending = 0;
  bool full = false;
#if BEEBUS_TOPIC_NAMES
  for (uint32_t k = 0; k < p.leaves; k++) {
    if (p.state[k] & BB_ISSUED) continue;
    if (full) { pending++; continue; }
    const BeeBusResult result =
        node->subscribe(p.peer, (uint16_t)(p.topicId + k), deadband, (bb_time_t)intervalMs,
                        reliable ? BeeBusQoS::Reliable : BeeBusQoS::Live);
    if (bb_accepted(result) || result == BeeBusResult::Duplicate) {
      p.state[k] = (uint8_t)(p.state[k] | BB_ISSUED);
    } else {
      if (last) *last = result;
      pending++;
      if (result == BeeBusResult::QueueFull) full = true;
    }
  }
#else
  (void)node; (void)deadband; (void)intervalMs;
  pending = p.leaves;
  if (last) *last = BeeBusResult::InvalidArgument;
#endif
  return pending;
}

// Subscriber, once a scan: copies arrivals into the variable and reports.
//   newCount   values that arrived since the last scan
//   firstNew   the first of them, by number from 0
//   missed     publishes the sequence says never arrived, since the last scan
//   worst      the worst quality across the values (BeeBusQuality order)
//   allSeen    every value has arrived at least once
// A string topic is bound to the variable's own buffer, so its text is there
// already; a converted value is taken from its copy.
void bb_planReceive(void* plan, BeeBusAPI* node, uint32_t* newCount, uint32_t* firstNew,
                    uint32_t* missed, uint8_t* worst, bool* allSeen, int32_t* oldestAgeMs)
{
  BbPlan& p = *(BbPlan*)plan;
  uint32_t fresh = 0, gaps = 0;
  bool seenAll = true;
  uint8_t bad = (uint8_t)BeeBusQuality::Good;
  int32_t oldest = 0;
  if (!p.state || !p.seen) return;
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++) {
      const uint32_t leaf = r.firstLeaf + e;
      const uint16_t id = (uint16_t)(p.topicId + leaf);
      uint16_t& seenReceived = p.seen[2 * (size_t)leaf];
      uint16_t& seenMissed = p.seen[2 * (size_t)leaf + 1];
      BeeBusTopicStream stream;
      bool isNew = false;
      if (node->topicStream(p.peer, id, stream)) {
        isNew = (stream.received != seenReceived);
        gaps += (uint16_t)(stream.missed - seenMissed);
        seenReceived = stream.received;
        seenMissed = stream.missed;
      }
      if (isNew) {
        if (fresh == 0 && firstNew) *firstNew = leaf;
        fresh++;
        p.state[leaf] = (uint8_t)(p.state[leaf] | BB_ARRIVED);
        if (r.conv != BB_CONV_NONE) {
          bbFromWire(r, e, bbShadow(p, r, e));
          bbSynced(p, r, e) = bbShadow(p, r, e);
        }
      }
      if (!(p.state[leaf] & BB_ARRIVED)) seenAll = false;
      // Ranked so the answer is the worst member: BAD, then UNCERTAIN, then
      // UNKNOWN (never arrived), and GOOD only when every member is good.
      const uint8_t q = (uint8_t)node->topicQuality(p.peer, id);
      if (bbQualityRank(q) > bbQualityRank(bad)) bad = q;
      const bb_time_t age = node->topicAge(p.peer, id);
      if (age != BEEBUS_SILENCE_NEVER && (int32_t)age > oldest) oldest = (int32_t)age;
    }
  }
  if (newCount) *newCount = fresh;
  if (missed) *missed = gaps;
  if (worst) *worst = bad;
  if (allSeen) *allSeen = seenAll;
  if (oldestAgeMs) *oldestAgeMs = oldest;
}

// ---- Binds: Bind ---------------------------------------------------
// Every member of the STRUCT bound to the owner's topic of the same place
// (BeeBusAPI::bind): the owner's value lands in the member, a change of the
// member goes to the owner, which decides. A converted member (TIME, DT ...)
// is bound through its copy, kept in step both ways each scan.
bool bb_planBind(void* plan, BeeBusAPI* node, uint8_t peer, uint16_t topicId,
                 const char* prefix, bool reliable, float deadband, char* err, size_t errCap)
{
  BbPlan& p = *(BbPlan*)plan;
  const char* pre = prefix ? prefix : "";
  if (topicId < BEEBUS_TOPIC_ID_MIN ||
      (uint32_t)topicId + p.leaves - 1 > (uint32_t)BEEBUS_TOPIC_ID_MAX) {
    snprintf(err, errCap, "nTopicId + members runs past 32767, or nTopicId is 0");
    return false;
  }
  if (!p.state || !p.seen) {
    delete[] p.state;
    delete[] p.seen;
    p.state = new (std::nothrow) uint8_t[p.leaves]();
    p.seen = new (std::nothrow) uint16_t[2 * (size_t)p.leaves]();
    if (!p.state || !p.seen) {
      snprintf(err, errCap, "no memory for the bind records");
      return false;
    }
  }
  BeeBusBindTerms terms;
  terms.qos = reliable ? BeeBusQoS::Reliable : BeeBusQoS::Live;
  terms.deadband = deadband;

  bbSyncShadows(p, false);
  uint32_t done = 0;
  char name[BB_PATH_MAX];
  for (uint32_t i = 0; i < p.runCount; i++) {
    BbRun& r = p.runs[i];
    for (uint32_t e = 0; e < r.count; e++) {
      const uint32_t leaf = r.firstLeaf + e;
      const uint16_t id = (uint16_t)(topicId + leaf);
      bbLeafName(p, r, e, pre, true, name, sizeof(name));
      const bool isText = r.wire == BEEBUS_T_STRING;
      void* where = isText ? (void*)bbElem(r, e) : bbBindingOf(p, r, e);
      const uint16_t textCap = isText ? (uint16_t)(r.cap + 1) : 0;
      if (!node->bindRaw(peer, id, r.wire, where, terms, nullptr, textCap)) {
        for (uint32_t k = 0; k < done; k++) node->unbind(peer, (uint16_t)(topicId + k));
        snprintf(err, errCap, "topic %u (%s) is already bound", (unsigned)id, name);
        return false;
      }
      done++;
    }
  }
  p.topics = true;
  p.binds = true;
  p.remote = true;
  p.peer = peer;
  p.topicId = topicId;
  return true;
}

// Once a scan: the copies of converted members in step both ways - a copy the
// bind moved (the owner's value) goes into the member, otherwise the member
// (the program's change) goes into the copy for the bind to send.
void bb_planBindSync(void* plan)
{
  BbPlan& p = *(BbPlan*)plan;
  bbSyncShadows(p, true);
}

// Once a scan, the members' states:
//   worst      the worst member: OFFLINE, SYNCING, FAILED, REFUSED, PENDING,
//              IN_SYNC, in that order
//   pending, refused, failed   how many members are in each
//   firstRefused               the first member REFUSED, by number from 0
//   allInSync                  every member IN_SYNC
void bb_planBindStatus(void* plan, BeeBusAPI* node, uint8_t* worst, uint32_t* pending,
                       uint32_t* refused, uint32_t* failed, uint32_t* firstRefused,
                       bool* allInSync)
{
  BbPlan& p = *(BbPlan*)plan;
  // Rank: the higher, the worse.
  static const uint8_t rank[] = {5, 4, 0, 1, 2, 3};   // by BeeBusBindState
  uint8_t bad = (uint8_t)BeeBusBindState::InSync;
  uint32_t nPending = 0, nRefused = 0, nFailed = 0, first = 0;
  bool all = true;
  for (uint32_t k = 0; k < p.leaves; k++) {
    const BeeBusBindState s = node->bindState(p.peer, (uint16_t)(p.topicId + k));
    const uint8_t v = (uint8_t)s;
    if (v < sizeof(rank) && rank[v] > rank[bad]) bad = v;
    if (s != BeeBusBindState::InSync) all = false;
    if (s == BeeBusBindState::Pending) nPending++;
    if (s == BeeBusBindState::Failed) nFailed++;
    if (s == BeeBusBindState::Refused) {
      if (nRefused == 0) first = k;
      nRefused++;
    }
  }
  if (worst) *worst = bad;
  if (pending) *pending = nPending;
  if (refused) *refused = nRefused;
  if (failed) *failed = nFailed;
  if (firstRefused) *firstRefused = first;
  if (allInSync) *allInSync = all;
}

// A plan that was never bound to a node (a read or a write buffer) can go.
void bb_planFree(void* plan)
{
  if (!plan) return;
  BbPlan* p = (BbPlan*)plan;
  if (p->bound || p->topics) return;   // the node holds pointers into it
  delete p;
}
// =============================================================================
// THE NODE, AND WHAT ITS METHODS KEEP
// =============================================================================
//
// A method keeps what it needs between calls in a record, keyed by the method
// and the declared name and type of its ANY argument (IEC_ANY::NAME,
// TYPENAME). An argument with no name - a literal - is keyed by its topic or
// address instead. PVALUE is kept only as a cache. The records belong to the
// node instance and live as long as it does: a settings change re-opens the
// same node, so they stay bound across it.

#ifndef BB_MAX_RECORDS
#define BB_MAX_RECORDS 256
#endif

namespace {

enum BbRecordKind : uint8_t {
  BB_REC_TOPIC,
  BB_REC_PUBLISH,
  BB_REC_SUBSCRIBE,
  BB_REC_PUBLISH_STRUCT,
  BB_REC_SUBSCRIBE_STRUCT,
  BB_REC_SERVE,
  BB_REC_BIND,
  BB_REC_WRITE,
  BB_REC_BUFFER,
  BB_REC_MODBUS_MAP,
  BB_REC_MODBUS_READ,
  BB_REC_MODBUS_WRITE,
};

struct BbRecord {
  uint8_t kind = 0;
  uint32_t key = 0;
  std::string name;
  std::string type;
  const uint8_t* cache = nullptr;

  // What the record was bound as (its topic ids, prefix, peer, table,
  // address), as a fingerprint: a later call that differs is refused, and a
  // refused bind is tried again only once it differs.
  bool bound = false;
  bool refused = false;
  uint32_t identity = 0;
  std::string why;
  void* plan = nullptr;          // a STRUCT's values, or a Modbus request's
  uint8_t wire = BEEBUS_T_COUNT;
  void* storage = nullptr;       // the address a single topic is bound to
  std::string* text = nullptr;   // Publish of a STRING: the copy its topic is bound to
  // A single topic's name. The node keeps a pointer to it, so it is the
  // record's own copy, never the method's parameter, which the next call
  // overwrites.
  std::string topicName;
  uint16_t topicId = 0;
  uint8_t peer = 0;
  uint16_t address = 0;
  bool bits = false;

  // A request.
  bool lastExecute = false;
  bool pending = false;
  bool waitingResult = false;
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  uint8_t target = 0;
  uint16_t resultCount = 0;
  uint8_t outcome = BEEBUS_OUTCOME_COUNT;
  bool accepted = false;
  bool refusedValue = false;
  double kept = 0.0;

  // A subscription.
  bool issued = false;
  float askedDeadband = 0.0f;
  int32_t askedInterval = 0;
  bool askedReliable = false;
  uint16_t seenReceived = 0;
  uint16_t seenMissed = 0;
  uint32_t missed = 0;

  // What a standing method holds from one call to the next.
  uint32_t lost = 0;
  uint32_t refusedCount = 0;
  std::string heldName;
  uint16_t heldIndex = 0;
  uint16_t heldCount = 0;
  uint16_t heldAddress = 0;
  uint8_t heldBy = 0;
  bool wasRefused = false;
  uint16_t seenFailsafe = 0;
  bool depthSet = false;
  uint8_t depth = 0;
  uint16_t members = 0;
  bool mapped = false;
};

struct BbNode {
  BeeBusAPI* api = nullptr;
  // The transport this block made (the Runtime's, a board's UDP), freed when
  // a settings change replaces it. A board's serial line is the node's own.
  BeeBusTransport* transport = nullptr;
  uint8_t openPort = 255;
  bool wanted = false;
  // One scan passes before the link opens, so every method has been called.
  bool settled = false;
  bool tried = false;
  bool waiting = false;
  bool rebind = false;
  uint32_t retryAt = 0;
  uint32_t backoff = 0;
  // The settings the link was opened with, as one short fingerprint. A change
  // re-opens the link under the same node.
  uint32_t settingsKey = 0;
  uint32_t changeAt = 0;
  bool debug = false;
  // The task the block runs in: see ONE TASK PER NODE.
  strucpp::XWORD_t task = 0;

  // The link's own fault, a duplicate id, and a line for sLastError while
  // nothing is wrong ("joining the network").
  bool linkError = false;
  E_BEEBUSRESULT linkResult = E_BEEBUSRESULT::OK;
  std::string linkText;
  std::string note;

  std::vector<BbRecord*> records;
  // The last method call that failed, by method and record: bError and
  // sLastError name it until that call succeeds.
  std::string failKey;
  std::string failText;
  E_BEEBUSRESULT failResult = E_BEEBUSRESULT::OK;
};

}  // namespace

// This instance's node state, made on first use, by the block or by a method
// called before it.
static BbNode* bb_stateOf(strucpp::XWORD_t held)
{
  BbNode* n = (BbNode*)(uintptr_t)held;
  if (n == nullptr) n = new (std::nothrow) BbNode();
  return n;
}

// A short fingerprint (FNV-1a, 32 bits): only to notice a change without
// keeping a second copy of every string.
static uint32_t bb_fingerprint(uint32_t hash, const void* data, size_t length)
{
  const uint8_t* bytes = (const uint8_t*)data;
  for (size_t i = 0; i < length; i++) {
    hash ^= bytes[i];
    hash *= 16777619u;
  }
  return hash;
}

static uint32_t bb_fingerprintText(uint32_t hash, const char* text)
{
  hash = bb_fingerprint(hash, text, strlen(text));
  return bb_fingerprint(hash, "", 1);   // a separator: "ab"+"c" differs from "a"+"bc"
}

template <typename T>
static uint32_t bb_fingerprintOf(uint32_t hash, T value)
{
  return bb_fingerprint(hash, &value, sizeof value);
}

// The record's name: the variable's declared name, or for a literal `fallback`
// (its topic or address).
static std::string bb_recordName(const strucpp::IEC_ANY* any, const char* fallback)
{
  if (any != nullptr && any->NAME != nullptr && any->NAME[0] != '\0') return any->NAME;
  return std::string("'") + (fallback ? fallback : "");
}

// The record of one call, found by its key or made. Null past BB_MAX_RECORDS
// or out of memory.
static BbRecord* bb_recordOf(BbNode* n, uint8_t kind, const std::string& name,
                             const char* type, const uint8_t* address)
{
  if (n == nullptr) return nullptr;
  if (type == nullptr) type = "";
  uint32_t key = bb_fingerprint(2166136261u, &kind, sizeof kind);
  key = bb_fingerprintText(bb_fingerprintText(key, name.c_str()), type);
  for (size_t i = 0; i < n->records.size(); i++) {
    BbRecord* r = n->records[i];
    if (r->kind != kind || r->key != key) continue;
    if (address != nullptr && r->cache == address) return r;
    if (r->name == name && r->type == type) {
      r->cache = address;
      return r;
    }
  }
  if (n->records.size() >= (size_t)BB_MAX_RECORDS) return nullptr;
  BbRecord* r = new (std::nothrow) BbRecord();
  if (r == nullptr) return nullptr;
  r->kind = kind;
  r->key = key;
  r->name = name;
  r->type = type;
  r->cache = address;
  n->records.push_back(r);
  return r;
}

static const char* bb_resultText(E_BEEBUSRESULT result)
{
  if (result == E_BEEBUSRESULT::WRONGTASK) return "wrong task: call it in the node's task";
  if (result == E_BEEBUSRESULT::OK) return "Ok";
  return bb_resultName((BeeBusResult)(int)result);
}

// A method call's result, noted on the node. A failing call is named on the
// block's bError / sLastError ("Serve STS: topic 300 (limit) is already
// bound") until the same call succeeds. Queued and not yet started are
// states, not failures; so is a peer out of the ring while this node is.
static E_BEEBUSRESULT bb_noteCall(BbNode* n, const char* method, const std::string& record,
                                  E_BEEBUSRESULT result, const char* why)
{
  // A call from another task touches nothing of the node's: it is told so.
  if (n == nullptr || result == E_BEEBUSRESULT::WRONGTASK) return result;
  std::string key = method;
  key += ' ';
  key += record;
  const bool offline = n->api == nullptr || !n->api->isConnected();
  const bool failed = result != E_BEEBUSRESULT::OK && result != E_BEEBUSRESULT::QUEUED &&
                      result != E_BEEBUSRESULT::NOTINITIALISED &&
                      !(result == E_BEEBUSRESULT::UNKNOWNNODE && offline);
  if (failed) {
    n->failKey = key;
    n->failResult = result;
    n->failText = key + ": " + (why != nullptr && why[0] != '\0' ? why : bb_resultText(result));
  } else if (n->failKey == key) {
    n->failKey.clear();
    n->failText.clear();
  }
  return result;
}

// A library result as the method's, Immediate being Ok.
static E_BEEBUSRESULT bb_resultOf(BeeBusResult result)
{
  return (E_BEEBUSRESULT)(int32_t)(int)result;
}

// --- opening the link, and trying again ------------------------------------
//
// A link that does not open now may open later: a USB adapter plugged in after
// boot, a network interface that comes up after the PLC, a port another
// program is holding. So a failed open (NotInitialised) is tried again, 1 s
// after the first failure, then 2, 4, 8, 16 and every 30 s after that. A
// wrong SETTING stays wrong however often it is tried, so those
// (InvalidArgument) are reported once, sLastError saying which, and tried
// again only when a setting changes.
static const uint32_t BB_RETRY_FIRST_MS = 1000;
static const uint32_t BB_RETRY_MAX_MS = 30000;

static void bb_debugLine(const char* category, const char* message)
{
  printf("[%s] %s\n", category, message);
}

void setup()
{
  bReady = false;
  bLinkUp = false;
  bConnected = false;
  bError = false;
  eErrorId = E_BEEBUSRESULT::OK;
  sLastError = "";
  nAttempts = 0;
  tRetryIn = bb_timeOf(0);
  nState = (strucpp::XWORD_t)0;
}

// A member of an option structure that does not apply to this target. Said,
// never ignored: a setting that quietly does nothing is how an afternoon goes
// missing. The node runs on regardless.
template <typename Serial, typename Network>
static const char* bb_misplaced(const Serial& serial, const Network& network)
{
#if defined(BEEBUS_PLATFORM_HOST)
  if ((uint8_t)serial.NPORT != 0 || (int16_t)serial.NRXPIN != -1 || (int16_t)serial.NTXPIN != -1) {
    return "stSerialConfig: nPort, nRxPin and nTxPin are a board's";
  }
  if (network.SSSID.length() > 0 || network.SWIFIPASSWORD.length() > 0 ||
      network.SMAC.length() > 0 || network.SIP.length() > 0) {
    return "stNetworkConfig: Wi-Fi and Ethernet are a board's; the Runtime uses its machine's network";
  }
#else
  if (serial.SDEVICE.length() > 0) return "stSerialConfig.sDevice is the Runtime's";
  if ((uint8_t)network.NTTL != 0 || network.SINTERFACEADDR.length() > 0) {
    return "stNetworkConfig: nTtl and sInterfaceAddr are the Runtime's";
  }
#endif
  return nullptr;
}

void loop()
{
  BbNode* n = bb_stateOf((strucpp::XWORD_t)nState);
  if (n == nullptr) {
    bError = true;
    eErrorId = E_BEEBUSRESULT::NOTINITIALISED;
    sLastError = "out of memory for the node";
    return;
  }
  nState = (strucpp::XWORD_t)(uintptr_t)n;
  n->task = bb_currentTask();   // its methods compare: see ONE TASK PER NODE

  // What the link is opened from. A change re-opens it (below).
  auto settingsKey = [&]() -> uint32_t {
    uint32_t h = 2166136261u;
    h = bb_fingerprintOf(h, (uint8_t)nNodeId);
    h = bb_fingerprintOf(h, (int32_t)(E_BEEBUSTRANSPORT)eTransport);
    h = bb_fingerprintOf(h, (bool)bFailsafe);
    h = bb_fingerprintOf(h, (uint8_t)nMaxPending);
    h = bb_fingerprintOf(h, (int32_t)stSerialConfig.NBAUD);
    h = bb_fingerprintOf(h, (uint8_t)stSerialConfig.NPORT);
    h = bb_fingerprintOf(h, (int16_t)stSerialConfig.NRXPIN);
    h = bb_fingerprintOf(h, (int16_t)stSerialConfig.NTXPIN);
    h = bb_fingerprintText(h, stSerialConfig.SDEVICE.c_str());
    h = bb_fingerprintOf(h, (uint16_t)stNetworkConfig.NUDPPORT);
    h = bb_fingerprintOf(h, (uint8_t)stNetworkConfig.NTTL);
    h = bb_fingerprintText(h, stNetworkConfig.SGROUPADDR.c_str());
    h = bb_fingerprintText(h, stNetworkConfig.SINTERFACEADDR.c_str());
    h = bb_fingerprintText(h, stNetworkConfig.SSSID.c_str());
    h = bb_fingerprintText(h, stNetworkConfig.SWIFIPASSWORD.c_str());
    h = bb_fingerprintText(h, stNetworkConfig.SMAC.c_str());
    h = bb_fingerprintText(h, stNetworkConfig.SIP.c_str());
    return h;
  };

  [&]() {
    if (!(bool)bReady || n->rebind) {
      // ONE SCAN BEFORE OPENING: every method has been called once, wherever
      // it sits in the program, and opening a socket costs longer than a scan.
      if (!n->settled) {
        n->settled = true;
        return;
      }

      // A SETTINGS CHANGE ON A RUNNING NODE: the same node is re-opened (see
      // BeeBusAPI::rebind), after a moment for it to leave the old ring.
      BeeBusAPI* existing = (bool)bReady ? n->api : nullptr;
      if (existing && (existing->isConnected() || existing->isLeaving()) &&
          (uint32_t)((uint32_t)bb_millis() - n->changeAt) < 1000u) {
        existing->loop();
        return;
      }

      if (n->tried && !n->waiting) {
        // A settings fault: said once, and not retried until a setting
        // changes - retrying the same ones cannot fix it, a settings page can.
        if (settingsKey() == n->settingsKey) return;
        n->tried = false;
      }
      if (n->tried) {
        const int32_t left = (int32_t)(n->retryAt - (uint32_t)bb_millis());
        if (left > 0) {
          tRetryIn = bb_timeOf(left);
          return;
        }
      }
      n->tried = true;
      n->waiting = false;
      tRetryIn = bb_timeOf(0);
      nAttempts = (uint32_t)nAttempts + 1;

      // A settings fault. Reported, and left: retrying cannot fix it.
      auto refuse = [&](const char* why) {
        n->settingsKey = settingsKey();
        n->linkError = true;
        n->linkResult = E_BEEBUSRESULT::INVALIDARGUMENT;
        n->linkText = why;
      };

      // The link did not open. Tried again later, each wait twice the last.
      auto later = [&](const char* why) {
        const uint32_t wait = n->backoff == 0
            ? BB_RETRY_FIRST_MS
            : (n->backoff * 2u > BB_RETRY_MAX_MS ? BB_RETRY_MAX_MS : n->backoff * 2u);
        n->backoff = wait;
        n->retryAt = (uint32_t)bb_millis() + wait;
        n->waiting = true;
        tRetryIn = bb_timeOf((int32_t)wait);
        n->linkError = true;
        n->linkResult = E_BEEBUSRESULT::NOTINITIALISED;
        n->linkText = why;
      };

      // 0 means "nobody" on the wire and 255 is the join token: the
      // protocol's own range, so the block and the core can never disagree.
      if ((uint8_t)nNodeId < BEEBUS_NODE_ID_MIN || (uint8_t)nNodeId > BEEBUS_NODE_ID_MAX) {
        refuse("nNodeId must be 1..254");
        return;
      }

      const E_BEEBUSTRANSPORT link = (E_BEEBUSTRANSPORT)eTransport;
      const bool runtimeLink = link == E_BEEBUSTRANSPORT::RUNTIMEUDP ||
                               link == E_BEEBUSTRANSPORT::RUNTIMESERIAL;

      BeeBusConfig config;
      config.enableFailSafe = (bool)bFailsafe;
      config.maxPendingOps = (uint8_t)nMaxPending;         // 0: the platform's default
      config.maxPendingResponses = (uint8_t)nMaxPending;

#if defined(BEEBUS_PLATFORM_HOST)
      if (!runtimeLink) {
        refuse("that eTransport needs a board, not the Runtime");
        return;
      }
      if (link == E_BEEBUSTRANSPORT::RUNTIMESERIAL && stSerialConfig.SDEVICE.length() == 0) {
        refuse("no serial device named: stSerialConfig.sDevice");
        return;
      }

      // nothrow throughout: a board has no exceptions, and the Runtime is told
      // the same way - out of memory is a reason on sLastError, not a crash.
      BeeBusAPI* node = existing ? existing : new (std::nothrow) BeeBusAPI();
      if (!node) {
        later("out of memory for the node");
        return;
      }
      BeeBusTransport* transport = nullptr;
      bool started = false;
      // Copied out: the text lives in the transport, which a failure deletes.
      char failure[96] = "";

      if (link == E_BEEBUSTRANSPORT::RUNTIMESERIAL) {
        // The option structure is a member of this instance, so its text
        // outlives the scan and the transport may hold it.
        BeeBusSerialConfig serial;
        serial.device = stSerialConfig.SDEVICE.c_str();
        if ((int32_t)stSerialConfig.NBAUD > 0) serial.baudRate = (uint32_t)(int32_t)stSerialConfig.NBAUD;
        BeeBusHostSerialTransport* port = new (std::nothrow) BeeBusHostSerialTransport(serial);
        if (!port) {
          if (!existing) delete node;
          later("out of memory for the link");
          return;
        }
        transport = port;
        started = existing ? existing->rebind(port, (uint8_t)nNodeId, &config)
                           : node->begin(port, (uint8_t)nNodeId, config);
        if (!started) snprintf(failure, sizeof(failure), "%s",
                               node->startError() ? node->startError() : port->lastError());
      } else {
        BeeBusUdpConfig udp;
        if (stNetworkConfig.SGROUPADDR.length() > 0) udp.groupAddress = stNetworkConfig.SGROUPADDR.c_str();
        if ((uint16_t)stNetworkConfig.NUDPPORT != 0) udp.port = (uint16_t)stNetworkConfig.NUDPPORT;
        if ((uint8_t)stNetworkConfig.NTTL != 0) udp.ttl = (uint8_t)stNetworkConfig.NTTL;
        if (stNetworkConfig.SINTERFACEADDR.length() > 0) {
          udp.interfaceAddress = stNetworkConfig.SINTERFACEADDR.c_str();
        }
        BeeBusHostUdpTransport* socket = new (std::nothrow) BeeBusHostUdpTransport(udp);
        if (!socket) {
          if (!existing) delete node;
          later("out of memory for the link");
          return;
        }
        transport = socket;
        started = existing ? existing->rebind(socket, (uint8_t)nNodeId, &config)
                           : node->begin(socket, (uint8_t)nNodeId, config);
        if (!started) snprintf(failure, sizeof(failure), "%s",
                               node->startError() ? node->startError() : socket->lastError());
      }

      if (!started) {
        // The node does not own the transport, so both go: a retry builds new.
        // A node being re-opened stays, on its old link.
        if (!existing) delete node;
        delete transport;
        later(failure[0] == '\0' ? "the link did not open" : failure);
        return;
      }
      if (n->transport && n->transport != transport) {
        n->transport->end();
        delete n->transport;
      }
      n->transport = transport;
#endif

#if defined(BEEBUS_PLATFORM_ARDUINO)
      if (runtimeLink) {
        refuse("that eTransport needs the Runtime, not a board");
        return;
      }

      BeeBusAPI* node = existing;
      bool started = false;
      BeeBusTransport* made = nullptr;   // ours to free when replaced; a serial line is the node's

      if (link == E_BEEBUSTRANSPORT::ARDUINOSERIAL) {
        const uint32_t baud = (int32_t)stSerialConfig.NBAUD > 0
            ? (uint32_t)(int32_t)stSerialConfig.NBAUD : 115200u;
        HardwareSerial* port = bbSerialPort((uint8_t)stSerialConfig.NPORT);
        if (port == nullptr) {
          refuse("stSerialConfig.nPort is not a hardware serial on this board");
          return;
        }
        // Re-opened: the line in use is closed first - the same one at a new
        // speed or on new pins, or one this node is leaving.
        if (existing && n->openPort != 255) {
          HardwareSerial* old = bbSerialPort(n->openPort);
          if (old) old->end();
        }
#if defined(ARDUINO_ARCH_ESP32)
        // Buffers that cover a scan. This core opens a UART with 256 bytes in
        // and none out: a write then waits inside the PLC scan until the frame
        // is nearly on the wire (about 9 ms per 100 bytes at 115200), and
        // whatever arrives after the first 256 bytes of a scan is lost. Out:
        // two whole frames, so a write never waits. In: four, more than a
        // scan's worth. Both only take effect before begin().
        port->setRxBufferSize(4u * BEEBUS_MAX_WIRE_FRAME);
        port->setTxBufferSize(2u * BEEBUS_MAX_WIRE_FRAME);
        // Only this core takes the pins; elsewhere they are fixed by the board.
        if ((int16_t)stSerialConfig.NRXPIN >= 0 && (int16_t)stSerialConfig.NTXPIN >= 0) {
          port->begin(baud, SERIAL_8N1, (int16_t)stSerialConfig.NRXPIN, (int16_t)stSerialConfig.NTXPIN);
        } else {
          port->begin(baud);
        }
#else
        port->begin(baud);
#endif
        if (existing) {
          started = existing->rebind(port, (uint8_t)nNodeId, baud, &config);
        } else {
          node = new (std::nothrow) BeeBusAPI();
          if (!node) {
            later("out of memory for the node");
            return;
          }
          started = node->begin(port, (uint8_t)nNodeId, config, baud);
        }
        if (started) n->openPort = (uint8_t)stSerialConfig.NPORT;
      } else {
        BeeBusUdpConfig udp;
        if (stNetworkConfig.SGROUPADDR.length() > 0) udp.groupAddress = stNetworkConfig.SGROUPADDR.c_str();
        if ((uint16_t)stNetworkConfig.NUDPPORT != 0) udp.port = (uint16_t)stNetworkConfig.NUDPPORT;

        IPAddress group;
        group.fromString(udp.groupAddress);

        BeeBusArduinoUdpTransport* transport = nullptr;

        if (link == E_BEEBUSTRANSPORT::ARDUINOWIFI) {
#if defined(BEEBUS_HAS_WIFI)
          static WiFiUDP wifiSocket;
          if (existing) {
            // Re-opened: leave the network and the group, then join again
            // with what the settings say now.
            wifiSocket.stop();
            WiFi.disconnect();
          }
          WiFi.begin(stNetworkConfig.SSSID.c_str(), stNetworkConfig.SWIFIPASSWORD.c_str());
          wifiSocket.beginMulticast(group, udp.port);
          transport = new (std::nothrow) BeeBusArduinoUdpTransport(&wifiSocket, udp);
#else
          refuse("this board has no WiFi");
          return;
#endif
        } else {
#if defined(BEEBUS_HAS_ETHERNET)
          static EthernetUDP ethSocket;
          if (existing) ethSocket.stop();
          uint8_t mac[6] = {0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED};
          bbParseMac(stNetworkConfig.SMAC.c_str(), mac);

          IPAddress address;
          if (address.fromString(stNetworkConfig.SIP.c_str())) {
            Ethernet.begin(mac, address);
          } else {
            // DHCP blocks, and the library waits 60 s by default - on a 1 ms
            // task that is a stopped PLC. Bound it to one second and let the
            // node's own retry carry the wait. A fixed address avoids it.
            Ethernet.begin(mac, 1000, 1000);
          }
          // "No controller on the SPI bus" is wiring; "nothing plugged in" a cable.
          if (Ethernet.hardwareStatus() == EthernetNoHardware) {
            refuse("no Ethernet controller found on SPI");
            return;
          }
          ethSocket.beginMulticast(group, udp.port);
          transport = new (std::nothrow) BeeBusArduinoUdpTransport(&ethSocket, udp);
#else
          refuse("set BEEBUS_ENABLE_ETHERNET to use Ethernet");
          return;
#endif
        }

        if (!transport) {
          later("out of memory for the link");
          return;
        }
        if (existing) {
          started = existing->rebind(transport, (uint8_t)nNodeId, &config);
        } else {
          node = new (std::nothrow) BeeBusAPI();
          if (!node) {
            delete transport;
            later("out of memory for the node");
            return;
          }
          started = node->begin(transport, (uint8_t)nNodeId, config);
        }
        if (!started) delete transport;
        else made = transport;
      }

      if (!started) {
        // The reason is a string constant of the core's, so it outlives the node.
        const char* why = (node && node->startError()) ? node->startError()
                                                        : "the link did not open";
        if (!existing) delete node;
        later(why);
        return;
      }
      if (n->transport && n->transport != made) {
        n->transport->end();
        delete n->transport;
      }
      n->transport = made;
#endif

      if ((bool)bConnect) node->connect();
      n->wanted = (bool)bConnect;
      n->api = node;
      n->debug = false;

      // Open. Whatever an earlier attempt said is over.
      n->backoff = 0;
      n->linkError = false;
      n->linkResult = E_BEEBUSRESULT::OK;
      n->linkText.clear();
      bReady = true;
      n->rebind = false;
      n->settingsKey = settingsKey();
    }

    if (!(bool)bReady) return;

    BeeBusAPI* node = n->api;
    if (!node) {
      bReady = false;
      bConnected = false;
      return;
    }

    // RE-OPEN WHEN THE SETTINGS CHANGE. A change leaves the ring and opens
    // again on the new settings, on the same node: every record stays bound,
    // and peers subscribe again when it returns.
    if (settingsKey() != n->settingsKey) {
      n->rebind = true;
      n->tried = false;
      n->waiting = false;
      n->backoff = 0;
      n->changeAt = (uint32_t)bb_millis();
      node->disconnect();
      n->wanted = false;
      node->loop();
      bConnected = false;
      return;
    }

    if ((bool)bDebug != n->debug) {
      n->debug = (bool)bDebug;
      node->onDebug(n->debug ? &bb_debugLine : nullptr);
    }

    n->note.clear();
    bLinkUp = true;
#if defined(BEEBUS_PLATFORM_ARDUINO)
    const E_BEEBUSTRANSPORT link = (E_BEEBUSTRANSPORT)eTransport;
    if (link == E_BEEBUSTRANSPORT::ARDUINOWIFI) {
#if defined(BEEBUS_HAS_WIFI)
      bLinkUp = WiFi.status() == WL_CONNECTED;
      // Joining takes seconds, and is not a fault. Said while it lasts.
      if (!(bool)bLinkUp) n->note = "joining the network";
#else
      bLinkUp = false;
#endif
    } else if (link == E_BEEBUSTRANSPORT::ARDUINOETHERNET) {
#if defined(BEEBUS_HAS_ETHERNET)
      bLinkUp = Ethernet.linkStatus() != LinkOFF;
      if (!(bool)bLinkUp) {
        n->note = "Ethernet cable unplugged";
      } else if (Ethernet.localIP() == IPAddress(0, 0, 0, 0)) {
        // The cable is live but DHCP has not answered yet. Each begin() is
        // bounded, so this clears itself once a lease arrives.
        n->note = "no address from DHCP yet";
      }
#else
      bLinkUp = false;
#endif
    }
#endif

    // Acted on the edge: connect() and disconnect() every scan would restart
    // the join each time and the node would never settle.
    const bool want = (bool)bConnect;
    if (want != n->wanted) {
      n->wanted = want;
      if (want) node->connect();
      else node->disconnect();
    }

    // Once per scan. Everything the protocol does - the token, the retries,
    // the receive path - happens here.
    node->loop();
    bConnected = node->isConnected();
  }();

  // What is wrong, most fundamental first: the link, another device on this
  // id, a setting for another target, then the last failing method call.
  const char* misplaced = bb_misplaced(stSerialConfig, stNetworkConfig);
  if (!(bool)bReady && !n->linkError) {
    bLinkUp = false;
    bConnected = false;
  }
  if (n->linkError) {
    bError = true;
    eErrorId = n->linkResult;
    sLastError = n->linkText.c_str();
  } else if (n->api != nullptr && n->api->hasDuplicateNodeID()) {
    // Held while the address is in use elsewhere, and dropped when it is not.
    bError = true;
    eErrorId = E_BEEBUSRESULT::DUPLICATENODEID;
    sLastError = "another device on this segment is transmitting as nNodeId";
  } else if (misplaced != nullptr) {
    bError = true;
    eErrorId = E_BEEBUSRESULT::INVALIDARGUMENT;
    sLastError = misplaced;
  } else if (!n->failKey.empty()) {
    bError = true;
    eErrorId = n->failResult;
    sLastError = n->failText.c_str();
  } else {
    bError = false;
    eErrorId = E_BEEBUSRESULT::OK;
    sLastError = n->note.c_str();
  }
}

// =============================================================================
// THE METHODS
// =============================================================================
//
// Each runs in the caller's task and is refused in any other. The record is
// found first, so a call that cannot go yet still keeps its record. A
// method's outputs are written on every return that has a record.

// The node a method acts on, and this call's record. *result is set when
// there is none to act on yet.
static BbRecord* bb_begin(strucpp::IEC_XWORD& slot, BbNode*& n, uint8_t kind,
                          const std::string& name, const char* type,
                          const uint8_t* address, E_BEEBUSRESULT& result)
{
  n = bb_stateOf((strucpp::XWORD_t)slot);
  if (n == nullptr) {
    result = E_BEEBUSRESULT::QUEUEFULL;
    return nullptr;
  }
  slot = (strucpp::XWORD_t)(uintptr_t)n;
  if (!bb_inTask(n->task)) {
    result = E_BEEBUSRESULT::WRONGTASK;
    return nullptr;
  }
  BbRecord* r = bb_recordOf(n, kind, name, type, address);
  if (r == nullptr) result = E_BEEBUSRESULT::QUEUEFULL;
  return r;
}

// A STRING(254) name pin may have been cut to fit, and two names cut alike
// would be one topic: names are 253 characters at most, a full pin refused.
static const uint16_t BB_NAME_PIN = 254u;

// A single topic's identity check for a bound record.
static bool bb_sameIdentity(BbRecord* r, uint32_t identity, char* why, size_t cap,
                            const char* what)
{
  if (r->identity == identity) return true;
  snprintf(why, cap, "%s changed after the first call; it is taken once", what);
  return false;
}

E_BEEBUSRESULT Topic()
{
  BbNode* n = nullptr;
  char why[112] = "";
  char id[16];
  snprintf(id, sizeof id, "#%u", (unsigned)(uint16_t)nTopicId);
  const std::string rec = bb_recordName(&anyValue, id);
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_TOPIC, rec, anyValue.TYPENAME, anyValue.PVALUE, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    BeeBusAPI* node = n->api;
    if (node == nullptr) return E_BEEBUSRESULT::NOTINITIALISED;
    const uint16_t topicId = (uint16_t)nTopicId;
    const uint32_t identity = bb_fingerprintOf(bb_fingerprintText(2166136261u, sName.c_str()), topicId);
    if (!r->bound) {
      if (r->refused && r->identity == identity) {
        snprintf(why, sizeof why, "%s", r->why.c_str());
        return E_BEEBUSRESULT::INVALIDARGUMENT;
      }
      r->identity = identity;
      r->refused = true;
      // A name the wire cannot carry whole is refused rather than cut down.
      if (sName.length() == 0 || sName.length() >= BB_NAME_PIN) {
        r->why = "sName is empty or longer than 253 characters";
      } else if ((r->wire = bb_wireTypeOfClass((uint32_t)anyValue.ELEMCLASS)) == BEEBUS_T_COUNT ||
                 anyValue.TYPECLASS == strucpp::TYPE_CLASS::TYPE_ARRAY || !anyValue.wired()) {
        r->why = "anyValue is a type BeeBus does not carry as one topic";
      } else {
        // The caller's own variable, straight off the pin. A STRING is its
        // buffer: n characters and the terminator (DISIZE bytes).
        void* where = (void*)anyValue.PVALUE;
        const uint16_t textCap = (r->wire == BEEBUS_T_STRING && anyValue.DISIZE > 1)
                                     ? (uint16_t)anyValue.DISIZE : 0;
        r->topicName = sName.c_str();
        if (node->addTopicRaw(topicId, r->wire, where, false, r->topicName.c_str(), textCap)) {
          r->refused = false;
          r->bound = true;
          r->storage = where;
          r->topicId = topicId;
        } else {
          char text[96];
          snprintf(text, sizeof text, "topic %u is already bound, or its id is out of range",
                   (unsigned)topicId);
          r->why = text;
        }
      }
      if (r->refused) {
        snprintf(why, sizeof why, "%s", r->why.c_str());
        return E_BEEBUSRESULT::INVALIDARGUMENT;
      }
    }
    if (!bb_sameIdentity(r, identity, why, sizeof why, "sName or nTopicId")) {
      return E_BEEBUSRESULT::INVALIDARGUMENT;
    }
    // A variable that moved (online change) is bound again where it is now.
    if ((void*)anyValue.PVALUE != r->storage) {
      if (!node->rebindTopic(r->topicId, (void*)anyValue.PVALUE)) {
        snprintf(why, sizeof why, "anyValue moved and could not be bound again");
        return E_BEEBUSRESULT::INVALIDARGUMENT;
      }
      r->storage = (void*)anyValue.PVALUE;
    }
    return E_BEEBUSRESULT::OK;
  }();
  return bb_noteCall(n, "Topic", rec, result, why);
}

E_BEEBUSRESULT Publish()
{
  BbNode* n = nullptr;
  char why[112] = "";
  char id[16];
  snprintf(id, sizeof id, "#%u", (unsigned)(uint16_t)nTopicId);
  const std::string rec = bb_recordName(&anyValue, id);
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_PUBLISH, rec, anyValue.TYPENAME, anyValue.PVALUE, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    const bool execute = (bool)bExecute;
    const bool rising = execute && !r->lastExecute;
    r->lastExecute = execute;
    BeeBusAPI* node = n->api;
    if (node == nullptr) {
      if (rising) r->result = E_BEEBUSRESULT::NOTINITIALISED;
      return E_BEEBUSRESULT::NOTINITIALISED;
    }

    const uint16_t topicId = (uint16_t)nTopicId;
    const uint32_t identity = bb_fingerprintOf(bb_fingerprintText(2166136261u, sName.c_str()), topicId);
    if (!r->bound) {
      if (r->refused && r->identity == identity) {
        snprintf(why, sizeof why, "%s", r->why.c_str());
        return E_BEEBUSRESULT::INVALIDARGUMENT;
      }
      r->identity = identity;
      r->refused = true;
      if (sName.length() == 0 || sName.length() >= BB_NAME_PIN) {
        r->why = "sName is empty or longer than 253 characters";
      } else if ((r->wire = bb_wireTypeOfClass((uint32_t)anyValue.ELEMCLASS)) == BEEBUS_T_COUNT ||
                 anyValue.TYPECLASS == strucpp::TYPE_CLASS::TYPE_ARRAY || !anyValue.wired()) {
        r->why = "anyValue is a type BeeBus does not carry as one topic";
      } else {
        // A STRING topic is bound to a std::string, which the variable is not.
        if (r->wire == BEEBUS_T_STRING && r->text == nullptr) r->text = new (std::nothrow) std::string();
        void* where = r->wire == BEEBUS_T_STRING ? (void*)r->text : (void*)anyValue.PVALUE;
        // Topic may already own it, which is not an error: this only sends it.
        r->topicName = sName.c_str();
        if (where != nullptr &&
            (node->addTopicRaw(topicId, r->wire, where, false, r->topicName.c_str()) ||
             node->topicIdOf(r->topicName.c_str()) == topicId)) {
          r->refused = false;
          r->bound = true;
          r->storage = where;
          r->topicId = topicId;
        } else {
          char text[96];
          snprintf(text, sizeof text, "topic %u is already bound under another name", (unsigned)topicId);
          r->why = where == nullptr ? std::string("out of memory for the text") : std::string(text);
        }
      }
      if (r->refused) {
        snprintf(why, sizeof why, "%s", r->why.c_str());
        if (rising) r->result = E_BEEBUSRESULT::INVALIDARGUMENT;
        return E_BEEBUSRESULT::INVALIDARGUMENT;
      }
    }
    if (!bb_sameIdentity(r, identity, why, sizeof why, "sName or nTopicId")) {
      return E_BEEBUSRESULT::INVALIDARGUMENT;
    }
    // A variable that moved is bound again where it is now.
    if (r->wire != BEEBUS_T_STRING && (void*)anyValue.PVALUE != r->storage) {
      if (node->rebindTopic(r->topicId, (void*)anyValue.PVALUE)) r->storage = (void*)anyValue.PVALUE;
    }
    // This node owns the topic: the variable is the truth, the copy follows.
    if (r->wire == BEEBUS_T_STRING && r->text != nullptr && anyValue.PVALUE != nullptr) {
      r->text->assign((const char*)anyValue.PVALUE);
    }

    if (r->pending) {
      BeeBusResult outcome = BeeBusResult::Immediate;
      const BeeBusRequestState state = node->requestState(r->target, r->topicId, outcome);
      if (state == BeeBusRequestState::Pending) return E_BEEBUSRESULT::QUEUED;
      r->pending = false;
      r->result = state == BeeBusRequestState::Done ? E_BEEBUSRESULT::OK
                : bb_accepted(outcome) ? E_BEEBUSRESULT::TIMEOUT : bb_resultOf(outcome);
    }
    if (!rising) return r->result;

    // A start: the inputs as they are now.
    const bool toPeer = (E_BEEBUSPUBLISHMODE)ePublishMode == E_BEEBUSPUBLISHMODE::TOPEER;
    const BeeBusDelivery delivery = (bool)bConfirmed ? BeeBusDelivery::Confirmed
                                                     : BeeBusDelivery::Unconfirmed;
    // Which peer the operation waits on, so a broadcast and a publish to one
    // node keep their own outstanding operation.
    r->target = toPeer ? (uint8_t)nPeer : BEEBUS_NODE_BROADCAST;
    const BeeBusResult asked = toPeer ? node->publishTo((uint8_t)nPeer, r->topicId, delivery)
                                      : node->publishAll(r->topicId, delivery);
    if (!bb_accepted(asked) && asked != BeeBusResult::Duplicate) {
      r->result = bb_resultOf(asked);
      return r->result;
    }
    // Unconfirmed, nothing waits: it went to the token at the call.
    if (delivery == BeeBusDelivery::Confirmed) {
      r->pending = true;
      r->result = E_BEEBUSRESULT::QUEUED;
    } else {
      r->result = E_BEEBUSRESULT::OK;
    }
    return r->result;
  }();
  return bb_noteCall(n, "Publish", rec, result, why);
}

E_BEEBUSRESULT Subscribe()
{
  BbNode* n = nullptr;
  char why[112] = "";
  char id[24];
  snprintf(id, sizeof id, "%u#%u", (unsigned)(uint8_t)nPeer, (unsigned)(uint16_t)nTopicId);
  const std::string rec = bb_recordName(&anyValue, id);
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_SUBSCRIBE, rec, anyValue.TYPENAME, anyValue.PVALUE, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    bNewValue = false;
    nMissed = r->missed;
    BeeBusAPI* node = n->api;
    if (node == nullptr) {
      eQuality = E_BEEBUSQUALITY::UNKNOWN;
      return E_BEEBUSRESULT::NOTINITIALISED;
    }
    const uint8_t peer = (uint8_t)nPeer;
    const uint16_t topicId = (uint16_t)nTopicId;
    const uint32_t identity = bb_fingerprintOf(bb_fingerprintOf(
        bb_fingerprintText(2166136261u, sName.c_str()), topicId), peer);
    if (!r->bound) {
      if (r->refused && r->identity == identity) {
        snprintf(why, sizeof why, "%s", r->why.c_str());
        return E_BEEBUSRESULT::INVALIDARGUMENT;
      }
      r->identity = identity;
      r->refused = true;
      if (sName.length() == 0 || sName.length() >= BB_NAME_PIN) {
        r->why = "sName is empty or longer than 253 characters";
      } else if ((r->wire = bb_wireTypeOfClass((uint32_t)anyValue.ELEMCLASS)) == BEEBUS_T_COUNT ||
                 anyValue.TYPECLASS == strucpp::TYPE_CLASS::TYPE_ARRAY || !anyValue.wired()) {
        r->why = "anyValue is a type BeeBus does not carry as one topic";
      } else {
        // The caller's own variable, and a peer's value arrives in it. A
        // STRING is its buffer; longer text is cut to fit.
        void* where = (void*)anyValue.PVALUE;
        const uint16_t textCap = (r->wire == BEEBUS_T_STRING && anyValue.DISIZE > 1)
                                     ? (uint16_t)anyValue.DISIZE : 0;
        r->topicName = sName.c_str();
        if (node->registerTopicRaw(peer, topicId, r->wire, where, r->topicName.c_str(), textCap)) {
          r->refused = false;
          r->bound = true;
          r->storage = where;
          r->topicId = topicId;
          r->peer = peer;
        } else {
          char text[96];
          snprintf(text, sizeof text, "topic %u of node %u is already bound, or out of range",
                   (unsigned)topicId, (unsigned)peer);
          r->why = text;
        }
      }
      if (r->refused) {
        snprintf(why, sizeof why, "%s", r->why.c_str());
        return E_BEEBUSRESULT::INVALIDARGUMENT;
      }
    }
    if (!bb_sameIdentity(r, identity, why, sizeof why, "nPeer, sName or nTopicId")) {
      return E_BEEBUSRESULT::INVALIDARGUMENT;
    }
    if ((void*)anyValue.PVALUE != r->storage) {
      r->storage = (void*)anyValue.PVALUE;
      node->rebindRemoteTopic(r->peer, r->topicId, (void*)anyValue.PVALUE);
    }

    E_BEEBUSRESULT outcome = E_BEEBUSRESULT::OK;
#if BEEBUS_TOPIC_NAMES
    // Asked for once, and again when the terms change. A subscription is a
    // standing intent: the protocol holds it until the peer is in the ring
    // and re-establishes it if the peer restarts.
    const float deadband = (float)fDeadband;
    const int32_t interval = bb_millisOf(tPeriod);
    const bool reliable = (bool)bReliable;
    if (!r->issued || r->askedDeadband != deadband || r->askedInterval != interval ||
        r->askedReliable != reliable) {
      const BeeBusResult asked = node->subscribe(r->peer, r->topicId, deadband, (bb_time_t)interval,
                                                 reliable ? BeeBusQoS::Reliable : BeeBusQoS::Live);
      r->issued = bb_accepted(asked) || asked == BeeBusResult::Duplicate;
      r->askedDeadband = deadband;
      r->askedInterval = interval;
      r->askedReliable = reliable;
      if (!r->issued) outcome = bb_resultOf(asked);
    }
    eQuality = (E_BEEBUSQUALITY)node->topicQuality(r->peer, r->topicId);
    const bb_time_t age = node->topicAge(r->peer, r->topicId);
    tAge = bb_timeOf(age == BEEBUS_SILENCE_NEVER ? 0 : (int32_t)age);
    bSeen = age != BEEBUS_SILENCE_NEVER;
#else
    snprintf(why, sizeof why, "this build has no topic names (BEEBUS_TOPIC_NAMES)");
    outcome = E_BEEBUSRESULT::INVALIDARGUMENT;
#endif
    // The node counts publishes and gaps; the record keeps what it last saw,
    // so two calls watching one topic do not take each other's arrivals.
    BeeBusTopicStream stream;
    if (node->topicStream(r->peer, r->topicId, stream)) {
      bNewValue = stream.received != r->seenReceived;
      r->missed += (uint16_t)(stream.missed - r->seenMissed);
      r->seenReceived = stream.received;
      r->seenMissed = stream.missed;
    }
    nMissed = r->missed;
    return outcome;
  }();
  return bb_noteCall(n, "Subscribe", rec, result, why);
}

// A STRUCT record's list of values, built and bound on the first call the
// node is there, through `bind`. A refusal stands until what the record is
// changes. False, with the reason in `why`, while it is not bound.
template <typename Bind>
static bool bb_planRecord(BbRecord* r, const strucpp::IEC_ANY& any, uint32_t identity,
                          bool bits, char* why, size_t cap, Bind bind)
{
  if (r->bound) {
    if (r->identity != identity) {
      snprintf(why, cap, "what it is bound as (topic, prefix, peer, table, address) changed "
                         "after the first call");
      return false;
    }
    if (bb_planMoved(r->plan, any)) {
      snprintf(why, cap, "anyData moved: wire the same variable every scan");
      return false;
    }
    return true;
  }
  if (r->refused && r->identity == identity) {
    snprintf(why, cap, "%s", r->why.c_str());
    return false;
  }
  r->identity = identity;
  char reason[112] = "";
  void* made = bb_planBuild(any, bits, reason, sizeof reason);
  if (made == nullptr || !bind(made, reason, sizeof reason)) {
    // A plan whose bind was undone is not the node's; one that bound and then
    // failed further on is kept, since the node points into it.
    if (made != nullptr) bb_planFree(made);
    r->refused = true;
    r->why = reason;
    snprintf(why, cap, "%s", reason);
    return false;
  }
  r->refused = false;
  r->bound = true;
  r->plan = made;
  r->members = (uint16_t)bb_planLeaves(made);
  return true;
}

static uint32_t bb_structIdentity(uint16_t topicId, const char* prefix, uint8_t peer, uint32_t flags)
{
  uint32_t h = bb_fingerprintOf(2166136261u, topicId);
  h = bb_fingerprintText(h, prefix);
  h = bb_fingerprintOf(h, peer);
  return bb_fingerprintOf(h, flags);
}

E_BEEBUSRESULT PublishStruct()
{
  BbNode* n = nullptr;
  char why[112] = "";
  char id[16];
  snprintf(id, sizeof id, "#%u", (unsigned)(uint16_t)nTopicId);
  const std::string rec = bb_recordName(&anyData, id);
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_PUBLISH_STRUCT, rec, anyData.TYPENAME, anyData.PVALUE, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    auto done = [&](E_BEEBUSRESULT value) -> E_BEEBUSRESULT {
      nMembers = r->members;
      nWritten = r->heldCount;
      sWrittenName = r->heldName.c_str();
      nWrittenIndex = r->heldIndex;
      nWrittenBy = r->heldBy;
      nLost = r->lost;
      return value;
    };
    bWritten = false;
    BeeBusAPI* node = n->api;
    if (node == nullptr) return done(E_BEEBUSRESULT::NOTINITIALISED);
    const bool writable = (bool)bWritable;
    const uint32_t identity = bb_structIdentity((uint16_t)nTopicId, sPrefix.c_str(), 0, writable);
    const bool ok = bb_planRecord(r, anyData, identity, false, why, sizeof why,
        [&](void* plan, char* reason, size_t cap) {
          return bb_planBindTopicsEx(plan, node, false, 0, (uint16_t)nTopicId, sPrefix.c_str(),
                                     writable, reason, cap) &&
                 (!writable || bb_planQueueWrites(plan, node, reason, cap));
        });
    if (!ok) return done(E_BEEBUSRESULT::INVALIDARGUMENT);

    // Peers' writes waiting in the node's queue: one per member, oldest
    // first, into the variable before the copies below follow it.
    uint32_t first = 0, lost = 0;
    uint8_t by = 0;
    const int32_t pulse = bb_millisOf(tPulse);
    const int32_t settle = bb_millisOf(tSettle);
    bb_planServeTerms(r->plan, (uint32_t)(settle > 0 ? settle : 0), false);
    const uint32_t taken = bb_planTakeWrites(r->plan, (uint32_t)(pulse > 0 ? pulse : 0), &first, &by, &lost);
    r->lost += lost;
    if (taken > 0) {
      char name[65] = "";
      bb_planLeafInfo(r->plan, first, name, sizeof name, nullptr);
      bWritten = true;
      r->heldCount = (uint16_t)taken;
      r->heldName = name;
      r->heldIndex = (uint16_t)(first + 1);
      r->heldBy = by;
    }
    // The topics are bound to the members themselves; a TIME, a DT or a DATE
    // goes through a copy in its wire form, brought up to date here, so the
    // node publishes what the program holds as of this scan.
    bb_planPublishSync(r->plan);
    return done(E_BEEBUSRESULT::OK);
  }();
  return bb_noteCall(n, "PublishStruct", rec, result, why);
}

E_BEEBUSRESULT Serve()
{
  BbNode* n = nullptr;
  char why[112] = "";
  char id[16];
  snprintf(id, sizeof id, "#%u", (unsigned)(uint16_t)nTopicId);
  const std::string rec = bb_recordName(&anyData, id);
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_SERVE, rec, anyData.TYPENAME, anyData.PVALUE, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    auto done = [&](E_BEEBUSRESULT value) -> E_BEEBUSRESULT {
      nMembers = r->members;
      nChanged = r->heldCount;
      sChangedName = r->heldName.c_str();
      nChangedIndex = r->heldIndex;
      nChangedBy = r->heldBy;
      nRefused = r->refusedCount;
      nLost = r->lost;
      return value;
    };
    bChanged = false;
    BeeBusAPI* node = n->api;
    if (node == nullptr) return done(E_BEEBUSRESULT::NOTINITIALISED);
    const bool writable = (bool)bWritable;
    const bool ok = bb_planRecord(r, anyData,
        bb_structIdentity((uint16_t)nTopicId, sPrefix.c_str(), 0, writable ? 1u : 0u),
        false, why, sizeof why,
        [&](void* plan, char* reason, size_t cap) {
          return bb_planBindTopicsEx(plan, node, false, 0, (uint16_t)nTopicId, sPrefix.c_str(),
                                     writable, reason, cap) &&
                 (!writable || bb_planQueueWrites(plan, node, reason, cap));
        });
    if (!ok) return done(E_BEEBUSRESULT::INVALIDARGUMENT);

    // The ring's depth may change while it runs; 127 at most.
    const uint8_t depth = (uint8_t)nDepth > 127 ? 127 : (uint8_t)nDepth;
    if (!r->depthSet || r->depth != depth) {
      char reason[96] = "";
      if (!bb_planBuffer(r->plan, node, depth, reason, sizeof reason) && depth > 0) {
        snprintf(why, sizeof why, "%s", reason);
        return done(E_BEEBUSRESULT::INVALIDARGUMENT);
      }
      if (depth == 0 && r->depthSet) {
        for (uint32_t k = 0; k < r->members; k++) node->bufferTopic((uint16_t)(nTopicId + k), 0);
      }
      r->depthSet = true;
      r->depth = depth;
    }

    // Peers' changes waiting in the node's queue: one per member, oldest
    // first, into the variable. Each is answered once the program has run
    // with it.
    uint32_t first = 0, lost = 0;
    uint8_t by = 0;
    const int32_t pulse = bb_millisOf(tPulse);
    const int32_t settle = bb_millisOf(tSettle);
    bb_planServeTerms(r->plan, (uint32_t)(settle > 0 ? settle : 0), (bool)bCommand);
    const uint32_t taken = bb_planTakeWrites(r->plan, (uint32_t)(pulse > 0 ? pulse : 0), &first, &by, &lost);
    r->lost += lost;
    if (taken > 0) {
      char name[65] = "";
      bb_planLeafInfo(r->plan, first, name, sizeof name, nullptr);
      bChanged = true;
      r->heldCount = (uint16_t)taken;
      r->heldName = name;
      r->heldIndex = (uint16_t)(first + 1);
      r->heldBy = by;
    }
    r->refusedCount += bb_planTakeRefused(r->plan);
    // A TIME, a DT or a DATE goes through a copy in its wire form, brought up
    // to date here, so the node serves what the program holds this scan.
    bb_planPublishSync(r->plan);
    return done(E_BEEBUSRESULT::OK);
  }();
  return bb_noteCall(n, "Serve", rec, result, why);
}

E_BEEBUSRESULT SubscribeStruct()
{
  BbNode* n = nullptr;
  char why[112] = "";
  char id[24];
  snprintf(id, sizeof id, "%u#%u", (unsigned)(uint8_t)nPeer, (unsigned)(uint16_t)nTopicId);
  const std::string rec = bb_recordName(&anyData, id);
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_SUBSCRIBE_STRUCT, rec, anyData.TYPENAME, anyData.PVALUE, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    auto done = [&](E_BEEBUSRESULT value) -> E_BEEBUSRESULT {
      nMembers = r->members;
      sNewName = r->heldName.c_str();
      nNewIndex = r->heldIndex;
      nMissed = r->missed;
      return value;
    };
    nNewValues = 0;
    BeeBusAPI* node = n->api;
    if (node == nullptr) {
      eQuality = E_BEEBUSQUALITY::UNKNOWN;
      return done(E_BEEBUSRESULT::NOTINITIALISED);
    }
    const uint8_t peer = (uint8_t)nPeer;
    const bool ok = bb_planRecord(r, anyData,
        bb_structIdentity((uint16_t)nTopicId, sPrefix.c_str(), peer, 0), false, why, sizeof why,
        [&](void* plan, char* reason, size_t cap) {
          return bb_planBindTopics(plan, node, true, peer, (uint16_t)nTopicId, sPrefix.c_str(),
                                   reason, cap);
        });
    if (!ok) return done(E_BEEBUSRESULT::INVALIDARGUMENT);

    // Asked for member by member until all are, a queue's worth a scan, and
    // again for every member when the terms change. The protocol holds each
    // subscription until the peer is in the ring and re-issues it when the
    // peer restarts.
    E_BEEBUSRESULT outcome = E_BEEBUSRESULT::OK;
    const float deadband = (float)fDeadband;
    const int32_t interval = bb_millisOf(tPeriod);
    const bool reliable = (bool)bReliable;
    const bool again = r->issued && (r->askedDeadband != deadband || r->askedInterval != interval ||
                                     r->askedReliable != reliable);
    if (!r->issued || again) {
      BeeBusResult last = BeeBusResult::Immediate;
      const uint32_t pending = bb_planSubscribe(r->plan, node, deadband, interval, again, &last, reliable);
      r->askedDeadband = deadband;
      r->askedInterval = interval;
      r->askedReliable = reliable;
      r->issued = pending == 0;
      if (pending != 0 && last != BeeBusResult::QueueFull) {
        snprintf(why, sizeof why, "a member's subscription was refused");
        outcome = bb_resultOf(last);
      }
    }

    uint32_t fresh = 0, first = 0, gaps = 0;
    uint8_t worst = 0;
    bool all = false;
    int32_t oldest = 0;
    bb_planReceive(r->plan, node, &fresh, &first, &gaps, &worst, &all, &oldest);
    eQuality = (E_BEEBUSQUALITY)worst;
    bSeen = all;
    tOldest = bb_timeOf(oldest);
    nNewValues = (uint16_t)fresh;
    if (fresh != 0) {
      char name[65] = "";
      bb_planLeafInfo(r->plan, first, name, sizeof name, nullptr);
      r->heldName = name;
      r->heldIndex = (uint16_t)(first + 1);
    }
    r->missed += gaps;
    return done(outcome);
  }();
  return bb_noteCall(n, "SubscribeStruct", rec, result, why);
}

E_BEEBUSRESULT Bind()
{
  BbNode* n = nullptr;
  char why[112] = "";
  char id[24];
  snprintf(id, sizeof id, "%u#%u", (unsigned)(uint8_t)nPeer, (unsigned)(uint16_t)nTopicId);
  const std::string rec = bb_recordName(&anyData, id);
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_BIND, rec, anyData.TYPENAME, anyData.PVALUE, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    auto done = [&](E_BEEBUSRESULT value) -> E_BEEBUSRESULT {
      nMembers = r->members;
      sRefusedName = r->heldName.c_str();
      nRefusedIndex = r->heldIndex;
      return value;
    };
    bNewValue = false;
    BeeBusAPI* node = n->api;
    if (node == nullptr) {
      eBindState = E_BEEBUSBINDSTATE::OFFLINE;
      return done(E_BEEBUSRESULT::NOTINITIALISED);
    }
    const uint8_t peer = (uint8_t)nPeer;
    const bool reliable = (bool)bReliable;
    const float deadband = (float)fDeadband;
    uint32_t terms = reliable ? 1u : 0u;
    terms = bb_fingerprintOf(terms, deadband);
    const bool ok = bb_planRecord(r, anyData,
        bb_structIdentity((uint16_t)nTopicId, sPrefix.c_str(), peer, terms), false, why, sizeof why,
        [&](void* plan, char* reason, size_t cap) {
          return bb_planBind(plan, node, peer, (uint16_t)nTopicId, sPrefix.c_str(), reliable,
                             deadband, reason, cap);
        });
    if (!ok) return done(E_BEEBUSRESULT::INVALIDARGUMENT);

    // A TIME, a DT or a DATE member goes through a copy in its wire form,
    // both ways: the owner's value into the member, the program's change into
    // the copy for the bind to send.
    bb_planBindSync(r->plan);

    uint8_t worst = (uint8_t)BeeBusBindState::Offline;
    uint32_t pending = 0, refused = 0, failed = 0, firstRefused = 0;
    bool allInSync = false;
    bb_planBindStatus(r->plan, node, &worst, &pending, &refused, &failed, &firstRefused, &allInSync);
    eBindState = (E_BEEBUSBINDSTATE)(int32_t)worst;
    bInSync = allInSync;
    bPending = pending > 0;
    bFailed = failed > 0;
    bRefused = refused > 0;
    if (refused > 0 && (!r->wasRefused || r->heldIndex != (uint16_t)(firstRefused + 1))) {
      char name[65] = "";
      bb_planLeafInfo(r->plan, firstRefused, name, sizeof name, nullptr);
      r->heldName = name;
      r->heldIndex = (uint16_t)(firstRefused + 1);
    }
    r->wasRefused = refused > 0;

    uint32_t fresh = 0, firstNew = 0, missed = 0;
    uint8_t quality = 0;
    bool allSeen = false;
    int32_t oldest = 0;
    bb_planReceive(r->plan, node, &fresh, &firstNew, &missed, &quality, &allSeen, &oldest);
    bNewValue = fresh > 0;
    tOldest = bb_timeOf(oldest);
    return done(E_BEEBUSRESULT::OK);
  }();
  return bb_noteCall(n, "Bind", rec, result, why);
}

E_BEEBUSRESULT Write()
{
  BbNode* n = nullptr;
  char why[112] = "";
  char id[24];
  snprintf(id, sizeof id, "%u#%u", (unsigned)(uint8_t)nPeer, (unsigned)(uint16_t)nTopicId);
  const std::string rec = bb_recordName(&anyValue, id);
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_WRITE, rec, anyValue.TYPENAME, anyValue.PVALUE, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    auto done = [&](E_BEEBUSRESULT value) -> E_BEEBUSRESULT {
      eOutcome = (E_BEEBUSOUTCOME)(int32_t)(r->outcome < BEEBUS_OUTCOME_COUNT ? r->outcome
                                                                             : BEEBUS_OUTCOME_COUNT);
      bAccepted = r->accepted;
      bRefused = r->refusedValue;
      fKeptValue = r->kept;
      return value;
    };
    const bool execute = (bool)bExecute;
    const bool rising = execute && !r->lastExecute;
    r->lastExecute = execute;
    BeeBusAPI* node = n->api;
    if (node == nullptr) {
      if (rising) r->result = E_BEEBUSRESULT::NOTINITIALISED;
      return done(E_BEEBUSRESULT::NOTINITIALISED);
    }

    if (r->pending) {
      BeeBusResult outcome = BeeBusResult::Immediate;
      const BeeBusRequestState state = node->requestState(r->peer, r->topicId, outcome);
      // With a result asked for, it waits for the owner's decision, which
      // follows the acknowledgement; the protocol gives up on it by itself.
      if (r->waitingResult && state != BeeBusRequestState::Failed) {
        uint8_t decided = BEEBUS_OUTCOME_NONE;
        BeeBusScalar kept;
        uint16_t count = 0;
        if (!node->topicResult(r->peer, r->topicId, decided, kept, count) || count == r->resultCount) {
          return done(E_BEEBUSRESULT::QUEUED);
        }
        r->pending = false;
        r->waitingResult = false;
        r->outcome = decided < BEEBUS_OUTCOME_COUNT ? decided : (uint8_t)BEEBUS_OUTCOME_COUNT;
        r->accepted = decided == BEEBUS_OUTCOME_ACCEPTED;
        r->refusedValue = decided == BEEBUS_OUTCOME_CHANGED || decided == BEEBUS_OUTCOME_REFUSED;
        r->kept = bb_topicTypeIsString(kept.type) ? 0.0 : bb_scalarToDouble(kept);
        const bool decision = decided == BEEBUS_OUTCOME_ACCEPTED ||
                              decided == BEEBUS_OUTCOME_CHANGED ||
                              decided == BEEBUS_OUTCOME_REFUSED;
        r->result = decision ? E_BEEBUSRESULT::OK : E_BEEBUSRESULT::TIMEOUT;
      } else if (state == BeeBusRequestState::Pending) {
        return done(E_BEEBUSRESULT::QUEUED);
      } else {
        r->pending = false;
        r->waitingResult = false;
        r->result = state == BeeBusRequestState::Done ? E_BEEBUSRESULT::OK
                  : bb_accepted(outcome) ? E_BEEBUSRESULT::TIMEOUT : bb_resultOf(outcome);
      }
    }
    if (!rising) return done(r->result);

    // A start: the inputs as they are now.
    r->peer = (uint8_t)nPeer;
    r->topicId = (uint16_t)nTopicId;
    const uint8_t wire = bb_wireTypeOfClass((uint32_t)anyValue.ELEMCLASS);
    if (wire == BEEBUS_T_COUNT || anyValue.TYPECLASS == strucpp::TYPE_CLASS::TYPE_ARRAY ||
        r->topicId == 0 || !anyValue.wired()) {
      snprintf(why, sizeof why, "anyValue is not one value BeeBus carries, or nTopicId is 0");
      r->result = E_BEEBUSRESULT::INVALIDARGUMENT;
      return done(r->result);
    }
    // A result is asked for only of a confirmed write: the decision answers a
    // request that arrived.
    const bool wantResult = (bool)bWantResult;
    const BeeBusDelivery delivery = ((bool)bConfirmed || wantResult) ? BeeBusDelivery::Confirmed
                                                                     : BeeBusDelivery::Unconfirmed;
    if (wantResult) {
      uint8_t decided = 0;
      BeeBusScalar kept;
      uint16_t count = 0;
      node->topicResult(r->peer, r->topicId, decided, kept, count);
      r->resultCount = count;
    }
    const BeeBusResult asked =
        wire == BEEBUS_T_STRING
            ? node->writeTopic(r->peer, r->topicId, (const char*)anyValue.PVALUE, delivery, wantResult)
            : node->writeTopicRaw(r->peer, r->topicId, bb_scalarLoad(wire, (const void*)anyValue.PVALUE),
                                  delivery, wantResult);
    if (!bb_accepted(asked) && asked != BeeBusResult::Duplicate) {
      r->result = bb_resultOf(asked);
      return done(r->result);
    }
    r->outcome = BEEBUS_OUTCOME_COUNT;
    r->accepted = false;
    r->refusedValue = false;
    r->kept = 0.0;
    if (delivery == BeeBusDelivery::Confirmed) {
      r->pending = true;
      r->waitingResult = wantResult;
      r->result = E_BEEBUSRESULT::QUEUED;
    } else {
      r->result = E_BEEBUSRESULT::OK;
    }
    return done(r->result);
  }();
  return bb_noteCall(n, "Write", rec, result, why);
}

E_BEEBUSRESULT Buffer()
{
  BbNode* n = nullptr;
  char why[112] = "";
  const std::string rec = bb_recordName(nullptr, sName.c_str());
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_BUFFER, rec, "", nullptr, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    nHeld = 0;
    BeeBusAPI* node = n->api;
    if (node == nullptr) return E_BEEBUSRESULT::NOTINITIALISED;
#if BEEBUS_TOPIC_NAMES
    // Topic or Publish binds the topic; this only asks for a depth.
    const uint16_t topicId = node->topicIdOf(sName.c_str());
    if (topicId == BEEBUS_TOPIC_NONE) {
      snprintf(why, sizeof why, "no topic of this node is named so");
      r->depthSet = false;
      return E_BEEBUSRESULT::NOTMAPPED;
    }
    const uint8_t depth = (uint8_t)nDepth;
    if (!r->depthSet || r->depth != depth || r->topicId != topicId) {
      if (!node->bufferTopic(topicId, depth)) {
        snprintf(why, sizeof why, "no memory for a ring of %u", (unsigned)depth);
        return E_BEEBUSRESULT::INVALIDARGUMENT;
      }
      r->depthSet = true;
      r->depth = depth;
      r->topicId = topicId;
    }
    nHeld = (uint16_t)node->bufferedCount(topicId);
    return E_BEEBUSRESULT::OK;
#else
    snprintf(why, sizeof why, "this build has no topic names (BEEBUS_TOPIC_NAMES)");
    return E_BEEBUSRESULT::NOTMAPPED;
#endif
  }();
  return bb_noteCall(n, "Buffer", rec, result, why);
}

E_BEEBUSRESULT ModbusMap()
{
  BbNode* n = nullptr;
  char why[112] = "";
  char id[24];
  snprintf(id, sizeof id, "@%d:%u", (int)(E_BEEBUSMODBUSTABLE)eTable, (unsigned)(uint16_t)nAddress);
  const std::string rec = bb_recordName(&anyData, id);
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_MODBUS_MAP, rec, anyData.TYPENAME, anyData.PVALUE, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    auto done = [&](E_BEEBUSRESULT value) -> E_BEEBUSRESULT {
      nCount = r->members;
      sWrittenName = r->heldName.c_str();
      nWrittenIndex = r->heldIndex;
      nWrittenAddr = r->heldAddress;
      nWritten = r->heldCount;
      return value;
    };
    bWritten = false;
    bSafeApplied = false;
    BeeBusAPI* node = n->api;
    if (node == nullptr) return done(E_BEEBUSRESULT::NOTINITIALISED);
    const BeeBusRegisterType table = (BeeBusRegisterType)(int)(E_BEEBUSMODBUSTABLE)eTable;
    const uint16_t address = (uint16_t)nAddress;
    const bool resetOnLoss = (E_BEEBUSMODBUSFAILSAFE)eOnLoss == E_BEEBUSMODBUSFAILSAFE::RESETTOVALUE;
    const int32_t safe = (int32_t)nSafeValue;
    uint32_t identity = bb_fingerprintOf(bb_fingerprintOf(2166136261u, (int32_t)table), address);
    identity = bb_fingerprintOf(bb_fingerprintOf(identity, resetOnLoss), safe);
    const bool ok = bb_planRecord(r, anyData, identity, bb_tableIsBits(table), why, sizeof why,
        [&](void* plan, char* reason, size_t cap) {
          if (!bb_planBindRegisters(plan, node, table, address, reason, cap)) return false;
          // The safe state is per address, and only a writable table has one.
          // Only a single number has one value to go to: a STRUCT, an array
          // or a string is left holding what it held.
          uint8_t wire = 0;
          if (resetOnLoss && bb_tableIsWritable(table) && bb_planSingle(plan, &wire)) {
            if (bb_tableIsBits(table)) {
              node->setCoilFailsafe(address, BeeBusFailsafe::ResetToValue, safe != 0);
            } else {
              // The safe value in the member's own type, then its register
              // image: nSafeValue := 5 on a REAL is 5.0, not the bits of 5.
              uint8_t image[8] = {0, 0, 0, 0, 0, 0, 0, 0};
              switch (wire) {
                case BEEBUS_T_F64: { const double f = (double)safe; memcpy(image, &f, 8); break; }
                case BEEBUS_T_I64:
                case BEEBUS_T_U64: { const int64_t s = (int64_t)safe; memcpy(image, &s, 8); break; }
                case BEEBUS_T_F32: { const float f = (float)safe; memcpy(image, &f, 4); break; }
                case BEEBUS_T_I32:
                case BEEBUS_T_U32: memcpy(image, &safe, 4); break;
                case BEEBUS_T_I16:
                case BEEBUS_T_U16: { const int16_t s = (int16_t)safe; memcpy(image, &s, 2); break; }
                default: { const int8_t s = (int8_t)safe; memcpy(image, &s, 1); break; }
              }
              const uint8_t words = bb_registersOf(wire);
              for (uint8_t w = 0; w < words; w++) {
                node->setHregFailsafe((uint16_t)(address + w), BeeBusFailsafe::ResetToValue,
                                      (int16_t)bb_valueRegister(image, wire, w));
              }
            }
          }
          return true;
        });
    if (!ok) return done(E_BEEBUSRESULT::INVALIDARGUMENT);
    if (!r->mapped) {
      // Counted once, after the bind: registers (or coils), not values.
      r->mapped = true;
      r->members = (uint16_t)bb_planRegisters(r->plan);
      r->address = address;
      r->bits = bb_tableIsBits(table);
      r->target = (uint8_t)table;
      r->seenFailsafe = node->failsafeCount(table, address);
    }

    // What peers wrote since the last call. The names and addresses hold
    // until the next write.
    uint32_t first = 0;
    const uint16_t written = bb_planServe(r->plan, node, &first);
    if (written != 0) {
      char name[65] = "";
      uint32_t offset = 0;
      bb_planLeafInfo(r->plan, first, name, sizeof name, &offset);
      bWritten = true;
      r->heldName = name;
      r->heldIndex = (uint16_t)(first + 1);
      r->heldAddress = (uint16_t)(r->address + offset);
      r->heldCount = written;
    }
    const uint16_t safed = node->failsafeCount((BeeBusRegisterType)r->target, r->address);
    bSafeApplied = safed != r->seenFailsafe;
    r->seenFailsafe = safed;
    return done(E_BEEBUSRESULT::OK);
  }();
  return bb_noteCall(n, "ModbusMap", rec, result, why);
}

// A finished Modbus request, polled. True once it has ended, *result its end.
static bool bb_modbusDone(BeeBusAPI* node, BbRecord* r, bool read, E_BEEBUSRESULT& result)
{
  BeeBusResult outcome = BeeBusResult::Immediate;
  const BeeBusRequestState state = node->requestState(r->peer, r->address, outcome);
  if (state == BeeBusRequestState::Pending) return false;
  r->pending = false;
  result = state == BeeBusRequestState::Done ? E_BEEBUSRESULT::OK
         : bb_accepted(outcome) ? E_BEEBUSRESULT::TIMEOUT : bb_resultOf(outcome);
  // The answers arrive in the record's own buffer and are unpacked here, in
  // the scan, so the program never sees half a value. A register holding a
  // number its member cannot (300 for a USINT) leaves that member as it was.
  if (read && result == E_BEEBUSRESULT::OK && r->plan != nullptr && !bb_planReadDone(r->plan, r->bits)) {
    result = E_BEEBUSRESULT::TYPEMISMATCH;
  }
  return true;
}

E_BEEBUSRESULT ModbusRead()
{
  BbNode* n = nullptr;
  char why[112] = "";
  char id[24];
  snprintf(id, sizeof id, "%u@%u", (unsigned)(uint8_t)nPeer, (unsigned)(uint16_t)nAddress);
  const std::string rec = bb_recordName(&anyData, id);
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_MODBUS_READ, rec, anyData.TYPENAME, anyData.PVALUE, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    const bool execute = (bool)bExecute;
    const bool rising = execute && !r->lastExecute;
    r->lastExecute = execute;
    BeeBusAPI* node = n->api;
    if (node == nullptr) {
      if (rising) r->result = E_BEEBUSRESULT::NOTINITIALISED;
      return E_BEEBUSRESULT::NOTINITIALISED;
    }
    if (r->pending) {
      if (!bb_modbusDone(node, r, true, r->result)) return E_BEEBUSRESULT::QUEUED;
    }
    if (!rising) return r->result;

    // A start: the inputs as they are now.
    r->peer = (uint8_t)nPeer;
    r->address = (uint16_t)nAddress;
    const BeeBusRegisterType table = (BeeBusRegisterType)(int)(E_BEEBUSMODBUSTABLE)eTable;
    const uint8_t wire = bb_wireTypeOfClass((uint32_t)anyData.ELEMCLASS);
    BeeBusResult asked = BeeBusResult::InvalidArgument;
    if (wire == BEEBUS_T_STRING && anyData.TYPECLASS == strucpp::TYPE_CLASS::TYPE_STRING) {
      // A string on its own is one object rather than a range, and reads only
      // as much as the field holds.
      if (bb_tableIsBits(table)) {
        snprintf(why, sizeof why, "a STRING is not read from a coil or input table");
        r->result = E_BEEBUSRESULT::INVALIDARGUMENT;
        return r->result;
      }
      asked = table == MB_HOLDING_REGISTER
          ? node->readString(r->peer, r->address, (char*)anyData.PVALUE, (uint16_t)anyData.DISIZE)
          : node->readInputString(r->peer, r->address, (char*)anyData.PVALUE, (uint16_t)anyData.DISIZE);
      if (r->plan) { bb_planFree(r->plan); r->plan = nullptr; }
    } else {
      // Everything else - a value, an array, a STRUCT - is laid out by the
      // rules ModbusMap uses, so a STRUCT read from a peer that mapped the
      // same STRUCT lands member for member.
      if (r->plan == nullptr || bb_planMoved(r->plan, anyData) || r->bits != bb_tableIsBits(table)) {
        bb_planFree(r->plan);
        r->bits = bb_tableIsBits(table);
        r->plan = bb_planBuild(anyData, r->bits, why, sizeof why);
      }
      if (r->plan != nullptr) {
        asked = bb_planReadPeer(r->plan, node, r->peer, table, r->address, (uint32_t)(uint16_t)nLength);
        if (asked == BeeBusResult::InvalidArgument && why[0] == '\0') {
          snprintf(why, sizeof why, "nLength is more than anyData holds, or past 65535 registers");
        }
      }
    }
    if (!bb_accepted(asked) && asked != BeeBusResult::Duplicate) {
      r->result = bb_resultOf(asked);
      return r->result;
    }
    if (asked == BeeBusResult::Immediate) {
      // A local address answers in place.
      r->result = E_BEEBUSRESULT::OK;
      if (r->plan != nullptr && !bb_planReadDone(r->plan, r->bits)) r->result = E_BEEBUSRESULT::TYPEMISMATCH;
      return r->result;
    }
    r->pending = true;
    r->result = E_BEEBUSRESULT::QUEUED;
    return r->result;
  }();
  return bb_noteCall(n, "ModbusRead", rec, result, why);
}

E_BEEBUSRESULT ModbusWrite()
{
  BbNode* n = nullptr;
  char why[112] = "";
  char id[24];
  snprintf(id, sizeof id, "%u@%u", (unsigned)(uint8_t)nPeer, (unsigned)(uint16_t)nAddress);
  const std::string rec = bb_recordName(&anyData, id);
  E_BEEBUSRESULT result = E_BEEBUSRESULT::OK;
  BbRecord* r = bb_begin(nState, n, BB_REC_MODBUS_WRITE, rec, anyData.TYPENAME, anyData.PVALUE, result);
  if (r != nullptr) result = [&]() -> E_BEEBUSRESULT {
    const bool execute = (bool)bExecute;
    const bool rising = execute && !r->lastExecute;
    r->lastExecute = execute;
    BeeBusAPI* node = n->api;
    if (node == nullptr) {
      if (rising) r->result = E_BEEBUSRESULT::NOTINITIALISED;
      return E_BEEBUSRESULT::NOTINITIALISED;
    }
    if (r->pending) {
      if (!bb_modbusDone(node, r, false, r->result)) return E_BEEBUSRESULT::QUEUED;
    }
    if (!rising) return r->result;

    // A start: the inputs and the values as they are now.
    r->peer = (uint8_t)nPeer;
    r->address = (uint16_t)nAddress;
    const BeeBusRegisterType table = (BeeBusRegisterType)(int)(E_BEEBUSMODBUSTABLE)eTable;
    // Only two of the four tables have a write function code.
    if (!bb_tableIsWritable(table)) {
      snprintf(why, sizeof why, "eTable must be Coil or HoldingRegister to write");
      r->result = E_BEEBUSRESULT::INVALIDARGUMENT;
      return r->result;
    }
    const BeeBusDelivery delivery = (bool)bConfirmed ? BeeBusDelivery::Confirmed
                                                     : BeeBusDelivery::Unconfirmed;
    const uint8_t wire = bb_wireTypeOfClass((uint32_t)anyData.ELEMCLASS);
    BeeBusResult asked = BeeBusResult::InvalidArgument;
    if (wire == BEEBUS_T_STRING && anyData.TYPECLASS == strucpp::TYPE_CLASS::TYPE_STRING) {
      // A string on its own costs the length of its text, not the field.
      if (table == MB_HOLDING_REGISTER) {
        asked = node->writeString(r->peer, r->address, (const char*)anyData.PVALUE, delivery);
      } else {
        snprintf(why, sizeof why, "a STRING is not written to a coil table");
      }
    } else {
      // Laid out afresh on each request, from the values at the edge: the
      // table (a coil list takes only BOOLs) or the variable may have changed.
      bb_planFree(r->plan);
      r->plan = bb_planBuild(anyData, bb_tableIsBits(table), why, sizeof why);
      if (r->plan != nullptr) {
        asked = bb_planWritePeer(r->plan, node, r->peer, table, r->address,
                                 (uint32_t)(uint16_t)nLength, delivery);
        if (asked == BeeBusResult::InvalidArgument && why[0] == '\0') {
          snprintf(why, sizeof why, "nLength is more than anyData holds, or past 65535 registers");
        }
      }
    }
    if (!bb_accepted(asked) && asked != BeeBusResult::Duplicate) {
      r->result = bb_resultOf(asked);
      return r->result;
    }
    if (delivery == BeeBusDelivery::Confirmed && asked != BeeBusResult::Immediate) {
      r->pending = true;
      r->result = E_BEEBUSRESULT::QUEUED;
    } else {
      r->result = E_BEEBUSRESULT::OK;
    }
    return r->result;
  }();
  return bb_noteCall(n, "ModbusWrite", rec, result, why);
}

E_BEEBUSRESULT Statistics()
{
  BbNode* n = bb_stateOf((strucpp::XWORD_t)nState);
  if (n == nullptr) return E_BEEBUSRESULT::QUEUEFULL;
  nState = (strucpp::XWORD_t)(uintptr_t)n;
  if (!bb_inTask(n->task)) return E_BEEBUSRESULT::WRONGTASK;
  BeeBusAPI* node = n->api;
  if (node == nullptr) return E_BEEBUSRESULT::NOTINITIALISED;
  nIdInUse = node->getNodeID();
  nMembers = node->getMemberCount();
  tRotation = bb_timeOf((int32_t)node->getRotationTime());
  nPendingOps = (int16_t)node->getPendingOpCount();
  const BeeBusIOStats stats = node->getLinkStatistics();
  nCrcErrors = (int32_t)stats.crcErrors;
  nNoiseBytes = (int32_t)stats.noiseBytesDiscarded;
  return E_BEEBUSRESULT::OK;
}

E_BEEBUSRESULT PeerStatus()
{
  BbNode* n = bb_stateOf((strucpp::XWORD_t)nState);
  if (n == nullptr) return E_BEEBUSRESULT::QUEUEFULL;
  nState = (strucpp::XWORD_t)(uintptr_t)n;
  if (!bb_inTask(n->task)) return E_BEEBUSRESULT::WRONGTASK;
  const uint8_t peer = (uint8_t)nPeer;
  if (peer < BEEBUS_NODE_ID_MIN || peer > BEEBUS_NODE_ID_MAX) {
    return bb_noteCall(n, "PeerStatus", "nPeer", E_BEEBUSRESULT::INVALIDARGUMENT,
                       "nPeer must be 1..254");
  }
  bb_noteCall(n, "PeerStatus", "nPeer", E_BEEBUSRESULT::OK, nullptr);
  BeeBusAPI* node = n->api;
  if (node == nullptr) return E_BEEBUSRESULT::NOTINITIALISED;
  bAlive = node->isAlive(peer);
  const bb_time_t silence = node->silenceFor(peer);
  tSilent = bb_timeOf(silence == BEEBUS_SILENCE_NEVER ? 0 : (int32_t)silence);
  bSeen = silence != BEEBUS_SILENCE_NEVER;
  tHop = bb_timeOf((int32_t)node->getHopTime(peer));
  tHopTimeout = bb_timeOf((int32_t)node->getHopTimeout(peer));
  return E_BEEBUSRESULT::OK;
}

END_FUNCTION_BLOCK
