(* Lets this PLC register itself with a modbee broker, so nobody types a
password into it. Optional - place it beside MQTT_CLIENT.

CLIENT    which client. Must be wired. Its CLIENT_ID is this PLC's NAME on the
          broker - unique on the site, like "pump-station-3" - and becomes its
          user name.
KEY       the provisioning key, made once on the broker with
          `modbee key create <name>`. The SAME key goes into every PLC of a
          site; each gets its own login with it.
FORGET    a rising edge forgets the stored login, and the PLC registers again.
          Rarely needed: a PLC whose login stops working re-registers by
          itself.

PROVISIONED  this PLC has its own login, and the client is using it.
PENDING      the broker's admin must approve this PLC first:
             `modbee user approve <name>`. It asks again every thirty seconds.
REFUSED      the broker said no; REASON says why. It asks again every five
             minutes, in case somebody fixes it at the other end.
USERNAME     the login in use: CLIENT_ID, once provisioned.
GROUP        what the key says this site's Sparkplug group is ("" if it says
             nothing). Wire it to SPARKPLUG_NODE's GROUP.
PREFIX       what the key says this site's topic prefix is ("" if it says
             nothing) - for the topics of this PLC's own, such as its firmware
             updates: PREFIX/<name>/... .
REASON       what the broker said, in words.
ERROR        REFUSED, or a pin that is not set.
STATUS       why. MQTT_OK when fine.

---

HOW IT GOES. On its first start the PLC has no login. It connects with the
key - which lets it do one thing only, ask - and the broker answers with a
login made for this PLC: its name, and a secret only it holds, and the values
the key hands its devices (GROUP and PREFIX). They are kept in this block's
RETAINED memory, and the client reconnects with the login. From then on the
PLC connects as itself, and nobody ever types, records or looks up its
password. While it is asking, the client's CONNECTED stays FALSE, so the rest
of the program waits for the real connection.

EVERY CONNECT IT ASKS AGAIN for GROUP and PREFIX (no new password), so a
change made for the site on the broker reaches it by itself.

WHEN THINGS CHANGE IT SORTS ITSELF OUT. A PLC replaced by a new one: download
the same program - same CLIENT_ID, same KEY - and the new PLC registers and
takes the name over; the old one's login stops working. An admin resets the
login (`modbee user reset`): the stored one is refused, so the PLC registers
again with its key, with no visit to the site. The old login is KEPT until the
broker issues a new one - a registration that is pending or refused never
leaves the PLC with no login at all - and while it waits the PLC tries the old
login again every five minutes, so a login put back on the broker works
again by itself. The site's group changed on
the broker: the broker refuses a connect whose Will (the Sparkplug NDEATH) is
on the old group, so the PLC connects once without a Will, asks again, and
reconnects with the new one. If asking again gives the same group, the
login's rights no longer cover its Will: REFUSED, REASON says so, and it
tries again every five minutes. An admin DISABLES the PLC: it stays out -
registering again does not undo that.

LEAVE USERNAME AND PASSWORD ON MQTT_CONFIG EMPTY. This block's login is used
instead of them.

WHAT IT MAY PUBLISH AND SUBSCRIBE TO is decided on the broker, by the key: a
key made with --publish 'plant/${username}/#' lets each PLC publish under its
own name and nowhere else. docs/logins.md in modbee-mqtt has the whole story.

For a modbee broker: the protocol is modbee's. *)

