(* Reads from a device, on a rising edge of REQ.

NODE     which node. Must be wired.
REQ      rising edge reads.
UNIT     the device's address, 1..247.
FC       which read. Named the way a device manual names it.
         MODBUS_FC01_READ_COILS, MODBUS_FC02_READ_DISCRETE_INPUTS,
         MODBUS_FC03_READ_HOLDING_REGISTERS, MODBUS_FC04_READ_INPUT_REGISTERS
ADDRESS  the first address on that device.
LENGTH   how many to move. Leave it at 0 and the variable says how many, which
         is almost always what you want. A smaller figure moves that many into
         a bigger buffer. Larger than the variable is MODBUS_INVALID_ARGUMENT
         rather than a read off the end.
ORDER    how a 32- or 64-bit value is laid out across its registers. Ignored
         for BOOL and WORD.
         MODBUS_ORDER_ABCD, MODBUS_ORDER_CDAB, MODBUS_ORDER_BADC,
         MODBUS_ORDER_DCBA
VALUE    the variable to read into. A single value or a fixed-bounds array.

BUSY   the request is outstanding.
DONE   one scan, when the answers arrived.
COUNT  how many addresses were moved.
ERROR  they did not.
STATUS why. MODBUS_OK when fine.
       MODBUS_QUEUED, MODBUS_OK, MODBUS_NOT_INITIALISED,
       MODBUS_INVALID_ARGUMENT, MODBUS_NOT_MAPPED, MODBUS_DUPLICATE,
       MODBUS_QUEUE_FULL, MODBUS_UNKNOWN_UNIT, MODBUS_SUPERSEDED,
       MODBUS_CANCELLED, MODBUS_TIMEOUT, MODBUS_REFUSED,
       MODBUS_ACKNOWLEDGED, MODBUS_BUSY, MODBUS_GATEWAY_PATH_UNAVAILABLE,
       MODBUS_GATEWAY_TARGET_FAILED, MODBUS_LINK_DOWN,
       MODBUS_CHECKSUM_ERROR, MODBUS_PROTOCOL_ERROR

---

One block for a single value or a whole range, for bits or registers, and for
values wider than a register. What was passed decides which:

  MODBUS_READ( NODE := node, UNIT := 2,
               FC := MODBUS_FC03_READ_HOLDING_REGISTERS,
               ADDRESS := 40, VALUE := mySpeed );

  MODBUS_READ( NODE := node, UNIT := 2,
               FC := MODBUS_FC03_READ_HOLDING_REGISTERS,
               ADDRESS := 100, VALUE := aTrend );

  MODBUS_READ( NODE := node, UNIT := 2,
               FC := MODBUS_FC01_READ_COILS,
               ADDRESS := 0, VALUE := myCoils );

  MODBUS_READ( NODE := node, UNIT := 2,
               FC := MODBUS_FC04_READ_INPUT_REGISTERS,
               ADDRESS := 30, ORDER := MODBUS_ORDER_CDAB, VALUE := flowRate );

A range is one request rather than one per address, which is the difference
between a scan and a second when there are a hundred of them. The answers land
together, on a later scan.

THE VARIABLE SAYS HOW MANY. Leave LENGTH at 0 and the count comes from the pin
itself, so `aTrend : ARRAY[0..99] OF WORD` reads a hundred registers without
you typing 100 anywhere - and it cannot drift when the array is resized later.
Getting a length wrong is the commonest mistake anyone makes on a Modbus
system and the one that reads past the end of a buffer, so the block does not
ask for a number it can work out.

An override is only for a deliberate partial transfer. Larger than the array
is refused, and so is more than one request may carry - 2000 bits or 125
registers - both with MODBUS_INVALID_ARGUMENT, before anything reaches the
wire.

FC says which of Modbus's four lists to read, and they are separate numbered
lists: address 40 in one is a different thing from address 40 in another.

  MODBUS_FC01_READ_COILS             on/off, a client may also write them
  MODBUS_FC02_READ_DISCRETE_INPUTS   on/off, read only
  MODBUS_FC03_READ_HOLDING_REGISTERS 16 bits, a client may also write them
  MODBUS_FC04_READ_INPUT_REGISTERS   16 bits, read only

A bit list needs a BOOL variable and a register list needs a numeric one.
Crossing them is refused rather than reinterpreted.

A REGISTER ARRAY IS WORD, NOT INT. WORD is what a program can mask, shift and
take a bit of - myWord.6 for bit 6 - and AND, OR and SHL are all typed ANY_BIT,
which INT is not. Use WORD_TO_INT where you want it as a signed number.

REAL, DINT, UDINT, LREAL, LINT and ULINT work too, and take two registers each
or four. Nothing on the wire says which way round a device puts them, which is
what ORDER is for: if a flow rate reads as 4.6e-41 rather than 1234.5, the
layout is wrong, not the address. MODBUS_ORDER_CDAB is the one to try next.

ONE REQUEST AT A TIME PER ADDRESS. A second read of the same address while the
first is still outstanding is refused as MODBUS_DUPLICATE rather than queued
twice - which is why holding REQ high is safe: it reads once, not once a scan. *)

