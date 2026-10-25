(* A DEVICE UNDER A SPARKPLUG NODE.

NODE      which node. Must be wired.
DEVICE    this device's ID. Must be unique among this node's devices.
ONLINE    TRUE births the device, FALSE kills it. Edge triggered, so holding it
          TRUE does not republish.
ENABLE    FALSE leaves the device alone entirely.

IS_ONLINE whether the device's birth certificate has gone.
BIRTHS    how many times it has birthed - which rises on every reconnect,
          because a device's birth is owed again each time its node births.
          Counted when its birth has gone (IS_ONLINE rising), not when it
          was asked for: a birth the queue had no room for waits, owed.
DEATHS    how many death certificates have gone.
ERROR     something failed.
STATUS    MQTT_OK when fine.

---

WHAT A DEVICE IS FOR. A node is the thing with the MQTT connection; a device is
something the node speaks FOR - a pump, a meter, a drive on a bus behind it.
The distinction is worth making when the node can be up while the thing it
reports on is not: a PLC talking to four VFDs over Modbus is one node and four
devices, and a VFD that stops answering gets a death certificate while the node
stays connected and keeps reporting the other three.

If everything lives or dies with the PLC, do not use this. Put the metrics on
the node and save yourself four topics.

YOU DO NOT NEED THIS BLOCK TO USE A DEVICE. SPARKPLUG_STRUCT and
SPARKPLUG_METRIC add the device themselves when their DEVICE pin is set, and
bring it online. This block is for when the device's presence is a decision the
program makes - which is the case that matters, because a device that is
"online" whenever the PLC is running is not telling anybody anything.

WITH THIS BLOCK, ITS ONLINE PIN DECIDES, whichever block is called first: a
SPARKPLUG_STRUCT or SPARKPLUG_METRIC under the same DEVICE declares its metrics
there but leaves the device's presence alone, so ONLINE := FALSE holds it
offline from the first scan - births included.

A DEATH CERTIFICATE CARRIES A SEQUENCE NUMBER. A node's does not. That is the
specification's rule, not a choice, and the library handles it - mentioned here
because it is the single most surprising thing about Sparkplug's two death
messages.

ORDER IS ENFORCED FOR YOU. A device cannot birth before its node has; asking
for it early leaves the birth OWED and it goes as soon as the node births. So a
program does not have to sequence itself against the link coming up. *)

FUNCTION_BLOCK SPARKPLUG_DEVICE
  VAR_INPUT
    DEVICE : STRING(47);
    ONLINE : BOOL := TRUE;
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    IS_ONLINE : BOOL;
    BIRTHS : DINT;
    DEATHS : DINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    NODE : SPARKPLUG_NODE;
  END_VAR
  VAR
    fbAdded : BOOL;
    fbLastWanted : BOOL;
    fbEverAsked : BOOL;
  END_VAR
#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugNode.h>

MqttSparkplugNode* mq_spNodeOf(strucpp::XWORD_t handle);


void setup()
{
    IS_ONLINE = false;
    BIRTHS = 0;
    DEATHS = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbAdded = false;
    fbLastWanted = false;
    fbEverAsked = false;
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    if (!(bool)ENABLE) return;

    MqttSparkplugNode* node = mq_spNodeOf((strucpp::XWORD_t)NODE.FBAPI);
    if (!node) {
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    if (DEVICE.length() == 0) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    if (!fbAdded) {
        fbAdded = true;
        // Refused if it is already there, which is not an error: a
        // SPARKPLUG_STRUCT with the same DEVICE pin may have added it first,
        // and both blocks referring to one device is the normal arrangement.
        node->addDevice(DEVICE.c_str());
    }

    const bool wanted = (bool)ONLINE;

    // EDGE TRIGGERED. Holding ONLINE true must not republish the birth
    // certificate on every scan - a host would see a rebirth storm and start
    // asking what was wrong.
    if (!fbEverAsked || wanted != (bool)fbLastWanted) {
        fbEverAsked = true;
        fbLastWanted = wanted;

        if (wanted) {
            if (!node->deviceOnline(DEVICE.c_str())) {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                return;
            }
        } else {
            if (node->deviceOffline(DEVICE.c_str())) {
                DEATHS = DEATHS + 1;
            } else {
                ERROR = true;
                STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
                return;
            }
        }
    }

    // The node re-owes every device's birth after a reconnect, so a device
    // that is meant to be online and is not gets asked again. Without this a
    // device would come back silent after a dropped link and nothing would say
    // why.
    // Asking for a birth the node already owes is harmless: it births an owed
    // device once, by itself.
    if (wanted && node->isBorn() && !node->deviceIsOnline(DEVICE.c_str())) {
        node->deviceOnline(DEVICE.c_str());
    }

    // A BIRTH IS COUNTED WHEN IT HAS GONE. Counting each successful ask
    // counted a birth that was only owed - and an owed one is asked for again
    // every scan until there is room for it.
    const bool nowOnline = node->deviceIsOnline(DEVICE.c_str());
    if (nowOnline && !(bool)IS_ONLINE) BIRTHS = BIRTHS + 1;
    IS_ONLINE = nowOnline;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK