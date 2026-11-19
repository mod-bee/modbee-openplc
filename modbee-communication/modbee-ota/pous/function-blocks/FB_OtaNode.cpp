(* Updates this board's firmware over MQTT. One per board, in the same task as its FB_MqttClient.

fbClient        the FB_MqttClient to use. Must be wired.
bEnable         take offers and run updates. FALSE: offers are ignored.
sBaseTopic      this node's OTA topic, e.g. 'modbee/pump-01/ota'. The server
                sends to <sBaseTopic>/offer, /data and /cmd and listens on
                <sBaseTopic>/req and /status.
sBoardName      what this hardware is called. An offer for another board is
                refused.
sFirmwareVersion  this firmware build's version, e.g. '1.4.0'. An offer for the same
                version is refused, and an older one unless bAllowDowngrade.
bAutoAccept     start an offered update at once. FALSE: eState waits at
                E_OtaState.Offered for bAcceptOffer or bRejectOffer.
bAutoApply      reboot into a verified update at once. FALSE: eState waits at
                E_OtaState.Ready for bApplyUpdate - e.g. until the machine is stopped.
bAllowDowngrade accept an older version.
eConfirmMode    when the new firmware is kept for good: E_OtaConfirmMode.OnLinkUp
                once MQTT is back (the default), .Manual on a rising edge of
                bConfirmNewFirmware, .OnBoot straight away.
tConfirmTimeout not confirmed in this time: the old firmware comes back.
nDownloadBufferBytes  bytes asked for at a time. 8192 suits Wi-Fi; 32768 a cellular link,
                where a small buffer and not the link sets the speed.
tStallTimeout   no progress at all for this long, link up: give up.
nProgressSaveBytes  bytes between saved progress points, so a power cut
                resumes instead of starting again. 0: none saved.
stSigningConfig only firmware signed with your key installs - see SIGNING.
                The defaults check no signature.
bAcceptOffer, bRejectOffer, bApplyUpdate, bAbortUpdate, bConfirmNewFirmware
                the program's commands, each on its rising edge.

bUpdaterRunning  the updater runs and takes offers.
eState          where the update is - see E_OtaState.
nProgressPct    percent downloaded.
nBytesReceived, nFirmwareSizeBytes  bytes so far, and of the whole image.
nUpdateJobNumber  the server's number for the update, the current or the last.
sOfferedVersion  the version on offer, or of the last update.
eLastOutcome    how the last update ended: E_OtaOutcome.Success or .Failed.
eLastOutcomeReason  why - E_OtaResult.RolledBack, .Timeout, .WrongBoard, ...
bSignatureCheckActive  stSigningConfig's key is in use: every update is checked.
bError          the block cannot run, or stSigningConfig's key cannot be used.
eErrorId        why. E_OtaResult.Ok when fine.
sLastError      in words, and a command the updater refused, e.g. "bApplyUpdate:
                no verified update waiting".

METHOD Sparkplug(fbNode := sp) reports the update as Sparkplug B metrics of
fbNode and takes the host's commands - see OVER SPARKPLUG.

---

NOTHING HERE WAITS. Flash is written by a background task below every PLC
task, and the board's boot record is only rewritten while the board starts,
before the PLC runs. Measured on the Node UIO with busy tasks on both cores:
nothing was held up while an update was checked, switched or confirmed, and
other tasks ran at most 10 ms late while one downloaded. The block's first
scan spends one deliberate ~50 ms flash erase - the first scan is not timed by
the watchdog - so a download never meets it mid-run. Put this block and its
FB_MqttClient in the comms task, at T#50ms or slower - never in a logic task.

THE REBOOT RESTARTS THE PLC, as any firmware update must. Retained values are
saved first. Use bAutoApply := FALSE and bApplyUpdate to choose the moment.

IF THE NEW FIRMWARE IS BAD - it crashes, or never gets back onto MQTT - the
board goes back to the old firmware by itself, and eLastOutcomeReason says
E_OtaResult.RolledBack or .NotConfirmed for that update.

A DROPPED LINK OR A POWER CUT resumes where it stopped when the same update is
offered again; the server's offer is retained for exactly this.

SIGNING. Without a key the node checks that an update arrived whole and is for
this board - not who made it: anyone able to publish to sBaseTopic could
install their own firmware. With stSigningConfig.sPublicKey only firmware
signed by the holder of the private key installs, and an unsigned one is
refused; the private key never leaves the PC that signs the releases. A key
that only arrives after the first scan (from retained memory, an HMI) is taken
when it does; bRequireSignedFirmware refuses every update until then. A key that is
set but cannot be used (not 128 hex characters, or the board cannot check
signatures) fails safe: no update is taken until it is fixed, and bError says
why. The check takes
about 160 ms on a Node UIO and runs in the background, never in a scan.

OVER SPARKPLUG. The image always travels on sBaseTopic's own topics, at full
speed - Sparkplug has no file transfer. Called every scan,
ota.Sparkplug(fbNode := sp) adds what a SCADA host needs to run an update
from its own screens, as metrics of the node:

  Firmware/Version   String  what is running
  Firmware/State     String  idle, offered, downloading, verifying, ready,
                             applying, testing, checking
  Firmware/Progress  Int32   0..100, sent as it moves
  Firmware/Offered   String  the version on offer, or of the last update
  Firmware/Status    String  the full JSON status, as <sBaseTopic>/status
                             carries it

and, written by the host (NCMD) as Sparkplug node control is - TRUE to act,
reported FALSE again:

  Node Control/Firmware Accept     start an offered update (bAutoAccept FALSE)
  Node Control/Firmware Reject     refuse it
  Node Control/Firmware Apply      reboot into a verified update (bAutoApply FALSE)
  Node Control/Firmware Abort      stop a download
  Node Control/Firmware Confirm    keep the new firmware (E_OtaConfirmMode.Manual)
  Node Control/Firmware Rollback   go back to the old firmware

The names are the ones OtaSparkplugLink uses, so a host reads one schema. A
program that never calls Sparkplug carries none of its code.

ONE TASK. The update arrives inside FB_MqttClient's scan, so this block and
its Sparkplug method run in the client's task, with the FB_SparkplugNode.
In any other they do nothing and say E_OtaResult.WrongTask, rather than race
the client.

SHARES THE CONNECTION. The image travels on sBaseTopic's own topics over the
same FB_MqttClient session as everything else the device says, an
FB_SparkplugNode included: one radio, one login.

ESP32 BOARDS ONLY. On the Runtime the block reports E_OtaResult.Unsupported:
the Runtime replaces its program, not its firmware.

Settings are read on the first scan. A change takes effect after a restart. *)

