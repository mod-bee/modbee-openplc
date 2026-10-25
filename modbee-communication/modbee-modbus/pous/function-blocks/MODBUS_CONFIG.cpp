(* Tunes a node. Optional: leave it out and the defaults are the ones you want.

NODE         which node. Must be wired.
TIMEOUT      how long to wait for a reply. T#0s measures it PER DEVICE, which is
             almost always better than any figure you could pick: a slow drive
             and a fast I/O block on one bus then each get the timeout they
             deserve. Set a number only to pin one figure for everything.
RETRIES      attempts after the first. 0 takes the library's own.
RECONNECT    how often to try a link that has dropped. ALREADY ON: T#0s takes the
             library's own two seconds, and a link that goes will come back on
             its own without this block. A positive figure paces it differently;
             -1 turns recovery off and the link then stays down until CONNECT
             is cycled.
FRAMING      how frames are found. MODBUS_FRAMING_AUTO reads RTU on a serial
             line and MBAP on a socket, which is right unless something between
             you and the device is doing violence to one of them - see below.
             MODBUS_FRAMING_AUTO, MODBUS_FRAMING_RTU, MODBUS_FRAMING_ASCII,
             MODBUS_FRAMING_TCP
FAILSAFE     drive this node's writable registers to their safe values when no
             client has written for this long. 0 leaves them alone. Needed
             before MODBUS_MAP's ON_LOSS can do anything.
MAX_CLIENTS  how many clients a TCP server holds at once. 0 for the default:
             eight on the Runtime, two on a board. No ceiling of its own - a
             board that cannot find room for that many says "out of memory for
             MAX_CLIENTS" on the node's LAST_ERROR instead of holding fewer.
IDLE         close a connection nobody is using after this long. T#0s NEVER
             closes one. T#60s is the usual value - type it rather than
             leaving the pin empty and hoping.
QUEUE        how many requests may wait at once. 0 for the default: 16 on a
             board, 64 on the Runtime. Past it a request is refused with
             MODBUS_QUEUE_FULL. Raise it for a program that asks for more at
             once than the bus can answer in a scan or two.
QUEUE_BYTES  the bytes the waiting requests' values share (a write's
             registers). 0 for the default: 1024 on a board, 16192 on the
             Runtime. Both are taken once, when the node opens; a figure the
             board cannot hold stops the node with "out of memory for the
             request queue" on LAST_ERROR.

APPLIED  the settings reached the node.
ERROR    they did not.
STATUS   why. MODBUS_OK when fine.

