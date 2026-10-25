(* READ ONE METRIC from a node a SPARKPLUG_HOST is watching.

The host keeps the current picture of the plant - every metric every edge node
declared, and what each one is reading now. This block takes one value out of
it and writes it into an IEC variable of the engineer's own type.

THE NAME IS THE ADDRESS, not a topic and not an alias. That is the whole point
of the protocol: the edge node declared "level" in its birth certificate and
this block asks for "level". A conformant node sends data by alias only and the
host resolves it back, so nothing here has to know what an alias is.

THE DECLARED TYPE IS CHECKED, not coerced. If the birth said "level" is a REAL
and VALUE is wired to a DINT, the read is REFUSED and TYPE_OK goes false rather
than silently truncating a reading a control decision is about to be made on.

NAME         the metric name, exactly as the edge node declared it.
VALUE        where to put it. Any IEC type; it must match what was declared.
NODE_ID      which edge node. Empty means the first node the host heard from,
             which is convenient with one node and wrong with two.
GROUP        which group. Empty means the host's watched group.
DEVICE       for a metric belonging to a device rather than the node itself.
ENABLE       false stops reading and holds VALUE at its last value.

VALID        the value was read and written into VALUE this scan.
TYPE_OK      false means VALUE's type does not match what the birth declared.
FRESH        the reading changed since the last scan.
AGE          milliseconds since the node's own timestamp on it. Not since we
             received it - on a slow link those differ by more than a control
             decision should ignore.
ERROR        something is wrong; STATUS says what.

NOT VALID IS NOT AN ERROR by itself. A node that has not birthed yet, a metric
that has not been published yet and a node that has died all read as VALID
false, and all three mean the same thing to a rung: do not act on this. *)

FUNCTION_BLOCK SPARKPLUG_SUBSCRIBE
  VAR_INPUT
    NAME : STRING(96);
    VALUE : ANY;
    NODE_ID : STRING(47);
    GROUP : STRING(47);
    DEVICE : STRING(47);
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    VALID : BOOL;
    TYPE_OK : BOOL;
    FRESH : BOOL;
    AGE : DINT;
    READS : DINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    HOST : SPARKPLUG_HOST;
  END_VAR
  VAR
    fbEver : BOOL;
    fbLastAt : LINT;
  END_VAR
#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugHost.h>

// Defined by SPARKPLUG_HOST, which sorts before this file - every C++ POU in a
// project lands in one translation unit in filename order.
MqttSparkplugHost* mq_spHostOf(strucpp::XWORD_t handle);

// Defined by SPARKPLUG_NODE. A declaration before use is all C++ needs.
bool mq_spWriteAny(const strucpp::IEC_ANY& any, const MqttSparkplugValue& value);

void setup()
{
    VALID = false;
    TYPE_OK = false;
    FRESH = false;
    AGE = 0;
    READS = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbEver = false;
    fbLastAt = 0;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)HOST.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    FRESH = false;

    if (!(bool)ENABLE) {
        VALID = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    MqttSparkplugHost* host = mq_spHostOf((strucpp::XWORD_t)HOST.FBAPI);
    if (host == nullptr) {
        // The host block has not built itself yet. Ordinary on the first scan.
        VALID = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    if (NAME.length() == 0) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        VALID = false;
        return;
    }

    // --- Which node ---
    //
    // With one node on the plant the empty case is what an engineer expects to
    // work, so it resolves to the only node there is. With two it would pick
    // whichever birthed first, which is a bug waiting to happen, so it is
    // resolved by NAME here and documented as such rather than left implicit.
    const MqttSparkplugTrackedNode* tracked = nullptr;
    if (NODE_ID.length() != 0) {
        const char* group = GROUP.length() != 0 ? GROUP.c_str() : nullptr;
        if (group != nullptr) {
            tracked = host->findNode(group, NODE_ID.c_str());
        } else {
            // No group given: take the node of that name whatever group it is
            // in. One plant, one naming scheme.
            for (size_t index = 0; index < host->nodeCount(); index++) {
                const MqttSparkplugTrackedNode* candidate = host->nodeAt(index);
                if (candidate == nullptr) continue;
                if (candidate->node != NODE_ID.c_str()) continue;
                tracked = candidate;
                break;
            }
        }
    } else if (host->nodeCount() > 0) {
        tracked = host->nodeAt(0);
    }

    if (tracked == nullptr) {
        // Nothing has been heard from. Not an error - a plant starting up
        // spends its first seconds here.
        VALID = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    const char* device = DEVICE.length() != 0 ? DEVICE.c_str() : nullptr;
    const MqttSparkplugTrackedMetric* metric =
        tracked->find(NAME.c_str(), device);

    if (metric == nullptr || !metric->hasValue) {
        // Declared but never published, or never declared at all. Both mean
        // the same thing to a rung.
        VALID = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    if (!mq_spWriteAny(VALUE, metric->value)) {
        // THE DECLARED TYPE DID NOT MATCH, and that is worth saying loudly.
        // The birth certificate is the contract; a rung wired to the wrong
        // type has misread it, and writing a coerced value would hide that
        // until something acted on a truncated number.
        VALID = false;
        TYPE_OK = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    TYPE_OK = true;
    VALID = true;
    READS = READS + 1;

    // Age from the NODE's timestamp, which is when the reading happened, not
    // when we received it.
    const int64_t at = (int64_t)metric->at;
    FRESH = !(bool)fbEver || at != (int64_t)fbLastAt;
    fbLastAt = at;
    fbEver = true;

    const int64_t now = (int64_t)mq_epochMillis();
    if (now > 0 && at > 0 && now >= at) {
        const int64_t age = now - at;
        // Clamped rather than wrapped: a DINT of milliseconds covers 24 days,
        // and anything past that is "very old" by any reading.
        AGE = (int32_t)(age > 2147483647LL ? 2147483647LL : age);
    } else {
        AGE = 0;
    }

    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK