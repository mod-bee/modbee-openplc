(* Keeps a value up to date on its own, and says how much to believe it.

NODE      which node. Must be wired.
UNIT      the device's address, 1..247.
FC        which read. Named the way a device manual names it.
          MODBUS_FC01_READ_COILS, MODBUS_FC02_READ_DISCRETE_INPUTS,
          MODBUS_FC03_READ_HOLDING_REGISTERS, MODBUS_FC04_READ_INPUT_REGISTERS
ADDRESS   the first address on that device.
EVERY     how often to read it. T#1s if left at T#0s.
LENGTH    how many to move. Leave it at 0 and the variable says how many.
ORDER     how a 32- or 64-bit value is laid out across its registers.
          MODBUS_ORDER_ABCD, MODBUS_ORDER_CDAB, MODBUS_ORDER_BADC,
          MODBUS_ORDER_DCBA
DEADBAND  how far the value must move to count as a change. 0 reports every
          read as one.
ENABLE    watch while this is TRUE. TRUE unless you say otherwise, so leave it
          unwired and the watch simply runs.
VALUE     the variable to keep up to date.

WATCHING  the watch is fbRunning.
COUNT     how many addresses it covers.
QUALITY   how much to believe VALUE right now.
          MODBUS_QUALITY_UNKNOWN, MODBUS_QUALITY_GOOD,
          MODBUS_QUALITY_UNCERTAIN, MODBUS_QUALITY_BAD
SEEN      a value has arrived at least ONCE since the program started. It
          is what tells an AGE of T#0s apart: SEEN FALSE means nothing has
          ever come, which is a COMMISSIONING fault - a wrong address, or
          a device never fitted. SEEN TRUE with a long AGE is a RUNNING
          fault - a cable, or a dead device. A ladder cannot compare an
          enumeration, so this is how a rung asks what QUALITY answers.
AGE       how long since it last arrived. T#0s until it ever has, which
          QUALITY reading UNKNOWN is what distinguishes from a fresh one.
FAILURES  reads that failed in a row. One is a hiccup, ten is a device that
          has gone.
ERROR     the watch could not be set up, or its last read failed.
STATUS    why. MODBUS_OK when fine.
          MODBUS_QUEUED, MODBUS_OK, MODBUS_NOT_INITIALISED,
          MODBUS_INVALID_ARGUMENT, MODBUS_NOT_MAPPED, MODBUS_DUPLICATE,
          MODBUS_QUEUE_FULL, MODBUS_UNKNOWN_UNIT, MODBUS_SUPERSEDED,
          MODBUS_CANCELLED, MODBUS_TIMEOUT, MODBUS_REFUSED,
          MODBUS_ACKNOWLEDGED, MODBUS_BUSY, MODBUS_GATEWAY_PATH_UNAVAILABLE,
          MODBUS_GATEWAY_TARGET_FAILED, MODBUS_LINK_DOWN,
          MODBUS_CHECKSUM_ERROR, MODBUS_PROTOCOL_ERROR

---

  MODBUS_WATCH( NODE := node, UNIT := 2,
                FC := MODBUS_FC04_READ_INPUT_REGISTERS,
                ADDRESS := 30, EVERY := T#2s, VALUE := tankLevel );

There is no request pin. Say what to read and how often, and it arrives.

THIS BLOCK NEVER TOUCHES THE WIRE. It decides a read is due - every two
seconds, above - and hands it to the same queue everything else uses. The node
transmits it on its next call, and the answer lands in your variable. So a
watch inherits the whole contract rather than being a special case:

  - a read still outstanding when the next falls due is refused as a duplicate
    rather than stacked, so a watch cannot flood the bus however short its
    interval;
  - a device that stops answering is backed off to as little as one attempt in
    sixteen, so one dead unit does not consume the segment;
  - every read reaches exactly one conclusion, which is what FAILURES counts.

WHY QUALITY MATTERS MORE HERE THAN ANYWHERE. A register holding 1234 tells you
nothing about whether 1234 is still true. On a bus where one device has
quietly failed, a stale reading looks exactly like a steady process - the
number is plausible, it does not flicker, and every alarm stays clear. QUALITY
is what separates the two:

  MODBUS_QUALITY_GOOD       read within the interval you asked for. Act on it.
  MODBUS_QUALITY_UNCERTAIN  late, but not by much. One missed read on a busy
                            bus looks like this and is usually nothing.
  MODBUS_QUALITY_BAD        stale past any reasonable allowance, or the last
                            read failed. Do not act on it.
  MODBUS_QUALITY_UNKNOWN    never read at all.

UNKNOWN AND BAD ARE NOT THE SAME THING, and it is worth wiring them to
different alarms. UNKNOWN means this value has never arrived - an address
typed wrong, a unit id that is not on the bus, a device never fitted. That is
a commissioning fault, found at the desk. BAD means it did arrive and has
since stopped - a cable, a power supply, a device that died. That is a fbRunning
fault, found in the plant. An alarm list that treats them alike sends somebody
to the wrong end of the site.

INTERLOCK ON QUALITY, NOT ON VALUE:

  IF watch.QUALITY = MODBUS_QUALITY_GOOD AND tankLevel > 900 THEN
      closeInletValve := TRUE;
  END_IF;

HOW OFTEN. EVERY is what you asked for, and it is also what QUALITY is
judged against - ask for 100 ms on a bus that cannot manage it and the value
will read UNCERTAIN for being exactly as late as you should have expected.
Ask for what the process needs. A tank level wants seconds; a torque feedback
may want a hundred milliseconds; a nameplate wants reading once. Every extra
read is bus time that a control word cannot have.

ENABLE stops and starts the watch in place, without adding a second one, so a
value watched only in one machine state costs nothing the rest of the time.
Starting it reads at once rather than waiting out an interval.

UNIT, FC, ADDRESS AND ORDER MAY CHANGE WHILE RUNNING - from settings, say - and
the watch follows: the same entry is re-aimed, QUALITY goes back to UNKNOWN
and the next read goes to the new place. LENGTH and VALUE are fixed at the
first call. For a point whose type and scaling come from settings too, use
MODBUS_POINT. *)

FUNCTION_BLOCK MODBUS_WATCH
  VAR_IN_OUT
    NODE : MODBUS_NODE;
  END_VAR
  VAR_INPUT
    UNIT : BYTE;
    FC : MODBUS_READ_FC;
    ADDRESS : UINT;
    EVERY : TIME;
    LENGTH : UINT;
    ORDER : MODBUS_ORDER;
    DEADBAND : UINT;
    ENABLE : BOOL := TRUE;
    VALUE : ANY;
  END_VAR
  VAR_OUTPUT
    WATCHING : BOOL;
    COUNT : UINT;
    QUALITY : MODBUS_QUALITY;
    SEEN : BOOL;
    AGE : TIME;
    FAILURES : UINT;
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
  END_VAR
  VAR
    fbHandle : __XWORD;
    fbStorage : __XWORD;
    fbRunning : BOOL;
    fbSeenInterval : DINT;
    fbSeenDeadband : UINT;
    fbSeenUnit : BYTE;
    fbSeenFc : MODBUS_READ_FC;
    fbSeenAddress : UINT;
    fbSeenOrder : MODBUS_ORDER;
  END_VAR
#include <ModBeeModbus.h>

// Defined by the MODBUS_NODE block, which every project has.
uint8_t mb_elementBits(uint32_t typeClass);
int32_t mb_millisOf(const strucpp::IEC_TIME& t);
int32_t mb_microsOf(const strucpp::IEC_LTIME& t);
strucpp::IEC_TIME mb_timeOf(int32_t milliseconds);
ModbusWideType mb_wideTypeOfClass(uint32_t typeClass);

strucpp::XWORD_t mb_currentTask();
bool mb_inTask(strucpp::XWORD_t owner);

void setup()
{
    WATCHING = false;
    COUNT = 0;
    QUALITY = MODBUS_QUALITY::MODBUS_QUALITY_UNKNOWN;
    AGE = mb_timeOf(0);
    SEEN = false;
    FAILURES = 0;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
    fbHandle = (strucpp::XWORD_t)0;
    fbStorage = (strucpp::XWORD_t)0;
    fbRunning = false;
    fbSeenInterval = 0;
    fbSeenDeadband = 0;
    fbSeenUnit = 0;
    fbSeenAddress = 0;
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
        WATCHING = false;
        QUALITY = MODBUS_QUALITY::MODBUS_QUALITY_UNKNOWN;
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_LINK_DOWN;
        return;
    }

    const mb_time_t interval =
        (mb_millisOf(EVERY) > 0) ? (mb_time_t)mb_millisOf(EVERY) : 1000u;

    // Held as fbHandle+1, so zero means "no watch yet" - index 0 is a real
    // watch and would otherwise be indistinguishable from never having made
    // one.
    size_t index = (size_t)(strucpp::XWORD_t)fbHandle;

    if (index == 0) {
        const int32_t held = VALUE.DICOUNT;
        const int32_t asked = (int32_t)(uint16_t)LENGTH;
        const int32_t count = (asked == 0) ? held : (asked <= held ? asked : 0);

        const uint8_t bits = mb_elementBits((uint32_t)VALUE.ELEMCLASS);
        const ModbusTable table = (ModbusTable)(MODBUS_READ_FC)FC;
        const bool wantsBits = mb_tableIsBits(table);

        if (count <= 0 || count > 0xFFFF || bits == 0 || VALUE.PVALUE == nullptr ||
            (wantsBits != (bits == 1))) {
            WATCHING = false;
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            return;
        }

        const uint16_t stride = (uint16_t)VALUE.DISTRIDE;
        const uint16_t many = (uint16_t)count;
        const uint8_t unit = (uint8_t)UNIT;
        const uint16_t first = (uint16_t)ADDRESS;

        size_t made;
        if (bits == 1) {
            made = mb->poller().addBits(unit, first, (bool*)VALUE.PVALUE, many,
                                        interval, table, stride);
        } else if (bits == 16) {
            made = mb->poller().addRegisters(unit, first, (uint16_t*)VALUE.PVALUE, many,
                                             interval, table, stride);
        } else {
            made = mb->poller().addWide(unit, first, VALUE.PVALUE,
                                        mb_wideTypeOfClass((uint32_t)VALUE.ELEMCLASS),
                                        many, interval,
                                        (ModbusOrder)(MODBUS_ORDER)ORDER, table, stride);
        }

        if (made == (size_t)-1) {
            WATCHING = false;
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            return;
        }

        index = made + 1;
        fbHandle = (strucpp::XWORD_t)index;
        fbStorage = (strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE;
        fbRunning = true;
        COUNT = (uint16_t)count;
        fbSeenInterval = (int32_t)interval;
        fbSeenDeadband = (uint16_t)DEADBAND;
        fbSeenUnit = (uint8_t)UNIT;
        fbSeenFc = FC;
        fbSeenAddress = (uint16_t)ADDRESS;
        fbSeenOrder = ORDER;
        if ((uint16_t)DEADBAND > 0) {
            mb->poller().setDeadband(made, (uint16_t)DEADBAND);
        }
    }

    const size_t poll = index - 1;

    // The descriptor is rebuilt at every call, and a pin that moved would
    // leave the poller writing where nothing reads.
    if ((strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE != (strucpp::XWORD_t)fbStorage) {
        fbStorage = (strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE;
        mb->poller().remove(poll);
        fbRunning = false;
        WATCHING = false;
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
        return;
    }

    // Stopped and started in place rather than added again, so a value watched
    // only in one machine state does not grow the poll table every time that
    // state is entered.
    const bool want = (bool)ENABLE;
    if (want != (bool)fbRunning) {
        fbRunning = want;
        if (want) mb->poller().resume(poll);
        else mb->poller().remove(poll);
    }

    // THE ADDRESS FOLLOWS THE PINS. UNIT, FC, ADDRESS and ORDER used to be read
    // once, at the first call, so a watch whose address came from settings
    // kept reading the old place for ever. Now a change re-aims the same
    // entry: the next read goes to the new address and QUALITY starts again
    // from UNKNOWN. LENGTH and the variable still fix the size at the first
    // call - the variable is what the entry writes into.
    if ((uint8_t)UNIT != (uint8_t)fbSeenUnit || FC != fbSeenFc ||
        (uint16_t)ADDRESS != (uint16_t)fbSeenAddress || ORDER != fbSeenOrder) {
        const ModbusTable table = (ModbusTable)(MODBUS_READ_FC)FC;
        if (!mb->poller().retarget(poll, (uint8_t)UNIT, (uint16_t)ADDRESS, table,
                                   (ModbusOrder)(MODBUS_ORDER)ORDER)) {
            // Bits asked of a register variable, or the reverse: the variable
            // cannot hold what that function code returns.
            WATCHING = false;
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            return;
        }
        fbSeenUnit = (uint8_t)UNIT;
        fbSeenFc = FC;
        fbSeenAddress = (uint16_t)ADDRESS;
        fbSeenOrder = ORDER;
    }

    // Both are changed in place, keeping the value, the quality and the index.
    if ((int32_t)interval != (int32_t)fbSeenInterval) {
        fbSeenInterval = (int32_t)interval;
        mb->poller().setInterval(poll, interval);
    }
    if ((uint16_t)DEADBAND != (uint16_t)fbSeenDeadband) {
        fbSeenDeadband = (uint16_t)DEADBAND;
        mb->poller().setDeadband(poll, (uint16_t)DEADBAND);
    }

    WATCHING = (bool)fbRunning;
    QUALITY = (MODBUS_QUALITY)(int32_t)mb->poller().quality(poll);

    const mb_time_t age = mb->poller().age(poll);
    AGE = mb_timeOf((age == ModbusPoller::NEVER) ? 0 : (int32_t)age);
    SEEN = (age != ModbusPoller::NEVER);

    FAILURES = (uint16_t)mb->poller().consecutiveFailures(poll);

    const ModbusResult last = mb->poller().lastResult(poll);
    STATUS = (MODBUS_RESULT)(int32_t)last;
    ERROR = !mb_accepted(last);
}

END_FUNCTION_BLOCK