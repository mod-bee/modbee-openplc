(* SETS THE CONTROLLER'S CLOCK FROM THE NETWORK - NTP over Wi-Fi or Ethernet,
the mobile network's own time over cellular - so Sparkplug timestamps and
CURRENT_DT are real time. One per controller, called every scan in the
network task. Standalone: it takes no FB_MqttClient.

eTimeSource  where the time comes from - the same list as FB_MqttClient, so a
           site that moves from Wi-Fi to cellular changes one pin on each:
             E_MqttTransport.RuntimeTcp       the Runtime's own clock, which
                                              its operating system keeps.
                                              Nothing is set
             E_MqttTransport.ArduinoWiFi      NTP from sNtpServer, through the
             E_MqttTransport.ArduinoEthernet  board's IP stack (ESP32).
                                              node-uio's NETWORK or the
                                              FB_MqttClient brings the
                                              network up; this waits for it
             E_MqttTransport.Cellular         the mobile network's time
                                              (NITZ) from the modem a
                                              modbee-gsm modem block runs.
                                              Costs no data. Not every
                                              network sends it
             E_MqttTransport.External         dtExternalUtc, when bExternalUtcValid - an
                                              RTC, the modem's NetworkTime UTC, a time a
                                              SCADA wrote
sNtpServer  the NTP server. 'pool.ntp.org' by default; a site with its own (a
           router, a SCADA server) should use it.
tResyncInterval  how often to ask again. T#1h by default - a board's crystal
           drifts a second or two a day, so hourly is plenty.
dtExternalUtc  E_MqttTransport.External: the time to set, in UTC.
bExternalUtcValid E_MqttTransport.External: dtExternalUtc is good. Its rising edge sets
           the clock, and again every tResyncInterval while it stays TRUE.
bEnable     FALSE stops asking. The clock keeps the time it has.

bClockSynced  the clock holds real time - a date after 2024. Exactly what
           FB_SparkplugNode's bClockSynced reports.
dtClockUtc       the time now, in UTC. DT#1970-01-01 while not bClockSynced.
tSinceLastSync  how long since the clock was last set. Grows while the network
           is away - the clock keeps running on its own crystal meanwhile.
bError      the transport cannot give the time on this target, or NTP has
           not answered for a minute after starting.
sLastError  why, in words. Empty when fine.

---

  wifi ( ENABLE := TRUE, SSID := ..., PASSWORD := ... );   NETWORK, node-uio
  ntp  ( eTimeSource := E_MqttTransport.ArduinoWiFi );
  mqtt ( eTimeSource := E_MqttTransport.ArduinoWiFi, sHostName := ..., ... );
  sp   ( fbClient := mqtt, ... );                          stamps with it

ONE CLOCK, AND EVERYTHING USES IT. This sets the board's system clock, so
FB_SparkplugNode's timestamps, CURRENT_DT and anything else that asks for the
date agree, with nothing to wire between them.

UNTIL IT IS SYNCED a board counts from when it started, and the timestamps it
sends are dates in January 1970 - unmistakably not real. A SCADA historian
should take a timestamp like that as "not synced" and stamp the value with
the time it arrived instead. bClockSynced here and on FB_SparkplugNode says which it is. Once set,
the clock survives a loss of network and keeps time on its own.

ON THE RUNTIME THIS BLOCK SETS NOTHING. The operating system's time service
owns the clock there, and a PLC program stepping it under every other program
on the machine would be a fault, not a feature. bClockSynced still reports it.

NOTHING HERE BLOCKS. NTP runs in the background on the board's network stack,
and the modem is asked through the modem block's queue. Put this in the network
task beside the MQTT blocks. *)

FUNCTION_BLOCK FB_MqttClock
  VAR_INPUT
    eTimeSource : E_MqttTransport; (* where the time comes from: OS clock, NTP over Wi-Fi/Ethernet, the mobile network, external *)
    sNtpServer : STRING(64) := 'pool.ntp.org'; (* the NTP server; default 'pool.ntp.org' *)
    tResyncInterval : TIME := T#1h; (* how often to ask for the time again; default T#1h *)
    dtExternalUtc : DT; (* External: the time to set, in UTC *)
    bExternalUtcValid : BOOL; (* External: dtExternalUtc is good; rising edge sets the clock *)
    bEnable : BOOL := TRUE; (* FALSE stops asking; the clock keeps its time *)
  END_VAR
  VAR_OUTPUT
    bClockSynced : BOOL; (* the clock holds real time (same name on FB_SparkplugNode) *)
    dtClockUtc : DT; (* the time now, in UTC; 1970 while not synced *)
    tSinceLastSync : TIME; (* time since the clock was last set *)
    bError : BOOL; (* the source cannot give the time here, or NTP silent for a minute *)
    sLastError : STRING(64); (* why, in words; empty when fine *)
  END_VAR
  VAR
    bStarted        : BOOL;                 (* SNTP started *)
    nSetAt          : DINT;                 (* when the clock was last set, ms *)
    bEverSet        : BOOL;
    nAskedAt        : DINT;                 (* when the time was last asked for, ms *)
    bAsked          : BOOL;
    bLastValid      : BOOL;                 (* bExternalUtcValid last scan *)
  END_VAR
#include <ModBeeMqtt.h>
#include <string.h>

#if defined(MQTT_PLATFORM_ARDUINO) && defined(ESP32)
  #include <esp_sntp.h>
  #define MQ_CLOCK_HAS_SNTP 1
#endif

// Defined by FB_MqttClient, which sorts before this file in the one translation
// unit every C++ POU lands in.
int32_t mq_millisOf(const strucpp::IEC_TIME& t);

// --- When SNTP last set the clock ---
//
// lwIP's SNTP client runs on its own and calls back when it has set the
// system clock - once after it starts and then every tResyncInterval. One client per
// board, so one record per board; the block reads it to say how old the time
// is. Written from the lwIP task, read from a PLC task: a 32-bit store, and a
// flag written after it.
#if defined(MQ_CLOCK_HAS_SNTP)
static volatile uint32_t mqClockSntpAt = 0;
static volatile bool mqClockSntpSeen = false;

static void mq_clockSntpSynced(struct timeval* tv) {
    (void)tv;
    mqClockSntpAt = (uint32_t)mq_millis();
    mqClockSntpSeen = true;
}
#endif

// The board's clock as an IEC DT: nanoseconds since 1970.
static int64_t mq_clockNowNs() {
    return (int64_t)mq_epochMillis() * 1000000LL;
}

void setup()
{
    bClockSynced = false;
    dtClockUtc = 0;
    tSinceLastSync = 0;
    bError = false;
    sLastError = "";
    bStarted = false;
    nSetAt = 0;
    bEverSet = false;
    nAskedAt = 0;
    bAsked = false;
    bLastValid = false;
}