FUNCTION_BLOCK MQTT_PROVISION
  VAR_INPUT
    KEY : STRING(127);
    FORGET : BOOL;
  END_VAR
  VAR_OUTPUT
    PROVISIONED : BOOL;
    PENDING : BOOL;
    REFUSED : BOOL;
    USERNAME : STRING(64);
    GROUP : STRING(64);
    PREFIX : STRING(127);
    REASON : STRING(64);
    ERROR : BOOL;
    STATUS : MQTT_RESULT;
  END_VAR
  VAR_IN_OUT
    CLIENT : MQTT_CLIENT;
  END_VAR

  (* WHAT THIS PLC WAS GIVEN, IN THE BLOCK'S OWN RETAINED VARIABLES - so it
     survives a power cut, and nothing has to be wired to keep it. Retained
     values are matched by name at an upload, so a variable added here starts
     empty and the rest keep theirs. A user name is the PLC's CLIENT_ID (48 at
     most) and a secret is 32 characters. *)
  VAR RETAIN
    fbLoginUser : STRING(64);
    fbLoginSecret : STRING(64);
    fbGroup : STRING(64);
    fbPrefix : STRING(127);
  END_VAR
  VAR
    fbUsingKey : BOOL;
    fbHandle : INT := -1;
    fbAsked : BOOL;
    fbAskedAt : DINT;
    fbSeenConnects : DINT;
    fbSwitchTo : SINT;         (* 0 none, 1 to the stored login, 2 to the key, 3 the login without a Will *)
    fbSwitchClosed : BOOL;
    fbRefusedAt : DINT;
    fbLastForget : BOOL;
    fbForgetSeen : BOOL;
    fbWithoutWill : BOOL;      (* this session is the login without a Will: asking again, then back *)
    fbLockedAt : DINT;         (* when the login was last refused as not authorized *)
    fbOldTriedAt : DINT;       (* when the kept login was last tried, while registering again *)
  END_VAR
#include <ModBeeMqtt.h>
#include <string>
#include <string.h>

// Defined by the MQTT_CLIENT block, which every project has. Declared here
// because every C++ POU in a project lands in ONE translation unit, in
// filename order - so a block whose name sorts before MQTT_CLIENT would not
// otherwise have seen them.
MqttClient* mq_clientOf(strucpp::XWORD_t handle);
bool mq_tolerated(MqttResult result);

// How often a pending PLC asks again, and how long after a refusal.
#ifndef MQ_PROVISION_PENDING_MS
#define MQ_PROVISION_PENDING_MS 30000
#endif
#ifndef MQ_PROVISION_REFUSED_MS
#define MQ_PROVISION_REFUSED_MS 300000
#endif

// One string field of the broker's small answer, written without spaces:
// {"status":"ok","username":"...","password":"...","data":{"group":"..."}}.
// Found by its NAME (`"name":`), never by a value that happens to read the
// same. A name unique to this block, because every POU shares one
// translation unit.
bool mq_provisionField(const char* doc, size_t length, const char* name, std::string& out)
{
    const std::string text(doc, length);
    const std::string key = std::string("\"") + name + "\":";
    size_t at = text.find(key);
    if (at == std::string::npos) return false;
    at = text.find('"', at + key.size());
    if (at == std::string::npos) return false;
    out.clear();
    for (size_t i = at + 1; i < text.size(); i++) {
        if (text[i] == '\\' && i + 1 < text.size()) { out.push_back(text[++i]); continue; }
        if (text[i] == '"') return true;
        out.push_back(text[i]);
    }
    return false;
}

void setup()
{
    PROVISIONED = false;
    PENDING = false;
    REFUSED = false;
    USERNAME = "";
    GROUP = "";
    PREFIX = "";
    REASON = "";
    ERROR = false;
    STATUS = MQTT_RESULT::MQTT_OK;
    // NOT fbLoginUser, fbLoginSecret, fbGroup or fbPrefix: retained, and the whole point.
    fbUsingKey = false;
    fbHandle = -1;
    fbAsked = false;
    fbAskedAt = 0;
    fbSeenConnects = -1;
    fbSwitchTo = 0;
    fbSwitchClosed = false;
    fbRefusedAt = 0;
    fbLastForget = false;
    fbForgetSeen = false;
    fbWithoutWill = false;
    fbLockedAt = 0;
    fbOldTriedAt = 0;
}

