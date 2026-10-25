(* A SPARKPLUG COMMAND, ARRIVING.

NODE      which node. Must be wired.
NAME      the metric a command is expected on. It must have been declared
          writable, by SPARKPLUG_STRUCT with WRITABLE set or by
          SPARKPLUG_METRIC.
DEVICE    the device the metric is under, for a DCMD. Empty (the default)
          for a node metric and an NCMD. A name is only unique within its
          device, so a metric under a device is only found with it.
ACK       TRUE takes the pending command, clearing it. Leave it FALSE to watch
          without consuming. Two writes that arrive together are two
          commands: the second is PENDING after the first is taken.

PENDING   a command has arrived and has not been taken.
VALUE     the value it carried, valid on the scan PENDING first goes true.
TEXT      the same for a String metric: up to 126 characters, the most a
          board's command holds.
COUNT     how many commands have arrived on this metric.
LOST      writes dropped because four were already waiting on this metric:
          the oldest goes, the newest is kept. 0 in any sane system.
REFUSED   how many the NODE refused across all metrics - an undeclared name, a
          read-only metric, a value of the wrong type. A running total from the
          node, not this metric alone: a host writing to a name nobody declared
          has no metric to be counted against.
ERROR     something failed.
STATUS    MQTT_OK when fine.

---

WHY THIS EXISTS WHEN SPARKPLUG_STRUCT ALREADY APPLIES COMMANDS. Because a
setpoint is usually not just a number to store. A recipe change wants to be
validated, a pump start wants an interlock checked, a mode change wants to be
logged. SPARKPLUG_STRUCT with WRITABLE writes the value straight into the
struct member and reports it back, which is right for a plain setpoint and
wrong for anything that needs a decision.

So: leave those members out of the writable struct, declare them with
SPARKPLUG_METRIC, and watch them here. PENDING goes true, the rung decides, and
the program writes the value where it belongs - or does not.

THE PAIR IS THE POINT. This is the callback-and-pollable pattern the whole
library follows, and it exists because generated ladder cannot register a
handler. PENDING and VALUE are the pollable half.

ACK CLEARS IT, so two rungs cannot both act on one command. That is the same
rule the MQTT_STATUS counters follow, and for the same reason: a command applied
twice is a pump started twice.

NO REPLY TOPIC. A Sparkplug command is not a request/response - the
acknowledgement is that the metric's next DATA message carries the new value,
which is what a host watches for. Publish the value back and the host has its
answer. *)

FUNCTION_BLOCK SPARKPLUG_COMMAND
  VAR_INPUT
    NAME : STRING(96);
    ACK : BOOL;
    DEVICE : STRING(47);
  END_VAR
  VAR_OUTPUT
    PENDING : BOOL;
    VALUE : LREAL;
    IS_TRUE : BOOL;
    TEXT : STRING(126);
    COUNT : DINT;
    REFUSED : DINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
    LOST : DINT;
  END_VAR
  VAR_IN_OUT
    NODE : SPARKPLUG_NODE;
  END_VAR
  VAR
    fbLastAck : BOOL;
    fbSeen : BOOL;
    fbTaken : UDINT;
  END_VAR
#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugNode.h>

MqttSparkplugNode* mq_spNodeOf(strucpp::XWORD_t handle);


void setup()
{
    PENDING = false;
    VALUE = 0.0;
    IS_TRUE = false;
    TEXT = "";
    COUNT = 0;
    REFUSED = 0;
    LOST = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbLastAck = false;
    fbSeen = false;
    fbTaken = 0;
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

    REFUSED = (int32_t)node->commandsRefused();

    if (NAME.length() == 0) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    // A DCMD is held on its device's metric, and a name is only unique within
    // its device - so the device is part of the question. Empty asks for the
    // node's own metric, as this block always did.
    const char* device = DEVICE.length() != 0 ? DEVICE.c_str() : nullptr;
    const int index = node->indexOf(device, NAME.c_str());
    const bool pending = index >= 0 && node->commandPendingAt((size_t)index);
    // Writes the queue had no room for (SPARKPLUG_NODE keeps four a metric).
    if (index >= 0) LOST = (int32_t)node->writesLostAt((size_t)index);

    // ANOTHER CALLER TOOK THE ONE WE LOOKED AT - a writable SPARKPLUG_METRIC
    // on the same name applies every write too - so a write still pending now
    // is the NEXT one, and is a command of its own.
    if (index >= 0 && (bool)fbSeen &&
        node->writesTakenAt((size_t)index) != (uint32_t)fbTaken) {
        fbSeen = false;
    }

    if (pending && !(bool)fbSeen) {
        // First sight of this command. The value is read WITHOUT taking it, so
        // a rung can look before deciding - node->take() would clear it. It
        // is the OLDEST write waiting: two writes in one scan are two
        // commands here, one after the other, each with its own ACK.
        fbSeen = true;
        fbTaken = node->writesTakenAt((size_t)index);
        COUNT = COUNT + 1;
        MqttSparkplugValue value;
        if (node->peekAt((size_t)index, value)) {
            VALUE = value.asNumber();
            IS_TRUE = value.asNumber() != 0.0;
            if (value.isText() && value.as.bytes.data != nullptr) {
                // Bounded by the pin's declared capacity. A longer value is
                // truncated HERE rather than refused, because unlike a topic a
                // display string that is too long is still useful - and the
                // full value is in the struct member if one is bound.
                char buffer[127];   // TEXT's 126 characters, a board's whole command text
                size_t length = value.as.bytes.length;
                if (length > sizeof buffer - 1) length = sizeof buffer - 1;
                memcpy(buffer, value.as.bytes.data, length);
                buffer[length] = '\0';
                TEXT = buffer;
            } else {
                TEXT = "";
            }
        }
    }

    PENDING = pending;

    // A rising edge on ACK consumes it.
    if ((bool)ACK && !(bool)fbLastAck && pending) {
        MqttSparkplugValue taken;
        node->takeAt((size_t)index, taken);
        PENDING = false;
        fbSeen = false;
    }
    fbLastAck = (bool)ACK;

    if (!pending) fbSeen = false;

    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK