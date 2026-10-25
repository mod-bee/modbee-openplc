(* ONE SPARKPLUG METRIC, for what a STRUCT member cannot express.

NODE      which node. Must be wired.
NAME      the metric name, exactly as it will appear at the far end. Case
          matters: Sparkplug metric names are case sensitive. Up to 96
          characters, the most a board's metric holds.
VALUE     the value. Its DECLARED IEC type becomes the metric's datatype.
DEVICE    a device under the node, or empty for a node metric.
UNITS     engineering units - 'kPa', 'metres'. Carried in the birth certificate
          as the engUnit property, which is what makes a number mean something
          at the far end.
QUALITY   MQTT_QUALITY_GOOD, _UNCERTAIN, _BAD or _UNKNOWN. Carried in the
          birth as the Quality property, which Sparkplug fixes to one of
          three codes - so UNCERTAIN becomes stale and UNKNOWN becomes bad.
WRITABLE  TRUE lets a Host Application command it - an NCMD for a node
          metric, a DCMD for one under DEVICE.
          Every write is seen, one a scan, oldest first.
          Declared writable once; while WRITABLE is FALSE after that, a write
          is dropped at once and the metric reported back unchanged. It is
          never kept for later.
DEADBAND  for a number: a move of this much or less, from the value last SENT,
          is not reported. In VALUE's own units - 0.01 on a level in metres
          is 10 mm. 0 (the default) reports every change. A slow drift still
          adds up and goes, and a birth always carries the value as it is.
          Refused on a BOOL or a STRING.
ENABLE    FALSE stops publishing without losing the declaration.

ALIAS     the number the far end will see instead of NAME after the birth. 0
          means the declaration was refused.
WRITTEN   how many commands have been applied.
LOST      writes dropped because four were already waiting on this metric:
          the oldest goes, the newest is kept. 0 in any sane system.
ERROR     something failed.
STATUS    MQTT_OK when fine.

---

USE SPARKPLUG_STRUCT WHERE YOU CAN. A struct gives you the metric name, the
datatype and the complete birth set from one declaration, and sends one message
for the lot. This block is for the cases it cannot cover: a value that is not a
member of anything, one that needs its own units and quality, or one whose
publishing is driven by different logic from the rest.

The two coexist happily on one node. Aliases come from a single counter, so a
metric here and thirty in a struct cannot collide.

NO QOS OR RETAINED PIN. Sparkplug fixes both.

THIS BLOCK DOES NOT PUBLISH ON ITS OWN. It writes the value into the node, and
the node publishes - one message carrying everything that moved, which is the
point of Sparkplug and the opposite of one topic per value. With PUBLISH (TRUE
unless wired otherwise) this block asks for that message, and SPARKPLUG_NODE
sends it on its next scan, once for every block that asked. Without it, a
SPARKPLUG_STRUCT or another SPARKPLUG_METRIC on the same node triggers the
send; if this is the only metric on the node, set MODE on its struct or use
REQ. *)

FUNCTION_BLOCK SPARKPLUG_METRIC
  VAR_INPUT
    (* PIN ORDER IS A DESIGN DECISION, not a listing.
       The first input is read - by an engineer and by `check --lint` - as the
       one that makes the block do something: "block-primary-input-unassigned"
       fires when it is left unwired. DEVICE was first and is OPTIONAL, so
       every node-level use of this block was reported as doing nothing. NAME and VALUE are
       what it operates on, so they are first. *)
    (* NO DEFAULT ON AN ENUM PIN, and that is the parser's rule rather than a
       preference: the block-header parser refuses a qualified enum literal in
       an initial value - "unexpected character: ->#<-". No MQTT_* block gives
       an enum pin a default either, for the same reason.

       Nothing is lost by it. Each enum TYPE carries its own default -
       MQTT_SECURITY is MQTT_PLAIN, MQTT_TRIGGER is MQTT_ON_CHANGE,
       MQTT_PROTOCOL is MQTT_V5_THEN_V311 - so an unwired pin behaves exactly
       as the prose above says. *)
    NAME : STRING(96);
    VALUE : ANY;
    DEVICE : STRING(47);
    UNITS : STRING(16);
    QUALITY : MQTT_QUALITY;
    WRITABLE : BOOL;
    PUBLISH : BOOL := TRUE;
    ENABLE : BOOL := TRUE;
    DEADBAND : REAL;
  END_VAR
  VAR_OUTPUT
    ALIAS : UDINT;
    WRITTEN : DINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
    LOST : DINT;
  END_VAR
  VAR_IN_OUT
    NODE : SPARKPLUG_NODE;
  END_VAR
  VAR
    fbDeclared : BOOL;
    fbDeadband : REAL;
    fbWritable : BOOL;
  END_VAR