FUNCTION_BLOCK MODBUS_READ
  VAR_IN_OUT
    NODE : MODBUS_NODE;
  END_VAR
  VAR_INPUT
    REQ : BOOL;
    UNIT : BYTE;
    FC : MODBUS_READ_FC;
    ADDRESS : UINT;
    LENGTH : UINT;
    ORDER : MODBUS_ORDER;
    VALUE : ANY;
  END_VAR
  VAR_OUTPUT
    BUSY : BOOL;
    DONE : BOOL;
    COUNT : UINT;
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
  END_VAR
  VAR
    fbLastReq : BOOL;
    fbPending : BOOL;
  END_VAR
#include <ModBeeModbus.h>

// Defined by the MODBUS_NODE block, which every project has.
uint8_t mb_elementBits(uint32_t typeClass);
ModbusWideType mb_wideTypeOfClass(uint32_t typeClass);

strucpp::XWORD_t mb_currentTask();
bool mb_inTask(strucpp::XWORD_t owner);

void setup()
{
    BUSY = false;
    DONE = false;
    COUNT = 0;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
    fbLastReq = false;
    fbPending = false;
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
        BUSY = false;
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_LINK_DOWN;
        return;
    }

    if ((bool)fbPending) {
        ModbusResult outcome = ModbusResult::Ok;
        const ModbusRequestState state =
            mb->status((uint8_t)UNIT, (uint16_t)ADDRESS, outcome);
        if (state == ModbusRequestState::Pending) {
            BUSY = true;
            DONE = false;
            ERROR = false;
            return;
        }
        fbPending = false;
        BUSY = false;
        DONE = (state == ModbusRequestState::Done);
        ERROR = (state == ModbusRequestState::Failed);
        STATUS = (MODBUS_RESULT)(int32_t)outcome;
        return;
    }

    // DONE and ERROR are one-scan edges: set on the scan the operation
    // finished and cleared on the next, so a caller counting them counts
    // operations.
    BUSY = false;
    DONE = false;
    ERROR = false;

    const bool rose = (bool)REQ && !(bool)fbLastReq;
    fbLastReq = (bool)REQ;
    if (!rose) return;

    // What was passed says how many unless LENGTH overrides it, and an
    // override bigger than what was passed is refused rather than read off the
    // end.
    const int32_t held = VALUE.DICOUNT;
    const int32_t asked = (int32_t)(uint16_t)LENGTH;
    const int32_t count = (asked == 0) ? held : (asked <= held ? asked : 0);

    const uint8_t bits = mb_elementBits((uint32_t)VALUE.ELEMCLASS);

    // MODBUS_READ_FC is ordered to match ModbusTable, so FC01 is the coil
    // list, FC02 the discrete inputs and so on.
    const ModbusTable table = (ModbusTable)(MODBUS_READ_FC)FC;
    const bool wantsBits = mb_tableIsBits(table);

    // A zeroed descriptor reads as TYPE_BOOL, because that class is zero - so
    // an unwired pin has to be caught by its storage, not by its type.
    if (count <= 0 || count > 0xFFFF || bits == 0 || VALUE.PVALUE == nullptr ||
        (wantsBits != (bits == 1))) {
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
        return;
    }

    // An element carries its forced state beside its value, so the elements
    // are not adjacent. The protocol is given the gap and fills them in place.
    const uint16_t stride = (uint16_t)VALUE.DISTRIDE;
    const uint16_t first = (uint16_t)ADDRESS;
    const uint8_t unit = (uint8_t)UNIT;
    const uint16_t many = (uint16_t)count;
    const ModbusOrder order = (ModbusOrder)(MODBUS_ORDER)ORDER;

    ModbusResult result = ModbusResult::InvalidArgument;

    if (bits == 1) {
        result = (table == ModbusTable::Coil)
            ? mb->client().readCoils(unit, first, (bool*)VALUE.PVALUE, many,
                                     nullptr, stride)
            : mb->client().readDiscreteInputs(unit, first, (bool*)VALUE.PVALUE, many,
                                              nullptr, stride);
    } else if (bits == 16) {
        result = (table == ModbusTable::HoldingRegister)
            ? mb->client().readHoldingRegisters(unit, first, (uint16_t*)VALUE.PVALUE,
                                                many, nullptr, stride)
            : mb->client().readInputRegisters(unit, first, (uint16_t*)VALUE.PVALUE,
                                              many, nullptr, stride);
    } else {
        // Wider than a register. Only the holding and input lists carry these,
        // and both arrive as registers that are converted on the way in.
        result = mb->client().readWideArray(
            unit, first, VALUE.PVALUE, mb_wideTypeOfClass((uint32_t)VALUE.ELEMCLASS),
            order, many, stride, nullptr, table);
    }

    if (!mb_accepted(result) && result != ModbusResult::Duplicate) {
        ERROR = true;
        STATUS = (MODBUS_RESULT)(int32_t)result;
        return;
    }

    COUNT = (uint16_t)count;

    if (result == ModbusResult::Ok) {
        // A local address answers in place.
        DONE = true;
        STATUS = (MODBUS_RESULT)(int32_t)result;
        return;
    }

    fbPending = true;
    BUSY = true;
    STATUS = (MODBUS_RESULT)(int32_t)result;
}

END_FUNCTION_BLOCK