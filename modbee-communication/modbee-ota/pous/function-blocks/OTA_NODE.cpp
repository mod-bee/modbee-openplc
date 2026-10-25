(* Updates this board's firmware over MQTT. One per board, in the same task as its MQTT_CLIENT.

CLIENT          the MQTT_CLIENT to use. Must be wired.
ENABLE          take offers and run updates. Off: offers are ignored.
BASE            this node's OTA topic, e.g. 'modbee/pump-01/ota'. The server
                sends to BASE/offer, BASE/data and BASE/cmd and listens on
                BASE/req and BASE/status.
BOARD           what this hardware is called. An offer for another board is
                refused.
VERSION         this program's version, e.g. '1.4.0'. An offer for the same
                version is refused, and an older one unless ALLOW_DOWNGRADE.
AUTO_ACCEPT     start an offered update at once. Off: STATE waits at
                OTA_OFFERED for ACCEPT or REJECT.
AUTO_APPLY      reboot into a verified update at once. Off: STATE waits at
                OTA_READY for APPLY - e.g. until the machine is stopped.
ALLOW_DOWNGRADE accept an older version.
REQUIRE_SIGNED  refuse every unsigned update. Needs an OTA_SIGNING block.
CONFIRM_MODE    when the new firmware is kept for good: OTA_CONFIRM_LINK once
                MQTT is back (the default), OTA_CONFIRM_PROGRAM when CONFIRM
                is pressed, OTA_CONFIRM_BOOT straight away.
CONFIRM_TIME    not confirmed in this time: the old firmware comes back.
BUFFER          bytes in flight. 8192 suits WiFi; 32768 a cellular link,
                where a small buffer and not the link sets the speed.
STALL_TIME      no progress at all for this long, link up: give up.
RESUME_EVERY    bytes between progress records, so a power cut resumes
                instead of starting again. 0: no records.
ACCEPT, REJECT, APPLY, ABORT, CONFIRM
                the program's commands, each on its rising edge.

ACTIVE          running and listening.
STATE           where the update is - see OTA_STATE.
PROGRESS        percent downloaded.
RECEIVED, SIZE  bytes so far, and of the whole image.
JOB             the server's number for the update, the current or the last.
OFFERED         the version on offer, or of the last update.
OUTCOME         how the last update ended: OTA_SUCCESS or OTA_FAILED.
RESULT          why - OTA_ROLLED_BACK, OTA_TIMEOUT, OTA_WRONG_BOARD, ...
ERROR           the block cannot run; LAST_ERROR says why.
LAST_ERROR      in words.

---

NOTHING HERE WAITS. Flash is written by a background task below every PLC
task, and the board's boot record is only rewritten while the board starts,
before the PLC runs. Measured on the Node UIO with busy tasks on both cores:
nothing was held up while an update was checked, switched or confirmed, and
other tasks ran at most 10 ms late while one downloaded. The block's first
scan spends one deliberate ~50 ms flash erase - the first scan is not timed by
the watchdog - so a download never meets it mid-run. Put this block and its
MQTT_CLIENT in the comms task, at T#50ms or slower - never in a logic task.

THE REBOOT RESTARTS THE PLC, as any firmware update must. Retained values are
saved first. Use AUTO_APPLY := FALSE and APPLY to choose the moment.

IF THE NEW FIRMWARE IS BAD - it crashes, or never gets back onto MQTT - the
board goes back to the old firmware by itself, and RESULT says OTA_ROLLED_BACK
or OTA_NOT_CONFIRMED for that update.

A DROPPED LINK OR A POWER CUT resumes where it stopped when the same update is
offered again; the server's offer is retained for exactly this.

ONE TASK. The update arrives inside MQTT_CLIENT's scan, so this block - with
OTA_SIGNING and OTA_SPARKPLUG - runs in the client's task. In any other it does
nothing and says so on ERROR, rather than race the client.

SHARES THE CONNECTION. The image travels on BASE's own topics over the same
MQTT_CLIENT session as everything else the device says, a SPARKPLUG_NODE
included: one radio, one login.

Settings are read on the first scan. A change takes effect after a restart. *)

FUNCTION_BLOCK OTA_NODE
  VAR_INPUT
    ENABLE : BOOL := TRUE;
    BASE : STRING(96);
    BOARD : STRING(31) := 'modbee-node-uio';
    VERSION : STRING(31);
    AUTO_ACCEPT : BOOL := TRUE;
    AUTO_APPLY : BOOL := TRUE;
    ALLOW_DOWNGRADE : BOOL;
    REQUIRE_SIGNED : BOOL;
    CONFIRM_MODE : OTA_CONFIRM := OTA_CONFIRM_LINK;
    CONFIRM_TIME : TIME := T#2m;
    BUFFER : UDINT := 8192;
    STALL_TIME : TIME := T#10m;
    ACCEPT : BOOL;
    REJECT : BOOL;
    APPLY : BOOL;
    ABORT : BOOL;
    CONFIRM : BOOL;
    RESUME_EVERY : UDINT := 65536;
  END_VAR
  VAR_OUTPUT
    ACTIVE : BOOL;
    STATE : OTA_STATE;
    PROGRESS : USINT;
    RECEIVED : UDINT;
    SIZE : UDINT;
    JOB : UDINT;
    OFFERED : STRING(31);
    OUTCOME : OTA_OUTCOME;
    RESULT : OTA_RESULT;
    ERROR : BOOL;
    LAST_ERROR : STRING(64);
  END_VAR
  VAR_IN_OUT
    CLIENT : MQTT_CLIENT;
  END_VAR
  VAR
    fbContext : __XWORD;
    fbLastAccept : BOOL;
    fbLastReject : BOOL;
    fbLastApply : BOOL;
    fbLastAbort : BOOL;
    fbLastConfirm : BOOL;
    fbTask : __XWORD;
  END_VAR
#include <ModBeeMqtt.h>
#include <ModBeeOta.h>
#include <links/OtaMqttLink.h>
#include <new>
#include <string.h>

// Defined by the MQTT_CLIENT block. Declared here because every C++ POU in a
// project lands in one translation unit, in filename order.
MqttClient* mq_clientOf(strucpp::XWORD_t handle);
int32_t mq_millisOf(const strucpp::IEC_TIME& t);
strucpp::XWORD_t mq_currentTask();
bool mq_inTask(strucpp::XWORD_t owner);
// The runtime's network lock (RTOS mode) and its retain flush, both weak so
// the block also builds where they do not exist.
extern "C" void openplc_net_lock(void) __attribute__((weak));
extern "C" void openplc_net_unlock(void) __attribute__((weak));
extern "C" uint8_t runtime_retain_flush_now(void) __attribute__((weak));

// The datatypes mirror the library's enums member for member, so a value is
// cast, never translated. A mismatch is a build error, not a wrong status.
static_assert((int)OTA_STATE::OTA_IDLE == (int)OtaState::Idle &&
                  (int)OTA_STATE::OTA_TESTING == (int)OtaState::Testing &&
                  (int)OTA_STATE::OTA_CHECKING == (int)OtaState::Checking &&
                  (int)OTA_STATE::OTA_CHECKING + 1 == MODBEE_OTA_STATE_COUNT,
              "OTA_STATE must mirror OtaState");
static_assert((int)OTA_RESULT::OTA_OK == (int)OtaResult::Ok &&
                  (int)OTA_RESULT::OTA_TIMEOUT == (int)OtaResult::Timeout &&
                  (int)OTA_RESULT::OTA_NOT_CONFIRMED == (int)OtaResult::NotConfirmed &&
                  (int)OTA_RESULT::OTA_NOT_CONFIRMED + 1 == MODBEE_OTA_RESULT_COUNT,
              "OTA_RESULT must mirror OtaResult");
static_assert((int)OTA_OUTCOME::OTA_FAILED == (int)OtaOutcome::Failed,
              "OTA_OUTCOME must mirror OtaOutcome");

#if defined(ESP_PLATFORM) && defined(MODBEE_OTA_HAS_ASYNC)
#define OTA_NODE_ON_BOARD 1

// Everything one OTA_NODE owns. Made on its first scan and never freed: a
// PLC program runs until the board resets. The flash work happens on the
// worker, a FreeRTOS task below every PLC task, so a scan never waits on an
// erase - measured on the Node UIO, see the library's docs.
struct OtaNodeContext {
  OtaEsp32Target flash;
  OtaAsyncTarget target;
  OtaEsp32Worker worker;
  OtaEsp32Store store;
  OtaUpdater ota;
  OtaMqttClientLink* link = nullptr;
  MqttClient* client = nullptr;
  bool enabled = true;
  bool begun = false;
  // OtaSettings keeps pointers; these outlive it.
  char base[MODBEE_OTA_TOPIC_MAX] = {};
  char board[MODBEE_OTA_BOARD_MAX] = {};
  char version[MODBEE_OTA_VERSION_MAX] = {};

  OtaNodeContext() : target(flash), worker(target), ota(target) {}
};

// A message for this node arrives inside MQTT_CLIENT's poll, in the task
// both blocks share - the loop below refuses to run in any other.
static bool ota_nodeGate(void* context) {
  return static_cast<OtaNodeContext*>(context)->enabled;
}
static void ota_nodeEvent(void*, OtaEvent event, OtaUpdater&) {
  // The boot slot has switched and the reboot is two seconds away: the last
  // moment to keep retained values, the same path RESTART takes.
  if (event == OtaEvent::Applying && runtime_retain_flush_now) runtime_retain_flush_now();
}

static void ota_nodeCopy(char* out, size_t capacity, const char* in) {
  size_t n = in ? strlen(in) : 0;
  if (n >= capacity) n = capacity - 1;
  if (n) memcpy(out, in, n);
  out[n] = '\0';
}
#endif

void setup()
{
#if defined(OTA_NODE_ON_BOARD)
    // The run's first flash erase freezes both cores ~45 ms on an ESP32-S3
    // (measured). Spent here, on a blank sector, in the first scan - which the
    // watchdog does not time - instead of in the middle of a later download.
    ota_esp32WarmUp();
#endif
    ACTIVE = false;
    STATE = OTA_STATE::OTA_IDLE;
    OUTCOME = OTA_OUTCOME::OTA_NONE;
    RESULT = OTA_RESULT::OTA_OK;
    ERROR = false;
    LAST_ERROR = "";
}