#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugNode.h>

MqttSparkplugNode* mq_spNodeOf(strucpp::XWORD_t handle);
bool mq_spTypeOfClass(int typeClass, MqttSparkplugDataType* out);
bool mq_spValueOfAny(const strucpp::IEC_ANY& any, MqttSparkplugValue* out);
bool mq_spWriteAny(const strucpp::IEC_ANY& any,
                   const MqttSparkplugValue& value);


void setup()
{
    ALIAS = 0;
    WRITTEN = 0;
    LOST = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbDeclared = false;
    fbDeadband = 0.0f;
    fbWritable = false;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)NODE.FBAPI);
    if (!node) {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    if (NAME.length() == 0) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    const char* device = DEVICE.length() != 0
        ? DEVICE.c_str() : nullptr;

    // --- Declare, once, before the node births ---
    if (!fbDeclared) {
        fbDeclared = true;

        MqttSparkplugDataType type = MqttSparkplugDataType::Unknown;
        if (!mq_spTypeOfClass(VALUE.TYPECLASS, &type)) {
            // A type the wire cannot carry, named rather than skipped.
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            return;
        }

        // Only the block that adds the device brings it online: one a
        // SPARKPLUG_DEVICE block added is that block's (see SPARKPLUG_STRUCT).
        const bool addedHere = device != nullptr && node->addDevice(device);

        // The two enums do not line up, and the mapping is a judgement.
        //
        // MQTT_QUALITY has four values because it answers "how much should I
        // believe this number", which is a question about freshness. Sparkplug
        // fixes exactly three codes - 0, 192, 500
        // ([tck-id-payloads-propertyset-quality-value-value]) - so UNCERTAIN
        // and UNKNOWN both have to land somewhere.
        //
        // UNCERTAIN becomes STALE: the value was good and is old, which is
        // what stale means. UNKNOWN becomes BAD: nothing is known about it, and
        // "do not trust this" is the honest answer rather than GOOD.
        int32_t quality = MQ_SP_QUALITY_GOOD;
        switch (QUALITY) {
        case MQTT_QUALITY::MQTT_QUALITY_GOOD:
            quality = MQ_SP_QUALITY_GOOD;
            break;
        case MQTT_QUALITY::MQTT_QUALITY_UNCERTAIN:
            quality = MQ_SP_QUALITY_STALE;
            break;
        case MQTT_QUALITY::MQTT_QUALITY_BAD:
        case MQTT_QUALITY::MQTT_QUALITY_UNKNOWN:
        default:
            quality = MQ_SP_QUALITY_BAD;
            break;
        }

        // Declared writable or not: what the node will take writes for,
        // whatever WRITABLE says later.
        fbWritable = (bool)WRITABLE;
        uint64_t alias = 0;
        if (device != nullptr) {
            alias = (bool)WRITABLE
                ? node->declareWritableFor(device, NAME.c_str(), type)
                : node->declareFor(device, NAME.c_str(), type);
        } else if ((bool)WRITABLE) {
            alias = node->declareWritable(NAME.c_str(), type);
        } else {
            // The units-and-quality overload, which only the node-level
            // declaration has - a device metric takes them from its own block.
            alias = node->declare(NAME.c_str(), type,
                                  UNITS.length() != 0
                                      ? UNITS.c_str() : nullptr,
                                  quality);
        }

        ALIAS = (uint32_t)alias;
        if (alias == 0) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            return;
        }
        if (addedHere) node->deviceOnline(device);
        fbDeadband = 0.0f;
        return;
    }

    // --- The deadband, whenever the pin changes ---
    //
    // Held by the node against what it last PUBLISHED, so a slow drift still
    // adds up and goes. A deadband on a BOOL or a STRING is refused by the
    // node - it would freeze a bit - and said so here rather than ignored.
    if ((float)DEADBAND != (float)fbDeadband) {
        const double band = (double)(float)DEADBAND;
        const bool ok = device != nullptr
            ? node->deadbandFor(device, NAME.c_str(), band < 0.0 ? -1.0 : band)
            : node->deadband(NAME.c_str(), band < 0.0 ? -1.0 : band);
        fbDeadband = (float)DEADBAND;
        if (!ok && band != 0.0) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            return;
        }
    }

    // --- NOT WRITABLE: a write is dropped at once, never kept ---
    //
    // Declared writable, the node still takes writes for this metric after
    // WRITABLE goes FALSE. They waited in its queue until WRITABLE was TRUE
    // again, and then the old command acted by itself. Each one is
    // taken and dropped, and VALUE put back into the node, so the next
    // message reports it unchanged: the host sees the write did not take.
    // Only for a metric declared writable - the node refuses writes to any
    // other - so a read-only metric pays nothing for it.
    if ((bool)fbWritable && !(bool)WRITABLE) {
        MqttSparkplugValue value;
        bool dropped = false;
        while (node->commandPendingFor(device, NAME.c_str()) &&
               node->takeFor(device, NAME.c_str(), value)) {
            dropped = true;
        }
        if (dropped && mq_spValueOfAny(VALUE, &value)) {
            if (device != nullptr) node->setFor(device, NAME.c_str(), value);
            else node->set(NAME.c_str(), value);
        }
    }

    if (!(bool)ENABLE) {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    // NOT BORN YET IS NOT "NOTHING TO DO": the value still goes into the node,
    // because the birth carries it [tck-id-operational-behavior-data-publish-
    // nbirth-values]. It used to wait for the birth, so the first birth after
    // a start reported this metric as null.
    const bool born = node->isBorn();

    // A command in, before the value out, so a setpoint written this scan is
    // reported back in the same publish.
    // ON ITS OWN DEVICE: a name is only unique within its device, and a DCMD
    // is held on the device's metric. Asking the node by name alone found the
    // node-level metric or nothing, so every DCMD was applied and then lost.
    //
    // ONE WRITE A SCAN, THE OLDEST FIRST. SPARKPLUG_NODE queues every write
    // (four a metric), so a host writing 1 and then 0 inside one scan gives
    // VALUE the 1 for a scan and then the 0 - the command in the 1 is seen.
    if (born && (bool)WRITABLE && node->commandPendingFor(device, NAME.c_str())) {
        MqttSparkplugValue value;
        if (node->takeFor(device, NAME.c_str(), value)) {
            if (mq_spWriteAny(VALUE, value)) {
                WRITTEN = WRITTEN + 1;
            } else {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
            }
        }
    }

    if ((bool)WRITABLE && born) {
        const int index = node->indexOf(device, NAME.c_str());
        if (index >= 0) LOST = (int32_t)node->writesLostAt((size_t)index);
    }

    MqttSparkplugValue value;
    if (!mq_spValueOfAny(VALUE, &value)) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    const bool ok = device != nullptr
        ? node->setFor(device, NAME.c_str(), value)
        : node->set(NAME.c_str(), value);
    if (!ok) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    if (!born) {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    // PUBLISH lets one metric drive a send where there is no struct to do it.
    // Off by default would leave a single-metric node silent, which looks
    // broken; on by default sends only what moved, which costs nothing.
    //
    // ASKED, NOT SENT: SPARKPLUG_NODE sends one message on its next scan for
    // everything on the node that moved, however many blocks asked.
    // This was a publishChanged() of its own, every scan, each one walking
    // every metric of the node.
    if ((bool)PUBLISH) node->publishAtPoll();

    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK