(* A small table of daily totals, kept by the project and sent on every birth
as historical values, so SCADA fills in the days the link was down.

NODE    which node. Must be wired.
TABLE   the days: ARRAY OF SPARKPLUG_DAY (DAY : DATE, TOTAL : REAL). Retain it.
        The FIRST row is today, saved every SAVE_EVERY; the rows after it
        are the days closed so far, newest first. 31 rows keep a month.
NAME    the metric, e.g. 'pumpedDay'. Its live value is the last closed day.
VALUE   today's running total, from your totaliser.
CLOCK   local date and time - the same clock your totaliser rolls its day on.
SAVE_EVERY  how often today's running total is written into TABLE (T#1h).
        TABLE is retained, and a retained store saves the whole of retained
        memory whenever any of it changes - every scan would be a save every
        flush period (flash wear on a board). A day that closes while the PLC
        runs is closed with its exact total all the same; only a power cut
        loses up to SAVE_EVERY of today. T#0s writes every scan.

DAYS    closed days held.
SENT    day values sent since the program started.
ERROR   the metric could not be declared, or TABLE has fewer than two rows.
STATUS  why. MQTT_OK when fine.

---

  VAR_GLOBAL RETAIN
    PUMPED_DAYS : ARRAY[0..31] OF SPARKPLUG_DAY;
  END_VAR

  days(NODE := sp, TABLE := PUMPED_DAYS, NAME := 'pumpedDay',
       VALUE := pumped.today, CLOCK := localNow);

WHEN THE DATE ON CLOCK CHANGES the day just ended is closed: its total - the
value VALUE had on the scan before - moves into the table as the newest
closed day, and the table shifts down a row (the oldest falls off). A day
closed across a power cut is closed when the PLC comes back, from the
retained table (today's total as last saved), so nothing is counted twice. Nothing happens while the
clock is not set (before 2020).

ON EVERY BIRTH every closed day is published as a historical value of NAME,
time-stamped at 00:00 of its date (the date as CLOCK has it, written as UTC -
read the date, not the hour). A host files them in its history and does not
overwrite the live value, which is the last closed day. Sending the same day
twice is harmless: it lands on the same timestamp. A day closed while the
node is born goes at once the same way.

Use it beside SPARKPLUG_HISTORY: the events say what happened and when, the
day totals and counters say how much. *)

FUNCTION_BLOCK SPARKPLUG_DAY_TOTALS
  VAR_IN_OUT
    NODE : SPARKPLUG_NODE;
    TABLE : ARRAY [*] OF SPARKPLUG_DAY;
  END_VAR
  VAR_INPUT
    NAME : STRING(32);
    VALUE : REAL;
    CLOCK : DT;
    SAVE_EVERY : TIME := T#1h;
  END_VAR
  VAR_OUTPUT
    DAYS : INT;
    SENT : UDINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR
    fbIndex : DINT := -1;
    fbDeclared : BOOL;
    fbBirths : UDINT;
    fbOwed : BOOL;
    fbLive : REAL;              (* VALUE on the last scan *)
    fbLiveDay : LINT := -1;     (* the day of that scan (-1: none yet) *)
    fbSavedNs : LINT := -1;     (* CLOCK when today's row was last written *)
  END_VAR
#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugNode.h>

MqttSparkplugNode* mq_spNodeOf(strucpp::XWORD_t handle);
int32_t mq_millisOf(const strucpp::IEC_TIME& t);

// 2020-01-01 in days since 1970: a clock before it has not been set.
static const int64_t MQ_SP_DAY_PLAUSIBLE = 18262;
static const int64_t MQ_SP_NS_PER_DAY = 86400000000000LL;

void setup()
{
    DAYS = 0;
    SENT = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbIndex = -1;
    fbDeclared = false;
    fbBirths = 0;
    fbOwed = false;
    fbLive = 0.0f;
    fbLiveDay = -1;
    fbSavedNs = -1;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    const int64_t lo = TABLE->lower_bound();
    const int64_t hi = TABLE->upper_bound();
    if (hi - lo < 1) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    // --- Today, and the close of a day ---
    const int64_t clockNs = (int64_t)CLOCK.get();
    const int64_t today = clockNs >= 0 ? clockNs / MQ_SP_NS_PER_DAY : -1;
    bool closed = false;
    if (today >= MQ_SP_DAY_PLAUSIBLE) {
        auto& open = (*TABLE)[lo];
        const int64_t openDay = (int64_t)open.DAY.get();
        const int64_t saveNs = (int64_t)mq_millisOf(SAVE_EVERY) * 1000000LL;
        if (openDay >= MQ_SP_DAY_PLAUSIBLE && openDay != today) {
            // The day in the first row has ended: it becomes the newest closed
            // day, with the total it had on the last scan of that day - or, if
            // the PLC was off when it ended, the total last saved.
            const float total = (int64_t)fbLiveDay == openDay ? (float)fbLive : (float)open.TOTAL;
            for (int64_t i = hi; i > lo + 1; i--) {
                (*TABLE)[i].DAY = (*TABLE)[i - 1].DAY.get();
                (*TABLE)[i].TOTAL = (float)(*TABLE)[i - 1].TOTAL;
            }
            (*TABLE)[lo + 1].DAY = (strucpp::DATE_t)openDay;
            (*TABLE)[lo + 1].TOTAL = total;
            closed = true;
        }
        if (openDay != today) {
            open.DAY = (strucpp::DATE_t)today;
            open.TOTAL = (float)VALUE;
            fbSavedNs = clockNs;
        } else if ((int64_t)fbSavedNs < 0 || clockNs < (int64_t)fbSavedNs) {
            fbSavedNs = clockNs;                  // the first scan, or the clock set back: start the period
        } else if (saveNs <= 0 || clockNs - (int64_t)fbSavedNs >= saveNs) {
            open.TOTAL = (float)VALUE;
            fbSavedNs = clockNs;
        }
        fbLive = (float)VALUE;
        fbLiveDay = today;
    }

    int16_t held = 0;
    for (int64_t i = lo + 1; i <= hi; i++) {
        if ((int64_t)(*TABLE)[i].DAY.get() >= MQ_SP_DAY_PLAUSIBLE) held++;
    }
    DAYS = held;

    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)NODE.FBAPI);
    if (node == nullptr) return;

    // --- Declare, once, before the node births ---
    if (!(bool)fbDeclared) {
        fbDeclared = true;
        if (NAME.length() == 0 ||
            node->declare(NAME.c_str(), MqttSparkplugDataType::Float) == 0) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            return;
        }
        fbIndex = node->indexOf(nullptr, NAME.c_str());
    }
    if ((int32_t)fbIndex < 0) return;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;

    // The live value: the last closed day, carried in the birth.
    const auto& last = (*TABLE)[lo + 1];
    if ((int64_t)last.DAY.get() >= MQ_SP_DAY_PLAUSIBLE) {
        node->setAt((size_t)(int32_t)fbIndex, mq_spFloat((float)last.TOTAL));
    }

    // --- Every birth, and every close, sends the closed days as history ---
    if (!node->isBorn()) return;
    if (node->birthCount() != (uint32_t)fbBirths) {
        fbBirths = node->birthCount();
        fbOwed = true;
    }
    if (closed) fbOwed = true;
    if (!(bool)fbOwed) return;

    MqttSparkplugRecord records[8];
    size_t n = 0;
    uint32_t sent = 0;
    bool ok = true;
    for (int64_t i = hi; i > lo && ok; i--) {   // oldest first
        const auto& row = (*TABLE)[i];
        const int64_t day = (int64_t)row.DAY.get();
        if (day < MQ_SP_DAY_PLAUSIBLE) continue;
        records[n].index = (size_t)(int32_t)fbIndex;
        records[n].value = mq_spFloat((float)row.TOTAL);
        records[n].timestamp = (uint64_t)day * 86400000ULL;
        n++;
        if (n == 8 || i == lo + 1) {
            ok = node->publishRecords(records, n, true);
            if (ok) sent += (uint32_t)n;
            n = 0;
        }
    }
    if (ok && n > 0) {
        ok = node->publishRecords(records, n, true);
        if (ok) sent += (uint32_t)n;
    }
    SENT = (uint32_t)SENT + sent;
    if (ok) fbOwed = false;   // otherwise the next scan tries again
}

END_FUNCTION_BLOCK