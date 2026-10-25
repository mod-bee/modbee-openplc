(* Writes to a device, on a rising edge of REQ.

NODE     which node. Must be wired.
REQ      rising edge writes.
UNIT     the device's address, 1..247. 0 broadcasts to every device on the
         segment, which none of them answers.
FC       which write. MODBUS_FC_AUTO picks it from what you passed, which is
         almost always right; name one where a device insists.
         MODBUS_FC_AUTO, MODBUS_FC05_WRITE_SINGLE_COIL,
         MODBUS_FC06_WRITE_SINGLE_REGISTER, MODBUS_FC15_WRITE_MULTIPLE_COILS,
         MODBUS_FC16_WRITE_MULTIPLE_REGISTERS, MODBUS_FC22_MASK_WRITE_REGISTER
ADDRESS  the first address on that device.
LENGTH   how many to move. Leave it at 0 and the variable says how many.
ORDER    how a 32- or 64-bit value is laid out across its registers.
         MODBUS_ORDER_ABCD, MODBUS_ORDER_CDAB, MODBUS_ORDER_BADC,
         MODBUS_ORDER_DCBA
AND_MASK for MODBUS_FC22_MASK_WRITE_REGISTER: the bits to keep.
OR_MASK  for MODBUS_FC22_MASK_WRITE_REGISTER: the bits to set.
VALUE    the variable to write from. A single value or a fixed-bounds array.
         Ignored by MODBUS_FC22_MASK_WRITE_REGISTER, which carries its two
         masks instead.

BUSY   the request is outstanding.
DONE   one scan, when the device confirmed it.
COUNT  how many addresses were written.
ERROR  it did not.
STATUS why. MODBUS_OK when fine.
       MODBUS_QUEUED, MODBUS_OK, MODBUS_NOT_INITIALISED,
       MODBUS_INVALID_ARGUMENT, MODBUS_NOT_MAPPED, MODBUS_DUPLICATE,
       MODBUS_QUEUE_FULL, MODBUS_UNKNOWN_UNIT, MODBUS_SUPERSEDED,
       MODBUS_CANCELLED, MODBUS_TIMEOUT, MODBUS_REFUSED,
       MODBUS_ACKNOWLEDGED, MODBUS_BUSY, MODBUS_GATEWAY_PATH_UNAVAILABLE,
       MODBUS_GATEWAY_TARGET_FAILED, MODBUS_LINK_DOWN,
       MODBUS_CHECKSUM_ERROR, MODBUS_PROTOCOL_ERROR

---

  MODBUS_WRITE( NODE := node, UNIT := 2, ADDRESS := 40, VALUE := setpoint );

  MODBUS_WRITE( NODE := node, UNIT := 2, ADDRESS := 100, VALUE := aRecipe );

  MODBUS_WRITE( NODE := node, UNIT := 2, ADDRESS := 0, VALUE := myCoils );

MODBUS_FC_AUTO, the default, reads what you passed and sends the function code
that matches it:

  a single BOOL     FC 05  write single coil
  an array of BOOL  FC 15  write multiple coils
  a single number   FC 06  write single register
  several numbers   FC 16  write multiple registers

That is the choice a person would make, and it is the one most devices expect.
Name a function code yourself for the devices that disagree - an older meter
that implements FC 06 and not FC 16, a drive whose manual says to use FC 16
even for one register. The manual will name it the same way this pin does.

MODBUS_FC22_MASK_WRITE_REGISTER is the only atomic read-modify-write Modbus
has, and it is the one to reach for on a shared status word. Without it, two
clients setting different bits of one register corrupt each other: each reads,
modifies and writes back, and whichever writes second erases the first's bit.
The device keeps (current AND AND_MASK) OR (OR_MASK AND NOT AND_MASK). To set
bit 3 and leave the rest alone: AND_MASK := 16#FFF7, OR_MASK := 16#0008.

A WRITE THAT REPEATS SENDS ONLY THE VALUE YOU SETTLED ON. Raise REQ again
while the first write is still outstanding and the newer value replaces it
before it goes out; the first is concluded as MODBUS_SUPERSEDED, so nothing is
left waiting. An operator dragging a setpoint slider therefore puts one value
on the bus, not forty.

BROADCAST. UNIT 0 means every device on the segment performs the write and
none of them answers, so DONE means "it was transmitted", not "they did it".
Useful for a synchronised command, and worth knowing that it can never be
confirmed.

ONE REQUEST AT A TIME PER ADDRESS. Holding REQ high is safe: it writes once,
not once a scan. *)

