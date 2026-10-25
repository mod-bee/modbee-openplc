(* SETS THE CONTROLLER'S CLOCK FROM THE NETWORK - NTP over Wi-Fi or Ethernet,
the mobile network's own time over cellular - so Sparkplug timestamps and
CURRENT_DT are real time. One per controller.

TRANSPORT  where the time comes from - the same list as MQTT_CLIENT and
           SPARKPLUG_NODE, so a site that moves from Wi-Fi to cellular changes
           one pin on each:
             MQTT_RUNTIME_TCP       the Runtime's own clock, which its operating
                                    system already keeps. Nothing is set.
             MQTT_ARDUINO_WIFI      NTP from SERVER, through the board's IP
             MQTT_ARDUINO_ETHERNET  stack (ESP32). NETWORK or MQTT_ARDUINO
                                    brings the network up; this waits for it.
             MQTT_CELLULAR          the mobile network's time (NITZ) from the
                                    modem a modbee-gsm GSM_MODEM runs. Costs no
                                    data. Not every network sends it.
             MQTT_LINK_EXTERNAL     UTC_IN, when UTC_IN_VALID - an RTC,
                                    GSM_TIME.UTC, a time SCADA wrote.
SERVER     the NTP server. Default 'pool.ntp.org'; a site with its own (a
           router, a SCADA server) should use it.
REFRESH    how often to ask again. Default T#1h - a board's crystal drifts a
           second or two a day, so hourly is plenty.
UTC_IN     MQTT_LINK_EXTERNAL: the time to set, in UTC.
UTC_IN_VALID  MQTT_LINK_EXTERNAL: UTC_IN is good. Its rising edge sets the
           clock, and again every REFRESH while it stays TRUE.
ENABLE     FALSE stops asking. The clock keeps the time it has.

SYNCED     the clock holds real time - a date after 2024. Exactly what
           SPARKPLUG_NODE.CLOCK_SET reports.
UTC        the time now, in UTC. DT#1970-01-01 while not SYNCED.
AGE        how long since the clock was last set. Grows while the network is
           away - the clock keeps running on its own crystal meanwhile.
ERROR      the transport cannot give the time on this target, or NTP has not
           answered for a minute after starting.
LAST_ERROR why, in words. Empty when fine.

---

  wifi( ENABLE := TRUE, SSID := ..., PASSWORD := ... );   NETWORK, node-uio
  ntp ( TRANSPORT := MQTT_ARDUINO_WIFI );
  sp  ( TRANSPORT := MQTT_ARDUINO_WIFI, ... );            stamps with it

ONE CLOCK, AND EVERYTHING USES IT. This sets the board's system clock, so
SPARKPLUG_NODE's timestamps, CURRENT_DT and anything else that asks for the
date agree, with nothing to wire between them.

UNTIL IT IS SYNCED a board counts from when it started, and the timestamps it
sends are dates in January 1970 - unmistakably not real. A SCADA historian
should take a timestamp like that as "not synced" and stamp the value with
the time it arrived instead. SYNCED and CLOCK_SET say which it is. Once set,
the clock survives a loss of network and keeps time on its own.

ON THE RUNTIME THIS BLOCK SETS NOTHING. The operating system's time service
owns the clock there, and a PLC program stepping it under every other program
on the machine would be a fault, not a feature. SYNCED still reports it.

NOTHING HERE BLOCKS. NTP runs in the background on the board's network stack,
and the modem is asked through GSM_MODEM's queue. Put this in the network task
beside the MQTT blocks. *)

FUNCTION_BLOCK MQTT_CLOCK
  VAR_INPUT
    TRANSPORT : MQTT_LINK;
    SERVER : STRING(64) := 'pool.ntp.org';
    REFRESH : TIME := T#1h;
    UTC_IN : DT;
    UTC_IN_VALID : BOOL;
    ENABLE : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    SYNCED : BOOL;
    UTC : DT;
    AGE : TIME;
    ERROR : BOOL;
    LAST_ERROR : STRING(64);
  END_VAR
  VAR
    fbStarted : BOOL;
    fbSetAt : DINT;
    fbEverSet : BOOL;
    fbAskedAt : DINT;
    fbAsked : BOOL;
    fbLastValid : BOOL;
  END_VAR
#include <ModBeeMqtt.h>
#include <string.h>

#if defined(MQTT_PLATFORM_ARDUINO) && defined(ESP32)
  #include <esp_sntp.h>
  #define MQ_CLOCK_HAS_SNTP 1
#endif

// Defined by MQTT_CLIENT, which sorts before this file in the one translation
// unit every C++ POU lands in.
int32_t mq_millisOf(const strucpp::IEC_TIME& t);

// --- When SNTP last set the clock ---
//
// lwIP's SNTP client runs on its own and calls back when it has set the
// system clock - once after it starts and then every REFRESH. One client per
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
    SYNCED = false;
    UTC = 0;
    AGE = 0;
    ERROR = false;
    LAST_ERROR = "";
    fbStarted = false;
    fbSetAt = 0;
    fbEverSet = false;
    fbAskedAt = 0;
    fbAsked = false;
    fbLastValid = false;
}

void loop()
{

    const MQTT_LINK link = (MQTT_LINK)TRANSPORT;
    const mq_time_t now = mq_millis();
    const int32_t refreshMs = mq_millisOf(REFRESH) > 0
        ? mq_millisOf(REFRESH) : 3600000;

    if ((bool)ENABLE) {
#if defined(MQTT_PLATFORM_HOST)
        // --- THE RUNTIME: the operating system keeps the time ---
        //
        // Its time service (chrony, systemd-timesyncd, the container host's)
        // has already done what this block would, and a program running as a
        // service has no business stepping the clock under everything else on
        // the machine. So nothing is set here; the block reports the clock.
        (void)refreshMs;   // the board branches' timers; nothing to time here
        if (link == MQTT_LINK::MQTT_RUNTIME_TCP ||
            link == MQTT_LINK::MQTT_LINK_EXTERNAL) {
            ERROR = false;
            LAST_ERROR = "";
        } else {
            ERROR = true;
            LAST_ERROR = "that transport needs a board, not the Runtime";
        }
#else
        if (link == MQTT_LINK::MQTT_ARDUINO_WIFI ||
            link == MQTT_LINK::MQTT_ARDUINO_ETHERNET) {
#if defined(MQ_CLOCK_HAS_SNTP)
            // --- NTP, through the board's own IP stack ---
            //
            // lwIP's SNTP client, started once: it polls SERVER on its own,
            // in the background, and sets the system clock every REFRESH.
            // Nothing here waits for a packet. The radio is somebody else's -
            // NETWORK or MQTT_ARDUINO joins it - and SNTP simply retries until
            // there is a network to ask.
            if (!(bool)fbStarted) {
                const char* server = SERVER.length() > 0 ? SERVER.c_str()
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
                fbStarted = true;
            }
            if (mqClockSntpSeen) {
                fbSetAt = (int32_t)mqClockSntpAt;
                fbEverSet = true;
            }
            ERROR = !(bool)fbEverSet &&
                    (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbAskedAt, now) > 60000 &&
                    (bool)fbAsked;
            if (!(bool)fbAsked) {
                fbAsked = true;
                fbAskedAt = (int32_t)now;
            }
            LAST_ERROR = (bool)fbEverSet ? "" : "waiting for NTP - is the network up?";
#else
            ERROR = true;
            LAST_ERROR = "NTP needs an ESP32's network stack";
#endif
        } else if (link == MQTT_LINK::MQTT_CELLULAR) {
#if defined(MQ_HAS_CELLULAR)
            // --- THE MOBILE NETWORK'S TIME ---
            //
            // The network sets the module's clock when it registers (NITZ),
            // which costs no data. Read every REFRESH and again after the
            // modem restarts, the way GSM_TIME does, and written into the
            // board's clock. Not every network sends it; until one does this
            // stays unsynced and says so.
            gsmplc::TryHold hold;
            if (hold.owned()) {
                if (!gsmplc::isOpen()) {
                    LAST_ERROR = "waiting for GSM_MODEM";
                } else {
                    GsmDevice& gsm = gsmplc::device();
                    if (gsm.isRegistered()) {
                        const bool due = !(bool)fbAsked ||
                            (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbAskedAt,
                                                now) >= refreshMs;
                        if (due) {
                            const GsmResult asked = gsm.refreshTime();
                            if (asked.status() == GsmStatus::Queued || asked.isOk()) {
                                fbAsked = true;
                                fbAskedAt = (int32_t)now;
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
                        if (plausible && (!(bool)fbEverSet ||
                                          (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbSetAt,
                                                              now) >= refreshMs)) {
                            if (mq_setEpochMillis((uint64_t)utcMs)) {
                                fbSetAt = (int32_t)now;
                                fbEverSet = true;
                            }
                        }
                        LAST_ERROR = plausible ? "" : "the network has not sent the time";
                    } else {
                        LAST_ERROR = "the network has not sent the time";
                    }
                }
            }
            ERROR = false;
#else
            ERROR = true;
            LAST_ERROR = "MQTT_CELLULAR needs the modbee-gsm library and a GSM_MODEM";
#endif
        } else if (link == MQTT_LINK::MQTT_LINK_EXTERNAL) {
            // --- FROM THE PINS: an RTC, GSM_TIME, a value SCADA wrote ---
            //
            // Set when UTC_IN_VALID rises, and again every REFRESH while it
            // stays true - not every scan, so the clock is not stepped by a
            // value that is a scan old.
            const bool valid = (bool)UTC_IN_VALID;
            const bool rising = valid && !(bool)fbLastValid;
            fbLastValid = valid;
            if (valid && (rising || !(bool)fbEverSet ||
                          (int32_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbSetAt,
                                              now) >= refreshMs)) {
                const int64_t ns = (int64_t)UTC_IN;
                if (ns > 0 && mq_setEpochMillis((uint64_t)(ns / 1000000LL))) {
                    fbSetAt = (int32_t)now;
                    fbEverSet = true;
                    LAST_ERROR = "";
                } else {
                    LAST_ERROR = "UTC_IN is not a date after 2024";
                }
            }
            ERROR = false;
        } else {
            ERROR = true;
            LAST_ERROR = "that transport needs the Runtime, not a board";
        }
#endif
    }

    // --- What the clock says now, whoever set it ---
    //
    // mq_epochMillis() is zero until the clock reads a date after 2024 - on a
    // board, until something set it. That is SYNCED, and it is the same test
    // SPARKPLUG_NODE's CLOCK_SET makes, so the two cannot disagree.
    const uint64_t epoch = mq_epochMillis();
    SYNCED = epoch != 0;
    UTC = SYNCED ? mq_clockNowNs() : 0;
#if defined(MQTT_PLATFORM_HOST)
    (void)now;
    AGE = 0;
#else
    AGE = (bool)fbEverSet
        ? (int64_t)mq_elapsed((mq_time_t)(uint32_t)(int32_t)fbSetAt, now) * 1000000LL
        : 0;
#endif
}

END_FUNCTION_BLOCK