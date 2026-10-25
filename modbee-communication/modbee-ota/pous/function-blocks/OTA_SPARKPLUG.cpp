(* Reports and controls this board's firmware updates over Sparkplug B. Optional: a project without it carries none of its code.

NODE       the OTA_NODE whose updates these are.
SPARKPLUG  the SPARKPLUG_NODE to report on - on the same MQTT_CLIENT, or
           another one in the same task.

ACTIVE     the metrics are declared and the node has birthed.
ERROR      something is wrong; LAST_ERROR says what - including a command the
           updater refused, e.g. "nothing in that state to act on".

---

THE IMAGE STILL TRAVELS ON OTA_NODE'S OWN TOPICS, at full speed - Sparkplug
has no file transfer. This block adds what a SCADA host needs to run an update
from its own screens, as metrics of the node:

  Firmware/Version   String  what is running
  Firmware/State     String  idle, offered, downloading, verifying, ready,
                             applying, testing, checking
  Firmware/Progress  Int32   0..100, sent as it moves
  Firmware/Offered   String  the version on offer, or of the last update
  Firmware/Status    String  the full JSON status, as BASE/status carries it

and, written by the host (NCMD) as Sparkplug node control is - TRUE to act,
reported FALSE again:

  Node Control/Firmware Accept     start an offered update (AUTO_ACCEPT off)
  Node Control/Firmware Reject     refuse it
  Node Control/Firmware Apply      reboot into a verified update (AUTO_APPLY off)
  Node Control/Firmware Abort      stop a download
  Node Control/Firmware Confirm    keep the new firmware (OTA_CONFIRM_PROGRAM)
  Node Control/Firmware Rollback   go back to the old firmware

The names are the ones OtaSparkplugLink uses, so a host reads one schema.

ONE TASK: this block, its OTA_NODE and its SPARKPLUG_NODE run in one task. *)

FUNCTION_BLOCK OTA_SPARKPLUG
  VAR_OUTPUT
    ACTIVE : BOOL;
    ERROR : BOOL;
    LAST_ERROR : STRING(64);
  END_VAR
  VAR_IN_OUT
    NODE : OTA_NODE;
    SPARKPLUG : SPARKPLUG_NODE;
  END_VAR
  VAR
    fbContext : __XWORD;
  END_VAR
#include <ModBeeOta.h>
#include <sparkplug/MqttSparkplugNode.h>
#include <new>
#include <string.h>

// Everything this block needs from OTA_NODE (OtaNodeContext, mq_inTask) is
// declared in OTA_NODE's code, which sorts before this file in the one
// translation unit every C++ POU lands in. SPARKPLUG_NODE's handle is the
// MQTT library's, defined later in that unit.
MqttSparkplugNode* mq_spNodeOf(strucpp::XWORD_t handle);
#if defined(OTA_NODE_ON_BOARD)
#define OTA_SPARKPLUG_ON_BOARD 1

// THE SAME NAMES OtaSparkplugLink USES, so a host application reads one
// schema whichever way the image travels.
#define OTA_SP_VERSION  "Firmware/Version"
#define OTA_SP_STATE    "Firmware/State"
#define OTA_SP_PROGRESS "Firmware/Progress"
#define OTA_SP_OFFERED  "Firmware/Offered"
#define OTA_SP_STATUS   "Firmware/Status"

// What a host may do, as Sparkplug does node control: one Boolean each, the
// host writes TRUE (NCMD), the node acts and reports it FALSE again.
enum OtaSpControl { OTA_SP_ACCEPT, OTA_SP_REJECT, OTA_SP_APPLY, OTA_SP_ABORT,
                    OTA_SP_CONFIRM, OTA_SP_ROLLBACK, OTA_SP_CONTROLS };
static const char* const OTA_SP_CONTROL_NAMES[OTA_SP_CONTROLS] = {
    "Node Control/Firmware Accept",  "Node Control/Firmware Reject",
    "Node Control/Firmware Apply",   "Node Control/Firmware Abort",
    "Node Control/Firmware Confirm", "Node Control/Firmware Rollback",
};

// Made once, never freed: the metrics it declared are in every birth.
struct OtaSparkplugContext {
  MqttSparkplugNode* sp = nullptr;
  int version = -1, state = -1, progress = -1, offered = -1, status = -1;
  int controls[OTA_SP_CONTROLS];
  // What was last reported, so a value goes out only when it moves.
  int lastState = -1;
  int lastProgress = -1;
  char lastOffered[MODBEE_OTA_VERSION_MAX] = {};
  char statusJson[MODBEE_OTA_STATUS_JSON_MAX] = {};
};

static bool ota_spDeclare(MqttSparkplugNode& sp, OtaSparkplugContext& c, const char* version) {
  bool ok = sp.declare(OTA_SP_VERSION, MqttSparkplugDataType::String) != 0 &&
            sp.declare(OTA_SP_STATE, MqttSparkplugDataType::String) != 0 &&
            sp.declare(OTA_SP_PROGRESS, MqttSparkplugDataType::Int32) != 0 &&
            sp.declare(OTA_SP_OFFERED, MqttSparkplugDataType::String) != 0 &&
            sp.declare(OTA_SP_STATUS, MqttSparkplugDataType::String) != 0;
  for (int i = 0; ok && i < OTA_SP_CONTROLS; i++) {
    ok = sp.declareWritable(OTA_SP_CONTROL_NAMES[i], MqttSparkplugDataType::Boolean) != 0;
  }
  if (!ok) return false;
  c.version = sp.indexOf(nullptr, OTA_SP_VERSION);
  c.state = sp.indexOf(nullptr, OTA_SP_STATE);
  c.progress = sp.indexOf(nullptr, OTA_SP_PROGRESS);
  c.offered = sp.indexOf(nullptr, OTA_SP_OFFERED);
  c.status = sp.indexOf(nullptr, OTA_SP_STATUS);
  for (int i = 0; i < OTA_SP_CONTROLS; i++) {
    c.controls[i] = sp.indexOf(nullptr, OTA_SP_CONTROL_NAMES[i]);
    sp.setAt((size_t)c.controls[i], mq_spBool(false));
  }
  // What is running does not change while it runs.
  sp.setAt((size_t)c.version, mq_spString(version));
  sp.setAt((size_t)c.state, mq_spString(ota_stateName(OtaState::Idle)));
  sp.setAt((size_t)c.progress, mq_spInt32(0));
  sp.setAt((size_t)c.offered, mq_spString(""));
  sp.setAt((size_t)c.status, mq_spString("{}"));
  return true;
}
#endif

void setup()
{
    ACTIVE = false;
    ERROR = false;
    LAST_ERROR = "";
}

void loop()
{
#if !defined(OTA_SPARKPLUG_ON_BOARD)
    ACTIVE = false;
    ERROR = true;
    LAST_ERROR = "firmware updates need an ESP32 board";
#else
    // ONE TASK: the updater is OTA_NODE's and the metrics SPARKPLUG_NODE's,
    // and both are touched here - so all three run in the one network task.
    if (!mq_inTask((strucpp::XWORD_t)NODE.FBTASK) ||
        !mq_inTask((strucpp::XWORD_t)SPARKPLUG.FBTASK)) {
        ACTIVE = false;
        ERROR = true;
        LAST_ERROR = "put OTA_SPARKPLUG in its OTA_NODE's task";
        return;
    }

    OtaNodeContext* node = (OtaNodeContext*)(uintptr_t)(strucpp::XWORD_t)NODE.FBCONTEXT;
    MqttSparkplugNode* sp = mq_spNodeOf((strucpp::XWORD_t)SPARKPLUG.FBAPI);
    if (!node || !node->begun || !sp) {
        // Either block may run after this one in a scan; nothing to do yet.
        ACTIVE = false;
        ERROR = false;
        LAST_ERROR = "waiting for OTA_NODE and SPARKPLUG_NODE";
        return;
    }

    OtaSparkplugContext* c = (OtaSparkplugContext*)(uintptr_t)(strucpp::XWORD_t)fbContext;
    if (!c) {
        c = new (std::nothrow) OtaSparkplugContext();
        if (!c) {
            ERROR = true;
            LAST_ERROR = "no memory for the Firmware metrics";
            return;
        }
        if (!ota_spDeclare(*sp, *c, node->version)) {
            // A name already declared - a second OTA_SPARKPLUG on the node -
            // or the node out of memory for metrics.
            delete c;
            ERROR = true;
            LAST_ERROR = "could not declare the Firmware metrics";
            return;
        }
        c->sp = sp;
        fbContext = (strucpp::XWORD_t)(uintptr_t)c;
    }
    if (c->sp != sp) {
        ERROR = true;
        LAST_ERROR = "SPARKPLUG changed while running - restart the PLC";
        return;
    }

    // --- The host's commands ---
    MqttSparkplugValue value;
    for (int i = 0; i < OTA_SP_CONTROLS; i++) {
        if (!sp->takeAt((size_t)c->controls[i], value)) continue;
        sp->setAt((size_t)c->controls[i], mq_spBool(false));
        if (value.asNumber() == 0.0) continue;   // FALSE asks for nothing
        OtaResult r = OtaResult::Ok;
        switch (i) {
        case OTA_SP_ACCEPT:   r = node->ota.accept(); break;
        case OTA_SP_REJECT:   r = node->ota.reject(); break;
        case OTA_SP_APPLY:    r = node->ota.apply(); break;
        case OTA_SP_ABORT:    r = node->ota.abort(); break;
        case OTA_SP_CONFIRM:  r = node->ota.confirm(); break;
        case OTA_SP_ROLLBACK: r = node->ota.rollback(); break;
        }
        LAST_ERROR = (r == OtaResult::Ok || r == OtaResult::Pending) ? ""
                   : r == OtaResult::NotReady ? "nothing in that state to act on"
                                              : ota_resultName(r);
    }

    // --- Where the update is, when it moves ---
    //
    // Progress in whole percent, so a download sends at most a hundred of
    // them; the full status with each state change, as the MQTT status topic
    // carries it.
    const int state = (int)node->ota.state();
    const int progress = (int)node->ota.progress();
    const char* offered = node->ota.image().version;
    bool moved = false;
    if (state != c->lastState) {
        c->lastState = state;
        sp->setAt((size_t)c->state, mq_spString(ota_stateName((OtaState)state)));
        if (ota_writeStatusJson(node->ota.status(), c->statusJson, sizeof(c->statusJson)) > 0) {
            sp->setAt((size_t)c->status, mq_spString(c->statusJson));
        }
        moved = true;
    }
    if (progress != c->lastProgress) {
        c->lastProgress = progress;
        sp->setAt((size_t)c->progress, mq_spInt32(progress));
        moved = true;
    }
    if (strncmp(offered, c->lastOffered, sizeof(c->lastOffered)) != 0) {
        strncpy(c->lastOffered, offered, sizeof(c->lastOffered) - 1);
        sp->setAt((size_t)c->offered, mq_spString(c->lastOffered));
        moved = true;
    }
    if (moved && sp->isBorn()) sp->publishChanged();

    ACTIVE = sp->isBorn();
    ERROR = false;
#endif
}


END_FUNCTION_BLOCK