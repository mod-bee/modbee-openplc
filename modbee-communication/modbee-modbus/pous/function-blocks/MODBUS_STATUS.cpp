(* How this link is doing. Every number is measured; nothing here is a setting.

NODE           which node. Must be wired.

CONNECTED      there is something at the other end.
CLIENTS        clients connected, for a server.
PENDING        requests queued and not yet concluded.
SENT           frames transmitted.
RECEIVED       frames received.
CHECKSUM_ERRORS  frames that arrived corrupt. On an otherwise quiet bus this
                 is the number to judge a link by.
FRAMING_ERRORS   frames that were structurally impossible.
NOISE_BYTES    bytes discarded while hunting for the start of a frame.
RECONNECTS     times this link has dropped and come back on its own. A link
               that works but reconnects nightly is a different problem from
               one that has never worked.
FRAMING_REASON how this link finds frames, and WHY, in a sentence.
ERROR          no such node.
STATUS         why. MODBUS_OK when fine.
               MODBUS_QUEUED, MODBUS_OK, MODBUS_NOT_INITIALISED,
               MODBUS_INVALID_ARGUMENT, MODBUS_NOT_MAPPED, MODBUS_DUPLICATE,
               MODBUS_QUEUE_FULL, MODBUS_UNKNOWN_UNIT, MODBUS_SUPERSEDED,
               MODBUS_CANCELLED, MODBUS_TIMEOUT, MODBUS_REFUSED,
               MODBUS_ACKNOWLEDGED, MODBUS_BUSY,
               MODBUS_GATEWAY_PATH_UNAVAILABLE, MODBUS_GATEWAY_TARGET_FAILED,
               MODBUS_LINK_DOWN, MODBUS_CHECKSUM_ERROR, MODBUS_PROTOCOL_ERROR

---

The three error counters are the ones worth putting on a screen, because the
DIFFERENCE between them says which fault you have, and none of them looks any
different from the application's point of view:

  CHECKSUM_ERRORS climbing    noise, a baud rate mismatch, or a missing
                              termination resistor. The bytes arrive and the
                              maths does not agree.
  NOISE_BYTES climbing        a floating bus. Nothing is holding the line at
                              idle, so the receiver keeps finding rubbish
                              between frames. Fit the bias resistors.
  FRAMING_ERRORS climbing     something on the bus is speaking a different
                              protocol, or frames are being split - see
                              FRAMING_REASON.

All three flat while a device does not answer means the bytes are not arriving
at all: wrong port, wrong wires, transmit and receive swapped, or the device
is off.

FRAMING_REASON is the first thing to read when frames go missing, and it is
the answer to the commonest question asked of any Modbus library: why is my
RTU splitting frames. RTU marks the end of a frame with silence - three and a
half character times of it - and a USB adapter, a virtual serial port or a
busy PLC scan can all destroy that silence by delivering bytes in clumps. The
library measures the line and says which rule it is using and why, in a
sentence you can read off the screen.

On a TCP link it says so and stops there - the MBAP header carries the length,
so there is nothing to predict and nothing to measure. On an RTU-over-TCP link
it reports the RTU rule instead, which is how you tell from one pin which of
the two a terminal server actually gave you.

THIS BLOCK HAS NO INPUTS. It reports and changes nothing, which is why it is
safe to drop onto a diagnostic page anywhere. To zero the counters, pulse
RESET_STATS on the node that owns the link. *)

FUNCTION_BLOCK MODBUS_STATUS
  VAR_IN_OUT
    NODE : MODBUS_NODE;
  END_VAR
  VAR_OUTPUT
    CONNECTED : BOOL;
    CLIENTS : INT;
    PENDING : INT;
    SENT : DINT;
    RECEIVED : DINT;
    CHECKSUM_ERRORS : DINT;
    FRAMING_ERRORS : DINT;
    NOISE_BYTES : DINT;
    RECONNECTS : DINT;
    FRAMING_REASON : STRING(160);
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
  END_VAR
  VAR
  END_VAR

#include <ModBeeModbus.h>

strucpp::XWORD_t mb_currentTask();
bool mb_inTask(strucpp::XWORD_t owner);

void setup()
{
    CONNECTED = false;
    CLIENTS = 0;
    PENDING = 0;
    SENT = 0;
    RECEIVED = 0;
    CHECKSUM_ERRORS = 0;
    FRAMING_ERRORS = 0;
    NOISE_BYTES = 0;
    RECONNECTS = 0;
    FRAMING_REASON = "";
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
    ModbusAPI* mb = (ModbusAPI*)(uintptr_t)(strucpp::XWORD_t)NODE.FBAPI;
    if (!mb || !(bool)NODE.READY) {
        CONNECTED = false;
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_LINK_DOWN;
        return;
    }

    CONNECTED = mb->connected();
    CLIENTS = (int16_t)mb->clients();
    PENDING = (int16_t)mb->pending();

    const ModbusLinkStats stats = mb->stats();
    SENT = (int32_t)stats.framesSent;
    RECEIVED = (int32_t)stats.framesReceived;
    CHECKSUM_ERRORS = (int32_t)stats.checksumErrors;
    FRAMING_ERRORS = (int32_t)stats.framingErrors;
    NOISE_BYTES = (int32_t)stats.noiseBytes;
    RECONNECTS = (int32_t)mb->reconnects();

    // Virtual on the base class, because a block holding ModbusAPI* cannot
    // know which kind of link it has - and this is the answer it most needs.
    FRAMING_REASON = mb->framingReason();

    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
}

END_FUNCTION_BLOCK