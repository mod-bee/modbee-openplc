(* Puts your variables at Modbus addresses, so other devices can read them.

NODE        which node. Must be wired.
TABLE       which of Modbus's four lists.
            MODBUS_COILS, MODBUS_DISCRETE_INPUTS, MODBUS_HOLDING_REGISTERS,
            MODBUS_INPUT_REGISTERS
ADDRESS     the first address.
ON_LOSS     what happens to a writable address when the client driving it goes
            quiet. Needs FAILSAFE on a MODBUS_CONFIG block to mean anything.
            MODBUS_HOLD_LAST_VALUE, MODBUS_RESET_TO_VALUE
SAFE_VALUE  the value MODBUS_RESET_TO_VALUE goes to.
VALUE       the variable to bind. A single value or a fixed-bounds array.

BOUND         the addresses are live. It stays FALSE while the node is not
              READY, because a binding made into a link that never opened goes
              into a map nothing serves - and a green pin over a dead device is
              worse than a red one.
COUNT         how many addresses were taken.
WRITTEN       one scan, when a client wrote any of them.
SAFE_APPLIED  one scan, when the safe state was applied.
ERROR         why not.
STATUS        why. MODBUS_OK when fine.
              MODBUS_QUEUED, MODBUS_OK, MODBUS_NOT_INITIALISED,
              MODBUS_INVALID_ARGUMENT, MODBUS_NOT_MAPPED, MODBUS_DUPLICATE,
              MODBUS_QUEUE_FULL, MODBUS_UNKNOWN_UNIT, MODBUS_SUPERSEDED,
              MODBUS_CANCELLED, MODBUS_TIMEOUT, MODBUS_REFUSED,
              MODBUS_ACKNOWLEDGED, MODBUS_BUSY,
              MODBUS_GATEWAY_PATH_UNAVAILABLE, MODBUS_GATEWAY_TARGET_FAILED,
              MODBUS_LINK_DOWN, MODBUS_CHECKSUM_ERROR, MODBUS_PROTOCOL_ERROR

---

This is the block that makes your PLC a Modbus device. Set ROLE on the node to
MODBUS_ROLE_SERVER or MODBUS_ROLE_BOTH, then say what lives where:

  MODBUS_MAP( NODE := node, TABLE := MODBUS_HOLDING_REGISTERS,
              ADDRESS := 40, VALUE := mySpeed );

  MODBUS_MAP( NODE := node, TABLE := MODBUS_INPUT_REGISTERS,
              ADDRESS := 100, VALUE := aTrend );

  MODBUS_MAP( NODE := node, TABLE := MODBUS_COILS,
              ADDRESS := 0, VALUE := myCoils );

THERE IS NO REQUEST PIN. Once bound, the variable IS the register: a client
reading gets what it holds this instant, and a client writing changes it.
Nothing is copied on either side and nothing is scheduled.

`aTrend : ARRAY[0..99] OF WORD` at ADDRESS 100 becomes addresses 100..199. The
array's lower bound maps to ADDRESS, whatever that bound is.

Call it more than once in a scan and it maps that many ranges, which is how
two non-consecutive ranges are expressed. The outputs describe the last call.

An array must be declared with FIXED BOUNDS. A generic pin takes a variable,
and ARRAY [*] is not one - it is a view, and views ride in-out pins only.

TABLE says which of Modbus's four lists your variables go in. They are
separate numbered lists, so address 40 in one is a different thing from
address 40 in another:

  MODBUS_COILS             on/off,  a client may write it   FC 1, 5, 15
  MODBUS_DISCRETE_INPUTS   on/off,  read only               FC 2
  MODBUS_HOLDING_REGISTERS 16 bits, a client may write it   FC 3, 6, 16, 22
  MODBUS_INPUT_REGISTERS   16 bits, read only               FC 4

Put anything a client must not change in a read-only list. It is not a
permission setting to be got wrong later; the list itself has no write
function code, so a client that tries is answered with an exception.

A BOOL goes in a bit list and a number in a register list. Crossing them is
refused, because a coil holds one bit and a register holds sixteen, and
binding one to the other would leave half a register pointing at whatever sits
beside your variable in memory.

**A mapped number is INT, UINT or WORD and nothing else.** REAL, DINT and the
64-bit types are refused with MODBUS_INVALID_ARGUMENT, and this is the one
place the library asks more of you than MODBUS_READ does. Nothing is copied
here: the register a client reads IS your variable, in place, this instant.
A REAL is not a pair of registers - it is four bytes in a layout ORDER would
have to rearrange, and rearranging means a copy, and a copy means a client can
read half of an old value and half of a new one. So the block refuses rather
than pretend.

Publish a scaled integer, as a real device does: milliamps x 100 in an INT
gives 0.01 mA of resolution over the whole range, and the client divides. Or
put the REAL behind MODBUS_READ instead, which does convert, because a read
completes as one operation and has no torn-value problem to cause.

ON_LOSS is what a writable address does when whoever was driving it stops. It
needs FAILSAFE set on a MODBUS_CONFIG block - without a silence to measure,
there is no
loss to act on. MODBUS_RESET_TO_VALUE applies to a single value only: a range
has no one safe value, and guessing one would be worse than holding.

WRITTEN rises for one scan when a client writes ANY address in this range,
whether or not the value changed. It is counted per binding, so two blocks
mapping two ranges do not take each other's edges. *)

FUNCTION_BLOCK MODBUS_MAP
  VAR_IN_OUT
    NODE : MODBUS_NODE;
  END_VAR
  VAR_INPUT
    TABLE : MODBUS_TABLE;
    ADDRESS : UINT;
    ON_LOSS : MODBUS_FAILSAFE;
    SAFE_VALUE : DINT;
    VALUE : ANY;
  END_VAR
  VAR_OUTPUT
    BOUND : BOOL;
    COUNT : UINT;
    WRITTEN : BOOL;
    SAFE_APPLIED : BOOL;
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
  END_VAR
  VAR
    fbBound : BOOL;
    fbStorage : __XWORD;
    fbSeenWrites : UDINT;
    fbSeenFailsafe : UINT;
  END_VAR
#include <ModBeeModbus.h>

// Defined by the MODBUS_NODE block, which every project has.
uint8_t mb_elementBits(uint32_t typeClass);

// The node's server half, also defined by MODBUS_NODE. A map is what a server
// serves, so this block hands it to its node; a project that only asks has no
// map, and so carries none of the server code.
MODBUS_RESULT mbServe(ModbusAPI* mb, uint8_t kind, bool onWifi, uint16_t tcpPort,
                      uint8_t maxClients, mb_time_t idleMs, uint8_t unitId,
                      bool& opened, const char*& why);

strucpp::XWORD_t mb_currentTask();
bool mb_inTask(strucpp::XWORD_t owner);

void setup()
{
    BOUND = false;
    COUNT = 0;
    WRITTEN = false;
    SAFE_APPLIED = false;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
    fbBound = false;
    fbStorage = (strucpp::XWORD_t)0;
    fbSeenWrites = 0;
    fbSeenFailsafe = 0;
}

void loop()
{
    if (!mb_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per node: see MODBUS_ARDUINO
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_WRONG_TASK;
        return;
    }
    // Before the READY check: the node opens a scan after its neighbours first
    // run, and it needs this by then.
    NODE.FBSERVE = (strucpp::XWORD_t)(uintptr_t)&mbServe;

    ModbusAPI* mb = (ModbusAPI*)(uintptr_t)(strucpp::XWORD_t)NODE.FBAPI;
    if (!mb || !(bool)NODE.READY) {
        BOUND = false;
        WRITTEN = false;
        SAFE_APPLIED = false;
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_LINK_DOWN;
        return;
    }

    const ModbusTable table = (ModbusTable)(MODBUS_TABLE)TABLE;
    const uint16_t first = (uint16_t)ADDRESS;
    const int32_t count = VALUE.DICOUNT;

    if (!(bool)fbBound) {
        const uint8_t bits = mb_elementBits((uint32_t)VALUE.ELEMCLASS);

        // A zeroed descriptor reads as TYPE_BOOL, because that class is zero -
        // so an unwired pin has to be caught by its fbStorage, not its type.
        if (count <= 0 || count > 0xFFFF || VALUE.PVALUE == nullptr ||
            (bits != 1 && bits != 16) || (mb_tableIsBits(table) != (bits == 1))) {
            BOUND = false;
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            return;
        }

        // An element carries its forced state beside its value, so the
        // elements are not adjacent. The map is given the gap and reads and
        // writes them in place; nothing is copied.
        const uint16_t stride = (uint16_t)VALUE.DISTRIDE;
        const bool ok = (bits == 1)
            ? mb->map().bindBlock(table, first, (bool*)VALUE.PVALUE,
                                  (uint16_t)count, stride)
            : mb->map().bindBlock(table, first, (uint16_t*)VALUE.PVALUE,
                                  (uint16_t)count, stride);

        if (!ok) {
            BOUND = false;
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
            return;
        }

        // The safe state is per address, and only a writable list has one to
        // set. A range has no single safe value, so it is left to the
        // single-value case rather than guessed at.
        const bool resetOnLoss =
            ((MODBUS_FAILSAFE)ON_LOSS == MODBUS_FAILSAFE::MODBUS_RESET_TO_VALUE);
        if (resetOnLoss && count == 1 && mb_tableIsWritable(table)) {
            if (bits == 1) {
                mb->failsafeCoil(first, (int32_t)SAFE_VALUE != 0);
            } else {
                mb->failsafeHreg(first, (uint16_t)(int32_t)SAFE_VALUE);
            }
        }

        fbStorage = (strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE;
        fbSeenWrites = mb->map().bindingWrites(table, first);
        fbSeenFailsafe = mb->map().failsafeCount(table, first);
        fbBound = true;
    }

    BOUND = true;
    COUNT = (uint16_t)count;

    // The descriptor is rebuilt at every call, and a pin that moved would
    // leave the protocol reading and writing where nothing looks.
    if ((strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE != (strucpp::XWORD_t)fbStorage) {
        fbStorage = (strucpp::XWORD_t)(uintptr_t)VALUE.PVALUE;
        WRITTEN = false;
        SAFE_APPLIED = false;
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_INVALID_ARGUMENT;
        return;
    }

    // The node counts a client's writes and every drive to a safe state. This
    // keeps what it last saw rather than resetting anything, so two blocks on
    // one node do not take each other's edges.
    const uint32_t writes = mb->map().bindingWrites(table, first);
    const uint16_t safed = mb->map().failsafeCount(table, first);
    WRITTEN = (writes != (uint32_t)fbSeenWrites);
    SAFE_APPLIED = (safed != (uint16_t)fbSeenFailsafe);
    fbSeenWrites = writes;
    fbSeenFailsafe = safed;

    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
}

END_FUNCTION_BLOCK