FUNCTION_BLOCK MODBUS_WRITE
  VAR_IN_OUT
    NODE : MODBUS_NODE;
  END_VAR
  VAR_INPUT
    REQ : BOOL;
    UNIT : BYTE;
    FC : MODBUS_WRITE_FC;
    ADDRESS : UINT;
    LENGTH : UINT;
    ORDER : MODBUS_ORDER;
    AND_MASK : WORD;
    OR_MASK : WORD;
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

    BUSY = false;
    DONE = false;
    ERROR = false;

    const bool rose = (bool)REQ && !(bool)fbLastReq;
    fbLastReq = (bool)REQ;
    if (!rose) return;

    const uint8_t unit = (uint8_t)UNIT;
    const uint16_t first = (uint16_t)ADDRESS;
    const MODBUS_WRITE_FC code = (MODBUS_WRITE_FC)FC;

    // The mask write carries its two masks rather than a variable, so it is
    // settled before the generic pin is looked at.
    if (code == MODBUS_WRITE_FC::MODBUS_FC22_MASK_WRITE_REGISTER) {
        const ModbusResult masked = mb->maskHreg(unit, first, (uint16_t)AND_MASK,
                                                 (uint16_t)OR_MASK);
        if (!mb_accepted(masked) && masked != ModbusResult::Duplicate) {
            ERROR = true;
            STATUS = (MODBUS_RESULT)(int32_t)masked;
            return;
        }
        COUNT = 1;
        if (masked == ModbusResult::Ok) {
            DONE = true;
        } else {
            fbPending = true;
            BUSY = true;
        }
        STATUS = (MODBUS_RESULT)(int32_t)masked;
        return;
    }

    const int32_t held = VALUE.DICOUNT;
    const int32_t asked = (int32_t)(uint16_t)LENGTH;
    const int32_t count = (asked == 0) ? held : (asked <= held ? asked : 0);

    const uint8_t bits = mb_elementBits((uint32_t)VALUE.ELEMCLASS);

    if (count <= 0 || count > 0xFFFF || bits == 0 || VALUE.PVALUE == nullptr) {
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
        return;
    }

    // What was passed decides which list, because only two of the four can be
    // written and a BOOL separates them exactly: a bit goes in the coil list
    // and a number in the holding list. A named function code must then agree
    // with what it was handed, rather than reinterpreting it.
    const bool haveBits = (bits == 1);
    const bool single = (count == 1);

    bool wantBits = haveBits;
    bool wantSingle = single;

    switch (code) {
        case MODBUS_WRITE_FC::MODBUS_FC05_WRITE_SINGLE_COIL:
            wantBits = true;  wantSingle = true;  break;
        case MODBUS_WRITE_FC::MODBUS_FC15_WRITE_MULTIPLE_COILS:
            wantBits = true;  wantSingle = false; break;
        case MODBUS_WRITE_FC::MODBUS_FC06_WRITE_SINGLE_REGISTER:
            wantBits = false; wantSingle = true;  break;
        case MODBUS_WRITE_FC::MODBUS_FC16_WRITE_MULTIPLE_REGISTERS:
            wantBits = false; wantSingle = false; break;
        default: break;   // MODBUS_FC_AUTO takes what was passed
    }

    if (wantBits != haveBits || (wantSingle && !single)) {
        // A single-value function code cannot carry an array, and a bit list
        // cannot carry a number. Refused rather than sent as something else.
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
        return;
    }

    const uint16_t stride = (uint16_t)VALUE.DISTRIDE;
    const uint16_t many = (uint16_t)count;
    const ModbusOrder order = (ModbusOrder)(MODBUS_ORDER)ORDER;

    ModbusResult result = ModbusResult::InvalidArgument;

    if (haveBits) {
        result = wantSingle
            ? mb->client().writeCoil(unit, first, *(const bool*)VALUE.PVALUE)
            : mb->client().writeCoils(unit, first, (const bool*)VALUE.PVALUE, many,
                                      nullptr, stride);
    } else if (bits == 16) {
        result = wantSingle
            ? mb->client().writeRegister(unit, first, *(const uint16_t*)VALUE.PVALUE)
            : mb->client().writeRegisters(unit, first, (const uint16_t*)VALUE.PVALUE,
                                          many, nullptr, stride);
    } else {
        // Wider than a register. One request whatever the count, because the
        // values are packed here and sent together - which also means a set of
        // values that only mean anything together cannot half-arrive.
        result = mb->client().writeWideArray(
            unit, first, VALUE.PVALUE, mb_wideTypeOfClass((uint32_t)VALUE.ELEMCLASS),
            order, many, stride, nullptr);
    }

    if (!mb_accepted(result) && result != ModbusResult::Duplicate) {
        ERROR = true;
        STATUS = (MODBUS_RESULT)(int32_t)result;
        return;
    }

    COUNT = (uint16_t)count;

    if (result == ModbusResult::Ok) {
        DONE = true;
        STATUS = (MODBUS_RESULT)(int32_t)result;
        return;
    }

    fbPending = true;
    BUSY = true;
    STATUS = (MODBUS_RESULT)(int32_t)result;
}

END_FUNCTION_BLOCK