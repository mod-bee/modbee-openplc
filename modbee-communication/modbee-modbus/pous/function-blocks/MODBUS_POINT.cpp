(* One value on a field device, defined entirely by settings.

NODE        which node. Must be wired.
UNIT        the device's address, 1..247.
FC          how it is reached. Named the way a device manual names it.
              MODBUS_PT_FC01_READ_COILS, MODBUS_PT_FC02_READ_DISCRETE_INPUTS,
              MODBUS_PT_FC03_READ_HOLDING_REGISTERS,
              MODBUS_PT_FC04_READ_INPUT_REGISTERS (reads)
              MODBUS_PT_FC05_WRITE_COIL, MODBUS_PT_FC06_WRITE_REGISTER,
              MODBUS_PT_FC16_WRITE_REGISTERS (writes)
ADDRESS     the register or coil, numbered from 0 as the manual's table does.
DTYPE       what it holds.
              MODBUS_PT_BIT (a coil or input), MODBUS_PT_INT16,
              MODBUS_PT_UINT16, MODBUS_PT_INT32, MODBUS_PT_UINT32,
              MODBUS_PT_FLOAT32, MODBUS_PT_REG_BIT (one bit of a register)
ORDER       the word order of a 32-bit value, from the manual.
              MODBUS_ORDER_ABCD, MODBUS_ORDER_CDAB, MODBUS_ORDER_BADC,
              MODBUS_ORDER_DCBA
BIT         MODBUS_PT_REG_BIT only: which bit, 0..15.
SCALE       VALUE = raw x SCALE + OFFSET. 1.0 unless you say otherwise.
OFFSET
EVERY       how often to read it - or to send a write again. T#1s if left at
            T#0s.
STALE       no good answer for this long and the value is lost (BAD). T#0s
            means 3 x EVERY.
TIMEOUT     how long this device may take to answer. T#0s measures it. Over
            the LoRa mesh give it the worst round trip, a few seconds.
WRITE_VALUE write points: the value to send, in engineering units.
ENABLE      FALSE = not fitted here: never asked, never OK.

VALUE       the value in engineering units. The last good one is held while
            it is not OK - never a made-up 0.
Q           VALUE <> 0, for a bit.
OK          VALUE is good, or a little late. FALSE before the first answer and
            once the device is lost. Interlock on this.
QUALITY     MODBUS_QUALITY_UNKNOWN never answered (check the address),
            MODBUS_QUALITY_GOOD, MODBUS_QUALITY_UNCERTAIN late,
            MODBUS_QUALITY_BAD lost.
AGE         since the last good answer.
FAILURES    failed attempts in a row.
ERROR       the last attempt failed, or the settings cannot work.
STATUS      why. MODBUS_OK when fine; MODBUS_INVALID_ARGUMENT for settings
            that cannot work (a FLOAT32 on FC06, a bit above 15, a REG_BIT
            write).

---

  flow( NODE := field, UNIT := CFG.flowUnit, FC := CFG.flowFc,
        ADDRESS := CFG.flowReg, DTYPE := CFG.flowType, ORDER := CFG.flowOrder,
        SCALE := CFG.flowScale, EVERY := T#2s );
  IF flow.OK THEN ... END_IF;

EVERY PIN IS A SETTING, READ EVERY SCAN. Change the address, unit, type or
order while running and the point follows: the next read goes to the new
place, and the old value, age and failures are dropped - QUALITY goes back to
UNKNOWN until the new address answers. So a sensor swapped for another model
is a settings change, not a PLC change.

A LOST DEVICE IS NEVER A VALID 0. Before the first answer OK is FALSE; when a
device stops answering, QUALITY goes UNCERTAIN, then BAD after STALE, and
VALUE keeps the last good reading. Wire OK, not VALUE, into anything that
protects the plant.

WRITES go when WRITE_VALUE changes, and again every EVERY, so a remote relay
with a watchdog is kept alive and one that lost power is told again.

A dead device is asked less often (up to eight intervals, at most a minute
apart) so it does not take the bus from the live ones.

For many points use MODBUS_POINTS: one block, a settings table and a status
table, same behaviour per row. *)

FUNCTION_BLOCK MODBUS_POINT
  VAR_IN_OUT
    NODE : MODBUS_NODE;
  END_VAR
  VAR_INPUT
    UNIT : BYTE;
    FC : MODBUS_PT_FC;
    ADDRESS : UINT;
    DTYPE : MODBUS_PT_TYPE;
    ORDER : MODBUS_ORDER;
    BIT : USINT;
    SCALE : REAL := 1.0;
    OFFSET : REAL;
    EVERY : TIME;
    STALE : TIME;
    TIMEOUT : TIME;
    WRITE_VALUE : REAL;
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    VALUE : REAL;
    Q : BOOL;
    OK : BOOL;
    QUALITY : MODBUS_QUALITY;
    AGE : TIME;
    FAILURES : UINT;
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
  END_VAR
  VAR
    fbIndex : __XWORD;
  END_VAR
#include <ModBeeModbus.h>

// Defined by the MODBUS_NODE block, which every project has.
int32_t mb_millisOf(const strucpp::IEC_TIME& t);
strucpp::IEC_TIME mb_timeOf(int32_t milliseconds);

// Shared with MODBUS_POINTS, which sorts after this file in the one
// translation unit every C++ POU lands in.
ModbusPointConfig mb_pointConfig(uint8_t unit, int32_t fc, uint16_t address, int32_t type,
                                 int32_t order, uint8_t bit, float scale, float offset,
                                 int32_t everyMs, int32_t staleMs, int32_t timeoutMs,
                                 bool enabled)
{
    ModbusPointConfig c;
    c.unit = unit;
    c.fc = (ModbusPointFc)(uint8_t)fc;
    c.address = address;
    c.type = (ModbusPointType)(uint8_t)type;
    c.order = (ModbusOrder)(uint8_t)order;
    c.bit = bit;
    c.scale = scale;
    c.offset = offset;
    c.everyMs = everyMs > 0 ? (mb_time_t)everyMs : 1000u;
    c.staleMs = staleMs > 0 ? (mb_time_t)staleMs : 0u;
    c.timeoutMs = timeoutMs > 0 ? (mb_time_t)timeoutMs : 0u;
    c.enabled = enabled;
    return c;
}

// Configures a point and reports whether its unit timeout changed, so the set
// can re-apply the per-unit timeouts.
bool mb_pointApply(ModbusAPI* mb, ModbusPoint* point, const ModbusPointConfig& wanted)
{
    const bool timeoutMoved = point->config().timeoutMs != wanted.timeoutMs ||
                              (wanted.timeoutMs != 0 && point->config().unit != wanted.unit);
    point->configure(wanted);
    if (timeoutMoved) mb->points().timeoutsChanged();
    return point->lastResult() != ModbusResult::InvalidArgument;
}

strucpp::XWORD_t mb_currentTask();
bool mb_inTask(strucpp::XWORD_t owner);

void setup()
{
    VALUE = 0.0f;
    Q = false;
    OK = false;
    QUALITY = MODBUS_QUALITY::MODBUS_QUALITY_UNKNOWN;
    AGE = mb_timeOf(0);
    FAILURES = 0;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
    fbIndex = (strucpp::XWORD_t)0;
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
        OK = false;
        QUALITY = MODBUS_QUALITY::MODBUS_QUALITY_UNKNOWN;
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_LINK_DOWN;
        return;
    }

    // Held as index+1, so zero means "none yet".
    size_t index = (size_t)(strucpp::XWORD_t)fbIndex;
    if (index == 0) {
        const size_t made = mb->points().add(1);
        if (made == (size_t)-1) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_NOT_INITIALISED;
            return;
        }
        index = made + 1;
        fbIndex = (strucpp::XWORD_t)index;
    }
    ModbusPoint* point = mb->points().at(index - 1);
    if (!point) return;

    const ModbusPointConfig wanted = mb_pointConfig(
        (uint8_t)UNIT, (int32_t)(MODBUS_PT_FC)FC, (uint16_t)ADDRESS, (int32_t)(MODBUS_PT_TYPE)DTYPE,
        (int32_t)(MODBUS_ORDER)ORDER,
        (uint8_t)BIT, (float)SCALE, (float)OFFSET, mb_millisOf(EVERY), mb_millisOf(STALE),
        mb_millisOf(TIMEOUT), (bool)ENABLE);
    const bool valid = mb_pointApply(mb, point, wanted);
    point->setWriteValue((double)(float)WRITE_VALUE);

    const mb_time_t now = mb_millis();
    const ModbusQuality quality = (bool)ENABLE ? point->quality(now) : ModbusQuality::Unknown;
    QUALITY = (MODBUS_QUALITY)(int32_t)quality;
    OK = valid && (bool)ENABLE && point->ok(now);
    VALUE = (float)point->value();
    Q = point->asBit();
    const mb_time_t age = point->age(now);
    AGE = mb_timeOf(age == ModbusPoller::NEVER ? 0 : (int32_t)age);
    FAILURES = point->failures();

    const ModbusResult last = valid ? point->lastResult() : ModbusResult::InvalidArgument;
    STATUS = (MODBUS_RESULT)(int32_t)last;
    ERROR = !valid || ((bool)ENABLE && !mb_accepted(last));
}

END_FUNCTION_BLOCK