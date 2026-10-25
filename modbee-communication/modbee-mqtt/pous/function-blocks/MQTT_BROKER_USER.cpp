(* ONE ACCOUNT ON THIS PLC'S BROKER. Draw one rung per device that connects.

USERNAME   the name the device logs in with. Compared exactly, case included -
           MQTT user names are case-sensitive.
PASSWORD   its password. Up to 64 characters, which is what a STRING pin
           carries; compared in full, never stopping at the first difference.
ENABLE     FALSE refuses this device without forgetting it. The account still
           counts as declared, so the broker STILL REQUIRES ACCOUNTS: switching
           off the last one locks the broker, it does not open it.

ACTIVE     the account is declared and enabled.
LOGINS     times this device has connected successfully.
REFUSED    times a connection under this name was turned away - a wrong
           password, or the account switched off. A number that climbs on one
           device and not the others is that device's configuration.
ERROR      the account could not be declared; STATUS says why.
STATUS     MQTT_INVALID_ARGUMENT for an empty USERNAME, MQTT_QUOTA_EXCEEDED
           when the broker cannot hold another account: when memory for one
           ran out. The table grows with these blocks, on a board and the
           Runtime alike.

WHY ONE BLOCK PER ACCOUNT rather than a list on MQTT_BROKER: an account is
something an engineer adds, removes and switches off one device at a time, and
a rung per device makes each one visible, commentable and interlockable. A
list on a pin would be an array, typed by hand, with no way to disable one
entry.

WHY EACH DEVICE GETS ITS OWN. A shared password cannot be revoked from one
controller without changing it on all of them, and a broker log that says
"plant-user refused" does not say which panel to go to.

WHAT IS NOT HERE: topic permissions. This decides who may CONNECT. *)

FUNCTION_BLOCK MQTT_BROKER_USER
  VAR_INPUT
    USERNAME : STRING(64);
    PASSWORD : STRING(64);
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    ACTIVE : BOOL;
    LOGINS : DINT;
    REFUSED : DINT;
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    BROKER : MQTT_BROKER;
  END_VAR
  VAR
    (* The name this block last declared, so a USERNAME changed while the
       program runs removes the old account rather than leaving it able to log
       in under a name nobody can see on the ladder any more. *)
    fbName : STRING(64);
  END_VAR
#include <ModBeeMqtt.h>
#include <string.h>

// Defined by MQTT_BROKER, which sorts before this file - every C++ POU in a
// project lands in one translation unit in filename order.
MqttBrokerAccounts* mq_brokerAccountsOf(strucpp::XWORD_t handle);

void setup()
{
    ACTIVE = false;
    LOGINS = 0;
    REFUSED = 0;
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    fbName = "";
}

void loop()
{
    if (!mq_inTask((strucpp::XWORD_t)BROKER.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    MqttBrokerAccounts* accounts =
        mq_brokerAccountsOf((strucpp::XWORD_t)BROKER.FBACCOUNTS);
    if (accounts == nullptr) {
        // The broker block has not run yet. Ordinary on the first scan when
        // this rung is drawn above it; the table exists from the broker's
        // first scan and the port does not open until its second.
        ACTIVE = false;
        ERROR = false;
        STATUS = MQTT_RESULT::MQTT_OK;
        return;
    }

    if (USERNAME.length() == 0) {
        // An account with no name would make anonymous a password.
        ACTIVE = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        return;
    }

    // RENAMED WHILE RUNNING: the old name goes, so nothing can still log in
    // under it.
    if (fbName.length() != 0 &&
        strcmp(fbName.c_str(), USERNAME.c_str()) != 0) {
        accounts->remove(fbName.c_str());
    }

    // Every scan, deliberately: the pins are the truth. A password changed on
    // the HMI takes effect on the next connection without a download, and the
    // counters survive because set() only resets them for a NEW account.
    if (!accounts->set(USERNAME.c_str(), PASSWORD.c_str(), (bool)ENABLE)) {
        ACTIVE = false;
        ERROR = true;
        // STRING(64) cannot exceed the field size, so the only way left to
        // fail is a table memory could not grow.
        STATUS = MQTT_RESULT::MQTT_QUOTA_EXCEEDED;
        return;
    }
    fbName = USERNAME;

    ACTIVE = (bool)ENABLE;
    LOGINS = (int32_t)accounts->logins(USERNAME.c_str());
    REFUSED = (int32_t)accounts->refusals(USERNAME.c_str());
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
}

END_FUNCTION_BLOCK