void loop()
{

    const E_MQTTTRANSPORT link = (E_MQTTTRANSPORT)eTimeSource;
    const mq_time_t now = mq_millis();
    const int32_t refreshMs = mq_millisOf(tResyncInterval) > 0
        ? mq_millisOf(tResyncInterval) : 3600000;

    if ((bool)bEnable) {
#if defined(MQTT_PLATFORM_HOST)
        // --- THE RUNTIME: the operating system keeps the time ---
        //
        // Its time service (chrony, systemd-timesyncd, the container host's)
        // has already done what this block would, and a program running as a
        // service has no business stepping the clock under everything else on
        // the machine. So nothing is set here; the block reports the clock.
        (void)refreshMs;   // the board branches' timers; nothing to time here
        if (link == E_MQTTTRANSPORT::RUNTIMETCP ||
            link == E_MQTTTRANSPORT::EXTERNAL) {
            bError = false;
            sLastError = "";
        } else {
            bError = true;
            sLastError = "that transport needs a board, not the Runtime";
        }
#else
        if (link == E_MQTTTRANSPORT::ARDUINOWIFI ||
            link == E_MQTTTRANSPORT::ARDUINOETHERNET) {
#if defined(MQ_CLOCK_HAS_SNTP)
            // --- NTP, through the board's own IP stack ---
            //
            // lwIP's SNTP client, started once: it polls sNtpServer on its own,
            // in the background, and sets the system clock every tResyncInterval.
            // Nothing here waits for a packet. The radio is somebody else's -
            // NETWORK or FB_MqttClient joins it - and SNTP simply retries until
            // there is a network to ask.
            if (!(bool)bStarted) {
                const char* server = sNtpServer.length() > 0 ? sNtpServer.c_str()
                                                         : "pool.ntp.org";
                // At least 15 s: lwIP refuses less, and a public pool asks
                // for no more than one query a minute or so per client.
                const uint32_t interval =
                    refreshMs < 15000 ? 15000u : (uint32_t)refreshMs;
                esp_sntp_set_time_sync_notification_cb(&mq_clockSntpSynced);
                esp_sntp_set_sync_interval(interval);
                // UTC. configTime() also sets TZ; offset 0 keeps the C
                // library's local time equal to UTC, which is what CURRENT_DT
                // and every timestamp here mean.
                configTime(0, 0, server);
                bStarted = true;
            }
            if (mqClockSntpSeen) {
                nSetAt = (int32_t)mqClockSntpAt;
                bEverSet = true;
            }
            bError = !(bool)bEverSet &&
                    (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)nAskedAt, now) > 60000 &&
                    (bool)bAsked;
            if (!(bool)bAsked) {
                bAsked = true;
                nAskedAt = (int32_t)now;
            }
            sLastError = (bool)bEverSet ? "" : "waiting for NTP - is the network up?";
#else
            bError = true;
            sLastError = "NTP needs an ESP32's network stack";
#endif
        } else if (link == E_MQTTTRANSPORT::CELLULAR) {
#if defined(MQ_HAS_CELLULAR)
            // --- THE MOBILE NETWORK'S TIME ---
            //
            // The network sets the module's clock when it registers (NITZ),
            // which costs no data. Read every tResyncInterval and again after the
            // modem restarts, the way NetworkTime does, and written into the
            // board's clock. Not every network sends it; until one does this
            // stays unsynced and says so.
            gsmplc::TryHold hold;
            if (hold.owned()) {
                if (!gsmplc::isOpen()) {
                    sLastError = "waiting for the modem block";
                } else {
                    GsmDevice& gsm = gsmplc::device();
                    if (gsm.isRegistered()) {
                        const bool due = !(bool)bAsked ||
                            (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)nAskedAt,
                                                now) >= refreshMs;
                        if (due) {
                            const GsmResult asked = gsm.refreshTime();
                            if (asked.status() == GsmStatus::Queued || asked.isOk()) {
                                bAsked = true;
                                nAskedAt = (int32_t)now;
                            }
                        }
                    }
                    if (gsm.hasNetworkTime()) {
                        const GsmParse::GsmDateTime& read = gsm.networkTime();
                        // A module whose clock nobody set reports its factory
                        // date. Not a time.
                        const bool plausible = read.year >= 2024 && read.year <= 2099 &&
                            read.month >= 1 && read.month <= 12 &&
                            read.day >= 1 && read.day <= 31;
                        const int64_t localMs = gsmplc::unixSeconds(read) * 1000LL +
                            (int64_t)gsm.networkTimeAgeMillis();
                        const int64_t utcMs = localMs -
                            (int64_t)read.zoneMinutes() * 60000LL;
                        // Written when it is fresh - once per read, not every
                        // scan, so the board's clock is not stepped for ever.
                        if (plausible && (!(bool)bEverSet ||
                                          (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)nSetAt,
                                                              now) >= refreshMs)) {
                            if (mq_setEpochMillis((uint64_t)utcMs)) {
                                nSetAt = (int32_t)now;
                                bEverSet = true;
                            }
                        }
                        sLastError = plausible ? "" : "the network has not sent the time";
                    } else {
                        sLastError = "the network has not sent the time";
                    }
                }
            }
            bError = false;
#else
            bError = true;
            sLastError = "E_MqttTransport.Cellular needs a modbee-gsm modem block";
#endif
        } else if (link == E_MQTTTRANSPORT::EXTERNAL) {
            // --- FROM THE PINS: an RTC, the modem's NetworkTime, a value SCADA wrote ---
            //
            // Set when bExternalUtcValid rises, and again every tResyncInterval while it
            // stays true - not every scan, so the clock is not stepped by a
            // value that is a scan old.
            const bool valid = (bool)bExternalUtcValid;
            const bool rising = valid && !(bool)bLastValid;
            bLastValid = valid;
            if (valid && (rising || !(bool)bEverSet ||
                          (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)nSetAt,
                                              now) >= refreshMs)) {
                const int64_t ns = (int64_t)dtExternalUtc;
                if (ns > 0 && mq_setEpochMillis((uint64_t)(ns / 1000000LL))) {
                    nSetAt = (int32_t)now;
                    bEverSet = true;
                    sLastError = "";
                } else {
                    sLastError = "dtExternalUtc is not a date after 2024";
                }
            }
            bError = false;
        } else {
            bError = true;
            sLastError = "that transport needs the Runtime, not a board";
        }
#endif
    }

    // --- What the clock says now, whoever set it ---
    //
    // mq_epochMillis() is zero until the clock reads a date after 2024 - on a
    // board, until something set it. That is bClockSynced, and it is the same test
    // FB_SparkplugNode's bClockSynced makes, so the two cannot disagree.
    const uint64_t epoch = mq_epochMillis();
    bClockSynced = epoch != 0;
    dtClockUtc = bClockSynced ? mq_clockNowNs() : 0;
#if defined(MQTT_PLATFORM_HOST)
    (void)now;
    tSinceLastSync = 0;
#else
    tSinceLastSync = (bool)bEverSet
        ? (int64_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)nSetAt, now) * 1000000LL
        : 0;
#endif
}

END_FUNCTION_BLOCK