void loop()
{
    // What the key handed this PLC, as kept: valid before the first connect, so
    // the node's Will is on the right group from the start.
    GROUP = fbGroup.c_str();
    PREFIX = fbPrefix.c_str();

    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {   // one task per client: see MQTT_ARDUINO
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_WRONG_TASK;
        return;
    }
    const mq_time_t now = mq_millis();

    if (CLIENT.CLIENT_ID.length() == 0) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        REASON = "set CLIENT_ID on MQTT_CLIENT - it is this PLC's name";
        return;
    }
    const bool haveLogin = fbLoginUser.length() > 0 && fbLoginSecret.length() > 0;
    if (!haveLogin && KEY.length() == 0) {
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_INVALID_ARGUMENT;
        REASON = "set KEY - from `modbee key create` on the broker";
        return;
    }

    // FORGET's rising edge - not at program start, where a FORGET wired TRUE
    // would otherwise throw the login away on every reboot.
    const bool forget = (bool)FORGET;
    if ((bool)fbForgetSeen && forget && !(bool)fbLastForget) {
        fbLoginUser = "";
        fbLoginSecret = "";
        if ((bool)CLIENT.LINK_UP) fbSwitchTo = 2;
    }
    fbLastForget = forget;
    fbForgetSeen = true;

    // --- Before the client builds its link: tell it which login to use ---
    if (!(bool)CLIENT.LINK_UP) {
        const bool stored = fbLoginUser.length() > 0 && fbLoginSecret.length() > 0;
        if (stored) {
            CLIENT.FBPROVUSER = fbLoginUser;
            CLIENT.FBPROVPASSWORD = fbLoginSecret.c_str();
        } else {
            CLIENT.FBPROVUSER = "$provision";
            CLIENT.FBPROVPASSWORD = KEY;
        }
        fbUsingKey = !stored;
        fbWithoutWill = false;
        CLIENT.FBPROVISIONING = !stored;
        PROVISIONED = false;
        USERNAME = stored ? fbLoginUser.c_str() : "";
        return;
    }

    MqttClient* client = mq_clientOf((strucpp::XWORD_t)CLIENT.FBAPI);
    if (!client) return;

    // --- Changing logins on the SAME client ---
    //
    // Never a new client: every other block holds handles into this one.
    // Down first, then the new login, then up - reconfigure() takes effect at
    // the next CONNECT.
    if ((int8_t)fbSwitchTo != 0) {
        if (client->isConnected()) {
            if (!(bool)fbSwitchClosed) {
                client->disconnect();
                fbSwitchClosed = true;
            }
        } else if (client->state() == MqttState::Idle || client->state() == MqttState::Reconnecting) {
            const bool toKey = (int8_t)fbSwitchTo == 2;
            const bool withoutWill = (int8_t)fbSwitchTo == 3;
            MqttConnectionConfig c = client->connection();
            c.hasUserName = true;
            c.hasPassword = true;
            // With the key, or the login only asking again: a session without
            // the node's Will (registration).
            c.registration = toKey || withoutWill;
            if (toKey) {
                c.userName = "$provision";
                c.password.assign(KEY.c_str(), KEY.c_str() + KEY.length());
            } else {
                c.userName = std::string(fbLoginUser.c_str(), fbLoginUser.length());
                c.password.assign(fbLoginSecret.c_str(), fbLoginSecret.c_str() + fbLoginSecret.length());
            }
            client->reconfigure(c);
            client->connect();
            fbUsingKey = toKey;
            fbWithoutWill = withoutWill;
            // Holds the program's other blocks (a Sparkplug node's birth) off
            // a session that only asks.
            CLIENT.FBPROVISIONING = toKey || withoutWill;
            fbSwitchTo = 0;
            fbSwitchClosed = false;
            fbAsked = false;
        }
    }

    const uint8_t refusal = client->status().connectReasonCode;
    const bool v311 = client->activeVersion() == MqttVersion::V311;
    const bool badLogin = !client->isConnected() &&
                          (refusal == MQ_REASON_BAD_USER_NAME_OR_PASSWORD ||
                           (v311 && refusal == MQ_RETURN_BAD_CREDENTIALS));
    const bool notAuthorized = !client->isConnected() &&
                               (refusal == MQ_REASON_NOT_AUTHORIZED || (v311 && refusal == MQ_RETURN_NOT_AUTHORIZED));

    // The reply topic, kept registered on the client: the key's answer, or the
    // login's when it asks again.
    const std::string id(CLIENT.CLIENT_ID.c_str(), CLIENT.CLIENT_ID.length());
    const std::string base = "$modbee/provision/" + id;
    MqttTopicHandle handle = (MqttTopicHandle)(int16_t)fbHandle;
    const std::string reply = base + "/reply";
    const char* held = handle >= 0 ? client->topicOf(handle) : nullptr;
    if (!held || reply != held) {
        handle = client->registerTopic(reply.c_str());
        if (handle == MQTT_TOPIC_HANDLE_NONE) {
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_QUEUE_FULL;
            REASON = "no topic slot left on the client";
            return;
        }
        fbHandle = (int16_t)handle;
        fbAsked = false;
    }
    // A new session needs asking again: the subscription and the request
    // belong to the connection they were made on.
    const int32_t connects = (int32_t)client->status().connects;
    if (connects != (int32_t)fbSeenConnects) {
        fbSeenConnects = connects;
        fbAsked = false;
    }

    if (!(bool)fbUsingKey) {
        // Using its own login. If the broker now says it is wrong - reset by
        // an admin, or taken over by a replacement PLC - ask again with the
        // key. The old login is KEPT until a new one is issued: it is tried
        // again every five minutes while the registration waits.
        if (badLogin && (int8_t)fbSwitchTo == 0 && KEY.length() > 0) {
            fbOldTriedAt = (int32_t)(uint32_t)now;
            fbSwitchTo = 2;
        }
        // "Not authorized" (0x87): disabled or pending - an admin's decision -
        // or a Will the login may no longer publish, because the site's group
        // changed. Connect once without the Will and ask again: if the group
        // changed, the next connect carries the new one; if the login is
        // disabled, that session is refused too, and it tries again later.
        if (notAuthorized && (int8_t)fbSwitchTo == 0 && !(bool)fbWithoutWill &&
            ((int32_t)fbLockedAt == 0 ||
             mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbLockedAt, now) >= MQ_PROVISION_REFUSED_MS)) {
            fbLockedAt = (int32_t)(uint32_t)(now | 1u);
            fbSwitchTo = 3;
        }
        if ((bool)fbWithoutWill && notAuthorized && (int8_t)fbSwitchTo == 0) {
            REFUSED = true;
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_NOT_AUTHORIZED;
            REASON = "this PLC's login is disabled or waiting for approval";
            fbSwitchTo = 1;                 // back to the normal session, Will and all; asks again later
            return;
        }

        // Connected: ask again for what the key hands its devices.
        if (client->isConnected() && !(bool)fbAsked) {
            client->subscribeTo(handle, MQ_QOS_1);
            const std::string request = base + "/request";
            const char refresh[] = "{\"refresh\":true}";
            const MqttResult asked = client->publish(request.c_str(), (const uint8_t*)refresh,
                                                     sizeof refresh - 1, MQ_QOS_1, false);
            if (mq_tolerated(asked)) {
                fbAsked = true;
                fbAskedAt = (int32_t)(uint32_t)now;
            }
        }
        uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
        size_t length = 0;
        while (client->takeMessage(handle, buffer, sizeof buffer, length)) {
            std::string status, group, prefix;
            mq_provisionField((const char*)buffer, length, "status", status);
            if (status != "ok") continue;
            // The whole set: a value the broker no longer has is gone here too.
            mq_provisionField((const char*)buffer, length, "group", group);
            mq_provisionField((const char*)buffer, length, "prefix", prefix);
            const bool moved = group.size() <= 64 && group != std::string(fbGroup.c_str(), fbGroup.length());
            if (group.size() <= 64) fbGroup = group.c_str();
            if (prefix.size() <= 127) fbPrefix = prefix.c_str();
            GROUP = fbGroup.c_str();
            PREFIX = fbPrefix.c_str();
            if (!(bool)fbWithoutWill) {
                fbLockedAt = 0;
            } else {
                // Only asking: back to the real session, with the Will on the new group.
                fbSwitchTo = 1;
                if (moved) {
                    // The group moved: that was why the Will was refused, and
                    // the next session carries it on the new one.
                    fbLockedAt = 0;
                } else {
                    // THE SAME GROUP: asking again changes nothing, so the
                    // login is fine and its Will is what the broker refuses -
                    // rights an admin changed, not the site. The hold is KEPT:
                    // cleared here, a refused session started this round again
                    // at once, over and over (134 sessions in 6 s in the rig;
                    // on a modem each one a TLS handshake), and the link never
                    // came up. It tries again when the hold is over.
                    REFUSED = true;
                    ERROR = true;
                    STATUS = MQTT_RESULT::MQTT_NOT_AUTHORIZED;
                    REASON = "the broker refuses this PLC's Will";
                }
            }
        }

        PROVISIONED = fbLoginUser.length() > 0 && client->isConnected() && !(bool)fbWithoutWill;
        PENDING = false;
        if (PROVISIONED) REFUSED = false;
        USERNAME = fbLoginUser.c_str();
        if ((int8_t)fbSwitchTo == 0 && !(bool)REFUSED) {
            ERROR = false;
            STATUS = MQTT_RESULT::MQTT_OK;
            REASON = "";
        }
        return;
    }

    // --- Connected with the key: ask for a login ---
    PROVISIONED = false;
    USERNAME = "";

    // Pending or refused, with a login kept from before: try it again every
    // five minutes - a login put back on the broker works again by itself.
    const bool keptLogin = fbLoginUser.length() > 0 && fbLoginSecret.length() > 0;
    if (keptLogin && ((bool)PENDING || (bool)REFUSED || badLogin) && (int8_t)fbSwitchTo == 0 &&
        mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbOldTriedAt, now) >= MQ_PROVISION_REFUSED_MS) {
        fbOldTriedAt = (int32_t)(uint32_t)now;
        fbSwitchTo = 1;
        return;
    }

    if (badLogin) {
        // The key itself was refused at CONNECT.
        if (!(bool)REFUSED) fbRefusedAt = (int32_t)(uint32_t)now;
        REFUSED = true;
        PENDING = false;
        ERROR = true;
        STATUS = MQTT_RESULT::MQTT_NOT_AUTHORIZED;
        REASON = "the broker refused the provisioning key";
        if (client->state() == MqttState::Idle &&
            mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbRefusedAt, now) >= MQ_PROVISION_REFUSED_MS) {
            fbRefusedAt = (int32_t)(uint32_t)now;
            client->connect();
        }
        return;
    }
    if (!client->isConnected()) return;

    const mq_time_t since = mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbAskedAt, now);
    const bool askAgain = ((bool)PENDING && since >= MQ_PROVISION_PENDING_MS) ||
                          ((bool)REFUSED && since >= MQ_PROVISION_REFUSED_MS);
    if (!(bool)fbAsked || askAgain) {
        if (!(bool)fbAsked) client->subscribeTo(handle, MQ_QOS_1);
        const std::string request = base + "/request";
        const MqttResult asked =
            client->publish(request.c_str(), (const uint8_t*)"{}", 2, MQ_QOS_1, false);
        if (mq_tolerated(asked)) {
            fbAsked = true;
            fbAskedAt = (int32_t)(uint32_t)now;
        }
    }

    uint8_t buffer[MQTT_HANDLE_PAYLOAD_MAX];
    size_t length = 0;
    while (client->takeMessage(handle, buffer, sizeof buffer, length)) {
        std::string status, user, secret, why, group, prefix;
        mq_provisionField((const char*)buffer, length, "status", status);
        if (status == "ok" && mq_provisionField((const char*)buffer, length, "username", user) &&
            mq_provisionField((const char*)buffer, length, "password", secret) &&
            !user.empty() && user.size() <= 64 && !secret.empty() && secret.size() <= 64) {
            mq_provisionField((const char*)buffer, length, "group", group);
            mq_provisionField((const char*)buffer, length, "prefix", prefix);
            fbLoginUser = user.c_str();
            fbLoginSecret = secret.c_str();
            fbGroup = group.size() <= 64 ? group.c_str() : "";
            fbPrefix = prefix.size() <= 127 ? prefix.c_str() : "";
            GROUP = fbGroup.c_str();
            PREFIX = fbPrefix.c_str();
            fbSwitchTo = 1;
            PENDING = false;
            REFUSED = false;
            ERROR = false;
            STATUS = MQTT_RESULT::MQTT_OK;
            REASON = "";
        } else if (status == "pending") {
            PENDING = true;
            REFUSED = false;
            ERROR = false;
            STATUS = MQTT_RESULT::MQTT_OK;
            REASON = "waiting for approval on the broker";
        } else {
            PENDING = false;
            REFUSED = true;
            ERROR = true;
            STATUS = MQTT_RESULT::MQTT_NOT_AUTHORIZED;
            if (!mq_provisionField((const char*)buffer, length, "reason", why)) why = "refused";
            if (why.size() > 63) why.resize(63);
            REASON = why.c_str();
        }
    }
}