void loop()
{
#if !defined(OTA_NODE_ON_BOARD)
    // The Runtime replaces its program, not its firmware.
    ACTIVE = false;
    ERROR = true;
    RESULT = OTA_RESULT::OTA_UNSUPPORTED;
    LAST_ERROR = "firmware updates need an ESP32 board";
#else
    // ONE TASK PER CLIENT, as for every block on an MQTT_CLIENT (see the MQTT
    // library's MQTT_ARDUINO): the update arrives inside MQTT_CLIENT's scan,
    // so this block runs in the same task or not at all - and OTA_SIGNING and
    // OTA_SPARKPLUG, which reach into this one, in this one's.
    fbTask = mq_currentTask();
    if (!mq_inTask((strucpp::XWORD_t)CLIENT.FBTASK)) {
        ACTIVE = false;
        ERROR = true;
        RESULT = OTA_RESULT::OTA_NOT_READY;
        LAST_ERROR = "put OTA_NODE in its MQTT_CLIENT's task";
        return;
    }
    if (openplc_net_lock) openplc_net_lock();
    OtaNodeContext* c = (OtaNodeContext*)(uintptr_t)(strucpp::XWORD_t)fbContext;
    if (!c) {
        c = new (std::nothrow) OtaNodeContext();
        if (!c) {
            ERROR = true;
            RESULT = OTA_RESULT::OTA_NO_MEMORY;
            LAST_ERROR = "no memory for the updater";
            if (openplc_net_unlock) openplc_net_unlock();
            return;
        }
        fbContext = (strucpp::XWORD_t)(uintptr_t)c;
    }
    c->enabled = (bool)ENABLE;

    MqttClient* client = mq_clientOf((strucpp::XWORD_t)CLIENT.FBAPI);
    bool configError = false;
    if (!client) {
        configError = true;
        RESULT = OTA_RESULT::OTA_NOT_READY;
        LAST_ERROR = "wire CLIENT to an MQTT_CLIENT";
    } else if (c->begun && client != c->client) {
        configError = true;
        RESULT = OTA_RESULT::OTA_INVALID_ARGUMENT;
        LAST_ERROR = "CLIENT changed while running - restart the PLC";
    } else if (!c->begun) {
        // The settings are read once, on the first scan with a client. A
        // firmware's version does not change while it runs; the rest take
        // effect after a restart.
        if (BASE.c_str()[0] == '\0') {
            configError = true;
            RESULT = OTA_RESULT::OTA_INVALID_ARGUMENT;
            LAST_ERROR = "set BASE, the node's OTA topic";
        } else if (VERSION.c_str()[0] == '\0') {
            configError = true;
            RESULT = OTA_RESULT::OTA_INVALID_ARGUMENT;
            LAST_ERROR = "set VERSION, this program's version";
        } else {
            ota_nodeCopy(c->base, sizeof(c->base), BASE.c_str());
            ota_nodeCopy(c->board, sizeof(c->board), BOARD.c_str());
            ota_nodeCopy(c->version, sizeof(c->version), VERSION.c_str());
            c->client = client;
            c->link = new (std::nothrow) OtaMqttClientLink(*client, c->base);
            if (c->link) c->link->gate(&ota_nodeGate, c);

            OtaSettings s;
            s.board = c->board;
            s.version = c->version;
            s.autoAccept = (bool)AUTO_ACCEPT;
            s.autoApply = (bool)AUTO_APPLY;
            s.allowDowngrade = (bool)ALLOW_DOWNGRADE;
            s.requireSignature = (bool)REQUIRE_SIGNED;
            s.confirm = CONFIRM_MODE == OTA_CONFIRM::OTA_CONFIRM_PROGRAM ? OtaConfirmPolicy::Manual
                      : CONFIRM_MODE == OTA_CONFIRM::OTA_CONFIRM_BOOT  ? OtaConfirmPolicy::OnBoot
                                                                        : OtaConfirmPolicy::OnLinkUp;
            const int32_t window = mq_millisOf(CONFIRM_TIME);
            s.confirmWindowMs = window > 0 ? (uint32_t)window : 120000;
            const int32_t stall = mq_millisOf(STALL_TIME);
            s.stallTimeoutMs = stall > 0 ? (uint32_t)stall : 600000;
            if ((uint32_t)BUFFER >= 1024) s.bufferSize = (uint32_t)BUFFER;
            s.resumeEveryBytes = (uint32_t)RESUME_EVERY;

            const bool workerStarted = c->worker.begin();
            c->ota.store(&c->store);
            if (c->link) c->ota.addLink(*c->link);
            c->ota.onEvent(&ota_nodeEvent, c);
            const OtaResult r = c->ota.begin(s);
            if (!c->link || !c->link->valid() || !workerStarted || r != OtaResult::Ok) {
                configError = true;
                RESULT = (OTA_RESULT)(int32_t)(int)(r != OtaResult::Ok ? r : OtaResult::InvalidArgument);
                LAST_ERROR = !c->link ? "no memory for the MQTT link"
                           : !c->link->valid() ? "BASE is too long"
                           : !workerStarted ? "could not start the OTA worker task"
                                            : "BOARD or VERSION too long";
            } else {
                c->begun = true;
                LAST_ERROR = "";
            }
        }
    }

    if (c->begun && !configError) {
        // The program's commands, on their rising edges.
        const bool accept = (bool)ACCEPT && !(bool)fbLastAccept;
        const bool reject = (bool)REJECT && !(bool)fbLastReject;
        const bool apply = (bool)APPLY && !(bool)fbLastApply;
        const bool abort = (bool)ABORT && !(bool)fbLastAbort;
        const bool confirm = (bool)CONFIRM && !(bool)fbLastConfirm;
        fbLastAccept = (bool)ACCEPT;
        fbLastReject = (bool)REJECT;
        fbLastApply = (bool)APPLY;
        fbLastAbort = (bool)ABORT;
        fbLastConfirm = (bool)CONFIRM;
        OtaResult asked = OtaResult::Ok;
        if (accept) asked = c->ota.accept();
        if (reject) asked = c->ota.reject();
        if (apply) asked = c->ota.apply();
        if (abort) asked = c->ota.abort();
        if (confirm) asked = c->ota.confirm();
        if (asked != OtaResult::Ok && asked != OtaResult::Pending) {
            LAST_ERROR = asked == OtaResult::NotReady ? "nothing in that state to act on"
                                                      : ota_resultName(asked);
        } else if (accept || reject || apply || abort || confirm) {
            LAST_ERROR = "";
        }

        if (c->enabled) c->ota.update();

        ACTIVE = c->enabled;
        STATE = (OTA_STATE)(int32_t)(int)c->ota.state();
        OUTCOME = (OTA_OUTCOME)(int32_t)(int)c->ota.outcome();
        RESULT = (OTA_RESULT)(int32_t)(int)c->ota.result();
        PROGRESS = (uint8_t)c->ota.progress();
        RECEIVED = (uint32_t)c->ota.received();
        SIZE = (uint32_t)c->ota.size();
        JOB = (uint32_t)c->ota.job();
        OFFERED = c->ota.image().version;
        ERROR = false;
    } else {
        ACTIVE = false;
        ERROR = configError;
    }

    if (openplc_net_unlock) openplc_net_unlock();
#endif
}


END_FUNCTION_BLOCK