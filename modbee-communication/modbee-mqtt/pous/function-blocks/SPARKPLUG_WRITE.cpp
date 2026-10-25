(* WRITE ONE METRIC on an edge node, from a SPARKPLUG_HOST.

This is the other direction: an NCMD, or a DCMD for a device metric. The edge
node applies it to whatever its SPARKPLUG_METRIC or SPARKPLUG_STRUCT block is
wired to, and reports the new value back under the SAME metric name.

THAT IS WHY THERE IS NO `_fb` TOPIC HERE. Under plain MQTT a writable setpoint
needs two topics - one to command and one to read back - and two tags at the
far end that nothing guarantees are the same number. Under Sparkplug the
direction lives in the message type, so one name is read and written.

THE NODE DECIDES. A command for a metric the node never declared, or declared
read-only, or declared with a different type, is REFUSED there and counted -
this block reports that it sent one, not that it took effect. Wire a
SPARKPLUG_SUBSCRIBE to the same NAME to see the value come back.

NAME         the metric name, exactly as the edge node declared it.
VALUE        what to write. Its IEC type must match what the birth declared.
REQ          rising edge sends. A level would send every scan.
NODE_ID      which edge node. Empty means the first node the host heard from.
GROUP        which group. Empty means the host's watched group.
DEVICE       for a metric belonging to a device rather than the node itself.
ENABLE       false sends nothing.

SENT         one command left this scan.
COUNT        how many have been sent.
ERROR        something is wrong; STATUS says what. *)

FUNCTION_BLOCK SPARKPLUG_WRITE
  VAR_INPUT
    NAME : STRING(96);
    VALUE : ANY;
    REQ : BOOL;
    NODE_ID : STRING(47);
    GROUP : STRING(47);
    DEVICE : STRING(47);
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    SENT : BOOL;
    COUNT : DINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    HOST : SPARKPLUG_HOST;
  END_VAR
  VAR
    fbLastReq : BOOL;
    (* A REQUEST THAT HAS NOT BEEN SENT YET.
       A rising edge is a decision made once, and the host may not be able to
       act on it the instant it arrives - the node it addresses may not have
       birthed yet. Consuming the edge on that attempt loses the command for
       ever, which is exactly what happened the first time this block was used:
       the settle timer elapsed before the edge node existed, the write was
       refused as NOT_CONNECTED, and nothing ever tried again. *)
    fbWanted : BOOL;
  END_VAR
#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugHost.h>

// Defined by SPARKPLUG_HOST, which sorts before this file.
MqttSparkplugHost* mq_spHostOf(strucpp::XWORD_t handle);

// Defined by SPARKPLUG_NODE. A declaration before use is all C++ needs.
bool mq_spValueOfAny(const strucpp::IEC_ANY& any, MqttSparkplugValue* out);

void setup()
{
    SENT = false;
    COUNT = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbLastReq = false;
    fbWanted = false;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)HOST.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    SENT = false;

    if (!(bool)ENABLE) {
        // Neither the edge nor a pending request survives a disable,
        // deliberately: an operator re-enabling a block should not have a
        // command they pressed minutes ago fire the instant it comes back.
        fbLastReq = (bool)REQ;
        fbWanted = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    // --- THE EDGE IS REMEMBERED UNTIL IT IS ACTED ON ---
    //
    // A rising edge latches the request; the attempt below clears it only when
    // the command actually goes. While REQ is held and the host cannot reach
    // the node yet, the next scan tries again.
    //
    // Not a queue with a lifetime of its own: if REQ falls before the command
    // can be sent, the request is DROPPED. A command is a decision made at a
    // moment, and one that arrives a minute after the operator let go is worse
    // than one that never arrived - the plant has moved on.
    if ((bool)REQ && !(bool)fbLastReq) fbWanted = true;
    if (!(bool)REQ) fbWanted = false;
    fbLastReq = (bool)REQ;

    if (!(bool)fbWanted) {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    MqttSparkplugHost* host = mq_spHostOf((strucpp::XWORD_t)HOST.FBAPI);
    if (host == nullptr || !host->isConnected()) {
        // Held, not lost - fbWanted stays set and the next scan tries again
        // while REQ is still asking.
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
        return;
    }

    if (NAME.length() == 0) {
        // A permanent refusal, so the latch is cleared: retrying an empty NAME
        // every scan would report the same error for ever and hide anything
        // else the block had to say.
        fbWanted = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    // Which node - same resolution as SPARKPLUG_SUBSCRIBE, and for the same
    // reason: with one node the empty case should work, with two it must not
    // guess.
    const MqttSparkplugTrackedNode* tracked = nullptr;
    if (NODE_ID.length() != 0) {
        const char* group = GROUP.length() != 0 ? GROUP.c_str() : nullptr;
        if (group != nullptr) {
            tracked = host->findNode(group, NODE_ID.c_str());
        } else {
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
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_CONNECTED;
        return;
    }

    MqttSparkplugValue value;
    if (!mq_spValueOfAny(VALUE, &value)) {
        // An IEC type with no Sparkplug datatype - a DATE, a STRUCT.
        // Refused by name rather than sent as something it is not, and
        // permanently, so the latch goes with it.
        fbWanted = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    bool ok = false;
    if (DEVICE.length() != 0) {
        ok = host->commandDevice(tracked->group.c_str(), tracked->node.c_str(),
                                 DEVICE.c_str(), NAME.c_str(), value);
    } else {
        ok = host->command(tracked->group.c_str(), tracked->node.c_str(),
                           NAME.c_str(), value);
    }

    if (!ok) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_REFUSED;
        return;
    }

    SENT = true;
    COUNT = COUNT + 1;
    fbWanted = false;          // acted on; a further send needs a new edge
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK