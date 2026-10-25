(* A table of field points: one block for every sensor and output on the bus.

NODE         which node. Must be wired.
SETTINGS     the points, one row each: ARRAY OF MODBUS_PT_CFG. Retain it -
             it is the site's configuration.
               unit, fc, address, dtype, order, bit, scale, offset, every,
               stale, timeout, enable  (the same as MODBUS_POINT's pins)
POINTS       what each row is doing: ARRAY OF MODBUS_PT_STS, the same length
             (extra rows on either side are ignored). Do NOT retain it.
               w        your logic: the value to write (write rows)
               v        the value in engineering units, held while not ok
               q        v <> 0, for a bit
               ok       good, or a little late. Interlock on this
               quality  UNKNOWN never answered, GOOD, UNCERTAIN late, BAD lost
               age, failures, result
RUN          FALSE stops asking. TRUE unless you say otherwise.

GOOD_COUNT   enabled rows that are ok.
LOST_COUNT   enabled rows that are not: never answered, lost, or settings
             that cannot work.
FIRST_LOST   the first such row (its index in SETTINGS), 0 when none.
ERROR        LOST_COUNT > 0.
STATUS       the first lost row's result. MODBUS_OK when all are fine.
STATUS_TEXT  that row in a few words, for a panel: 'pt 3 unit 5 lost',
             'pt 2 unit 9 no answer' (never answered: check the address),
             'pt 4 bad settings', 'tables differ', 'field bus down'.

---

  VAR_GLOBAL RETAIN
    FIELD_CFG : ARRAY[1..16] OF MODBUS_PT_CFG;
  END_VAR
  VAR_GLOBAL
    FIELD : ARRAY[1..16] OF MODBUS_PT_STS;
  END_VAR

  points( NODE := field, SETTINGS := FIELD_CFG, POINTS := FIELD );
  pondLevel := FIELD[3].v;  pondLevelOk := FIELD[3].ok;
  FIELD[7].w := BOOL_TO_REAL(irrigatorValveOpen);

EACH ROW BEHAVES EXACTLY AS A MODBUS_POINT, and each is re-read from SETTINGS
every scan, so a row changed on the HMI takes effect at once: a new address
starts at UNKNOWN until it answers, and nothing the old address said is kept.
enable FALSE is a point not fitted on this site - never asked and never ok.

A LOST DEVICE IS NEVER A VALID 0: ok is FALSE until the first answer and once a
device stops answering for `stale`; v keeps the last good value. Feed ok into
the IO map's quality, so a lost radio takes its function's fail-safe.

RADIO DEVICES (the LoRa mesh on the field bus) need `timeout` - the worst round
trip, a few seconds - and an `every` of seconds to minutes. The longest
`timeout` among a unit's rows is that unit's; rows without one are measured.
One request is on a serial bus at a time, so a radio answer holds the wired
devices meanwhile: keep fast protection reads off a bus that carries radio.

The table is fixed when the program starts. Its length is the number of
points; an unused row is enable FALSE. *)

FUNCTION_BLOCK MODBUS_POINTS
  VAR_IN_OUT
    NODE : MODBUS_NODE;
    SETTINGS : ARRAY [*] OF MODBUS_PT_CFG;
    POINTS : ARRAY [*] OF MODBUS_PT_STS;
  END_VAR
  VAR_INPUT
    RUN : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    GOOD_COUNT : INT;
    LOST_COUNT : INT;
    FIRST_LOST : INT;
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
    STATUS_TEXT : STRING(30);
  END_VAR
  VAR
    fbFirst : __XWORD;
    fbRows : INT;
  END_VAR
#include <ModBeeModbus.h>
#include <cstdio>

// Defined by MODBUS_NODE and MODBUS_POINT, which sort before this file.
int32_t mb_millisOf(const strucpp::IEC_TIME& t);
strucpp::IEC_TIME mb_timeOf(int32_t milliseconds);
ModbusPointConfig mb_pointConfig(uint8_t unit, int32_t fc, uint16_t address, int32_t type,
                                 int32_t order, uint8_t bit, float scale, float offset,
                                 int32_t everyMs, int32_t staleMs, int32_t timeoutMs,
                                 bool enabled);
bool mb_pointApply(ModbusAPI* mb, ModbusPoint* point, const ModbusPointConfig& wanted);

strucpp::XWORD_t mb_currentTask();
bool mb_inTask(strucpp::XWORD_t owner);

void setup()
{
    GOOD_COUNT = 0;
    LOST_COUNT = 0;
    FIRST_LOST = 0;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
    STATUS_TEXT = "";
    fbFirst = (strucpp::XWORD_t)0;
    fbRows = 0;
}

void loop()
{
    if (!mb_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per node: see MODBUS_ARDUINO
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_WRONG_TASK;
        return;
    }
    ModbusAPI* mb = (ModbusAPI*)(uintptr_t)(strucpp::XWORD_t)NODE.FBAPI;
    const int64_t lo = SETTINGS->lower_bound();
    const int64_t hi = SETTINGS->upper_bound();
    const int64_t stsLo = POINTS->lower_bound();
    const int64_t stsHi = POINTS->upper_bound();
    int64_t rows = hi - lo + 1;
    if (stsHi - stsLo + 1 < rows) rows = stsHi - stsLo + 1;
    if (rows < 0) rows = 0;

    if (!mb || !(bool)NODE.READY) {
        for (int64_t k = 0; k < rows; k++) (*POINTS)[stsLo + k].OK = false;
        GOOD_COUNT = 0;
        LOST_COUNT = (int16_t)rows;
        FIRST_LOST = rows > 0 ? (int16_t)lo : 0;
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_LINK_DOWN;
        STATUS_TEXT = "field bus down";
        return;
    }

    // The points are made once, on the first scan the node is up, one per row.
    // Held as index+1, so zero means "none yet".
    size_t first = (size_t)(strucpp::XWORD_t)fbFirst;
    if (first == 0 && rows > 0) {
        const size_t made = mb->points().add((size_t)rows);
        if (made == (size_t)-1) {
            ERROR = true;
            STATUS = MODBUS_RESULT::MODBUS_NOT_INITIALISED;
            STATUS_TEXT = "out of memory";
            return;
        }
        first = made + 1;
        fbFirst = (strucpp::XWORD_t)first;
        fbRows = (int16_t)rows;
    }
    if ((int64_t)(int16_t)fbRows < rows) rows = (int16_t)fbRows;

    const mb_time_t now = mb_millis();
    int16_t good = 0, lost = 0;
    int64_t firstLost = -1;
    ModbusResult firstResult = ModbusResult::Ok;
    bool firstInvalid = false;
    bool firstNever = false;
    uint8_t firstUnit = 0;

    for (int64_t k = 0; k < rows; k++) {
        auto& cfg = (*SETTINGS)[lo + k];
        auto& sts = (*POINTS)[stsLo + k];
        ModbusPoint* point = mb->points().at(first - 1 + (size_t)k);
        if (!point) continue;

        const bool enabled = (bool)cfg.ENABLE && (bool)RUN;
        const ModbusPointConfig wanted = mb_pointConfig(
            (uint8_t)cfg.UNIT, (int32_t)(strucpp::MODBUS_PT_FC)cfg.FC, (uint16_t)cfg.ADDRESS,
            (int32_t)(strucpp::MODBUS_PT_TYPE)cfg.DTYPE,
            (int32_t)(strucpp::MODBUS_ORDER)cfg.ORDER, (uint8_t)cfg.BIT, (float)cfg.SCALE, (float)cfg.OFFSET,
            mb_millisOf(cfg.EVERY), mb_millisOf(cfg.STALE), mb_millisOf(cfg.TIMEOUT),
            enabled);
        const bool valid = mb_pointApply(mb, point, wanted);
        point->setWriteValue((double)(float)sts.W);

        const ModbusQuality quality = enabled ? point->quality(now) : ModbusQuality::Unknown;
        const bool ok = valid && enabled && point->ok(now);
        sts.QUALITY = (strucpp::MODBUS_QUALITY)(int32_t)quality;
        sts.OK = ok;
        sts.V = (float)point->value();
        sts.Q = point->asBit();
        const mb_time_t age = point->age(now);
        sts.AGE = mb_timeOf(age == ModbusPoller::NEVER ? 0 : (int32_t)age);
        sts.FAILURES = point->failures();
        const ModbusResult last = valid ? point->lastResult() : ModbusResult::InvalidArgument;
        sts.RESULT = (strucpp::MODBUS_RESULT)(int32_t)last;

        if (!(bool)cfg.ENABLE) continue;   // not fitted: neither good nor lost
        if (ok) {
            good++;
        } else {
            lost++;
            if (firstLost < 0) {
                firstLost = lo + k;
                firstResult = last;
                firstInvalid = !valid;
                firstNever = !point->everGood();
                firstUnit = (uint8_t)cfg.UNIT;
            }
        }
    }

    GOOD_COUNT = good;
    LOST_COUNT = lost;
    FIRST_LOST = firstLost >= 0 ? (int16_t)firstLost : 0;
    ERROR = lost > 0;
    STATUS = (MODBUS_RESULT)(int32_t)(firstLost >= 0 ? firstResult : ModbusResult::Ok);

    // One short line for a panel. Codes are on STATUS and in each row.
    char text[31];
    if (stsHi - stsLo != hi - lo) {
        std::snprintf(text, sizeof text, "tables differ");
    } else if (firstLost < 0) {
        text[0] = '\0';
    } else if (firstInvalid) {
        std::snprintf(text, sizeof text, "pt %d bad settings", (int)firstLost);
    } else if (!(bool)RUN) {
        std::snprintf(text, sizeof text, "stopped");
    } else if (firstNever) {
        std::snprintf(text, sizeof text, "pt %d unit %u no answer", (int)firstLost,
                      (unsigned)firstUnit);
    } else {
        std::snprintf(text, sizeof text, "pt %d unit %u lost", (int)firstLost,
                      (unsigned)firstUnit);
    }
    STATUS_TEXT = text;
}

END_FUNCTION_BLOCK