FUNCTION_BLOCK FB_OtaNode
  VAR_INPUT
    bEnable         : BOOL := TRUE;         (* take offers and run updates; FALSE ignores offers *)
    sBaseTopic      : STRING(96);           (* this node's OTA topic, e.g. 'modbee/pump-01/ota' *)
    sBoardName : STRING(31) := 'modbee-node-uio'; (* what this hardware is called; an offer for another board is refused *)
    sFirmwareVersion : STRING(31); (* the version of this firmware build, e.g. '1.4.0'; same or older offers are refused *)
    bAutoAccept : BOOL := TRUE; (* start an offered update at once; FALSE waits at Offered for bAcceptOffer *)
    bAutoApply : BOOL := TRUE; (* reboot into a verified update at once; FALSE waits at Ready for bApplyUpdate *)
    bAllowDowngrade : BOOL; (* accept an older version *)
    eConfirmMode : E_OtaConfirmMode := E_OtaConfirmMode.OnLinkUp; (* when the new firmware is kept: MQTT back (default), bConfirmNewFirmware, or at boot *)
    tConfirmTimeout : TIME := T#2m; (* not confirmed within this time: the old firmware comes back; default T#2m *)
    nDownloadBufferBytes : UDINT := 8192; (* bytes requested at a time; 8192 for Wi-Fi, 32768 for cellular *)
    tStallTimeout : TIME := T#10m; (* no progress for this long with the link up: give up; default T#10m *)
    nProgressSaveBytes : UDINT := 65536; (* bytes downloaded between saved progress points, so a power cut resumes; 0 = none *)
    stSigningConfig : ST_OtaSigningConfig; (* the public key firmware must be signed with; default no check *)
    bAcceptOffer : BOOL; (* rising edge starts the offered update *)
    bRejectOffer : BOOL; (* rising edge refuses the offered update *)
    bApplyUpdate : BOOL; (* rising edge reboots into the verified update *)
    bAbortUpdate : BOOL; (* rising edge stops an update before the reboot *)
    bConfirmNewFirmware : BOOL; (* rising edge keeps the new firmware (Manual confirm mode) *)
  END_VAR
  VAR_IN_OUT
    fbClient : FB_MqttClient; (* the connection the update travels on *)
  END_VAR
  VAR_OUTPUT
    bUpdaterRunning : BOOL; (* the updater runs and takes offers: built, bEnable TRUE, no error *)
    eState : E_OtaState; (* where the update is: Idle, Offered, Downloading, Verifying, Ready, Applying, Testing, Checking *)
    nProgressPct : USINT; (* percent downloaded *)
    nBytesReceived : UDINT; (* bytes downloaded so far *)
    nFirmwareSizeBytes : UDINT; (* size of the whole firmware image *)
    nUpdateJobNumber : UDINT; (* the server's number for the current or last update *)
    sOfferedVersion : STRING(31); (* the version on offer, or of the last update *)
    eLastOutcome : E_OtaOutcome; (* how the last update ended: Success or Failed *)
    eLastOutcomeReason : E_OtaResult; (* why the last update ended so, e.g. RolledBack, Timeout, WrongBoard *)
    bSignatureCheckActive : BOOL; (* stSigningConfig's key is in use: every update is checked *)
    bError : BOOL; (* the block cannot run, or the signing key cannot be used *)
    eErrorId : E_OtaResult; (* why; Ok when fine *)
    sLastError : STRING(64); (* why in words, or a command the updater refused *)
  END_VAR
  VAR
    nContext        : __XWORD;              (* the updater, made on the first scan *)
    nSparkplug      : __XWORD;              (* the Firmware metrics, made on Sparkplug's first call *)
    nTask           : __XWORD;              (* the task this block runs in *)
    bLastAccept     : BOOL;
    bLastReject     : BOOL;
    bLastApply      : BOOL;
    bLastAbort      : BOOL;
    bLastConfirm    : BOOL;
  END_VAR
(* The update as Sparkplug B metrics of fbNode, and the host's Node Control
   commands, called every scan. Ok while the metrics are declared and fbNode
   is born; NotReady while either block is still starting. *)
METHOD PUBLIC Sparkplug : E_OtaResult
  VAR_IN_OUT
    fbNode          : FB_SparkplugNode;     (* the Sparkplug node to report the update on *)
  END_VAR
  VAR_OUTPUT
    eLastHostCommandResult      : E_OtaResult;          (* the updater's answer to the last host command *)
    nHostCommandCount         : DINT;                 (* host commands taken *)
  END_VAR
END_METHOD

#include <ModBeeMqtt.h>
#include <sparkplug/MqttSparkplugNode.h>
#include <ModBeeOta.h>
#include <links/OtaMqttLink.h>
#include <verifiers/OtaEcdsaP256Verifier.h>
#include <new>
#include <string.h>

// Defined by FB_MqttClient and FB_SparkplugNode. Every C++ POU of a project
// lands in one translation unit; declared here so this file need not come
// after theirs (today the modbee-mqtt blocks come first).
MqttClient* mq_clientOf(strucpp::XWORD_t handle);
MqttSparkplugNode* mq_spNodeOf(strucpp::XWORD_t handle);
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
static_assert((int)E_OTASTATE::IDLE == (int)OtaState::Idle &&
                  (int)E_OTASTATE::TESTING == (int)OtaState::Testing &&
                  (int)E_OTASTATE::CHECKING == (int)OtaState::Checking &&
                  (int)E_OTASTATE::CHECKING + 1 == MODBEE_OTA_STATE_COUNT,
              "E_OtaState must mirror OtaState");
// WrongTask is the PLC's own, one past the library's last result.
static_assert((int)E_OTARESULT::OK == (int)OtaResult::Ok &&
                  (int)E_OTARESULT::TIMEOUT == (int)OtaResult::Timeout &&
                  (int)E_OTARESULT::NOTCONFIRMED == (int)OtaResult::NotConfirmed &&
                  (int)E_OTARESULT::WRONGTASK == MODBEE_OTA_RESULT_COUNT,
              "E_OtaResult must mirror OtaResult");
static_assert((int)E_OTAOUTCOME::FAILED == (int)OtaOutcome::Failed,
              "E_OtaOutcome must mirror OtaOutcome");

#if defined(ESP_PLATFORM) && defined(MODBEE_OTA_HAS_ASYNC)
#define OTA_ON_BOARD 1

#if defined(MODBEE_OTA_HAS_ECDSA) && defined(MODBEE_OTA_HAS_ASYNC_VERIFIER)
#define OTA_SIGNS_ON_BOARD 1
// The check takes ~160 ms on the Node UIO, so it runs on the node's OTA
// worker, never in a scan. Made once, never freed.
struct OtaSigningContext {
  OtaEcdsaP256Verifier ecdsa;
  OtaAsyncVerifier async;
  explicit OtaSigningContext(const uint8_t key[64]) : ecdsa(key), async(ecdsa) {}
};
#endif

// Everything one FB_OtaNode owns. Made on its first scan and never freed: a
// PLC program runs until the board resets. Flash work runs on the worker, a
// FreeRTOS task below every PLC task, so a scan never waits on an erase.
struct OtaNodeContext {
  OtaEsp32Target flash;
  OtaAsyncTarget target;
  OtaEsp32Worker worker;
  OtaEsp32Store store;
  OtaUpdater ota;
  OtaMqttClientLink* link = nullptr;
  MqttClient* client = nullptr;
  bool enabled = true;
  bool keyUnusable = false;   // a key is set but cannot be used: no update is taken
  bool begun = false;
  bool signing = false;  // a verifier is attached
  // OtaSettings keeps pointers; these outlive it.
  char base[MODBEE_OTA_TOPIC_MAX] = {};
  char board[MODBEE_OTA_BOARD_MAX] = {};
  char version[MODBEE_OTA_VERSION_MAX] = {};

  OtaNodeContext() : target(flash), worker(target), ota(target) {}
};

// A message for this node arrives inside FB_MqttClient's poll, in the task
// both blocks share - the loop below refuses to run in any other.
static bool ota_nodeGate(void* context) {
  const OtaNodeContext* c = static_cast<OtaNodeContext*>(context);
  return c->enabled && !c->keyUnusable;
}
static void ota_nodeEvent(void*, OtaEvent event, OtaUpdater&) {
  // The boot slot has switched and the reboot is two seconds away: the last
  // moment to keep retained values, the same path node-uio's FB_Restart takes.
  if (event == OtaEvent::Applying && runtime_retain_flush_now) runtime_retain_flush_now();
}

static void ota_nodeCopy(char* out, size_t capacity, const char* in) {
  size_t n = in ? strlen(in) : 0;
  if (n >= capacity) n = capacity - 1;
  if (n) memcpy(out, in, n);
  out[n] = '\0';
}

// Attaches stSigningConfig's key to a started updater. Ok once attached,
// NotReady while there is no key, otherwise why it cannot be used.
static OtaResult ota_nodeSign(OtaNodeContext& c, const char* hex) {
  if (c.signing) return OtaResult::Ok;
  if (!hex || hex[0] == '\0') return OtaResult::NotReady;
#if defined(OTA_SIGNS_ON_BOARD)
  // The P-256 point, X then Y, as 128 hex characters.
  uint8_t key[64];
  if (strlen(hex) != 128 || ota_fromHex(hex, 128, key, sizeof(key)) != 64) {
    return OtaResult::InvalidArgument;
  }
  OtaSigningContext* s = new (std::nothrow) OtaSigningContext(key);
  if (!s) return OtaResult::NoMemory;
  if (!c.worker.add(s->async)) {
    delete s;
    return OtaResult::NoMemory;
  }
  c.ota.verifier(&s->async);
  c.signing = true;
  return OtaResult::Ok;
#else
  return OtaResult::Unsupported;
#endif
}

// --- Sparkplug ---
//
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
  OtaResult cmdResult = OtaResult::Ok;
  int32_t cmdCount = 0;
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

// A refused command, in words: NotReady names the command and what it needs.
static const char* ota_nodeRefusal(OtaResult r, const char* notReady) {
  return r == OtaResult::NotReady ? notReady : ota_resultName(r);
}
#endif

void setup()
{
#if defined(OTA_ON_BOARD)
    // The run's first flash erase freezes both cores ~45 ms on an ESP32-S3
    // (measured). Spent here, on a blank sector, in the first scan - which the
    // watchdog does not time - instead of in the middle of a later download.
    ota_esp32WarmUp();
#endif
    bUpdaterRunning = false;
    eState = E_OTASTATE::IDLE;
    eLastOutcome = E_OTAOUTCOME::NONE;
    eLastOutcomeReason = E_OTARESULT::OK;
    bSignatureCheckActive = false;
    bError = false;
    eErrorId = E_OTARESULT::OK;
    sLastError = "";
}

void loop()
{
#if !defined(OTA_ON_BOARD)
    // The Runtime replaces its program, not its firmware.
    bUpdaterRunning = false;
    bError = true;
    eLastOutcomeReason = E_OTARESULT::UNSUPPORTED;
    eErrorId = E_OTARESULT::UNSUPPORTED;
    sLastError = "firmware updates need an ESP32 board";
#else
    // ONE TASK PER CLIENT, as for every block on an FB_MqttClient: the update
    // arrives inside the client's scan, so this block - and its Sparkplug
    // method - runs in the same task or not at all.
    nTask = mq_currentTask();
    if (!mq_inTask((strucpp::XWORD_t)fbClient.NTASK)) {
        bUpdaterRunning = false;
        bError = true;
        eLastOutcomeReason = E_OTARESULT::NOTREADY;
        eErrorId = E_OTARESULT::WRONGTASK;
        sLastError = "put FB_OtaNode in its FB_MqttClient's task";
        return;
    }
    if (openplc_net_lock) openplc_net_lock();
    OtaNodeContext* c = (OtaNodeContext*)(uintptr_t)(strucpp::XWORD_t)nContext;
    if (!c) {
        c = new (std::nothrow) OtaNodeContext();
        if (!c) {
            bError = true;
            eLastOutcomeReason = E_OTARESULT::NOMEMORY;
            eErrorId = E_OTARESULT::NOMEMORY;
            sLastError = "no memory for the updater";
            if (openplc_net_unlock) openplc_net_unlock();
            return;
        }
        nContext = (strucpp::XWORD_t)(uintptr_t)c;
    }
    c->enabled = (bool)bEnable;

    MqttClient* client = mq_clientOf((strucpp::XWORD_t)fbClient.NAPI);
    bool configError = false;
    if (!client) {
        configError = true;
        eLastOutcomeReason = E_OTARESULT::NOTREADY;
        sLastError = "wire fbClient to an FB_MqttClient";
    } else if (c->begun && client != c->client) {
        configError = true;
        eLastOutcomeReason = E_OTARESULT::INVALIDARGUMENT;
        sLastError = "fbClient changed while running - restart the PLC";
    } else if (!c->begun) {
        // The settings are read once, on the first scan with a client. A
        // firmware's version does not change while it runs; the rest take
        // effect after a restart.
        if (sBaseTopic.c_str()[0] == '\0') {
            configError = true;
            eLastOutcomeReason = E_OTARESULT::INVALIDARGUMENT;
            sLastError = "set sBaseTopic, the node's OTA topic";
        } else if (sFirmwareVersion.c_str()[0] == '\0') {
            configError = true;
            eLastOutcomeReason = E_OTARESULT::INVALIDARGUMENT;
            sLastError = "set sFirmwareVersion, this firmware's version";
        } else {
            ota_nodeCopy(c->base, sizeof(c->base), sBaseTopic.c_str());
            ota_nodeCopy(c->board, sizeof(c->board), sBoardName.c_str());
            ota_nodeCopy(c->version, sizeof(c->version), sFirmwareVersion.c_str());
            c->client = client;
            c->link = new (std::nothrow) OtaMqttClientLink(*client, c->base);
            if (c->link) c->link->gate(&ota_nodeGate, c);

            OtaSettings s;
            s.board = c->board;
            s.version = c->version;
            s.autoAccept = (bool)bAutoAccept;
            s.autoApply = (bool)bAutoApply;
            s.allowDowngrade = (bool)bAllowDowngrade;
            s.requireSignature = (bool)stSigningConfig.BREQUIRESIGNEDFIRMWARE;
            s.confirm = eConfirmMode == E_OTACONFIRMMODE::MANUAL ? OtaConfirmPolicy::Manual
                      : eConfirmMode == E_OTACONFIRMMODE::ONBOOT  ? OtaConfirmPolicy::OnBoot
                                                                  : OtaConfirmPolicy::OnLinkUp;
            const int32_t window = mq_millisOf(tConfirmTimeout);
            s.confirmWindowMs = window > 0 ? (uint32_t)window : 120000;
            const int32_t stall = mq_millisOf(tStallTimeout);
            s.stallTimeoutMs = stall > 0 ? (uint32_t)stall : 600000;
            if ((uint32_t)nDownloadBufferBytes >= 1024) s.bufferSize = (uint32_t)nDownloadBufferBytes;
            s.resumeEveryBytes = (uint32_t)nProgressSaveBytes;

            const bool workerStarted = c->worker.begin();
            c->ota.store(&c->store);
            if (c->link) c->ota.addLink(*c->link);
            c->ota.onEvent(&ota_nodeEvent, c);
            const OtaResult r = c->ota.begin(s);
            if (!c->link || !c->link->valid() || !workerStarted || r != OtaResult::Ok) {
                configError = true;
                eLastOutcomeReason = (E_OTARESULT)(int32_t)(int)(r != OtaResult::Ok ? r : OtaResult::InvalidArgument);
                sLastError = !c->link ? "no memory for the MQTT link"
                           : !c->link->valid() ? "sBaseTopic is too long"
                           : !workerStarted ? "could not start the OTA worker task"
                                            : "sBoardName or sFirmwareVersion too long";
            } else {
                c->begun = true;
                sLastError = "";
            }
        }
    }

    if (c->begun && !configError) {
        // The signing key, as soon as there is one: before the first offer
        // when it is set in the declaration, later when it arrives later.
        const OtaResult signedBy = ota_nodeSign(*c, stSigningConfig.SPUBLICKEY.c_str());
        const bool keyError = signedBy != OtaResult::Ok && signedBy != OtaResult::NotReady;
        // A key that is set but cannot be used fails safe: no update is taken
        // until it is fixed, whatever bRequireSignedFirmware says. Unsigned firmware
        // must never install because a key was mistyped.
        c->keyUnusable = keyError;

        // The program's commands, on their rising edges.
        const bool accept = (bool)bAcceptOffer && !(bool)bLastAccept;
        const bool reject = (bool)bRejectOffer && !(bool)bLastReject;
        const bool apply = (bool)bApplyUpdate && !(bool)bLastApply;
        const bool abort = (bool)bAbortUpdate && !(bool)bLastAbort;
        const bool confirm = (bool)bConfirmNewFirmware && !(bool)bLastConfirm;
        bLastAccept = (bool)bAcceptOffer;
        bLastReject = (bool)bRejectOffer;
        bLastApply = (bool)bApplyUpdate;
        bLastAbort = (bool)bAbortUpdate;
        bLastConfirm = (bool)bConfirmNewFirmware;
        OtaResult asked = OtaResult::Ok;
        const char* askedText = "";
        if (accept) { asked = c->ota.accept(); askedText = "bAcceptOffer: no update on offer"; }
        if (reject) { asked = c->ota.reject(); askedText = "bRejectOffer: no update on offer"; }
        if (apply) { asked = c->ota.apply(); askedText = "bApplyUpdate: no verified update waiting"; }
        if (abort) { asked = c->ota.abort(); askedText = "bAbortUpdate: no update to stop"; }
        if (confirm) { asked = c->ota.confirm(); askedText = "bConfirmNewFirmware: no new firmware on trial"; }
        if (asked != OtaResult::Ok && asked != OtaResult::Pending) {
            sLastError = ota_nodeRefusal(asked, askedText);
        } else if (accept || reject || apply || abort || confirm) {
            sLastError = "";
        }

        if (c->enabled) c->ota.update();

        bUpdaterRunning = c->enabled;
        eState = (E_OTASTATE)(int32_t)(int)c->ota.state();
        eLastOutcome = (E_OTAOUTCOME)(int32_t)(int)c->ota.outcome();
        eLastOutcomeReason = (E_OTARESULT)(int32_t)(int)c->ota.result();
        nProgressPct = (uint8_t)c->ota.progress();
        nBytesReceived = (uint32_t)c->ota.received();
        nFirmwareSizeBytes = (uint32_t)c->ota.size();
        nUpdateJobNumber = (uint32_t)c->ota.job();
        sOfferedVersion = c->ota.image().version;
        bSignatureCheckActive = c->signing;
        bError = keyError;
        eErrorId = (E_OTARESULT)(int32_t)(int)(keyError ? signedBy : OtaResult::Ok);
        if (keyError) {
            sLastError = signedBy == OtaResult::InvalidArgument
                             ? "sPublicKey is not 128 hex characters: no update is taken until it is fixed"
                         : signedBy == OtaResult::NoMemory ? "no memory for the signature check: no update is taken"
                                                           : "this board cannot check signatures: no update is taken";
        }
    } else {
        bUpdaterRunning = false;
        bError = configError;
        eErrorId = configError ? (E_OTARESULT)eLastOutcomeReason : E_OTARESULT::OK;
    }

    if (openplc_net_unlock) openplc_net_unlock();
#endif
}

// ota.Sparkplug(fbNode := sp): a standing method, called every scan while
// the update is to be reported on sp.
E_OTARESULT Sparkplug()
{
#if !defined(OTA_ON_BOARD)
    (void)fbNode;
    eLastHostCommandResult = E_OTARESULT::OK;
    nHostCommandCount = 0;
    return E_OTARESULT::UNSUPPORTED;
#else
    OtaSparkplugContext* c = (OtaSparkplugContext*)(uintptr_t)(strucpp::XWORD_t)nSparkplug;
    eLastHostCommandResult = (E_OTARESULT)(int32_t)(int)(c ? c->cmdResult : OtaResult::Ok);
    nHostCommandCount = c ? c->cmdCount : 0;

    // ONE TASK: the updater is this block's and the metrics fbNode's, and
    // both are touched here - so all three run in the one network task.
    if (!mq_inTask((strucpp::XWORD_t)nTask) || !mq_inTask((strucpp::XWORD_t)fbNode.NTASK)) {
        return E_OTARESULT::WRONGTASK;
    }
    OtaNodeContext* node = (OtaNodeContext*)(uintptr_t)(strucpp::XWORD_t)nContext;
    MqttSparkplugNode* sp = mq_spNodeOf((strucpp::XWORD_t)fbNode.NAPI);
    if (!node || !node->begun || !sp) {
        // Either block may not have started yet; nothing to do until both have.
        return E_OTARESULT::NOTREADY;
    }

    if (!c) {
        c = new (std::nothrow) OtaSparkplugContext();
        if (!c) return E_OTARESULT::NOMEMORY;
        if (!ota_spDeclare(*sp, *c, node->version)) {
            // A name already declared - a second FB_OtaNode on the node - or
            // the node out of memory for metrics. Tried again next call.
            delete c;
            return E_OTARESULT::INVALIDARGUMENT;
        }
        c->sp = sp;
        nSparkplug = (strucpp::XWORD_t)(uintptr_t)c;
    }
    if (c->sp != sp) return E_OTARESULT::INVALIDARGUMENT;   // fbNode changed while running

    // --- The host's commands ---
    MqttSparkplugValue value;
    for (int i = 0; i < OTA_SP_CONTROLS; i++) {
        if (!sp->takeAt((size_t)c->controls[i], value)) continue;
        sp->setAt((size_t)c->controls[i], mq_spBool(false));
        if (value.asNumber() == 0.0) continue;   // FALSE asks for nothing
        OtaResult r = OtaResult::Ok;
        const char* what = "";
        switch (i) {
        case OTA_SP_ACCEPT:   r = node->ota.accept();   what = "Firmware Accept: no update on offer"; break;
        case OTA_SP_REJECT:   r = node->ota.reject();   what = "Firmware Reject: no update on offer"; break;
        case OTA_SP_APPLY:    r = node->ota.apply();    what = "Firmware Apply: no verified update waiting"; break;
        case OTA_SP_ABORT:    r = node->ota.abort();    what = "Firmware Abort: no update to stop"; break;
        case OTA_SP_CONFIRM:  r = node->ota.confirm();  what = "Firmware Confirm: no new firmware on trial"; break;
        case OTA_SP_ROLLBACK: r = node->ota.rollback(); what = "Firmware Rollback: not possible now"; break;
        }
        if (r == OtaResult::Pending) r = OtaResult::Ok;
        c->cmdResult = r;
        c->cmdCount++;
        sLastError = r == OtaResult::Ok ? "" : ota_nodeRefusal(r, what);
    }
    eLastHostCommandResult = (E_OTARESULT)(int32_t)(int)c->cmdResult;
    nHostCommandCount = c->cmdCount;

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

    return sp->isBorn() ? E_OTARESULT::OK : E_OTARESULT::NOTREADY;
#endif
}

END_FUNCTION_BLOCK