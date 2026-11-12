(* A SPARKPLUG B EDGE NODE on an FB_MqttClient's connection. Call it once every
scan, in the client's task. What it reports is its methods: a whole STRUCT by
point list (Record), one value (Metric), a device (Device), a host's write
(Command), events kept through an outage (History) and daily totals
(DayTotals).

sGroupId    the Sparkplug Group ID: a logical grouping of nodes - a site, a
           pipeline segment, a cell. Descriptive but small: it is in every
           topic. Up to 47 characters, as every Sparkplug id here; no + / #.
sEdgeNodeId this node's ID. sGroupId and sEdgeNodeId together are the node's
           address in the whole system and MUST be unique in it.
sPrimaryHostId  the Sparkplug Host ID this node answers to, or empty for none.
           EMPTY BY DEFAULT - see below.
tRebirthHoldoff  the shortest time between two answers to rebirth requests
           (Node Control/Rebirth): requests in between are answered together,
           once, when it is up. T#2s by default. On a metered link (a cellular
           SIM) set a minute or more: a host that asks again and again then
           costs one birth a minute at most.
bEnable     FALSE sends the NDEATH and keeps the node down without losing a
           metric; the connection stays up for everything else on it.
stReportConfig  ST_SparkplugReportConfig, how Record's classes report:
             tLogInterval   how often the log class looks for what moved.
                            T#15m by default and at most; T#0s is refused
             tLiveInterval  how often the live class sends what moved, and
                            the log class while someone views. T#30s by
                            default. T#0s is refused, never every scan
             fDeadbandPct   the log class's deadband, in % of the value last
                            sent, for a REAL or LREAL member whose clause
                            gives no pct=. 0 = none
             bRemoteControl TRUE: the host may write the cmd and set classes.
                            FALSE: a write is dropped at once and the value
                            reported back unchanged, so the host sees it did
                            not take. Never kept for later
anyUnits    optional: a STRUCT of STRINGs whose members a point list names
           with u=@<member>, so units can come from a settings page. A change
           shows at the next birth.
fbClient    the FB_MqttClient this node rides on. Must be assigned.
           Everything about the connection is set there - broker, TLS, login,
           keep-alive, protocol - and the device's own topics and its firmware
           updates share the one session.

bLinkUp     the client's session is up.
bBorn       the birth certificate has gone. NOT the same as bLinkUp: a node
           waiting for its primary host is connected and not born.
nSeq        the current sequence number, 0-255.
nBdSeq      the birth/death sequence number of this connection.
nPoints     metrics declared, node and devices together. No limit but memory:
           past it the declaration is refused and sLastError says "out of
           memory for metrics or devices".
bError, eErrorId  E_MqttResult.Ok when fine. WrongTask: this block is not in
           its client's task, and does nothing until it is. QueueFull: out of
           memory. InvalidArgument: a Record call whose point list is wrong.
           NotConnected (bError FALSE): the client is not connected.
sLastError  what the node waits for, or what failed:
             "no STATE from primary host 'scada'"   the host has never
                                    reached this broker - or the id differs
             "offline STATE from primary host 'scada'"  the host is down
             "broker refused STATE/scada subscription (not authorized)"
             "birth could not be queued - retrying"
             "out of memory for metrics or devices"
             "another layer owns the client's Will"  an FB_SparkplugHost or a
                                    second node on fbClient
             "Record pump: clause 3"  that record's point list; also "not a
                                    STRUCT with a STRING point list",
                                    "tLiveInterval is T#0s", "message not
                                    queued"
           Empty once born.
bClockSet   the timestamps are real time. Always on the Runtime; on a board
           once FB_MqttClock has set the clock. Until then they count from
           boot - a date in January 1970 - which a host should take as "not
           synced" and replace with the time it received the message.
bViewed     Live Demand: a host says someone is viewing this node now.
sDemand     Live Demand: the devices demanded now, e.g. 'live,cfg-pump'.

METHODS

Every method is standing: call it every scan while it is wanted, after the
node's own call. Ok while the node is born; E_MqttResult.NotConnected while it
is not, the value kept for the next birth. WrongTask in any other task than
the node's; NotInitialised before the node's first call. A node holds up to
1024 Metric, Device, Command, History and DayTotals calls; past that,
QueueFull. A BIRTH CARRIES EVERY METRIC: declare on the first scans and the
node births with all of them (it waits up to 2 s for the first declaration).
A metric first declared after the birth makes the node birth again.

  sp.Record(anyData, sSettings, sPrefix, bSend, nMetricCnt =>, nBadClause =>)
     A WHOLE STRUCT, EACH MEMBER BY ITS CLASS. anyData is the record (nested
     STRUCTs and arrays included); sSettings its point list, a STRING of any
     length or a literal; sPrefix goes before every metric name. A record is
     found by its declared name and type and sPrefix: the same STRUCT with
     two prefixes is two records. nMetricCnt: metrics it declared.
     nBadClause: the first clause that cannot be used, counting from 1; 0
     none; -1 when anyData is not a STRUCT or sSettings not a STRING. The
     other clauses still apply.

     THE POINT LIST is clauses split by ';':
         <members> = <class> [, <option>]*
     <members> is a comma list of paths: 'level', 'pump.hours', 'spare[2]'.
     A path covers everything below it ('pump' is every value in pump), a
     name without an index covers every element ('spare' is spare[1] ..
     spare[n]), and '*' is any one segment ('*' alone is every member,
     'sts.*' everything in sts). A member no clause covers is not reported.
     Case does not matter; spaces are ignored.

     <class> says when it goes, where, and whether the host may write it:
       now         at once, always. Read only. Alarms, states, faults
       cmd         at once, always; the host writes it while
                   stReportConfig.bRemoteControl is TRUE
       view        at once while someone views (bViewed); otherwise held
       log         what moved past its deadband, every tLogInterval (every
                   tLiveInterval while someone views). For a metered link:
                   a value that sits still costs nothing
       live        on device 'live': what moved, every tLiveInterval, while
                   a host demands it
       set:<page>  on device 'cfg-<page>': at once while demanded; the host
                   writes it while bRemoteControl is TRUE. <page> up to 43
                   characters, no + / #
       every:<time>  all of them every <time> (T#1m, 30s, 1h30m), moved or
                   not; a birth counts as a send
       onreq       all of them on a rising edge of Record's bSend
     A value takes the class of the LAST now/cmd/view/log/every/onreq clause
     covering it, on the node and, separately, on each dev= device; it may
     also be in live and in any number of set pages, each a metric of its own
     on that device. Options come from the clause that gave the class.

     <option>:
       db=<n>      deadband in the member's units: a move this size or less
                   from the value last sent is not reported
       pct=<n>     deadband in % of the value last sent. With db=, a move
                   must clear both. Not given on a log REAL: fDeadbandPct
       u=<text>    engineering units, in the birth (engUnit). A TIME says
                   'ms' by itself
       u=@<member> the units are that STRING member of anyUnits
       lo=<n>, hi=<n>  the range a gauge or trend should show (engLow,
                   engHigh); equal = none
       pulse=<ms>  cmd and set only: the PLC puts the member back to 0,
                   FALSE or '' this many milliseconds after a host write,
                   for a command that acts on an edge
       dev=<name>  now, cmd, view, log, every and onreq: the members go
                   under the program's own device <name> instead of the
                   node. The program brings it on and off line with
                   sp.Device; Live Demand never touches it. Not 'live' or
                   'cfg-...'
     A deadband on a BOOL or STRING the clause names itself is an error;
     covered by a wider path, the BOOL simply reports every change. A value
     the host writes is always reported back, whatever the deadband.

     METRIC NAMES are sPrefix and the path: 'pump/' and sts.fault give
     'pump/sts.fault'; array elements count from 1 whatever the bounds. The
     live class drops a leading 'det.' and a set page a leading 'set.', so
     det.rate on 'live' is 'pump/rate' and set.onLevel on 'cfg-pump' is
     'pump/onLevel'. An enumeration goes as its unsigned integer; a TIME as
     Int64 milliseconds; a DATE or TIME_OF_DAY has no Sparkplug type and is
     left out.

     WHICH MEMBERS, AND THEIR CLASS, ARE READ AT THE FIRST CALL. Options
     follow later changes of the text, of anyUnits and of fDeadbandPct (units
     and ranges show at the next birth); adding or removing a clause later is
     reported on nBadClause - restart the PLC to change membership.
     Ok, NotConnected, InvalidArgument (a bad clause, or tLogInterval or
     tLiveInterval T#0s where it is used), QueueFull (out of memory, or a message
     asked for could not be queued: it asks again).

     LIVE DEMAND. A record with a view, log, live or set class makes the
     node offer the metric 'Node Control/Live Demand', a String whose value
     names what can be demanded:
         {"devices":["live","cfg-pump"],"required":false}
     A host viewing the node writes it:
         {"demand":true,"leaseS":120,"devices":["live","cfg-pump"]}
     Then bViewed is TRUE for leaseS seconds (120 when missing or outside 1
     to 86399): the view class sends, the log class goes at tLiveInterval,
     and each device listed is born (DBIRTH) and sends; a device not listed
     dies (DDEATH). The host writes again before the lease ends to keep it;
     {"demand":false} ends it at once; a write without "demand", or longer
     than 200 characters, is ignored. The offer is put back after every
     write. sDemand lists the devices demanded now. Devices 'live' and
     'cfg-...' are the node's: Device and Metric refuse them.

  sp.Metric(anyValue, sMetricName, sDeviceId, sUnits, eQuality, fDeadband,
            bWritable, bPublish, bUpdate, nAlias =>, nWrittenCnt =>,
            nLostCnt =>)
     ONE VALUE THE PROGRAM SETS. anyValue's declared type is the metric's
     datatype, declared at the first call; sMetricName is the name the host
     sees (case matters); sDeviceId puts it under a device of this node,
     which the first such call adds and brings online unless a Device call
     added it. sUnits goes in the birth. eQuality (Good by default) goes
     with the value: Uncertain as stale, Bad and Unknown as bad. fDeadband:
     a move this size or less from the value last sent is not reported
     (numbers only; InvalidArgument on a BOOL or STRING). bWritable TRUE at
     the first call declares it writable: a host command is written into
     anyValue, one a call, oldest first, up to four waiting (nLostCnt counts
     the dropped); bWritable FALSE later drops a write at once and reports
     the value back. bUpdate FALSE holds the last value and takes no
     command. nAlias: the alias the host sees, 0 refused. nWrittenCnt: host
     commands written. Ok, NotConnected, InvalidArgument (empty name, a type
     with no Sparkplug datatype, a name taken, a device the node manages),
     QueueFull.

  sp.Device(sDeviceId, bOnline, bDeviceOnline =>, nBirthCnt =>,
            nDeathCnt =>)
     A DEVICE THE PROGRAM BRINGS ONLINE AND OFFLINE: a pump skid, a remote
     I/O drop - something that can be lost while the node is fine. Acts on a
     change of bOnline (TRUE: DBIRTH, FALSE: DDEATH), never every scan, and
     births the device again after every node birth. Its metrics are
     Metric calls with this sDeviceId. bDeviceOnline: its birth has gone.
     nBirthCnt, nDeathCnt: births gone, deaths of an online device. Ok,
     NotConnected, InvalidArgument (empty, or 'live' or 'cfg-...', which
     Live Demand manages), QueueFull.

  sp.Command(sMetricName, sDeviceId, bAck, bPending =>, fValue =>,
             bValue =>, sText =>, nCmdCnt =>, nRefusedCnt =>, nLostCnt =>)
     A HOST'S WRITE FOR THE PROGRAM TO DECIDE ON, on a metric declared
     writable with Metric; call it BEFORE that Metric call. bPending shows
     the oldest write waiting, read without taking it, so a rung can look
     before it decides; a rising edge of bAck takes it, so two rungs cannot
     both act on one command. fValue: its value as a number (bValue = fValue
     <> 0), sText a String metric's value cut to 126 characters. nCmdCnt:
     commands seen on this metric. nRefusedCnt: commands the node refused -
     undeclared, read only or the wrong type - all metrics together.
     nLostCnt: writes dropped with four waiting. Ok, NotInitialised (the
     metric is not declared yet), InvalidArgument (not writable), QueueFull.

  sp.History(nSource, nCode, fValue, sMetricPrefix, nDepth, nBatch, tPeriod,
             bAdd, nStoredCnt =>, nLostCnt =>, nSentCnt =>, bReplaying =>)
     EVENTS KEPT THROUGH AN OUTAGE. bAdd TRUE records one event on this call
     - wire a one-scan pulse - with what it is about (nSource: a pump, an
     alarm number), what happened (nCode) and a number (fValue). While the
     node is born it goes at once as live data; recorded while it is not, it
     waits and goes after the next node birth flagged historical, at its own
     time, oldest first, nBatch at a time (at most 64) every tPeriod. Each
     event is the metrics <sMetricPrefix>/source, /code, /value and /seq (a
     count from 1, so the host sees a gap), plus /lost. Calls with one
     sMetricPrefix share one buffer of nDepth events (256: about a week of a
     normal site, 24 bytes each, in PSRAM on a board); nDepth and nBatch are
     fixed at the first call. A full buffer drops the oldest (nLostCnt).
     Not retained. Sent at least once: an event is forgotten only after the
     node stays born on the same birth for half a second; a device's birth
     does not count. Events recorded before the clock is set are placed on
     it once set; they wait for the clock up to five minutes after a birth.
     nStoredCnt waiting, nSentCnt sent, bReplaying catching up. Ok,
     NotConnected, NotInitialised (no memory for the buffer),
     InvalidArgument (the metrics could not be declared), QueueFull.

  sp.DayTotals(anyDays, sMetricName, fValue, dtClock, tSaveEvery, nDays =>,
               nSentCnt =>)
     DAILY TOTALS, sent on every node birth as historical values, so a host
     fills in the days the link was down. anyDays is a RETAINED ARRAY OF
     ST_SparkplugDay, two rows or more: the first is today, the rest closed
     days, newest first. fValue is today's running total; dtClock the local
     date and time the totaliser rolls its day on. When dtClock's date
     changes the day is closed with the total of its last call and becomes
     the newest closed day; the oldest falls off. A day that ended during a
     power cut is closed when the PLC returns, from the total last saved:
     today's total is written into anyDays every tSaveEvery (T#1h; T#0s
     every call). Each closed day goes as a value of sMetricName stamped
     00:00 of its date (the date as dtClock has it, written as UTC: read
     the date, not the hour), on every node birth and every close - not on
     a device's birth. The live value is the last closed day. Nothing
     happens while the clock is not set. nDays: closed days held. Ok,
     NotConnected, InvalidArgument (anyDays is not an ARRAY OF
     ST_SparkplugDay of two rows or more, or the metric could not be
     declared), QueueFull.

---

WHY SPARKPLUG AND NOT PLAIN MQTT. Two things, and they are why a SCADA
system wants it.

A TOPIC IS A ONE-WAY PIPE, so a writable setpoint under plain MQTT needs two
of them, one to write and one to read back. Under Sparkplug the direction is
in the MESSAGE TYPE: the host writes SETPOINT with a command, the node
publishes SETPOINT with its data. One name, one member.

AND THE DATATYPE IS DECLARED. Every metric's type travels in the birth
certificate, so the far end is told REAL rather than guessing from the first
sample. A counter that started at zero is not filed as an integer.

WHAT IT COSTS. The metric set is CLOSED. The birth certificate carries every
metric the node will publish, and a write to an undeclared name is refused
rather than invented. So the methods are called from the first scan; one
first called later costs a rebirth.

sPrimaryHostId IS EMPTY BY DEFAULT, deliberately. Set it and this node
publishes NOTHING until that host announces itself online - right for a
system with one nominated master, and what stops a node shouting into a
broker nobody is reading. Empty, the node births as soon as it connects. A
node waiting for a host that does not exist looks exactly like a node that is
broken, so the default is the one that cannot be mistaken.

ONE CONNECTION, SHARED. This node is a layer on fbClient's session, not a
second connection. What Sparkplug needs of that session it takes on every
CONNECT: the Will is this node's NDEATH, so no stWillConfig on that client
(the birth and death certificates are the presence); the session is always
clean, whatever stSessionConfig says; and the transmit buffer grows to hold
the birth certificate. Started on a session already up, the node reconnects
it once so the next CONNECT carries the NDEATH. The same when the primary
host goes offline: Sparkplug requires a new session. One node per client: a
connection carries one Will.

