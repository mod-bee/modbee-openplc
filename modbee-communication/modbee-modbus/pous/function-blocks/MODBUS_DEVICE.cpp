(* How one device on the bus is doing, and what it says it is.

NODE        which node. Must be wired.
UNIT        the device's address, 1..247.
IDENTIFY    rising edge asks the device for its nameplate. Once is enough.
POLL        ask this device whether it is alive, this often. T#0s watches only
            the traffic your program already makes, which costs nothing but
            answers nothing about a device nobody talks to.

ANSWERING   this device has answered within the last GONE.
SEEN        it has answered at least ONCE since the program started. SEEN
            FALSE is a device never fitted or addressed wrongly - found at
            the desk. SEEN TRUE with ANSWERING FALSE is one that has died -
            found in the plant.
SILENT      how long since it last answered anything. T#0s until it ever
            has.
ROUND_TRIP  how long it takes to reply, measured.
VENDOR      who made it.
PRODUCT     what it is.
REVISION    which version.
IDENTIFIED  one scan, when the nameplate arrived.
ERROR       no such node, or the nameplate could not be read.
STATUS      why. MODBUS_OK when fine.
            MODBUS_QUEUED, MODBUS_OK, MODBUS_NOT_INITIALISED,
            MODBUS_INVALID_ARGUMENT, MODBUS_NOT_MAPPED, MODBUS_DUPLICATE,
            MODBUS_QUEUE_FULL, MODBUS_UNKNOWN_UNIT, MODBUS_SUPERSEDED,
            MODBUS_CANCELLED, MODBUS_TIMEOUT, MODBUS_REFUSED,
            MODBUS_ACKNOWLEDGED, MODBUS_BUSY,
            MODBUS_GATEWAY_PATH_UNAVAILABLE, MODBUS_GATEWAY_TARGET_FAILED,
            MODBUS_LINK_DOWN, MODBUS_CHECKSUM_ERROR, MODBUS_PROTOCOL_ERROR

GONE        how long a device may be silent before ANSWERING drops. T#0s
            uses T#5s. Give it room for at least two POLL intervals.

---

ANSWERING, SILENT and ROUND_TRIP ARE READ OFF TRAFFIC YOU ARE ALREADY
MAKING. With POLL at T#0s this block sends nothing at all, so a screen showing
thirty devices you are already reading costs not one extra frame.

WHICH MEANS A DEVICE NOBODY ASKS ANYTHING READS AS NOT ANSWERING. That is
literally true and thoroughly unhelpful: the device may be in perfect health
and simply have nothing to say, because nothing has spoken to it. If this is
the only block pointed at a device - a standby unit, a device another PLC owns,
one you watch but never read - give it a POLL and it will ask:

  MODBUS_DEVICE( NODE := node, UNIT := 5, POLL := T#2s );

The question it sends is the standard link test, function code 8: whatever is
sent comes back unchanged, and it touches no register. A device that does not
implement FC 8 answers with an EXCEPTION - which still proves it is alive and
still counts as answering, because a unit that is transmitting is a unit that
is there. So the check works on devices that refuse it.

SILENT AT T#0s IS NOT A SHORT SILENCE. While ANSWERING is FALSE it means
this device has never answered
at all, which is a different fault from one that has gone quiet:

  never answered   the unit id is wrong, the device was never fitted, or it is
                   set to a different address. A commissioning fault, found at
                   the desk with a wiring drawing.
  gone quiet       it was answering and has stopped. A cable, a power supply,
                   a failed device. A running fault, found in the plant.

An alarm list that shows both as "no comms" sends somebody to the wrong end of
the site, so the two are kept apart here rather than collapsed into one big
number.

ROUND_TRIP is the number to quote when somebody asks whether a device is
slow or the bus is. A drive answering in 45 ms on a bus whose other devices
answer in 6 ms is a slow drive, and no amount of changing the baud rate will
help.

IDENTIFY reads the device's own nameplate with function code 43 - the same
information a handheld tool shows. Not every device implements it; one that
does not answers with an exception, which arrives as MODBUS_REFUSED and is
not a fault worth alarming on. Ask once at start-up and keep what comes back. *)

FUNCTION_BLOCK MODBUS_DEVICE
  VAR_IN_OUT
    NODE : MODBUS_NODE;
  END_VAR
  VAR_INPUT
    UNIT : BYTE;
    IDENTIFY : BOOL;
    POLL : TIME;
    GONE : TIME;
  END_VAR
  VAR_OUTPUT
    ANSWERING : BOOL;
    SEEN : BOOL;
    SILENT : TIME;
    ROUND_TRIP : TIME;
    VENDOR : STRING(32);
    PRODUCT : STRING(32);
    REVISION : STRING(32);
    IDENTIFIED : BOOL;
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
  END_VAR
  VAR
    fbLastIdentify : BOOL;
    fbState : __XWORD;
    fbNextPoll : DINT;
    fbPolling : BOOL;
  END_VAR
#include <ModBeeModbus.h>

// Defined in MODBUS_NODE.cpp. Every C++ POU lands in ONE translation
// unit in filename order, so a block sorting before it declares them.
int32_t mb_millisOf(const strucpp::IEC_TIME& t);
int32_t mb_microsOf(const strucpp::IEC_LTIME& t);
strucpp::IEC_TIME mb_timeOf(int32_t milliseconds);

#include <new>
#include <string.h>

// What one outstanding identity read needs, owned by this block instance.
//
// Held here rather than on the pins because the reply is raw bytes that have
// to survive until the bus gets round to the request, and because an IEC array
// is not a run of raw bytes: every element carries its forced fbState beside its
// value, so a buffer built from one would interleave the reply with flags.
struct MbIdentityState {
    uint8_t  reply[128];
    bool     inFlight;
    bool     arrived;
    ModbusResult result;
};

// One object out of a function code 43 response, into a bounded buffer.
//
// The response carries a list of {id, length, bytes} with no terminator and a
// length that comes off the wire, so every step is bounded by what actually
// arrived rather than by what the device claims.
// The read's completion: a function and the block's state, so nothing is
// allocated per read.
static void mbIdentityArrived(void* state, ModbusResult r) {
    MbIdentityState* own = (MbIdentityState*)state;
    own->result = r;
    own->arrived = true;
}

static void mbIdentityObject(const uint8_t* data, uint16_t length, uint8_t wanted,
                             char* out, size_t capacity)
{
    out[0] = '\0';
    if (!data || length < 6) return;

    // The response's data begins after the function code AND the MEI type,
    // both of which the decoder strips: the read-device-id code, the
    // conformity level, more-follows, the next object id, the object count,
    // and then the objects themselves.
    //
    // A decoder that leaves the MEI type on is also accepted, because the two
    // layouts cannot be confused: byte 0 is either the MEI type, always 0x0E,
    // or a read-device-id code, which is only ever 1 to 4. Getting this offset
    // wrong reads the object count out of the conformity level and returns
    // nothing at all, which is exactly what it did.
    uint16_t at = (data[0] == 0x0E) ? 1 : 0;
    if ((uint16_t)(at + 5) > length) return;

    uint16_t objects = data[at + 4];
    at = (uint16_t)(at + 5);
    while (objects-- > 0) {
        if ((uint16_t)(at + 2) > length) return;
        const uint8_t id = data[at];
        const uint8_t len = data[at + 1];
        at = (uint16_t)(at + 2);
        if ((uint32_t)at + len > length) return;

        if (id == wanted) {
            size_t take = len;
            if (take > capacity - 1) take = capacity - 1;
            memcpy(out, data + at, take);
            out[take] = '\0';
            return;
        }
        at = (uint16_t)(at + len);
    }
}

strucpp::XWORD_t mb_currentTask();
bool mb_inTask(strucpp::XWORD_t owner);

void setup()
{
    ANSWERING = false;
    SILENT = mb_timeOf(0);
    ROUND_TRIP = mb_timeOf(0);
    SEEN = false;
    VENDOR = "";
    PRODUCT = "";
    REVISION = "";
    IDENTIFIED = false;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
    fbLastIdentify = false;
    fbState = (strucpp::XWORD_t)0;
    fbNextPoll = 0;
    fbPolling = false;
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
        ANSWERING = false;
        IDENTIFIED = false;
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_LINK_DOWN;
        return;
    }

    const uint8_t unit = (uint8_t)UNIT;
    const mb_time_t gone =
        (mb_millisOf(GONE) > 0) ? (mb_time_t)mb_millisOf(GONE) : 5000u;

    // Observed from traffic already happening, so a screen full of these puts
    // nothing extra on the bus.
    const mb_time_t silence = mb->silenceFor(unit);
    if (silence == MB_NEVER_HEARD) {
        SILENT = mb_timeOf(0);
        SEEN = false;
        ANSWERING = false;
    } else {
        SILENT = mb_timeOf((int32_t)silence);
        SEEN = true;
        ANSWERING = (silence <= gone);
    }
    ROUND_TRIP = mb_timeOf((int32_t)mb->roundTrip(unit));

    // An active health check, for a device this block is the only thing
    // pointed at. Paced by POLL and skipped entirely at T#0s.
    const int32_t pollEvery = mb_millisOf(POLL);
    if (pollEvery > 0) {
        const mb_time_t now = mb_millis();
        if (!(bool)fbPolling ||
            (int32_t)(now - (mb_time_t)(uint32_t)(int32_t)fbNextPoll) >= 0) {
            fbPolling = true;
            fbNextPoll = (int32_t)(uint32_t)(now + (mb_time_t)pollEvery);

            // Refused as a duplicate while one is still outstanding, which is
            // what stops a short interval stacking pings on a slow device.
            mb->ping(unit);
        }
    }

    IDENTIFIED = false;

    MbIdentityState* own = (MbIdentityState*)(uintptr_t)(strucpp::XWORD_t)fbState;

    // The outcome is taken from a completion handler rather than by asking
    // status() for unit and address. A function code 43 request carries no
    // address, so it would be asked for as address 0 - and a read of coil 0 on
    // the same device is also address 0. Two different operations answering to
    // one question is how a block ends up reporting somebody else's result.
    if (own && own->arrived) {
        own->arrived = false;
        own->inFlight = false;

        STATUS = (MODBUS_RESULT)(int32_t)own->result;
        ERROR = !mb_succeeded(own->result);

        if (mb_succeeded(own->result)) {
            char field[32];
            mbIdentityObject(own->reply, sizeof own->reply, 0x00, field, sizeof field);
            VENDOR = field;
            mbIdentityObject(own->reply, sizeof own->reply, 0x01, field, sizeof field);
            PRODUCT = field;
            mbIdentityObject(own->reply, sizeof own->reply, 0x02, field, sizeof field);
            REVISION = field;
            IDENTIFIED = true;
        }
        return;
    }

    const bool rose = (bool)IDENTIFY && !(bool)fbLastIdentify;
    fbLastIdentify = (bool)IDENTIFY;
    if (!rose) return;

    if (!own) {
        own = new (std::nothrow) MbIdentityState();
        if (!own) {
            // Arduino cores build without exceptions, so an exhausted heap has
            // to be handled here. The nameplate is not read and says so; the
            // PLC keeps running.
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_NOT_INITIALISED;
            return;
        }
        fbState = (strucpp::XWORD_t)(uintptr_t)own;
    }

    // One at a time. A second ask while the first is outstanding would leave
    // two requests writing into one buffer.
    if (own->inFlight) {
        STATUS = MODBUS_RESULT::MODBUS_DUPLICATE;
        return;
    }

    memset(own->reply, 0, sizeof own->reply);
    own->arrived = false;
    own->result = ModbusResult::Queued;
    own->inFlight = true;

    const ModbusResult asked =
        mb->readDeviceId(unit, own->reply, (uint16_t)sizeof own->reply,
                         ModbusDone(&mbIdentityArrived, own));

    if (!mb_accepted(asked)) {
        // Refused before it reached the wire. The handler still runs, on the
        // node's next call, so nothing is concluded twice here.
        STATUS = (MODBUS_RESULT)(int32_t)asked;
        return;
    }

    STATUS = (MODBUS_RESULT)(int32_t)asked;
}

END_FUNCTION_BLOCK