---

  cfg( NODE := node, TIMEOUT := T#500ms, RETRIES := 3, FAILSAFE := T#5s );

Put it in the same program as the node, above or below - the node waits a scan
before opening so that whatever this block sets has been seen.

EVERY PIN HERE HAS A DEFAULT THAT WORKS. This block exists so that a node which
wants none of them is eleven pins instead of twenty-eight, not because a node
needs it. If you are not changing any of these, do not place it.

TIMEOUT IS THE ONE TO THINK TWICE ABOUT. Left at T#0s the timeout is measured
per device and includes the airtime the medium physically needs, so it adapts
to the bus you actually have. A figure you pick is a figure that is wrong on
one device or the other.

FAILSAFE AND MODBUS_MAP GO TOGETHER. Neither does anything alone: this sets
the silence that counts as losing the client, and ON_LOSS on the map says what
a particular address does about it. Test it by pulling the cable and watching
SAFE_APPLIED - a failsafe nobody has seen fire is a failsafe nobody knows works.

FRAMING IS THE PIN FOR A CONVERTER. A serial-to-Ethernet box puts a raw RTU
frame inside a TCP stream with no MBAP header, and listens on 502 like the real
thing - so a normal TCP client gets silence and nothing to go on. One pin says
so:

  node( TRANSPORT := MODBUS_RUNTIME_TCP, ROLE := MODBUS_ROLE_CLIENT,
        TCP_HOST := '192.168.1.50', TCP_PORT := 4001 );
  cfg ( NODE := node, TIMEOUT := T#0s, FRAMING := MODBUS_FRAMING_RTU );

Terminal servers usually put each serial port on its own TCP port - 4001, 4002
and so on - rather than on 502. Check the box's own web page.

If you are not sure which sort you have, leave it at AUTO, and if nothing comes
back try MODBUS_FRAMING_RTU. Then read MODBUS_STATUS.FRAMING_REASON, which says
which rule is in force in a sentence.

AUTOMATIC RECOVERY IS ALREADY ON, AND YOU DO NOT NEED THIS BLOCK FOR IT. The
far end of a Modbus link is a device that gets rebooted, a switch that gets
swapped, an adapter that gets unplugged and put back; a link that dropped is
retried every two seconds until it comes back, and every watched value is made
due the moment it does. RECONNECT is here only to pace that differently, or
to turn it off on a link where the application would rather decide.

ASSIGN TIMEOUT EVEN WHEN YOU WANT THE DEFAULT. The editor reports a block
whose first input is never assigned, because that is usually a mistake, and
this block's first input is TIMEOUT. Writing TIMEOUT := T#0s says "I have
thought about the timeout and I want the measured one", which is worth saying
out loud on a tuning block.

The nameplate lives on MODBUS_IDENTITY, not here. *)

FUNCTION_BLOCK MODBUS_CONFIG
  VAR_IN_OUT
    NODE : MODBUS_NODE;
  END_VAR
  VAR_INPUT
    TIMEOUT : TIME;
    RETRIES : BYTE;
    RECONNECT : TIME;
    FRAMING : MODBUS_FRAMING;
    FAILSAFE : TIME;
    MAX_CLIENTS : BYTE;
    IDLE : TIME;
    QUEUE : UINT;
    QUEUE_BYTES : UINT;
  END_VAR
  VAR_OUTPUT
    APPLIED : BOOL;
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
  END_VAR
  VAR
  END_VAR
#include <ModBeeModbus.h>

// Defined in MODBUS_NODE.cpp. Every C++ POU lands in ONE translation
// unit in filename order, so a block sorting before it declares them.
int32_t mb_millisOf(const strucpp::IEC_TIME& t);
int32_t mb_microsOf(const strucpp::IEC_LTIME& t);
strucpp::IEC_TIME mb_timeOf(int32_t milliseconds);

strucpp::XWORD_t mb_currentTask();
bool mb_inTask(strucpp::XWORD_t owner);

void setup()
{
    APPLIED = false;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
}

void loop()
{
    if (!mb_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per node: see MODBUS_ARDUINO
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_WRONG_TASK;
        return;
    }
    // NOT guarded on NODE.READY, unlike every other block that takes a node.
    // This one has to run BEFORE the link opens - that is its whole purpose -
    // so it writes into the node's own settings and lets the node use them
    // when it builds the link.
    NODE.FBFRAMING = FRAMING;
    NODE.FBTIMEOUTMS = mb_millisOf(TIMEOUT);
    NODE.FBRETRIES = RETRIES;
    NODE.FBFAILSAFEMS = mb_millisOf(FAILSAFE);
    NODE.FBMAXCLIENTS = MAX_CLIENTS;
    NODE.FBQUEUE = QUEUE;
    NODE.FBQUEUEBYTES = QUEUE_BYTES;
    NODE.FBIDLEMS = mb_millisOf(IDLE);
    NODE.FBRECONNECTMS = mb_millisOf(RECONNECT);

    // Timeout and retries are settable on a live link, so a change to either
    // takes effect without reopening anything.
    ModbusAPI* mb = (ModbusAPI*)(uintptr_t)(strucpp::XWORD_t)NODE.FBAPI;
    if (mb && (bool)NODE.READY) {
        const int32_t timeoutMs = mb_millisOf(TIMEOUT);
        if (timeoutMs > 0) mb->timeout((mb_time_t)timeoutMs);
        if ((uint8_t)RETRIES > 0) mb->retries((uint8_t)RETRIES);
    }

    APPLIED = true;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
}

END_FUNCTION_BLOCK