ONE MESSAGE A SCAN. The methods do not send: each marks what moved and asks,
and this block, on its next scan, sends ONE NDATA - and one DDATA for each
online device with something to say - carrying everything that moved. Births,
deaths and History's events go when they happen.

ONE TASK. This block, its methods and fbClient run in the network task, and
the machine's program trades values with them through globals.

sGroupId, sEdgeNodeId AND sPrimaryHostId MAY CHANGE WHILE IT RUNS. The node
leaves under the old identity (the host sees the NDEATH) and births under the
new one with the next bdSeq; declarations and devices stay, so nothing else in
the program notices. *)

FUNCTION_BLOCK FB_SparkplugNode
  VAR_INPUT
    sGroupId        : STRING(47);           (* the Sparkplug Group ID *)
    sEdgeNodeId     : STRING(47);           (* this node's Edge Node ID; with sGroupId unique in the system *)
    sPrimaryHostId  : STRING(47);           (* the Primary Host this node answers to; empty for none *)
    tRebirthHoldoff : TIME := T#2s;         (* the shortest time between two answers to rebirth requests *)
    bEnable         : BOOL := TRUE;         (* FALSE keeps the node down without losing its metrics *)
    stReportConfig  : ST_SparkplugReportConfig; (* Record: intervals, log deadband, remote control *)
    anyUnits        : ANY;                  (* Record: a STRUCT of STRINGs that u=@<member> names; optional *)
  END_VAR
  VAR_IN_OUT
    fbClient        : FB_MqttClient;        (* the connection this node rides on *)
  END_VAR
  VAR_OUTPUT
    bLinkUp         : BOOL;                 (* the client's session is up *)
    bBorn           : BOOL;                 (* the birth certificate has gone *)
    nSeq            : USINT;                (* the current sequence number *)
    nBdSeq          : USINT;                (* the birth/death sequence number of this connection *)
    nPoints         : INT;                  (* metrics declared *)
    bError          : BOOL;
    eErrorId        : E_MqttResult;
    sLastError      : STRING(64);           (* what the node waits for, or what failed *)
    bClockSet       : BOOL;                 (* the timestamps are real time *)
    bViewed         : BOOL;                 (* Live Demand: someone views this node now *)
    sDemand         : STRING(200);          (* Live Demand: the devices demanded now, e.g. 'live,cfg-pump' *)
  END_VAR
  VAR
    nApi            : __XWORD;              (* the node, for the methods *)
    bConnectAsked   : BOOL;
    nDeclaredAt     : DINT;
    nSessionKey     : UDINT;
    nClient         : __XWORD;
    nTask           : __XWORD;
    nReport         : __XWORD;              (* the records, for Record *)
    nBirthsSeen     : UDINT;                (* node births seen, and the metrics the last one carried *)
    nPointsBorn     : UDINT;
    nMethodCalls    : __XWORD;              (* the per-call table of Metric, Device, Command, History, DayTotals *)
  END_VAR

(* A STRUCT's members as metrics, each by its class, from one point list of
   clauses '<members> = <class> [, <option>]*' split by ';'. Classes now,
   cmd, view, log, live, set:<page>; options db=, pct=, u=, u=@<member>,
   lo=, hi=, pulse=. Called every scan. Ok while the node is born,
   NotConnected while not (the record goes in the next birth). *)
METHOD PUBLIC Record : E_MqttResult
  VAR_INPUT
    anyData    : ANY;                       (* the record: a STRUCT *)
    sSettings  : ANY;                       (* its point list: a STRING of any length, or a literal *)
    sPrefix    : STRING(32);                (* put before every metric name *)
    bSend      : BOOL;                      (* onreq: a rising edge sends those members, all of them *)
  END_VAR
  VAR_OUTPUT
    nMetricCnt : INT;                       (* metrics the record declared *)
    nBadClause : INT;                       (* the first clause that cannot be used, from 1; 0 none *)
  END_VAR
END_METHOD

(* One metric the program sets, called every scan. anyValue's declared type
   is its datatype, declared at the first call. Ok while the node is born,
   NotConnected while not (the value goes in the next birth). *)
METHOD PUBLIC Metric : E_MqttResult
  VAR_INPUT
    anyValue        : ANY;                  (* the value; a host command is written here when bWritable *)
    sMetricName     : STRING(96);           (* the name the host sees; case matters *)
    sDeviceId       : STRING(47);           (* a device of this node; empty for a node metric *)
    sUnits          : STRING(16);           (* engUnit in the birth *)
    eQuality        : E_MqttQuality := E_MqttQuality.Good; (* Uncertain goes as stale, Unknown as bad *)
    fDeadband       : REAL;                 (* numbers: a move this size or less from the value last sent is not reported *)
    bWritable       : BOOL;                 (* a host may command it; declared once, writes dropped while FALSE *)
    bPublish        : BOOL := TRUE;         (* asks the node for this scan's data message *)
    bUpdate         : BOOL := TRUE;         (* FALSE holds the last value and takes no command *)
  END_VAR
  VAR_OUTPUT
    nAlias          : UDINT;                (* the alias the host sees after the birth; 0 refused *)
    nWrittenCnt     : DINT;                 (* host commands written into anyValue *)
    nLostCnt        : DINT;                 (* writes dropped with four already waiting *)
  END_VAR
END_METHOD

(* A device the program brings online and offline, called every scan. Acts on
   a change of bOnline; births it again after every node birth. Ok while the
   node is born. Devices the node manages itself ('live', 'cfg-...') are
   refused. *)
METHOD PUBLIC Device : E_MqttResult
  VAR_INPUT
    sDeviceId       : STRING(47);           (* unique among this node's devices *)
    bOnline         : BOOL := TRUE;         (* TRUE births the device, FALSE sends its death *)
  END_VAR
  VAR_OUTPUT
    bDeviceOnline   : BOOL;                 (* its birth has gone *)
    nBirthCnt       : DINT;                 (* births gone; one more after every node birth *)
    nDeathCnt       : DINT;                 (* deaths of an online device *)
  END_VAR
END_METHOD

(* A host command on a writable metric, for the program to decide on, called
   every scan. bPending shows the oldest write; a rising edge of bAck takes it.
   NotInitialised until the metric is declared. *)
METHOD PUBLIC Command : E_MqttResult
  VAR_INPUT
    sMetricName     : STRING(96);           (* a metric declared writable *)
    sDeviceId       : STRING(47);           (* its device; empty for a node metric *)
    bAck            : BOOL;                 (* rising edge takes the pending command *)
  END_VAR
  VAR_OUTPUT
    bPending        : BOOL;                 (* a command waits, not taken *)
    fValue          : LREAL;                (* its value as a number, from the call it was first seen *)
    bValue          : BOOL;                 (* fValue <> 0 *)
    sText           : STRING(126);          (* a String metric's value, cut to 126 characters *)
    nCmdCnt         : DINT;                 (* commands seen on this metric *)
    nRefusedCnt     : DINT;                 (* commands the node refused, all metrics together *)
    nLostCnt        : DINT;                 (* writes dropped on this metric with four already waiting *)
  END_VAR
END_METHOD

(* Events kept while the node cannot publish, sent after the next birth
   flagged historical, in order, at their own time. Called every scan; calls
   with one sMetricPrefix share one buffer. *)
METHOD PUBLIC History : E_MqttResult
  VAR_INPUT
    nSource         : UINT;                 (* what the event is about: a pump, an alarm number *)
    nCode           : UINT;                 (* what happened: a status, fault or stop code *)
    fValue          : REAL;                 (* a number that goes with it *)
    sMetricPrefix   : STRING(24) := 'Event'; (* metrics <prefix>/source, /code, /value, /seq, /lost *)
    nDepth          : UINT := 256;          (* events kept; fixed at the first call *)
    nBatch          : UINT := 20;           (* events a catch-up message, at most 64; fixed at the first call *)
    tPeriod         : TIME := T#1s;         (* between catch-up messages *)
    bAdd            : BOOL;                 (* TRUE records one event on this call *)
  END_VAR
  VAR_OUTPUT
    nStoredCnt      : UINT;                 (* events waiting to be sent *)
    nLostCnt        : UDINT;                (* events dropped with the buffer full: the oldest go *)
    nSentCnt        : UDINT;                (* events sent since the program started *)
    bReplaying      : BOOL;                 (* sending what was kept during an outage *)
  END_VAR
END_METHOD

(* A table of daily totals kept by the program and sent on every birth as
   historical values, so the host fills in the days the link was down. Called
   every scan. A change of date on dtClock closes the day. Ok while born. *)
METHOD PUBLIC DayTotals : E_MqttResult
  VAR_INPUT
    anyDays         : ANY;                  (* ARRAY OF ST_SparkplugDay, retained, 2 rows or more: today, then closed days newest first *)
    sMetricName     : STRING(32);           (* the metric; its live value is the last closed day *)
    fValue          : REAL;                 (* today's running total *)
    dtClock         : DT;                   (* local date and time, the clock the total rolls its day on *)
    tSaveEvery      : TIME := T#1h;         (* how often today's total is written into anyDays; T#0s every call *)
  END_VAR
  VAR_OUTPUT
    nDays           : INT;                  (* closed days held *)
    nSentCnt        : UDINT;                (* day values sent since the program started *)
  END_VAR
END_METHOD

#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugNode.h>
#include <new>
#include <string>
#include <vector>
#include <string.h>
#include <strings.h>
#include <stdlib.h>

// --- Everything this block made, freed when the program is unloaded ---
//
// The Runtime swaps a new program into the SAME process on every stop and
// re-download. A node only leaves its client here: the connection is
// FB_MqttClient's, whose own cleanup runs after this one (its client was made
// first: a node needs one) and closes the link WITHOUT a
// DISCONNECT - so the broker publishes this node's NDEATH, the Will it
// registered, the moment the PLC stops.
namespace {
// Made on first use, so a program that never uses this block links none of
// it, and freed when the program is unloaded, before what was made earlier.
struct MqSpNodesOwned {
    std::vector<MqttSparkplugNode*> all;
    ~MqSpNodesOwned() {
        for (size_t i = 0; i < all.size(); i++) delete all[i];
    }
};
MqSpNodesOwned& mqSpNodesOwned() {
    static MqSpNodesOwned owned;
    return owned;
}
}  // namespace
// Declared here because every C++ POU in a project lands in ONE translation
// unit, in filename order - and FB_SparkplugNode sorts after FB_MqttClient, which
// is where these are defined.
MqttClient* mq_clientOf(strucpp::XWORD_t handle);
uint32_t mq_fingerprint(uint32_t hash, const void* data, size_t length);
uint32_t mq_fingerprintText(uint32_t hash, const char* text);
strucpp::XWORD_t mq_currentTask();
bool mq_inTask(strucpp::XWORD_t owner);
bool mq_tolerated(MqttResult result);
int32_t mq_millisOf(const strucpp::IEC_TIME& t);
size_t mq_formatAny(const strucpp::IEC_ANY& any, char* out, size_t capacity);
bool mq_numberOf(const strucpp::IEC_ANY& any, double* out);
bool mq_memberAsAny(const strucpp::MemberDesc& member, uint8_t* base,
                    strucpp::IEC_ANY* out);
bool mq_memberIsPublishable(const strucpp::MemberDesc& member);

// --- What the methods reach through nApi ---
//
// Null until the node has been built, which is what bLinkUp says. A handle
// rather than a pointer on the pin because that is what an IEC XWORD is.
MqttSparkplugNode* mq_spNodeOf(strucpp::XWORD_t handle) {
    return (MqttSparkplugNode*)(uintptr_t)handle;
}

// --- IEC type to Sparkplug datatype ---
//
// THE DECLARED TYPE IS THE ANSWER, which is the whole point: an IEC declaration
// already says REAL or DINT, so nothing has to be inferred from a value. This
// is the mapping in MqttSparkplugValue.h, applied to strucpp's type classes.
//
// All seventeen IEC types the MQTT blocks can publish have a Sparkplug
// datatype, so a STRUCT that FB_MqttClient.PublishStruct would accept
// is one Record accepts too.
//
// AND TIME, which Sparkplug alone carries: an Int64 of MILLISECONDS. Sparkplug
// has no duration type, and a setpoint struct is full of TIMEs - a run time, a
// delay, a stagger - so refusing them left half a settings struct unwritable
// from SCADA while the panel next to it could write all of it. Milliseconds
// because that is what CODESYS and every SCADA tag editor mean by a TIME, and
// Int64 because the IEC range does not fit in 32 bits of them. (The text
// payloads of FB_MqttClient.PublishStruct still refuse a TIME: there is no one way to
// write it as text that every subscriber would read the same.)
bool mq_spTypeOfClass(int typeClass, MqttSparkplugDataType* out) {
    switch (typeClass) {
    case strucpp::TYPE_BOOL:  *out = MqttSparkplugDataType::Boolean; return true;
    case strucpp::TYPE_SINT:  *out = MqttSparkplugDataType::Int8;    return true;
    case strucpp::TYPE_INT:   *out = MqttSparkplugDataType::Int16;   return true;
    case strucpp::TYPE_DINT:  *out = MqttSparkplugDataType::Int32;   return true;
    case strucpp::TYPE_LINT:  *out = MqttSparkplugDataType::Int64;   return true;
    case strucpp::TYPE_USINT: *out = MqttSparkplugDataType::UInt8;   return true;
    case strucpp::TYPE_BYTE:  *out = MqttSparkplugDataType::UInt8;   return true;
    case strucpp::TYPE_UINT:  *out = MqttSparkplugDataType::UInt16;  return true;
    case strucpp::TYPE_WORD:  *out = MqttSparkplugDataType::UInt16;  return true;
    case strucpp::TYPE_UDINT: *out = MqttSparkplugDataType::UInt32;  return true;
    case strucpp::TYPE_DWORD: *out = MqttSparkplugDataType::UInt32;  return true;
    case strucpp::TYPE_ULINT: *out = MqttSparkplugDataType::UInt64;  return true;
    case strucpp::TYPE_LWORD: *out = MqttSparkplugDataType::UInt64;  return true;
    case strucpp::TYPE_REAL:  *out = MqttSparkplugDataType::Float;   return true;
    case strucpp::TYPE_LREAL: *out = MqttSparkplugDataType::Double;  return true;
    case strucpp::TYPE_STRING: *out = MqttSparkplugDataType::String; return true;
    case strucpp::TYPE_TIME:  *out = MqttSparkplugDataType::Int64;   return true;
    default:
        return false;
    }
}

// TIME is signed nanoseconds in strucpp. On the wire it is milliseconds,
// truncated: T#1500us goes as 1, and a value read back is the same TIME to the
// millisecond, which is the resolution every PLC timer here has anyway.
static const int64_t MQ_SP_NS_PER_MS = 1000000LL;

// Reads one IEC value as a Sparkplug value of its declared type.
//
// The declared type decides, not the value: a DINT holding 1 is an Int32 of 1
// and not a UInt8, because the birth certificate said Int32 and the far end is
// entitled to rely on that.
bool mq_spValueOfAny(const strucpp::IEC_ANY& any, MqttSparkplugValue* out) {
    if (!out || !any.PVALUE) return false;
    switch (any.TYPECLASS) {
    case strucpp::TYPE_BOOL:
        *out = mq_spBool(*(const bool*)any.PVALUE);
        return true;
    case strucpp::TYPE_SINT:
        *out = mq_spInt8(*(const int8_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_INT:
        *out = mq_spInt16(*(const int16_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_DINT:
        *out = mq_spInt32(*(const int32_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_LINT:
        *out = mq_spInt64(*(const int64_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_USINT:
    case strucpp::TYPE_BYTE:
        *out = mq_spUInt8(*(const uint8_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_UINT:
    case strucpp::TYPE_WORD:
        *out = mq_spUInt16(*(const uint16_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_UDINT:
    case strucpp::TYPE_DWORD:
        *out = mq_spUInt32(*(const uint32_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_ULINT:
    case strucpp::TYPE_LWORD:
        *out = mq_spUInt64(*(const uint64_t*)any.PVALUE);
        return true;
    case strucpp::TYPE_REAL:
        *out = mq_spFloat(*(const float*)any.PVALUE);
        return true;
    case strucpp::TYPE_LREAL:
        *out = mq_spDouble(*(const double*)any.PVALUE);
        return true;
    case strucpp::TYPE_STRING:
        // Points at the runtime's own buffer, which outlives the publish -
        // MqttSparkplugValue deliberately does not copy text.
        *out = mq_spString((const char*)any.PVALUE);
        return true;
    case strucpp::TYPE_TIME:
        *out = mq_spInt64(*(const int64_t*)any.PVALUE / MQ_SP_NS_PER_MS);
        return true;
    default:
        return false;
    }
}

// Writes a Sparkplug value back into one IEC value. What a command does.
//
// Refuses on a type mismatch rather than coercing: a host writing a float into
// a BOOL has made a mistake, and rounding it would hide that.
bool mq_spWriteAny(const strucpp::IEC_ANY& any,
                   const MqttSparkplugValue& value) {
    if (!any.PVALUE) return false;
    if (value.isNull) return false;

    MqttSparkplugDataType declared = MqttSparkplugDataType::Unknown;
    if (!mq_spTypeOfClass(any.TYPECLASS, &declared)) return false;
    if (declared != value.type) return false;

    switch (any.TYPECLASS) {
    case strucpp::TYPE_BOOL:
        *(bool*)any.PVALUE = value.as.boolean;
        return true;
    case strucpp::TYPE_SINT:
        *(int8_t*)any.PVALUE = (int8_t)value.as.signedValue;
        return true;
    case strucpp::TYPE_INT:
        *(int16_t*)any.PVALUE = (int16_t)value.as.signedValue;
        return true;
    case strucpp::TYPE_DINT:
        *(int32_t*)any.PVALUE = (int32_t)value.as.signedValue;
        return true;
    case strucpp::TYPE_LINT:
        *(int64_t*)any.PVALUE = value.as.signedValue;
        return true;
    case strucpp::TYPE_USINT:
    case strucpp::TYPE_BYTE:
        *(uint8_t*)any.PVALUE = (uint8_t)value.as.unsignedValue;
        return true;
    case strucpp::TYPE_UINT:
    case strucpp::TYPE_WORD:
        *(uint16_t*)any.PVALUE = (uint16_t)value.as.unsignedValue;
        return true;
    case strucpp::TYPE_UDINT:
    case strucpp::TYPE_DWORD:
        *(uint32_t*)any.PVALUE = (uint32_t)value.as.unsignedValue;
        return true;
    case strucpp::TYPE_ULINT:
    case strucpp::TYPE_LWORD:
        *(uint64_t*)any.PVALUE = value.as.unsignedValue;
        return true;
    case strucpp::TYPE_REAL:
        *(float*)any.PVALUE = value.as.float32;
        return true;
    case strucpp::TYPE_LREAL:
        *(double*)any.PVALUE = value.as.float64;
        return true;
    case strucpp::TYPE_STRING: {
        // Bounded by the DECLARED capacity, which is what any.DISIZE carries.
        // A longer value is refused rather than truncated: a truncated
        // setpoint name or recipe id is worse than none.
        if (value.as.bytes.data == nullptr) return false;
        const int32_t capacity = any.DISIZE;
        if (capacity <= 0) return false;
        if ((int32_t)value.as.bytes.length >= capacity) return false;
        char* target = (char*)any.PVALUE;
        memcpy(target, value.as.bytes.data, value.as.bytes.length);
        target[value.as.bytes.length] = '\0';
        return true;
    }
    case strucpp::TYPE_TIME: {
        // Milliseconds. A negative duration is refused (TIME is unsigned in
        // CODESYS, and no setting here means anything by one), and so is one
        // past what nanoseconds can hold - about 292 years - rather than
        // wrapped into a small number that looks plausible.
        const int64_t ms = value.as.signedValue;
        if (ms < 0 || ms > INT64_MAX / MQ_SP_NS_PER_MS) return false;
        *(int64_t*)any.PVALUE = ms * MQ_SP_NS_PER_MS;
        return true;
    }
    default:
        return false;
    }
}

// =============================================================================
// RECORD: a STRUCT's members as metrics, each by its class
// =============================================================================
//
// One call per record: sp.Record(anyData := DEV.pump, sSettings := '...').
// The point list names members and gives each a class (when it goes, on which
// device, whether the host may write it) and its options. The node keeps one
// group per class and device of the record: its members (where each value is,
// the node's index for it) and that group's timing state. Membership is read
// at the first call; options follow later changes of the text.

namespace {

enum MqSpKind : uint8_t {
    MQ_SP_NOW = 0,    // at once, always; read only
    MQ_SP_CMD,        // at once, always; written by the host while remote control is on
    MQ_SP_VIEW,       // at once, while someone views
    MQ_SP_LOG,        // what moved past its deadband, every log interval
    MQ_SP_LIVE,       // device 'live': what moved, every live interval, while demanded
    MQ_SP_SET,        // device 'cfg-<page>': at once, while demanded; written while remote control is on
    MQ_SP_EVERY,      // every:<time>: all members every period, whether they moved or not
    MQ_SP_ONREQ       // onreq: all members on a rising edge of Record's bSend
};

// A member of a group: 16 bytes.
struct MqSpLeaf {
    uint32_t offset = 0;      // from the record's first byte
    uint32_t point = 0;       // the node's index
    uint16_t size = 0;        // bytes, or a STRING's capacity
    uint16_t clause = 0;      // the clause that gave it its class and options
    uint8_t cls = 0;          // strucpp::TYPE_CLASS; an ENUM as its integer
    uint8_t named = 0;        // the clause names this member itself
};

struct MqSpPulse {
    int64_t pulseNs = 0;
    mq_time_t writtenAt = 0;
    bool pulsing = false;
};

struct MqSpGroup {
    uint8_t kind = MQ_SP_NOW;
    int16_t device = -1;               // MqSpReport::devices (Live Demand's), -1 none
    int16_t ownDevice = -1;            // MqSpReport::ownDevices (dev=), -1 none; neither: the node
    int32_t periodMs = 0;              // every:<time>
    mq_time_t sentAt = 0;              // every:<time>: when the whole set last went
    uint32_t births = 0;               // the node's births seen: a birth sends the whole set
    std::vector<MqSpLeaf> leaves;
    std::vector<MqSpPulse> pulses;     // empty until a member has pulse=
    int pulsing = 0;
    uint32_t writesSeen = 0;
    bool writesLeft = false;
    bool held = false;
    bool wasOnline = false;
    bool wasEnabled = false;
    bool everSent = false;
    bool asking = false;
    uint32_t slot = 0;                 // the interval slot last looked at
    uint32_t askedAt = 0;
};

struct MqSpRecord {
    std::string name;                  // the descriptor's NAME and TYPENAME, and the prefix
    std::string typeName;
    std::string prefix;
    const uint8_t* address = nullptr;  // a cache of where the record is
    const strucpp::TypeDesc* type = nullptr;
    std::vector<MqSpGroup> groups;
    uint32_t settingsSum = 0;
    uint32_t unitsSum = 0;
    float defaultPct = -1.0f;
    uint16_t clauses = 0;              // clauses at the first call
    int16_t points = 0;
    int16_t bad = 0;                   // the first clause that could not be used
    int16_t declareBad = 0;            // the same, found when the members were declared
    bool lastSend = false;             // bSend at the last call, for onreq's edge
    bool applied = false;
    bool usesUnits = false;
};

struct MqSpReport {
    std::vector<MqSpRecord*> records;
    std::vector<std::string> devices;  // 'live', 'cfg-<page>', as first used
    std::vector<std::string> ownDevices;  // dev=<name>: the program's devices
    std::vector<uint8_t> demanded;
    std::vector<uint8_t> online;
    std::string offer;
    std::string demandList;            // sDemand
    int demandPoint = -1;
    bool viewed = false;
    mq_time_t viewedAt = 0;
    uint32_t leaseMs = 0;
    bool usesUnits = false;
    uint32_t unitsSum = 0;
    std::string failKey;               // the record whose call failed last
    std::string failText;
    uint8_t failResult = 0;
    ~MqSpReport() {
        for (size_t i = 0; i < records.size(); i++) delete records[i];
    }
};

// Made on first use, so a program that never uses this block links none of
// it, and freed when the program is unloaded, before what was made earlier.
struct MqSpReportsOwned {
    std::vector<MqSpReport*> all;
    ~MqSpReportsOwned() {
        for (size_t i = 0; i < all.size(); i++) delete all[i];
    }
};
MqSpReportsOwned& mqSpReportsOwned() {
    static MqSpReportsOwned owned;
    return owned;
}

// One clause of the point list: members '=' class [',' option]*.
struct MqSpClause {
    std::vector<std::string> members;
    std::string page;                  // set:<page>
    std::string dev;                   // dev=<name>: a device of the program's own
    int32_t periodMs = 0;              // every:<time>
    std::string units;                 // u=<text>, or the member of anyUnits for u=@<member>
    float band = 0.0f, pct = 0.0f, low = 0.0f, high = 0.0f;
    int64_t pulseNs = 0;
    uint8_t kind = MQ_SP_NOW;
    bool hasPct = false;
    bool unitsRef = false;
    bool fault = false;
};

const char* const MQ_SP_LIVE_DEMAND = "Node Control/Live Demand";
const size_t MQ_SP_DEMAND_MAX = 200;   // characters the Live Demand metric takes
const uint32_t MQ_SP_LEASE_DEFAULT_S = 120;
const int32_t MQ_SP_LOG_MAX_MS = 15 * 60 * 1000;

}  // namespace

MqSpReport* mq_spReportOf(strucpp::XWORD_t handle) {
    return (MqSpReport*)(uintptr_t)handle;
}

static std::string mq_spTrim(const std::string& t) {
    size_t a = 0, b = t.size();
    while (a < b && (unsigned char)t[a] <= ' ') a++;
    while (b > a && (unsigned char)t[b - 1] <= ' ') b--;
    return t.substr(a, b - a);
}

static bool mq_spIsWritableKind(uint8_t kind) {
    return kind == MQ_SP_CMD || kind == MQ_SP_SET;
}

// Whether a class follows someone viewing: what makes the node offer Live Demand.
static bool mq_spIsViewedKind(uint8_t kind) {
    return kind == MQ_SP_VIEW || kind == MQ_SP_LOG || kind == MQ_SP_LIVE ||
           kind == MQ_SP_SET;
}

// A duration in milliseconds, as IEC writes one (T#1m30s, TIME#500ms) or
// without the prefix (1m30s); -1 when it is not one.
static int64_t mq_spDurationMs(const std::string& text) {
    const char* p = text.c_str();
    if (strncasecmp(p, "TIME#", 5) == 0) p += 5;
    else if (strncasecmp(p, "T#", 2) == 0) p += 2;
    if (*p == '\0') return -1;
    double total = 0.0;
    while (*p != '\0') {
        if (*p == '_') {
            p++;
            continue;
        }
        char* stop = nullptr;
        const double n = strtod(p, &stop);
        if (stop == p || n < 0) return -1;
        p = stop;
        double unit;
        if (strncasecmp(p, "ms", 2) == 0) { unit = 1.0; p += 2; }
        else if (*p == 'd' || *p == 'D') { unit = 86400000.0; p++; }
        else if (*p == 'h' || *p == 'H') { unit = 3600000.0; p++; }
        else if (*p == 'm' || *p == 'M') { unit = 60000.0; p++; }
        else if (*p == 's' || *p == 'S') { unit = 1000.0; p++; }
        else return -1;
        total += n * unit;
    }
    return (int64_t)total;
}

// The point list, clause by clause, bounded by the STRING's size. A clause that
// cannot be read is kept with `fault` set, so nBadClause points at it.
static void mq_spParseClauses(const char* text, int32_t bound,
                              std::vector<MqSpClause>& out) {
    out.clear();
    size_t length = 0;
    while ((bound <= 0 || (int32_t)length < bound) && text[length] != '\0') length++;
    const std::string all(text, length);
    size_t at = 0;
    while (at <= all.size()) {
        size_t end = all.find(';', at);
        if (end == std::string::npos) end = all.size();
        const std::string item = mq_spTrim(all.substr(at, end - at));
        at = end + 1;
        if (!item.empty()) {
            MqSpClause c;
            const size_t eq = item.find('=');
            if (eq == std::string::npos) {
                c.fault = true;
            } else {
                // Members: a comma list of paths.
                const std::string left = item.substr(0, eq);
                size_t m = 0;
                while (m <= left.size()) {
                    size_t comma = left.find(',', m);
                    if (comma == std::string::npos) comma = left.size();
                    const std::string member = mq_spTrim(left.substr(m, comma - m));
                    if (member.empty()) c.fault = true;
                    else c.members.push_back(member);
                    m = comma + 1;
                }
                // The class, then options.
                const std::string right = item.substr(eq + 1);
                size_t p = 0;
                bool first = true;
                while (p <= right.size()) {
                    size_t comma = right.find(',', p);
                    if (comma == std::string::npos) comma = right.size();
                    const std::string part = mq_spTrim(right.substr(p, comma - p));
                    p = comma + 1;
                    if (first) {
                        first = false;
                        const char* k = part.c_str();
                        if (strcasecmp(k, "now") == 0) c.kind = MQ_SP_NOW;
                        else if (strcasecmp(k, "cmd") == 0) c.kind = MQ_SP_CMD;
                        else if (strcasecmp(k, "view") == 0) c.kind = MQ_SP_VIEW;
                        else if (strcasecmp(k, "log") == 0) c.kind = MQ_SP_LOG;
                        else if (strcasecmp(k, "live") == 0) c.kind = MQ_SP_LIVE;
                        else if (strncasecmp(k, "set:", 4) == 0) {
                            c.kind = MQ_SP_SET;
                            c.page = mq_spTrim(part.substr(4));
                            // 'cfg-' + page is a device id: at most 47, no + / #.
                            if (c.page.empty() || c.page.size() > 43 ||
                                c.page.find_first_of("+/#") != std::string::npos) {
                                c.fault = true;
                            }
                        } else if (strncasecmp(k, "every:", 6) == 0) {
                            c.kind = MQ_SP_EVERY;
                            const int64_t ms = mq_spDurationMs(mq_spTrim(part.substr(6)));
                            if (ms <= 0 || ms > INT32_MAX) c.fault = true;
                            else c.periodMs = (int32_t)ms;
                        } else if (strcasecmp(k, "onreq") == 0) {
                            c.kind = MQ_SP_ONREQ;
                        } else {
                            c.fault = true;
                        }
                        continue;
                    }
                    const size_t q = part.find('=');
                    if (q == std::string::npos) {
                        c.fault = true;
                        continue;
                    }
                    const std::string key = mq_spTrim(part.substr(0, q));
                    const std::string val = mq_spTrim(part.substr(q + 1));
                    if (strcasecmp(key.c_str(), "dev") == 0) {
                        // A device id; 'live' and 'cfg-*' are Live Demand's.
                        c.dev = val;
                        if (val.empty() || val.size() > 47 ||
                            val.find_first_of("+/#") != std::string::npos ||
                            strcmp(val.c_str(), "live") == 0 || strncmp(val.c_str(), "cfg-", 4) == 0) {
                            c.fault = true;
                        }
                        continue;
                    }
                    if (strcasecmp(key.c_str(), "u") == 0) {
                        c.unitsRef = !val.empty() && val[0] == '@';
                        c.units = c.unitsRef ? mq_spTrim(val.substr(1)) : val;
                        if (c.unitsRef && c.units.empty()) c.fault = true;
                        continue;
                    }
                    char* stop = nullptr;
                    const double num = strtod(val.c_str(), &stop);
                    if (val.empty() || stop == nullptr || *stop != '\0') {
                        c.fault = true;
                        continue;
                    }
                    if (strcasecmp(key.c_str(), "db") == 0) c.band = (float)num;
                    else if (strcasecmp(key.c_str(), "pct") == 0) {
                        c.pct = (float)num;
                        c.hasPct = true;
                    } else if (strcasecmp(key.c_str(), "lo") == 0) c.low = (float)num;
                    else if (strcasecmp(key.c_str(), "hi") == 0) c.high = (float)num;
                    else if (strcasecmp(key.c_str(), "pulse") == 0)
                        c.pulseNs = (int64_t)(num * 1000000.0);
                    else c.fault = true;
                }
                if (!(c.band >= 0.0f) || !(c.pct >= 0.0f) || c.pulseNs < 0) c.fault = true;
                // A pulse takes back a write: only a class the host writes has one.
                if (c.pulseNs > 0 && !mq_spIsWritableKind(c.kind)) c.fault = true;
                // live and set:<page> are devices of their own already.
                if (!c.dev.empty() && (c.kind == MQ_SP_LIVE || c.kind == MQ_SP_SET)) c.fault = true;
            }
            out.push_back(c);
        }
        if (end >= all.size()) break;
    }
}

// Whether `pattern` covers `path`, segment by segment ('.'): '*' is any one
// segment, a name without an index covers it with one ('spare' covers
// 'spare[3]'), and the path may go on past the pattern ('pump' covers
// 'pump.hours'). Case does not matter. `exact`: the pattern names the value itself.
static bool mq_spCovers(const char* path, const char* pattern, bool* exact) {
    bool whole = true;
    const char* p = path;
    const char* q = pattern;
    for (;;) {
        const char* pe = p;
        while (*pe != '\0' && *pe != '.') pe++;
        const char* qe = q;
        while (*qe != '\0' && *qe != '.') qe++;
        const size_t pn = (size_t)(pe - p), qn = (size_t)(qe - q);
        if (qn == 1 && q[0] == '*') {
            whole = false;
        } else if (pn == qn && strncasecmp(p, q, qn) == 0) {
            // the same segment
        } else if (pn > qn && p[qn] == '[' && memchr(q, '[', qn) == nullptr &&
                   strncasecmp(p, q, qn) == 0) {
            whole = false;
        } else {
            return false;
        }
        if (*qe == '\0') {
            if (exact) *exact = whole && *pe == '\0';
            return true;
        }
        if (*pe == '\0') return false;
        p = pe + 1;
        q = qe + 1;
    }
}

template <typename Visit>
static void mq_spRecordValue(const std::string& path, uint32_t offset,
                             strucpp::TYPE_CLASS cls, uint32_t bytes,
                             uint32_t cap, Visit& visit) {
    MqttSparkplugDataType type = MqttSparkplugDataType::Unknown;
    const bool text = (cls == strucpp::TYPE_STRING);
    // An enumeration travels as the unsigned integer it is stored as.
    if (cls == strucpp::TYPE_ENUM) {
        if (bytes == 1) cls = strucpp::TYPE_USINT;
        else if (bytes == 2) cls = strucpp::TYPE_UINT;
        else if (bytes == 4) cls = strucpp::TYPE_UDINT;
    }
    // No Sparkplug datatype (DATE, TOD), or a STRING whose capacity the layout lacks.
    if (!mq_spTypeOfClass((int)cls, &type) || (text && cap == 0)) return;
    visit(path, offset, cls, (uint32_t)(text ? cap : (bytes > 0 ? bytes : 1)));
}

// Every value of a STRUCT, in declared order, named by path: level,
// pump.hours, spare[3] (array elements from 1, whatever the bounds).
template <typename Visit>
static void mq_spRecordWalk(const strucpp::TypeDesc* d, uint32_t base,
                            std::string& path, int depth, Visit& visit) {
    if (d == nullptr || depth > 8) return;
    for (uint16_t i = 0; i < d->MEMBERCOUNT; i++) {
        const strucpp::MemberDesc& m = d->MEMBERS[i];
        const size_t mark = path.size();
        path += (m.NAME ? m.NAME : "?");
        const uint32_t at = base + m.BYTEOFFSET;
        if (m.TYPECLASS == strucpp::TYPE_USERDEF) {
            path += '.';
            mq_spRecordWalk(m.NESTED, at, path, depth + 1, visit);
        } else if (m.TYPECLASS == strucpp::TYPE_ARRAY) {
            const size_t name = path.size();
            for (uint32_t e = 0; e < m.NUMELEMENTS; e++) {
                path.resize(name);
                path += '[';
                path += std::to_string((unsigned long)(e + 1));
                path += ']';
                const uint32_t where = at + e * m.STRIDE;
                if (m.BASETYPECLASS == strucpp::TYPE_USERDEF) {
                    path += '.';
                    mq_spRecordWalk(m.NESTED, where, path, depth + 1, visit);
                } else {
                    mq_spRecordValue(path, where, m.BASETYPECLASS,
                                     m.ELEMBITSIZE / 8, m.CAP, visit);
                }
            }
        } else {
            mq_spRecordValue(path, at, m.TYPECLASS, m.BITSIZE / 8, m.CAP, visit);
        }
        path.resize(mark);
    }
}

static strucpp::IEC_ANY mq_spLeafAny(const MqSpLeaf& leaf, uint8_t* base) {
    strucpp::IEC_ANY any;
    any.TYPECLASS = (strucpp::TYPE_CLASS)leaf.cls;
    any.ELEMCLASS = (strucpp::TYPE_CLASS)leaf.cls;
    any.PVALUE = base + leaf.offset;
    any.DISIZE = leaf.size;
    any.DICOUNT = 1;
    return any;
}

// A member of anyUnits by path, as text: the units u=@<member> names.
static bool mq_spUnitsText(const strucpp::IEC_ANY& units, const char* member,
                           std::string& out) {
    if (!units.wired() || units.TYPECLASS != strucpp::TYPE_USERDEF ||
        units.TYPEDESC == nullptr || units.PVALUE == nullptr) {
        return false;
    }
    bool found = false;
    auto visit = [&](const std::string& path, uint32_t offset,
                     strucpp::TYPE_CLASS cls, uint32_t size) {
        if (found || cls != strucpp::TYPE_STRING ||
            strcasecmp(path.c_str(), member) != 0) {
            return;
        }
        const char* text = (const char*)(units.PVALUE + offset);
        out.assign(text, strnlen(text, size));
        found = true;
    };
    std::string path;
    mq_spRecordWalk(units.TYPEDESC, 0, path, 0, visit);
    return found;
}

// A fingerprint of anyUnits' texts: a change re-applies the units (shown at the next birth).
static uint32_t mq_spUnitsSum(const strucpp::IEC_ANY& units) {
    if (!units.wired() || units.TYPECLASS != strucpp::TYPE_USERDEF ||
        units.TYPEDESC == nullptr || units.PVALUE == nullptr) {
        return 0;
    }
    uint32_t h = 2166136261u;
    auto visit = [&](const std::string&, uint32_t offset, strucpp::TYPE_CLASS cls,
                     uint32_t size) {
        if (cls != strucpp::TYPE_STRING) return;
        const char* text = (const char*)(units.PVALUE + offset);
        h = mq_fingerprint(h, text, strnlen(text, size));
        h = mq_fingerprint(h, "", 1);
    };
    std::string path;
    mq_spRecordWalk(units.TYPEDESC, 0, path, 0, visit);
    return h;
}

// {"devices":["live","cfg-tanks"],"required":false}: what the node offers a viewer.
static void mq_spDemandOffer(MqttSparkplugNode* node, MqSpReport& report) {
    std::string offer = "{\"devices\":[";
    for (size_t i = 0; i < report.devices.size(); i++) {
        if (i > 0) offer += ',';
        offer += '"';
        offer += report.devices[i];
        offer += '"';
    }
    offer += "],\"required\":false}";
    report.offer = offer;
    if (report.demandPoint >= 0) {
        node->setAt((size_t)report.demandPoint, mq_spString(report.offer.c_str()));
    }
}

// The index of a device the records use, added to the node the first time.
static int mq_spRecordDevice(MqttSparkplugNode* node, MqSpReport& report,
                             const std::string& name) {
    for (size_t i = 0; i < report.devices.size(); i++) {
        if (report.devices[i] == name) return (int)i;
    }
    // Added here: brought online by Live Demand, never by a record.
    if (!node->addDevice(name.c_str()) && node->deviceIndexOf(name.c_str()) < 0) {
        return -1;
    }
    report.devices.push_back(name);
    report.demanded.push_back(0);
    report.online.push_back(0);
    mq_spDemandOffer(node, report);
    return (int)report.devices.size() - 1;
}

// Whether a device is one the records' Live Demand brings on and off line.
bool mq_spDeviceIsManaged(strucpp::XWORD_t reportHandle, const char* name) {
    MqSpReport* report = mq_spReportOf(reportHandle);
    if (name == nullptr) return false;
    if (strcmp(name, "live") == 0 || strncmp(name, "cfg-", 4) == 0) return true;
    if (report == nullptr) return false;
    for (size_t i = 0; i < report->devices.size(); i++) {
        if (report->devices[i] == name) return true;
    }
    return false;
}

// The value after `"key"` and its ':' in a JSON object, or nullptr.
static const char* mq_spJsonValue(const std::string& text, const char* key) {
    const std::string quoted = std::string("\"") + key + "\"";
    size_t at = text.find(quoted);
    if (at == std::string::npos) return nullptr;
    at += quoted.size();
    while (at < text.size() && (unsigned char)text[at] <= ' ') at++;
    if (at >= text.size() || text[at] != ':') return nullptr;
    at++;
    while (at < text.size() && (unsigned char)text[at] <= ' ') at++;
    return text.c_str() + at;
}

// One write of Live Demand: {"demand":true,"leaseS":120,"devices":["live",...]}.
// A write without "demand" is ignored; demand:false ends the viewing at once.
static void mq_spDemandWrite(MqSpReport& report, const std::string& text,
                             mq_time_t now) {
    const char* demand = mq_spJsonValue(text, "demand");
    if (demand == nullptr) return;
    bool on;
    if (strncmp(demand, "true", 4) == 0) on = true;
    else if (strncmp(demand, "false", 5) == 0) on = false;
    else return;
    for (size_t i = 0; i < report.demanded.size(); i++) report.demanded[i] = 0;
    if (!on) {
        report.viewed = false;
        return;
    }
    uint32_t leaseS = MQ_SP_LEASE_DEFAULT_S;
    const char* lease = mq_spJsonValue(text, "leaseS");
    if (lease != nullptr && *lease >= '0' && *lease <= '9') {
        const unsigned long v = strtoul(lease, nullptr, 10);
        if (v > 0 && v < 86400UL) leaseS = (uint32_t)v;
    }
    report.viewed = true;
    report.viewedAt = now;
    report.leaseMs = leaseS * 1000u;
    const char* list = mq_spJsonValue(text, "devices");
    if (list == nullptr || *list != '[') return;
    const char* p = list + 1;
    while (*p != '\0' && *p != ']') {
        if (*p != '"') {
            p++;
            continue;
        }
        const char* start = ++p;
        while (*p != '\0' && *p != '"') p++;
        const std::string name(start, (size_t)(p - start));
        for (size_t i = 0; i < report.devices.size(); i++) {
            if (report.devices[i] == name) report.demanded[i] = 1;
        }
        if (*p == '"') p++;
    }
}

// Every scan, after the node's poll: Live Demand's writes, its lease, and the
// devices it brings on and off line. sDemand lists the devices demanded now.
static void mq_spDemandStep(MqttSparkplugNode* node, MqSpReport& report) {
    std::string& demandList = report.demandList;
    const mq_time_t now = mq_millis();
    if (report.demandPoint >= 0) {
        const size_t dp = (size_t)report.demandPoint;
        bool wrote = false;
        MqttSparkplugValue value;
        while (node->commandPendingAt(dp) && node->takeAt(dp, value)) {
            wrote = true;
            // Longer than the metric takes: refused, never cut.
            if (!value.isText() || value.as.bytes.data == nullptr ||
                value.as.bytes.length > MQ_SP_DEMAND_MAX) {
                continue;
            }
            mq_spDemandWrite(report,
                             std::string((const char*)value.as.bytes.data,
                                         value.as.bytes.length),
                             now);
        }
        if (wrote) {
            // The offer is put back after each write.
            node->setAt(dp, mq_spString(report.offer.c_str()));
            if (node->changePendingAt(dp)) node->publishAtPoll();
        }
    }
    if (report.viewed && mq_elapsed(report.viewedAt, now) >= report.leaseMs) {
        report.viewed = false;
        for (size_t i = 0; i < report.demanded.size(); i++) report.demanded[i] = 0;
    }
    demandList.clear();
    for (size_t i = 0; i < report.devices.size(); i++) {
        const bool want = report.viewed && report.demanded[i] != 0;
        if (want) {
            if (!demandList.empty()) demandList += ',';
            demandList += report.devices[i];
        }
        if (want == (report.online[i] != 0)) continue;
        if (want) node->deviceOnline(report.devices[i].c_str());
        else node->deviceOffline(report.devices[i].c_str());
        report.online[i] = want ? 1 : 0;
    }
}

// The metric name of a value in a class: the prefix, then the path; live
// drops a leading 'det.', set a leading 'set.'.
static void mq_spMetricName(const std::string& prefix, const std::string& path,
                            uint8_t kind, std::string& out) {
    out.assign(prefix);
    const char* drop = kind == MQ_SP_LIVE ? "det." : kind == MQ_SP_SET ? "set." : nullptr;
    if (drop != nullptr && path.size() > 4 && strncasecmp(path.c_str(), drop, 4) == 0) {
        out.append(path, 4, std::string::npos);
    } else {
        out += path;
    }
}

static MqSpGroup& mq_spGroupFor(MqSpRecord& record, uint8_t kind, int device, int ownDevice,
                                int32_t periodMs) {
    for (size_t i = 0; i < record.groups.size(); i++) {
        const MqSpGroup& g = record.groups[i];
        if (g.kind == kind && g.device == device && g.ownDevice == ownDevice &&
            g.periodMs == periodMs) {
            return record.groups[i];
        }
    }
    record.groups.push_back(MqSpGroup());
    MqSpGroup& g = record.groups.back();
    g.kind = kind;
    g.device = (int16_t)device;
    g.ownDevice = (int16_t)ownDevice;
    g.periodMs = periodMs;
    return g;
}

// The index of a device of the program's own (dev=), added to the node the
// first time. Never brought on or off line here: that is the program's, with
// sp.Device, and Live Demand never touches it.
static int mq_spOwnDevice(MqttSparkplugNode* node, MqSpReport& report, const std::string& name) {
    for (size_t i = 0; i < report.ownDevices.size(); i++) {
        if (report.ownDevices[i] == name) return (int)i;
    }
    if (!node->addDevice(name.c_str()) && node->deviceIndexOf(name.c_str()) < 0) return -1;
    report.ownDevices.push_back(name);
    return (int)report.ownDevices.size() - 1;
}

// The device a group's metrics are on, or nullptr for the node.
static const char* mq_spGroupDevice(const MqSpReport& report, const MqSpGroup& group) {
    if (group.device >= 0) return report.devices[(size_t)group.device].c_str();
    if (group.ownDevice >= 0) return report.ownDevices[(size_t)group.ownDevice].c_str();
    return nullptr;
}

// Declares a record's members, once: each value takes one class on the node
// (the last now/cmd/view/log/every/onreq clause naming it without dev=), one on
// each dev= device the same way, its live class and each set page, as metrics
// of the node or of that device. Returns the first bad clause, from 1.
static int mq_spRecordDeclare(MqttSparkplugNode* node, MqSpReport& report,
                              MqSpRecord& record,
                              const std::vector<MqSpClause>& clauses,
                              const std::string& prefix) {
    std::vector<uint8_t> matched(clauses.size(), 0);
    std::vector<uint8_t> refused(clauses.size(), 0);
    std::vector<int> pages;           // per clause: its page's index among the set clauses
    std::vector<std::string> pageNames;
    for (size_t k = 0; k < clauses.size(); k++) {
        int page = -1;
        if (!clauses[k].fault && clauses[k].kind == MQ_SP_SET) {
            for (size_t p = 0; p < pageNames.size(); p++) {
                if (pageNames[p] == clauses[k].page) page = (int)p;
            }
            if (page < 0) {
                pageNames.push_back(clauses[k].page);
                page = (int)pageNames.size() - 1;
            }
        }
        pages.push_back(page);
    }
    std::vector<int> pageClause(pageNames.size(), -1);
    std::string name;
    auto declareIn = [&](uint8_t kind, int device, int ownDevice, int32_t periodMs, size_t k,
                         const std::string& path, uint32_t offset,
                         strucpp::TYPE_CLASS cls, uint32_t size) {
        bool named = false;
        for (size_t m = 0; m < clauses[k].members.size() && !named; m++) {
            bool exact = false;
            named = mq_spCovers(path.c_str(), clauses[k].members[m].c_str(), &exact) && exact;
        }
        MqttSparkplugDataType type = MqttSparkplugDataType::Unknown;
        mq_spTypeOfClass((int)cls, &type);
        mq_spMetricName(prefix, path, kind, name);
        const char* dev = device >= 0      ? report.devices[(size_t)device].c_str()
                          : ownDevice >= 0 ? report.ownDevices[(size_t)ownDevice].c_str()
                                           : nullptr;
        const bool writable = mq_spIsWritableKind(kind);
        uint64_t alias;
        if (dev != nullptr) {
            alias = writable ? node->declareWritableFor(dev, name.c_str(), type)
                             : node->declareFor(dev, name.c_str(), type);
        } else {
            alias = writable ? node->declareWritable(name.c_str(), type)
                             : node->declare(name.c_str(), type);
        }
        const int point = alias != 0 ? node->indexOf(dev, name.c_str()) : -1;
        if (point < 0) {
            // A name already taken on this node or device, or out of memory.
            refused[k] = 1;
            return;
        }
        MqSpLeaf leaf;
        leaf.offset = offset;
        leaf.point = (uint32_t)point;
        leaf.size = (uint16_t)size;
        leaf.cls = (uint8_t)cls;
        leaf.clause = (uint16_t)k;
        leaf.named = named ? 1 : 0;
        mq_spGroupFor(record, kind, device, ownDevice, periodMs).leaves.push_back(leaf);
        record.points++;
    };
    // Per value: the clause each scope (the node '', each dev=) takes it from.
    std::vector<std::pair<std::string, int>> scopes;
    auto visit = [&](const std::string& path, uint32_t offset,
                     strucpp::TYPE_CLASS cls, uint32_t size) {
        int liveClause = -1;
        scopes.clear();
        for (size_t p = 0; p < pageClause.size(); p++) pageClause[p] = -1;
        for (size_t k = 0; k < clauses.size(); k++) {
            const MqSpClause& c = clauses[k];
            if (c.fault) continue;
            bool covered = false;
            for (size_t m = 0; m < c.members.size() && !covered; m++) {
                covered = mq_spCovers(path.c_str(), c.members[m].c_str(), nullptr);
            }
            if (!covered) continue;
            matched[k] = 1;
            if (c.kind == MQ_SP_LIVE) {
                liveClause = (int)k;
            } else if (c.kind == MQ_SP_SET) {
                pageClause[(size_t)pages[k]] = (int)k;
            } else {
                bool seen = false;
                for (size_t sc = 0; sc < scopes.size(); sc++) {
                    if (scopes[sc].first == c.dev) {
                        scopes[sc].second = (int)k;
                        seen = true;
                    }
                }
                if (!seen) scopes.push_back(std::make_pair(c.dev, (int)k));
            }
        }
        for (size_t sc = 0; sc < scopes.size(); sc++) {
            const size_t k = (size_t)scopes[sc].second;
            int own = -1;
            if (!scopes[sc].first.empty()) {
                own = mq_spOwnDevice(node, report, scopes[sc].first);
                if (own < 0) {
                    refused[k] = 1;
                    continue;
                }
            }
            declareIn(clauses[k].kind, -1, own, clauses[k].periodMs, k, path, offset, cls, size);
        }
        if (liveClause >= 0) {
            const int device = mq_spRecordDevice(node, report, "live");
            if (device < 0) refused[(size_t)liveClause] = 1;
            else declareIn(MQ_SP_LIVE, device, -1, 0, (size_t)liveClause, path, offset, cls, size);
        }
        for (size_t p = 0; p < pageClause.size(); p++) {
            if (pageClause[p] < 0) continue;
            const int device = mq_spRecordDevice(node, report, "cfg-" + pageNames[p]);
            if (device < 0) refused[(size_t)pageClause[p]] = 1;
            else declareIn(MQ_SP_SET, device, -1, 0, (size_t)pageClause[p], path, offset, cls, size);
        }
    };
    std::string path;
    mq_spRecordWalk(record.type, 0, path, 0, visit);

    for (size_t g = 0; g < record.groups.size(); g++) {
        if (mq_spIsViewedKind(record.groups[g].kind) && report.demandPoint < 0) {
            // Live Demand: the platform's viewer contract, offered by the node.
            if (node->declareWritable(MQ_SP_LIVE_DEMAND, MqttSparkplugDataType::String) != 0) {
                report.demandPoint = node->indexOf(nullptr, MQ_SP_LIVE_DEMAND);
                mq_spDemandOffer(node, report);
            }
        }
    }
    for (size_t k = 0; k < clauses.size(); k++) {
        if (clauses[k].fault || !matched[k] || refused[k]) return (int)k + 1;
    }
    return 0;
}

// Deadbands, units, ranges and pulses, from the clauses; again whenever the
// text, anyUnits or the log deadband changes. Returns the first bad clause.
static int mq_spRecordApply(MqttSparkplugNode* node, MqSpRecord& record,
                            const std::vector<MqSpClause>& clauses,
                            const strucpp::IEC_ANY& units, float defaultPct) {
    int bad = 0;
    std::vector<uint8_t> fault(clauses.size(), 0);
    std::string unitsText;
    record.usesUnits = false;
    for (size_t g = 0; g < record.groups.size(); g++) {
        MqSpGroup& group = record.groups[g];
        for (size_t i = 0; i < group.leaves.size(); i++) {
            const MqSpLeaf& leaf = group.leaves[i];
            if (leaf.clause >= clauses.size()) continue;
            const MqSpClause& c = clauses[leaf.clause];
            const bool analog = leaf.cls == strucpp::TYPE_REAL || leaf.cls == strucpp::TYPE_LREAL;
            // The log class's deadband % is the node's where the clause gives none.
            const double pct = c.hasPct ? (double)c.pct
                               : (group.kind == MQ_SP_LOG && analog ? (double)defaultPct : 0.0);
            if (!node->deadbandAt(leaf.point, (double)c.band, pct)) {
                // A deadband on a BOOL or STRING would freeze it: an error when the
                // clause names that member itself, else it reports every change.
                node->deadbandAt(leaf.point, 0.0, 0.0);
                if (leaf.named) fault[leaf.clause] = 1;
            }
            // A TIME goes as milliseconds.
            const char* text = leaf.cls == strucpp::TYPE_TIME ? "ms" : "";
            if (c.unitsRef) {
                record.usesUnits = true;
                if (mq_spUnitsText(units, c.units.c_str(), unitsText)) text = unitsText.c_str();
                else fault[leaf.clause] = 1;
            } else if (!c.units.empty()) {
                text = c.units.c_str();
            }
            node->unitsAt(leaf.point, text);
            node->rangeAt(leaf.point, (double)c.low, (double)c.high);
            if (c.pulseNs > 0 && group.pulses.empty()) group.pulses.resize(group.leaves.size());
            if (!group.pulses.empty()) group.pulses[i].pulseNs = c.pulseNs;
        }
    }
    for (size_t k = 0; k < clauses.size() && bad == 0; k++) {
        if (fault[k] || clauses[k].fault) bad = (int)k + 1;
    }
    return bad;
}

// One group's scan: writes in (or refused while the host may not write),
// pulses, values into the node, and what is to go. Ported from the 0.1
// SPARKPLUG_STRUCT, with its mode fixed by the class. Returns QueueFull when a
// message asked for could not be queued, else Ok. `request`: Record's bSend
// rose this scan (onreq).
static uint8_t mq_spGroupScan(MqttSparkplugNode* node, MqSpReport& report,
                              MqSpGroup& group, uint8_t* base, bool remote,
                              int32_t intervalMs, bool request) {
    MqSpLeaf* const leaves = group.leaves.data();
    const size_t count = group.leaves.size();
    const char* device = mq_spGroupDevice(report, group);
    const bool born = node->isBorn();
    const bool online = born && (device == nullptr || node->deviceIsOnline(device));
    const bool changedEvery = group.kind == MQ_SP_LOG || group.kind == MQ_SP_LIVE;
    // every:<time> and onreq send the whole set, on their own clock or edge.
    const bool wholeSet = group.kind == MQ_SP_EVERY || group.kind == MQ_SP_ONREQ;
    const bool enabled =
        group.kind == MQ_SP_VIEW ? report.viewed
        : device != nullptr      ? online
                                 : true;
    const mq_time_t now = mq_millis();

    // Held: an interval class goes on its clock, and a class switched off
    // keeps its values current without riding along in other reports.
    const bool hold = changedEvery || wholeSet || !enabled;
    if (hold != group.held) {
        group.held = hold;
        for (size_t i = 0; i < count; i++) node->holdAt(leaves[i].point, hold);
    }
    const bool bornNow = online && !group.wasOnline;
    // A birth carried every member, so an every:<time> set counts its period from it.
    const uint32_t births = node->birthCount();
    if (online && (!group.wasOnline || births != group.births) && group.kind == MQ_SP_EVERY) {
        group.everSent = true;
        group.sentAt = now;
    }
    group.births = births;
    group.wasOnline = online;

    // What became of the message asked for last.
    bool askFailed = false;
    if (group.asking && node->pollPublishes() != group.askedAt) {
        group.asking = false;
        if (!node->pollPublishSent() && online) askFailed = true;
    }

    // Writes the host may not make now: taken and dropped, the value put back.
    const bool writable = mq_spIsWritableKind(group.kind);
    const uint32_t applied = node->commandsApplied();
    if (writable && !remote && (applied != group.writesSeen || group.writesLeft)) {
        group.writesSeen = applied;
        group.writesLeft = false;
        for (size_t i = 0; i < count; i++) {
            MqttSparkplugValue value;
            bool dropped = false;
            while (node->commandPendingAt(leaves[i].point) &&
                   node->takeAt(leaves[i].point, value)) {
                dropped = true;
            }
            if (dropped && mq_spValueOfAny(mq_spLeafAny(leaves[i], base), &value)) {
                node->setAt(leaves[i].point, value);
            }
        }
    }

    if (!enabled) {
        group.wasEnabled = false;
        for (size_t i = 0; i < count; i++) {
            MqttSparkplugValue value;
            if (mq_spValueOfAny(mq_spLeafAny(leaves[i], base), &value)) {
                node->setAt(leaves[i].point, value);
            }
        }
        return askFailed ? (uint8_t)E_MQTTRESULT::QUEUEFULL : (uint8_t)E_MQTTRESULT::OK;
    }
    if (!group.wasEnabled) {
        group.wasEnabled = true;
        // Switched on: an interval class sends what moved at once, unless its
        // birth this scan carried every member; an every:<time> set goes at once.
        if ((changedEvery || group.kind == MQ_SP_EVERY) && !bornNow) group.everSent = false;
    }

    // Commands before values, so a write is reported back in the same message.
    const bool takeWrites = born && writable && remote &&
        (applied != group.writesSeen || group.writesLeft);
    if (takeWrites) {
        group.writesSeen = applied;
        group.writesLeft = false;
    }
    const bool watch = online && !changedEvery && !wholeSet;
    int going = 0;
    for (size_t i = 0; i < count; i++) {
        MqSpLeaf& leaf = leaves[i];
        if (takeWrites) {
            MqttSparkplugValue value;
            if (node->commandPendingAt(leaf.point) && node->takeAt(leaf.point, value)) {
                if (mq_spWriteAny(mq_spLeafAny(leaf, base), value)) {
                    if (!group.pulses.empty() && group.pulses[i].pulseNs > 0) {
                        MqSpPulse& pulse = group.pulses[i];
                        if (!pulse.pulsing) group.pulsing++;
                        pulse.pulsing = true;
                        pulse.writtenAt = now;
                    }
                }
            }
            if (node->commandPendingAt(leaf.point)) group.writesLeft = true;
        }
        if (group.pulsing > 0 && group.pulses[i].pulsing) {
            MqSpPulse& pulse = group.pulses[i];
            const int64_t heldNs = (int64_t)mq_elapsed(pulse.writtenAt, now) * 1000000LL;
            if (heldNs >= pulse.pulseNs) {
                pulse.pulsing = false;
                group.pulsing--;
                uint8_t* at = base + leaf.offset;
                if (leaf.cls == strucpp::TYPE_STRING) at[0] = '\0';
                else if (leaf.cls == strucpp::TYPE_BOOL) *(bool*)at = false;
                else memset(at, 0, (size_t)leaf.size);
            }
        }
        // The value into the node, born or not: the birth carries it.
        MqttSparkplugValue value;
        if (mq_spValueOfAny(mq_spLeafAny(leaf, base), &value)) node->setAt(leaf.point, value);
        if (watch && node->changePendingAt(leaf.point)) going++;
    }
    if (!online || count == 0) {
        return askFailed ? (uint8_t)E_MQTTRESULT::QUEUEFULL : (uint8_t)E_MQTTRESULT::OK;
    }

    bool ask = false;
    if (wholeSet) {
        // The whole set: every period, or on bSend's edge; one the node could
        // not queue is asked for again at once.
        const bool due = group.kind == MQ_SP_ONREQ
                             ? request
                             : !group.everSent ||
                                   (int32_t)mq_elapsed(group.sentAt, now) >= group.periodMs;
        if (due || askFailed) {
            for (size_t i = 0; i < count; i++) node->reportAt(leaves[i].point);
            ask = true;
            if (group.kind == MQ_SP_EVERY && due) {
                group.everSent = true;
                group.sentAt = now;
            }
        }
    } else if (!changedEvery) {
        ask = going > 0;
    } else {
        // Every interval, what moved past its deadband since it was last sent.
        // On the node's clock, so every group with the same interval looks in
        // the same scan and their changes go in one message.
        const uint32_t slot = (uint32_t)now / (uint32_t)intervalMs;
        if (askFailed) {
            ask = true;
        } else if (!group.everSent || slot != group.slot) {
            int marked = 0;
            for (size_t i = 0; i < count; i++) {
                const size_t point = leaves[i].point;
                node->holdAt(point, false);
                const bool moved = node->changePendingAt(point);
                node->holdAt(point, true);
                if (moved) {
                    node->reportAt(point);
                    marked++;
                }
            }
            ask = marked > 0;
            group.everSent = true;
            group.slot = slot;
        }
    }
    if (ask) {
        node->publishAtPoll();
        if (!group.asking) {
            group.asking = true;
            group.askedAt = node->pollPublishes();
        }
    }
    return askFailed ? (uint8_t)E_MQTTRESULT::QUEUEFULL : (uint8_t)E_MQTTRESULT::OK;
}

static bool mq_spSame(const std::string& kept, const char* text) {
    return strcmp(kept.c_str(), text != nullptr ? text : "") == 0;
}

// The same record: its declared name and type, and the prefix. The address is
// only a cache: an online change moves a record, its name stays.
static bool mq_spRecordIs(const MqSpRecord& record, const strucpp::IEC_ANY& data,
                          const char* prefix) {
    return mq_spSame(record.name, data.NAME) &&
           mq_spSame(record.typeName, data.TYPENAME) &&
           mq_spSame(record.prefix, prefix);
}

static E_MQTTRESULT mq_spRecordFail(MqSpReport& report, const strucpp::IEC_ANY& data,
                                    const char* prefix, E_MQTTRESULT result, int bad) {
    report.failKey.assign(data.NAME != nullptr ? data.NAME : "");
    report.failKey += '\n';
    report.failKey += prefix;
    report.failResult = (uint8_t)result;
    report.failText = "Record ";
    report.failText += data.NAME != nullptr && data.NAME[0] != '\0' ? data.NAME
                       : data.TYPENAME != nullptr ? data.TYPENAME : "?";
    if (bad > 0) {
        report.failText += ": clause ";
        report.failText += std::to_string(bad);
    } else if (bad == -2) {
        report.failText += ": tLiveInterval is T#0s";
    } else if (bad == -3) {
        report.failText += ": tLogInterval is T#0s";
    } else if (bad < 0) {
        report.failText += ": not a STRUCT with a STRING point list";
    } else {
        report.failText += ": message not queued";
    }
    return result;
}

// A call that succeeds clears the failure it reported before.
static void mq_spRecordClear(MqSpReport& report, const strucpp::IEC_ANY& data,
                             const char* prefix) {
    if (report.failKey.empty()) return;
    const char* name = data.NAME != nullptr ? data.NAME : "";
    const size_t n = strlen(name);
    if (report.failKey.compare(0, n, name) == 0 && report.failKey.size() > n &&
        report.failKey[n] == '\n' && strcmp(report.failKey.c_str() + n + 1, prefix) == 0) {
        report.failKey.clear();
        report.failText.clear();
    }
}

void setup()
{
    bLinkUp = false;
    bBorn = false;
    nSeq = 0;
    nBdSeq = 0;
    nPoints = 0;
    bError = false;
    eErrorId = E_MQTTRESULT::OK;
    sLastError = "";
    bClockSet = false;
    nApi = (strucpp::XWORD_t)0;
    nClient = (strucpp::XWORD_t)0;
    bConnectAsked = false;
    nDeclaredAt = 0;
    nSessionKey = 0;
    nReport = (strucpp::XWORD_t)0;
    nBirthsSeen = 0;
    nPointsBorn = 0;
    bViewed = false;
    sDemand = "";
}

void loop()
{
    nTask = mq_currentTask();   // every method of this block shares it

    // --- THE CONNECTION IS FB_MqttClient'S ---
    //
    // Where, how, as whom and whether to be connected at all: its pins, its
    // stSessionConfig, stTlsConfig and stNetworkConfig. This node rides on that session,
    // with the device's own topics and its firmware updates beside it, and
    // takes what Sparkplug needs of it on every CONNECT: the Will (its NDEATH),
    // Clean Start, and a transmit buffer that holds the birth certificate.
    if (!mq_inTask((strucpp::XWORD_t)fbClient.NTASK)) {   // one task per client: see FB_MqttClient
        bLinkUp = false;
        bBorn = false;
        bError = true;
        eErrorId = E_MQTTRESULT::WRONGTASK;
        sLastError = "put FB_SparkplugNode in its FB_MqttClient's task";
        return;
    }
    MqttClient* client = mq_clientOf((strucpp::XWORD_t)fbClient.NAPI);
    if (client == nullptr) {
        // Not built yet - its first scan has not run, or it is out of memory,
        // which it says itself.
        bLinkUp = false;
        bBorn = false;
        bError = false;
        eErrorId = E_MQTTRESULT::NOTINITIALISED;
        sLastError = "waiting for its FB_MqttClient";
        return;
    }

    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)nApi);
    if (!(bool)bEnable) {
        // The NDEATH goes by hand and the connection stays up for everything
        // else on it; declarations stay for the next bEnable.
        if (node) {
            node->disconnect();
            node->poll();
        }
        bLinkUp = client->isConnected();
        bBorn = false;
        bConnectAsked = false;
        bError = false;
        eErrorId = E_MQTTRESULT::OK;
        sLastError = "";
        return;
    }

    // sGroupId, sEdgeNodeId and sPrimaryHostId: who this node is. Read every scan.
    auto identityKey = [&]() -> uint32_t {
        uint32_t h = 2166136261u;
        h = mq_fingerprintText(h, sGroupId.c_str());
        h = mq_fingerprintText(h, sEdgeNodeId.c_str());
        h = mq_fingerprintText(h, sPrimaryHostId.c_str());
        return h;
    };
    auto applyIdentity = [&](MqttSparkplugNode* n) -> bool {
        if (sGroupId.length() == 0 || sEdgeNodeId.length() == 0) {
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
            sLastError = "a Sparkplug node needs a sGroupId and a sEdgeNodeId";
            return false;
        }
        if (!n->group(sGroupId.c_str()) || !n->node(sEdgeNodeId.c_str())) {
            bError = true;
            eErrorId = E_MQTTRESULT::INVALIDTOPIC;
            sLastError = "sGroupId or sEdgeNodeId contains + / or #";
            return false;
        }
        n->primaryHost(sPrimaryHostId.c_str());   // empty: none
        return true;
    };

    // --- Build once ---
    //
    // On the first enabled scan, for the life of the program. A PLC does not
    // restart its blocks, and a node that rebuilt itself would lose its metric
    // declarations - which cannot be re-made, because the birth certificate
    // has already described them.
    if (node == nullptr) {
        node = new (std::nothrow) MqttSparkplugNode(*client);
        if (node == nullptr) {
            bError = true;
            eErrorId = E_MQTTRESULT::NOTINITIALISED;
            sLastError = "out of memory";
            return;
        }
        if (!applyIdentity(node)) {
            delete node;
            return;
        }
        // Up to four host writes per writable metric are kept between scans,
        // so a setpoint written twice in one scan loses neither.
        node->queueWrites(4);
        mqSpNodesOwned().all.push_back(node);
        MqSpReport* report = new (std::nothrow) MqSpReport();
        if (report != nullptr) {
            mqSpReportsOwned().all.push_back(report);
            nReport = (strucpp::XWORD_t)(uintptr_t)report;
        }
        nApi = (strucpp::XWORD_t)(uintptr_t)node;
        nClient = (strucpp::XWORD_t)(uintptr_t)client;
        nSessionKey = identityKey();
        // The methods declare on this scan, wherever they
        // sit in the program; the node connects on a later one.
        nDeclaredAt = (int32_t)mq_millis();
        bLinkUp = client->isConnected();
        return;
    }
    if ((strucpp::XWORD_t)(uintptr_t)client != (strucpp::XWORD_t)nClient) {
        bError = true;
        eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
        sLastError = "fbClient changed while running - restart the PLC";
        return;
    }

    // The shortest time between two answers to rebirth requests. Read every scan.
    const int32_t holdoffMs = mq_millisOf(tRebirthHoldoff);
    node->rebirthHoldoff((mq_time_t)(holdoffMs > 0 ? holdoffMs : 0));

    // --- A NEW IDENTITY IS A NEW sEdgeNodeId TO THE HOST ---
    //
    // It leaves under the old one (the host sees that NDEATH) and births under
    // the new one with the next bdSeq. Declarations and devices stay, so
    // nothing else in the program notices.
    const uint32_t identity = identityKey();
    if (identity != (uint32_t)nSessionKey) {
        nSessionKey = identity;
        node->disconnect();
        if (!applyIdentity(node)) {
            bLinkUp = client->isConnected();
            bBorn = false;
            return;
        }
        bConnectAsked = false;
        nDeclaredAt = (int32_t)mq_millis();
    }

    if (!bConnectAsked) {
        // A node with nothing declared would birth an empty certificate and
        // have to rebirth for the first metric: give the declaring blocks a
        // moment, then birth whatever there is.
        if (node->pointCount() == 0 &&
            (int32_t)mq_elapsed((mq_time_t)(uint32_t)nDeclaredAt, mq_millis()) < 2000) {
            node->poll();
            bLinkUp = client->isConnected();
            return;
        }
        // Refused only when another layer owns the client's Will - a
        // FB_SparkplugHost, or a second node on the same client - and then it is
        // asked again every scan, so removing that one is enough.
        bConnectAsked = node->connect();
    }
    node->poll();

    // A BIRTH CARRIES EVERY METRIC. One declared after it (a Record or Metric
    // first called later) gets a new birth sequence; until then it would go
    // in data messages a host has no birth for.
    if (node->isBorn()) {
        const uint32_t births = node->nodeBirthCount();
        const uint32_t points = (uint32_t)node->pointCount();
        if (births != (uint32_t)nBirthsSeen) {
            nBirthsSeen = births;
            nPointsBorn = points;
        } else if (points > (uint32_t)nPointsBorn) {
            nPointsBorn = points;
            node->rebirth();
        }
    }

    // Live Demand: its writes and lease, and the devices it brings on line.
    MqSpReport* report = mq_spReportOf((strucpp::XWORD_t)nReport);
    if (report != nullptr) {
        if (report->usesUnits) report->unitsSum = mq_spUnitsSum(anyUnits);
        mq_spDemandStep(node, *report);
        bViewed = report->viewed;
        sDemand = report->demandList.c_str();
    }

    bLinkUp = client->isConnected();
    bBorn = node->isBorn();
    nSeq = (uint8_t)node->sequence();
    nBdSeq = (uint8_t)node->birthDeathSequence();
    nPoints = (int16_t)node->pointCount();
    bClockSet = node->clockIsSet();

    if (!bConnectAsked) {
        bError = true;
        eErrorId = E_MQTTRESULT::REFUSED;
        sLastError = node->waitingFor();
        return;
    }
    if (node->outOfMemory()) {
        bError = true;
        eErrorId = E_MQTTRESULT::QUEUEFULL;
        sLastError = "out of memory for metrics or devices";
        return;
    }
    const MqttSparkplugError payloadError = node->lastPayloadError();
    if (payloadError != MqttSparkplugError::None) {
        bError = true;
        eErrorId = E_MQTTRESULT::INVALIDARGUMENT;
        sLastError = mq_sparkplugErrorName(payloadError);
        return;
    }
    if (report != nullptr && !report->failKey.empty()) {
        // A Record call that failed, by its record's name.
        bError = true;
        eErrorId = static_cast<E_MQTTRESULT>(report->failResult);
        sLastError = report->failText.c_str();
        return;
    }
    if (!bLinkUp) {
        // Why the link is down is FB_MqttClient's to say, on its own pins.
        bError = false;
        eErrorId = E_MQTTRESULT::NOTCONNECTED;
        sLastError = "FB_MqttClient is not connected";
        return;
    }
    bError = false;
    eErrorId = E_MQTTRESULT::OK;
    sLastError = node->waitingFor();
}

// sp.Record(anyData := DEV.pump, sSettings := '...', sPrefix := 'pump/'):
// a standing method, called every scan while the record is to be reported.
E_MQTTRESULT Record()
{
    nMetricCnt = 0;
    nBadClause = 0;
    if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)nApi);
    MqSpReport* report = mq_spReportOf((strucpp::XWORD_t)nReport);
    if (node == nullptr || report == nullptr) return E_MQTTRESULT::NOTINITIALISED;

    const char* prefix = sPrefix.c_str();
    if (anyData.TYPECLASS != strucpp::TYPE_USERDEF || anyData.TYPEDESC == nullptr ||
        anyData.PVALUE == nullptr || !sSettings.wired() ||
        sSettings.TYPECLASS != strucpp::TYPE_STRING || sSettings.PVALUE == nullptr) {
        // One STRUCT and its point list as a STRING: anything else is refused.
        nBadClause = -1;
        return mq_spRecordFail(*report, anyData, prefix, E_MQTTRESULT::INVALIDARGUMENT, -1);
    }
    const char* text = (const char*)sSettings.PVALUE;
    const int32_t bound = sSettings.DISIZE;

    // --- The record's state: found by its address, else by its name ---
    MqSpRecord* record = nullptr;
    for (size_t i = 0; i < report->records.size() && record == nullptr; i++) {
        MqSpRecord* r = report->records[i];
        if (r->address == anyData.PVALUE && r->type == anyData.TYPEDESC &&
            mq_spRecordIs(*r, anyData, prefix)) {
            record = r;
        }
    }
    for (size_t i = 0; i < report->records.size() && record == nullptr; i++) {
        MqSpRecord* r = report->records[i];
        if (r->type == anyData.TYPEDESC && mq_spRecordIs(*r, anyData, prefix)) {
            r->address = anyData.PVALUE;
            record = r;
        }
    }
    std::vector<MqSpClause> clauses;
    if (record == nullptr) {
        // --- Declared once, before the node births: the birth carries every metric ---
        record = new (std::nothrow) MqSpRecord();
        if (record == nullptr) {
            return mq_spRecordFail(*report, anyData, prefix, E_MQTTRESULT::QUEUEFULL, 0);
        }
        record->name = anyData.NAME != nullptr ? anyData.NAME : "";
        record->typeName = anyData.TYPENAME != nullptr ? anyData.TYPENAME : "";
        record->prefix = prefix;
        record->address = anyData.PVALUE;
        record->type = anyData.TYPEDESC;
        report->records.push_back(record);
        mq_spParseClauses(text, bound, clauses);
        record->clauses = (uint16_t)clauses.size();
        record->declareBad = (int16_t)mq_spRecordDeclare(node, *report, *record, clauses,
                                                         record->prefix);
    }

    // --- Options: whenever the text, the units or the log deadband change ---
    size_t length = 0;
    while ((bound <= 0 || (int32_t)length < bound) && text[length] != '\0') length++;
    const uint32_t sum = mq_fingerprint(2166136261u, text, length);
    float pct = (float)stReportConfig.FDEADBANDPCT;
    if (!(pct >= 0.0f)) pct = 0.0f;
    if (!record->applied || sum != record->settingsSum || pct != record->defaultPct ||
        (record->usesUnits && report->unitsSum != record->unitsSum)) {
        if (clauses.empty()) mq_spParseClauses(text, bound, clauses);
        int bad;
        if (clauses.size() != record->clauses) {
            // The members were read at the first call; a clause added or
            // removed since then would not line up with them.
            bad = (int)(clauses.size() < record->clauses ? clauses.size() : record->clauses) + 1;
        } else {
            bad = mq_spRecordApply(node, *record, clauses, anyUnits, pct);
        }
        record->bad = (int16_t)(record->declareBad != 0 ? record->declareBad : bad);
        record->applied = true;
        record->settingsSum = sum;
        record->defaultPct = pct;
        if (record->usesUnits) {
            report->usesUnits = true;
            record->unitsSum = report->unitsSum;
        }
    }
    nMetricCnt = record->points;
    nBadClause = record->bad;

    // --- Each class on its own clock ---
    int32_t logMs = mq_millisOf(stReportConfig.TLOGINTERVAL);
    if (logMs > MQ_SP_LOG_MAX_MS) logMs = MQ_SP_LOG_MAX_MS;
    const int32_t liveMs = mq_millisOf(stReportConfig.TLIVEINTERVAL);
    const bool request = (bool)bSend && !record->lastSend;
    record->lastSend = (bool)bSend;
    bool queueFull = false;
    int noInterval = 0;                // -2 tLiveInterval, -3 tLogInterval
    for (size_t g = 0; g < record->groups.size(); g++) {
        MqSpGroup& group = record->groups[g];
        int32_t interval = 0;
        if (group.kind == MQ_SP_LOG) interval = report->viewed ? liveMs : logMs;
        else if (group.kind == MQ_SP_LIVE) interval = liveMs;
        if ((group.kind == MQ_SP_LOG || group.kind == MQ_SP_LIVE) && interval <= 0) {
            // Never "every scan": a whole record at the task rate floods the link.
            noInterval = group.kind == MQ_SP_LOG && !report->viewed ? -3 : -2;
            continue;
        }
        if (mq_spGroupScan(node, *report, group, anyData.PVALUE,
                           (bool)stReportConfig.BREMOTECONTROL, interval, request) ==
            (uint8_t)E_MQTTRESULT::QUEUEFULL) {
            queueFull = true;
        }
    }

    if (record->bad != 0) {
        return mq_spRecordFail(*report, anyData, prefix, E_MQTTRESULT::INVALIDARGUMENT,
                               record->bad);
    }
    if (noInterval != 0) {
        return mq_spRecordFail(*report, anyData, prefix, E_MQTTRESULT::INVALIDARGUMENT, noInterval);
    }
    if (queueFull) {
        return mq_spRecordFail(*report, anyData, prefix, E_MQTTRESULT::QUEUEFULL, 0);
    }
    mq_spRecordClear(*report, anyData, prefix);
    return node->isBorn() ? E_MQTTRESULT::OK : E_MQTTRESULT::NOTCONNECTED;
}

// =============================================================================
// THE METHODS: Metric, Device, Command, History, DayTotals
// =============================================================================
//
// Refused outside this block's task. Each call keeps its state in a row of
// this node's table (nMethodCalls), kept as long as the program runs.
//
// A row is keyed by what the call is about: device and metric name (with the
// ANY's declared name and type for Metric and DayTotals), the device, or the
// event prefix.

#include <sparkplug/MqttSparkplugHistory.h>
#include <new>
#include <string>
#include <string.h>

#ifndef MQ_SPM_MAX_CALLS
#define MQ_SPM_MAX_CALLS 1024
#endif

namespace {

enum MqSpmKind : uint8_t {
    MQ_SPM_METRIC,
    MQ_SPM_DEVICE,
    MQ_SPM_COMMAND,
    MQ_SPM_HISTORY,
    MQ_SPM_DAYS,
};

struct MqSpmCall {
    uint8_t kind = 0;
    uint32_t key = 0;
    std::string id;               // the key's parts, each ended by \x1f
    MqSpmCall() = default;
    MqSpmCall(const MqSpmCall&) = delete;
    MqSpmCall& operator=(const MqSpmCall&) = delete;
    virtual ~MqSpmCall() {}
};

struct MqSpmMetric : MqSpmCall {
    bool declared = false;
    E_MQTTRESULT refused = E_MQTTRESULT::OK;   // the declaration's refusal, kept
    bool writable = false;        // as declared, whatever bWritable says later
    float deadband = 0.0f;
    int32_t quality = MQ_SP_QUALITY_GOOD;
    std::string units;
    uint32_t alias = 0;
    int32_t written = 0;
    int32_t lost = 0;
};

struct MqSpmDevice : MqSpmCall {
    bool added = false;
    bool asked = false;
    bool wanted = false;
    bool online = false;
    int32_t births = 0;
    int32_t deaths = 0;
};

struct MqSpmCommand : MqSpmCall {
    bool lastAck = false;
    bool seen = false;
    uint32_t taken = 0;
    bool pending = false;
    double value = 0.0;
    std::string text;
    int32_t count = 0;
    int32_t lost = 0;
};

// History's buffer: the ring, and the records a batch is built in - both in
// PSRAM where the board has it, so a catch-up message costs the stack nothing.
struct MqSpmHistory : MqSpmCall {
    MqttSparkplugHistory ring;
    MqttSparkplugRecord* scratch = nullptr;
    size_t scratchCount = 0;
    bool begun = false;
    bool declared = false;
    bool refused = false;
    std::string names[5];         // <prefix>/source, /code, /value, /seq, /lost
    int index[5] = {-1, -1, -1, -1, -1};
    uint16_t limit = 0;           // events a message; halved when one does not fit
    uint32_t seq = 0;
    uint16_t pending = 0;         // events in the message last sent, not yet confirmed
    int32_t sentAt = 0;
    uint32_t births = 0;
    int32_t bornAt = 0;
    bool wasBorn = false;
    uint32_t sent = 0;
    ~MqSpmHistory() override {
        if (scratch != nullptr) {
            for (size_t i = 0; i < scratchCount; i++) scratch[i].~MqttSparkplugRecord();
            mq_freeLarge(scratch);
        }
    }
};

struct MqSpmDays : MqSpmCall {
    bool declared = false;
    bool refused = false;
    std::string name;
    int index = -1;
    uint32_t births = 0;
    bool owed = false;
    float live = 0.0f;            // fValue on the last call
    int64_t liveDay = -1;         // the day of that call (-1: none yet)
    int64_t savedNs = -1;         // dtClock when today's row was last written
    uint32_t sent = 0;
};

struct MqSpmCalls {
    std::vector<MqSpmCall*> calls;
    size_t next = 0;              // calls come in the same order every scan
    strucpp::XWORD_t node = 0;
    void drop() {
        for (size_t i = 0; i < calls.size(); i++) delete calls[i];
        calls.clear();
        next = 0;
    }
    ~MqSpmCalls() { drop(); }
};

// Freed when the program is unloaded: the Runtime loads the next program into
// the same process. Runs before the nodes are deleted (constructed after).
// Made on first use, so a program that never uses this block links none of
// it, and freed when the program is unloaded, before what was made earlier.
struct MqSpmTablesOwned {
    std::vector<MqSpmCalls*> all;
    ~MqSpmTablesOwned() {
        for (size_t i = 0; i < all.size(); i++) delete all[i];
    }
};
MqSpmTablesOwned& mqSpmTablesOwned() {
    static MqSpmTablesOwned owned;
    return owned;
}

// 2020-01-01 in days since 1970: a clock before it has not been set.
const int64_t MQ_SPM_DAY_PLAUSIBLE = 18262;
const int64_t MQ_SPM_NS_PER_DAY = 86400000000000LL;

}  // namespace

static const char* mq_spmText(const char* text) { return text != nullptr ? text : ""; }

// This node's table, made on first use - before the node exists, too: History
// keeps events from the first scan.
static MqSpmCalls* mq_spmTable(strucpp::XWORD_t& held, strucpp::XWORD_t node) {
    MqSpmCalls* table = (MqSpmCalls*)(uintptr_t)held;
    if (table == nullptr) {
        table = new (std::nothrow) MqSpmCalls();
        if (table == nullptr) return nullptr;
        mqSpmTablesOwned().all.push_back(table);
        held = (strucpp::XWORD_t)(uintptr_t)table;
    }
    if (node != 0 && table->node != node) {
        if (table->node != 0) table->drop();   // another node: its declarations are not this one's
        table->node = node;
    }
    return table;
}

static uint32_t mq_spmKey(uint8_t kind, const char* const* parts, int count) {
    uint32_t key = mq_fingerprint(2166136261u, &kind, sizeof kind);
    for (int i = 0; i < count; i++) {
        key = mq_fingerprintText(key, parts[i]);
        key = mq_fingerprint(key, "\x1f", 1);
    }
    return key;
}

static bool mq_spmSameId(const MqSpmCall* call, uint8_t kind, uint32_t key,
                         const char* const* parts, int count) {
    if (call->kind != kind || call->key != key) return false;
    const std::string& id = call->id;
    size_t at = 0;
    for (int i = 0; i < count; i++) {
        const size_t length = strlen(parts[i]);
        if (id.compare(at, length, parts[i]) != 0) return false;
        at += length;
        if (at >= id.size() || id[at] != '\x1f') return false;
        at++;
    }
    return at == id.size();
}

// The row of one call, found by its key or made. Null past MQ_SPM_MAX_CALLS or
// out of memory.
template <typename Row>
static Row* mq_spmRowOf(MqSpmCalls* table, uint8_t kind, const char* const* parts, int count) {
    if (table == nullptr) return nullptr;
    const uint32_t key = mq_spmKey(kind, parts, count);
    std::vector<MqSpmCall*>& calls = table->calls;
    size_t index = table->next;
    if (index >= calls.size() || !mq_spmSameId(calls[index], kind, key, parts, count)) {
        for (index = 0; index < calls.size(); index++) {
            if (mq_spmSameId(calls[index], kind, key, parts, count)) break;
        }
        if (index == calls.size()) {
            if (calls.size() >= (size_t)MQ_SPM_MAX_CALLS) return nullptr;
            Row* made = new (std::nothrow) Row();
            if (made == nullptr) return nullptr;
            made->kind = kind;
            made->key = key;
            for (int i = 0; i < count; i++) {
                made->id += parts[i];
                made->id += '\x1f';
            }
            calls.push_back(made);
        }
    }
    table->next = index + 1;
    return static_cast<Row*>(calls[index]);
}

// A node metric's index, the one held when it still names that metric:
// indices move when metrics are removed.
static int mq_spmPointIndex(MqttSparkplugNode* node, int& held, const char* name) {
    if (held >= 0) {
        const MqttSparkplugPoint* point = node->pointAt((size_t)held);
        if (point != nullptr && point->device < 0 && point->name == name) return held;
    }
    held = node->indexOf(nullptr, name);
    return held;
}

// E_MqttQuality has four values and Sparkplug three codes
// ([tck-id-payloads-propertyset-quality-value-value]): Uncertain is a good
// value grown old, stale; Unknown is nothing known, bad.
static int32_t mq_spmQualityOf(E_MQTTQUALITY quality) {
    switch (quality) {
    case E_MQTTQUALITY::GOOD:      return MQ_SP_QUALITY_GOOD;
    case E_MQTTQUALITY::UNCERTAIN: return MQ_SP_QUALITY_STALE;
    default:                       return MQ_SP_QUALITY_BAD;
    }
}

static bool mq_spmSameName(const char* a, const char* b) {
    if (a == nullptr || b == nullptr) return false;
    for (; *a != '\0' && *b != '\0'; a++, b++) {
        char x = *a, y = *b;
        if (x >= 'A' && x <= 'Z') x = (char)(x - 'A' + 'a');
        if (y >= 'A' && y <= 'Z') y = (char)(y - 'A' + 'a');
        if (x != y) return false;
    }
    return *a == *b;
}

// Where dDay and fTotal sit in each row of an ARRAY OF ST_SparkplugDay.
static bool mq_spmDayLayout(const strucpp::IEC_ANY& any, uint32_t* day, uint32_t* total) {
    if (any.TYPECLASS != strucpp::TYPE_ARRAY || any.ELEMCLASS != strucpp::TYPE_USERDEF ||
        any.TYPEDESC == nullptr || any.PVALUE == nullptr) {
        return false;
    }
    bool hasDay = false;
    bool hasTotal = false;
    for (uint16_t i = 0; i < any.TYPEDESC->MEMBERCOUNT; i++) {
        const strucpp::MemberDesc& member = any.TYPEDESC->MEMBERS[i];
        if (member.TYPECLASS == strucpp::TYPE_DATE && mq_spmSameName(member.NAME, "dDay")) {
            *day = member.BYTEOFFSET;
            hasDay = true;
        } else if (member.TYPECLASS == strucpp::TYPE_REAL && mq_spmSameName(member.NAME, "fTotal")) {
            *total = member.BYTEOFFSET;
            hasTotal = true;
        }
    }
    return hasDay && hasTotal;
}

E_MQTTRESULT Metric()
{
    if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
    strucpp::XWORD_t held = (strucpp::XWORD_t)nMethodCalls;
    MqSpmCalls* table = mq_spmTable(held, (strucpp::XWORD_t)nApi);
    nMethodCalls = held;
    const char* parts[4] = {mq_spmText(anyValue.NAME), mq_spmText(anyValue.TYPENAME),
                            sDeviceId.c_str(), sMetricName.c_str()};
    MqSpmMetric* r = mq_spmRowOf<MqSpmMetric>(table, MQ_SPM_METRIC, parts, 4);
    if (r == nullptr) return E_MQTTRESULT::QUEUEFULL;
    nAlias = r->alias;
    nWrittenCnt = r->written;
    nLostCnt = r->lost;

    if (sMetricName.length() == 0) return E_MQTTRESULT::INVALIDARGUMENT;
    const char* device = sDeviceId.length() != 0 ? sDeviceId.c_str() : nullptr;
    // The devices Live Demand brings on and off line are not the program's.
    if (device != nullptr && mq_spDeviceIsManaged((strucpp::XWORD_t)nReport, device)) {
        return E_MQTTRESULT::INVALIDARGUMENT;
    }
    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)nApi);
    if (node == nullptr) return E_MQTTRESULT::NOTINITIALISED;
    const char* name = sMetricName.c_str();
    const int32_t quality = mq_spmQualityOf((E_MQTTQUALITY)eQuality);

    // --- Declared once, on the first call: the node births with it ---
    if (!r->declared) {
        r->declared = true;
        MqttSparkplugDataType type = MqttSparkplugDataType::Unknown;
        if (!mq_spTypeOfClass(anyValue.TYPECLASS, &type)) {
            r->refused = E_MQTTRESULT::INVALIDARGUMENT;   // a type the wire cannot carry
            return r->refused;
        }
        // Only the call that adds the device brings it online: one a Device
        // call added is that call's to switch.
        const bool addedHere = device != nullptr && node->addDevice(device);
        r->writable = (bool)bWritable;
        r->quality = quality;
        r->units = sUnits.c_str();
        uint64_t alias = 0;
        if (device != nullptr) {
            alias = r->writable ? node->declareWritableFor(device, name, type)
                                : node->declareFor(device, name, type);
        } else if (r->writable) {
            alias = node->declareWritable(name, type);
        } else {
            alias = node->declare(name, type, r->units.empty() ? nullptr : r->units.c_str(), quality);
        }
        r->alias = (uint32_t)alias;
        nAlias = r->alias;
        if (alias == 0) {
            r->refused = E_MQTTRESULT::INVALIDARGUMENT;
            return r->refused;
        }
        if (device != nullptr || r->writable) {
            // The units and quality the node-level declaration takes itself.
            const int index = node->indexOf(device, name);
            if (index >= 0 && !r->units.empty()) node->unitsAt((size_t)index, r->units.c_str());
            if (index >= 0 && quality != MQ_SP_QUALITY_GOOD) node->qualityAt((size_t)index, quality);
        }
        if (addedHere) node->deviceOnline(device);
    }
    if (r->refused != E_MQTTRESULT::OK) return r->refused;

    // --- Units and quality, when they change: units show at the next birth,
    // a quality goes in the next data message ---
    if (quality != r->quality || r->units != sUnits.c_str()) {
        const int index = node->indexOf(device, name);
        if (index >= 0) {
            if (quality != r->quality) node->qualityAt((size_t)index, quality);
            if (r->units != sUnits.c_str()) node->unitsAt((size_t)index, sUnits.c_str());
        }
        r->quality = quality;
        r->units = sUnits.c_str();
    }

    // --- The deadband, when it changes: held against the value last SENT, so
    // a slow drift still adds up. Refused on a BOOL or a STRING. ---
    if ((float)fDeadband != r->deadband) {
        const double band = (double)(float)fDeadband;
        const bool ok = device != nullptr
            ? node->deadbandFor(device, name, band < 0.0 ? -1.0 : band)
            : node->deadband(name, band < 0.0 ? -1.0 : band);
        r->deadband = (float)fDeadband;
        if (!ok && band != 0.0) return E_MQTTRESULT::INVALIDARGUMENT;
    }

    // --- Declared writable and bWritable FALSE: a write is dropped at once,
    // never kept for later, and the value put back so the host sees it did
    // not take ---
    if (r->writable && !(bool)bWritable) {
        MqttSparkplugValue value;
        bool dropped = false;
        while (node->commandPendingFor(device, name) && node->takeFor(device, name, value)) {
            dropped = true;
        }
        if (dropped && mq_spValueOfAny(anyValue, &value)) {
            if (device != nullptr) node->setFor(device, name, value);
            else node->set(name, value);
        }
    }

    const bool born = node->isBorn();
    if (!(bool)bUpdate) return born ? E_MQTTRESULT::OK : E_MQTTRESULT::NOTCONNECTED;

    // A command in before the value out, so a setpoint written this scan is
    // reported back in the same message. One write a call, the oldest first:
    // a host writing 1 then 0 within a scan gives anyValue each for a scan.
    bool refusedWrite = false;
    if (born && (bool)bWritable && node->commandPendingFor(device, name)) {
        MqttSparkplugValue value;
        if (node->takeFor(device, name, value)) {
            if (mq_spWriteAny(anyValue, value)) {
                r->written = r->written + 1;
                nWrittenCnt = r->written;
            } else {
                refusedWrite = true;   // too long for the STRING, or a TIME out of range
            }
        }
    }
    if (born && (bool)bWritable) {
        const int index = node->indexOf(device, name);
        if (index >= 0) {
            r->lost = (int32_t)node->writesLostAt((size_t)index);
            nLostCnt = r->lost;
        }
    }

    // NOT BORN IS NOT NOTHING TO DO: the value goes into the node, and the
    // birth carries it [tck-id-operational-behavior-data-publish-nbirth-values].
    MqttSparkplugValue value;
    if (!mq_spValueOfAny(anyValue, &value)) return E_MQTTRESULT::INVALIDARGUMENT;
    const bool set = device != nullptr ? node->setFor(device, name, value)
                                       : node->set(name, value);
    if (!set) return E_MQTTRESULT::INVALIDARGUMENT;
    if (!born) return E_MQTTRESULT::NOTCONNECTED;

    // Asked, not sent: the node sends one data message on its next scan for
    // everything that moved, however many calls asked.
    if ((bool)bPublish) node->publishAtPoll();
    return refusedWrite ? E_MQTTRESULT::INVALIDARGUMENT : E_MQTTRESULT::OK;
}

E_MQTTRESULT Device()
{
    if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
    strucpp::XWORD_t held = (strucpp::XWORD_t)nMethodCalls;
    MqSpmCalls* table = mq_spmTable(held, (strucpp::XWORD_t)nApi);
    nMethodCalls = held;
    const char* parts[1] = {sDeviceId.c_str()};
    MqSpmDevice* r = mq_spmRowOf<MqSpmDevice>(table, MQ_SPM_DEVICE, parts, 1);
    if (r == nullptr) return E_MQTTRESULT::QUEUEFULL;
    bDeviceOnline = r->online;
    nBirthCnt = r->births;
    nDeathCnt = r->deaths;

    if (sDeviceId.length() == 0) return E_MQTTRESULT::INVALIDARGUMENT;
    const char* device = sDeviceId.c_str();
    if (mq_spDeviceIsManaged((strucpp::XWORD_t)nReport, device)) return E_MQTTRESULT::INVALIDARGUMENT;
    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)nApi);
    if (node == nullptr) return E_MQTTRESULT::NOTINITIALISED;

    if (!r->added) {
        r->added = true;
        // Refused when it is there already, which is no error: a Metric call
        // under the same device may have added it first.
        node->addDevice(device);
    }

    // ON A CHANGE, and on the first call: bOnline held TRUE must not birth it
    // every scan, which a host would see as a rebirth storm.
    const bool wanted = (bool)bOnline;
    if (!r->asked || wanted != r->wanted) {
        r->asked = true;
        r->wanted = wanted;
        if (wanted) {
            if (!node->deviceOnline(device)) return E_MQTTRESULT::INVALIDARGUMENT;
        } else {
            const bool wasOnline = node->deviceIsOnline(device);
            if (!node->deviceOffline(device)) return E_MQTTRESULT::INVALIDARGUMENT;
            if (wasOnline) {
                r->deaths = r->deaths + 1;
                nDeathCnt = r->deaths;
            }
        }
    }

    // The node owes every device's birth again after a reconnect: a device
    // meant to be online and not is asked again (the node births it once).
    const bool born = node->isBorn();
    if (wanted && born && !node->deviceIsOnline(device)) node->deviceOnline(device);

    // A birth is counted when it has gone, not when it was asked for.
    const bool online = node->deviceIsOnline(device);
    if (online && !r->online) r->births = r->births + 1;
    r->online = online;
    bDeviceOnline = online;
    nBirthCnt = r->births;
    return born ? E_MQTTRESULT::OK : E_MQTTRESULT::NOTCONNECTED;
}

E_MQTTRESULT Command()
{
    if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
    strucpp::XWORD_t held = (strucpp::XWORD_t)nMethodCalls;
    MqSpmCalls* table = mq_spmTable(held, (strucpp::XWORD_t)nApi);
    nMethodCalls = held;
    const char* parts[2] = {sDeviceId.c_str(), sMetricName.c_str()};
    MqSpmCommand* r = mq_spmRowOf<MqSpmCommand>(table, MQ_SPM_COMMAND, parts, 2);
    if (r == nullptr) return E_MQTTRESULT::QUEUEFULL;
    const bool ack = (bool)bAck;
    const bool rising = ack && !r->lastAck;
    r->lastAck = ack;

    E_MQTTRESULT result = E_MQTTRESULT::OK;
    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)nApi);
    if (node == nullptr) {
        result = E_MQTTRESULT::NOTINITIALISED;
    } else if (sMetricName.length() == 0) {
        result = E_MQTTRESULT::INVALIDARGUMENT;
    } else {
        // A name is only unique within its device, and a DCMD is held on the
        // device's metric: the device is part of the question.
        const char* device = sDeviceId.length() != 0 ? sDeviceId.c_str() : nullptr;
        const int index = node->indexOf(device, sMetricName.c_str());
        const MqttSparkplugPoint* point = index >= 0 ? node->pointAt((size_t)index) : nullptr;
        if (point == nullptr) {
            r->pending = false;
            r->seen = false;
            result = E_MQTTRESULT::NOTINITIALISED;   // not declared, or not yet
        } else if (!point->writable) {
            r->pending = false;
            r->seen = false;
            result = E_MQTTRESULT::INVALIDARGUMENT;  // no command can arrive on it
        } else {
            const bool pending = node->commandPendingAt((size_t)index);
            r->lost = (int32_t)node->writesLostAt((size_t)index);
            // Another caller took the one looked at (a writable Metric applies
            // every write): one still pending is the NEXT, a command of its own.
            if (r->seen && node->writesTakenAt((size_t)index) != r->taken) r->seen = false;
            if (pending && !r->seen) {
                // First sight, read WITHOUT taking it, so a rung can look
                // before it decides. The oldest write waiting.
                r->seen = true;
                r->taken = node->writesTakenAt((size_t)index);
                r->count = r->count + 1;
                MqttSparkplugValue value;
                if (node->peekAt((size_t)index, value)) {
                    r->value = value.asNumber();
                    if (value.isText() && value.as.bytes.data != nullptr) {
                        // Cut, not refused: a display text too long is still
                        // useful, and the whole value is in the metric.
                        size_t length = value.as.bytes.length;
                        if (length > 126) length = 126;
                        r->text.assign((const char*)value.as.bytes.data, length);
                    } else {
                        r->text.clear();
                    }
                }
            }
            r->pending = pending;
            // A rising edge of bAck consumes it, so two rungs cannot both act
            // on one command.
            if (rising && pending) {
                MqttSparkplugValue taken;
                node->takeAt((size_t)index, taken);
                r->pending = false;
                r->seen = false;
            }
            if (!pending) r->seen = false;
            if (!node->isBorn()) result = E_MQTTRESULT::NOTCONNECTED;
        }
    }
    if (node != nullptr) nRefusedCnt = (int32_t)node->commandsRefused();
    bPending = r->pending;
    fValue = r->value;
    bValue = r->value != 0.0;
    sText = r->text.c_str();
    nCmdCnt = r->count;
    nLostCnt = r->lost;
    return result;
}

E_MQTTRESULT History()
{
    if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
    strucpp::XWORD_t held = (strucpp::XWORD_t)nMethodCalls;
    MqSpmCalls* table = mq_spmTable(held, (strucpp::XWORD_t)nApi);
    nMethodCalls = held;
    const char* prefix = sMetricPrefix.length() != 0 ? sMetricPrefix.c_str() : "Event";
    const char* parts[1] = {prefix};
    MqSpmHistory* h = mq_spmRowOf<MqSpmHistory>(table, MQ_SPM_HISTORY, parts, 1);
    if (h == nullptr) return E_MQTTRESULT::QUEUEFULL;

    // --- The buffer, on the first call: a scan, long after PSRAM is up ---
    if (!h->begun) {
        h->begun = true;
        const size_t depth = (uint16_t)nDepth != 0 ? (size_t)(uint16_t)nDepth : 256u;
        size_t batch = (uint16_t)nBatch != 0 ? (size_t)(uint16_t)nBatch : 20u;
        if (batch > 64) batch = 64;
        h->ring.begin(depth);
        void* raw = mq_allocLarge(batch * 4 * sizeof(MqttSparkplugRecord));
        if (raw != nullptr) {
            h->scratch = static_cast<MqttSparkplugRecord*>(raw);
            h->scratchCount = batch * 4;
            for (size_t i = 0; i < h->scratchCount; i++) new (&h->scratch[i]) MqttSparkplugRecord();
        }
        h->limit = (uint16_t)batch;
        for (int k = 0; k < 5; k++) {
            static const char* const kParts[5] = {"/source", "/code", "/value", "/seq", "/lost"};
            h->names[k] = std::string(prefix) + kParts[k];
        }
    }
    nSentCnt = h->sent;
    bReplaying = false;
    if (!h->ring.ready() || h->scratch == nullptr) {
        if ((bool)bAdd) h->ring.add(MqttSparkplugEvent());   // counted as lost
        nStoredCnt = 0;
        nLostCnt = h->ring.lost();
        return E_MQTTRESULT::NOTINITIALISED;   // no memory for the buffer
    }

    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)nApi);
    const mq_time_t now = mq_millis();

    // --- Record, whatever the node is doing ---
    if ((bool)bAdd) {
        MqttSparkplugEvent event;
        event.source = (uint16_t)nSource;
        event.code = (uint16_t)nCode;
        event.value = (float)fValue;
        h->seq = h->seq + 1u;
        event.seq = h->seq;
        const bool clockSet = node != nullptr ? node->clockIsSet() : mq_epochMillis() != 0;
        if (clockSet) {
            event.timestamp = node != nullptr ? node->timestamp() : mq_epochMillis();
        } else {
            event.timestamp = (uint64_t)now;
            event.flags |= MQ_SP_EVENT_UPTIME;
        }
        if (node == nullptr || !node->isBorn()) event.flags |= MQ_SP_EVENT_OFFLINE;
        h->ring.add(event);
    }
    nStoredCnt = (uint16_t)h->ring.count();
    nLostCnt = h->ring.lost();
    if (node == nullptr) return E_MQTTRESULT::NOTCONNECTED;

    // --- Declared once, before the node births ---
    if (!h->declared) {
        h->declared = true;
        static const MqttSparkplugDataType types[5] = {
            MqttSparkplugDataType::UInt16, MqttSparkplugDataType::UInt16,
            MqttSparkplugDataType::Float, MqttSparkplugDataType::UInt32,
            MqttSparkplugDataType::UInt32};
        for (int k = 0; k < 5; k++) {
            if (node->declare(h->names[k].c_str(), types[k]) == 0) {
                h->refused = true;
                break;
            }
        }
    }
    if (h->refused) return E_MQTTRESULT::INVALIDARGUMENT;
    for (int k = 0; k < 5; k++) {
        if (mq_spmPointIndex(node, h->index[k], h->names[k].c_str()) < 0) {
            return E_MQTTRESULT::INVALIDARGUMENT;
        }
    }

    // The lost count is live data, reported by exception with the rest.
    node->setAt((size_t)h->index[4], mq_spUInt32(h->ring.lost()));

    const bool born = node->isBorn();
    if (born && !h->wasBorn) h->bornAt = (int32_t)(uint32_t)now;
    h->wasBorn = born;

    // --- What went is confirmed by the node staying born on the same NBIRTH:
    // a device's birth does not withdraw it ---
    if (h->pending > 0) {
        if (!born || node->nodeBirthCount() != h->births) {
            h->pending = 0;   // not known to have arrived: sent again
        } else if ((int32_t)(now - (mq_time_t)(uint32_t)h->sentAt) >= 500) {
            h->ring.drop(h->pending);
            h->sent = h->sent + h->pending;
            h->pending = 0;
        }
    }
    nStoredCnt = (uint16_t)h->ring.count();
    nSentCnt = h->sent;
    bReplaying = born && h->ring.count() > 0 &&
                 (h->ring.peek(0)->flags & MQ_SP_EVENT_OFFLINE) != 0;
    if (!born) return E_MQTTRESULT::NOTCONNECTED;
    if (h->pending > 0 || h->ring.empty()) return E_MQTTRESULT::OK;

    // --- The next batch: one message all historical or all live ---
    if (node->clockIsSet()) h->ring.placeOnClock(node->timestamp(), now);
    const MqttSparkplugEvent* first = h->ring.peek(0);
    const bool historical = (first->flags & MQ_SP_EVENT_OFFLINE) != 0;
    if ((first->flags & MQ_SP_EVENT_UPTIME) != 0 &&
        (int32_t)(now - (mq_time_t)(uint32_t)h->bornAt) < 300000) {
        return E_MQTTRESULT::OK;   // waits for the clock up to five minutes after the birth
    }
    if (historical) {
        const int32_t period = mq_millisOf(tPeriod) > 0 ? mq_millisOf(tPeriod) : 1000;
        if ((int32_t)(now - (mq_time_t)(uint32_t)h->sentAt) < period) return E_MQTTRESULT::OK;
    }
    size_t limit = h->limit != 0 ? (size_t)h->limit : 1u;
    if (limit * 4 > h->scratchCount) limit = h->scratchCount / 4;
    size_t n = 0;
    while (n < limit && n < h->ring.count()) {
        const MqttSparkplugEvent* e = h->ring.peek(n);
        if (((e->flags & MQ_SP_EVENT_OFFLINE) != 0) != historical) break;
        MqttSparkplugRecord* rec = &h->scratch[n * 4];
        for (int k = 0; k < 4; k++) {
            rec[k].index = (size_t)h->index[k];
            rec[k].timestamp = e->timestamp;
        }
        rec[0].value = mq_spUInt16(e->source);
        rec[1].value = mq_spUInt16(e->code);
        rec[2].value = mq_spFloat(e->value);
        rec[3].value = mq_spUInt32(e->seq);
        n++;
    }
    if (n == 0) return E_MQTTRESULT::OK;
    if (node->publishRecords(h->scratch, n * 4, historical)) {
        h->pending = (uint16_t)n;
        h->sentAt = (int32_t)(uint32_t)now;
        h->births = node->nodeBirthCount();
    } else if (n > 1 && node->isBorn()) {
        h->limit = (uint16_t)(n / 2);   // too big for the link's buffer, most likely
    }
    return E_MQTTRESULT::OK;
}

E_MQTTRESULT DayTotals()
{
    if (!mq_inTask((strucpp::XWORD_t)nTask)) return E_MQTTRESULT::WRONGTASK;
    strucpp::XWORD_t held = (strucpp::XWORD_t)nMethodCalls;
    MqSpmCalls* table = mq_spmTable(held, (strucpp::XWORD_t)nApi);
    nMethodCalls = held;
    const char* parts[3] = {mq_spmText(anyDays.NAME), mq_spmText(anyDays.TYPENAME),
                            sMetricName.c_str()};
    MqSpmDays* d = mq_spmRowOf<MqSpmDays>(table, MQ_SPM_DAYS, parts, 3);
    if (d == nullptr) return E_MQTTRESULT::QUEUEFULL;
    nSentCnt = d->sent;

    uint32_t dayAt = 0;
    uint32_t totalAt = 0;
    if (!mq_spmDayLayout(anyDays, &dayAt, &totalAt) || anyDays.DICOUNT < 2) {
        nDays = 0;
        return E_MQTTRESULT::INVALIDARGUMENT;   // not an ARRAY OF ST_SparkplugDay of two rows or more
    }
    const int32_t rows = anyDays.DICOUNT;
    auto dayOf = [&](int32_t row) -> int64_t& { return *(int64_t*)(anyDays.at(row) + dayAt); };
    auto totalOf = [&](int32_t row) -> float& { return *(float*)(anyDays.at(row) + totalAt); };

    // --- Today, and the close of a day ---
    const int64_t clockNs = (int64_t)dtClock.get();
    const int64_t today = clockNs >= 0 ? clockNs / MQ_SPM_NS_PER_DAY : -1;
    bool closed = false;
    if (today >= MQ_SPM_DAY_PLAUSIBLE) {
        const int64_t openDay = dayOf(0);
        const int64_t saveNs = (int64_t)mq_millisOf(tSaveEvery) * 1000000LL;
        if (openDay >= MQ_SPM_DAY_PLAUSIBLE && openDay != today) {
            // The first row's day has ended: it becomes the newest closed day,
            // with the total of its last call - or, if the PLC was off when it
            // ended, the total last saved.
            const float total = d->liveDay == openDay ? d->live : totalOf(0);
            for (int32_t i = rows - 1; i > 1; i--) {
                dayOf(i) = dayOf(i - 1);
                totalOf(i) = totalOf(i - 1);
            }
            dayOf(1) = openDay;
            totalOf(1) = total;
            closed = true;
        }
        if (openDay != today) {
            dayOf(0) = today;
            totalOf(0) = (float)fValue;
            d->savedNs = clockNs;
        } else if (d->savedNs < 0 || clockNs < d->savedNs) {
            d->savedNs = clockNs;   // the first call, or the clock set back: the period starts
        } else if (saveNs <= 0 || clockNs - d->savedNs >= saveNs) {
            totalOf(0) = (float)fValue;
            d->savedNs = clockNs;
        }
        d->live = (float)fValue;
        d->liveDay = today;
    }
    int16_t closedDays = 0;
    for (int32_t i = 1; i < rows; i++) {
        if (dayOf(i) >= MQ_SPM_DAY_PLAUSIBLE) closedDays++;
    }
    nDays = closedDays;

    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)nApi);
    if (node == nullptr) return E_MQTTRESULT::NOTCONNECTED;

    // --- Declared once, before the node births ---
    if (!d->declared) {
        d->declared = true;
        d->name = sMetricName.c_str();
        d->refused = d->name.empty() ||
                     node->declare(d->name.c_str(), MqttSparkplugDataType::Float) == 0;
    }
    if (d->refused) return E_MQTTRESULT::INVALIDARGUMENT;
    const int index = mq_spmPointIndex(node, d->index, d->name.c_str());
    if (index < 0) return E_MQTTRESULT::INVALIDARGUMENT;

    // The live value: the last closed day, carried in the birth.
    if (dayOf(1) >= MQ_SPM_DAY_PLAUSIBLE) node->setAt((size_t)index, mq_spFloat(totalOf(1)));

    // --- Every node birth, and every close, sends the closed days as history;
    // a device's birth (Live Demand's, often) does not ---
    if (!node->isBorn()) return E_MQTTRESULT::NOTCONNECTED;
    if (node->nodeBirthCount() != d->births) {
        d->births = node->nodeBirthCount();
        d->owed = true;
    }
    if (closed) d->owed = true;
    if (!d->owed) return E_MQTTRESULT::OK;

    MqttSparkplugRecord records[8];
    size_t n = 0;
    uint32_t sent = 0;
    bool ok = true;
    for (int32_t i = rows - 1; i >= 1 && ok; i--) {   // oldest first
        const int64_t day = dayOf(i);
        if (day >= MQ_SPM_DAY_PLAUSIBLE) {
            // At 00:00 of its date, the date as dtClock has it written as UTC.
            records[n].index = (size_t)index;
            records[n].value = mq_spFloat(totalOf(i));
            records[n].timestamp = (uint64_t)day * 86400000ULL;
            n++;
        }
        if (n > 0 && (n == 8 || i == 1)) {
            ok = node->publishRecords(records, n, true);
            if (ok) sent += (uint32_t)n;
            n = 0;
        }
    }
    d->sent = d->sent + sent;
    nSentCnt = d->sent;
    if (ok) d->owed = false;   // otherwise the next call tries again
    return E_MQTTRESULT::OK;
}

END_FUNCTION_BLOCK