(* Runs the cellular modem and hands itself to every other GSM block. Call it
first. A PLC has one.

CONNECT       TRUE brings the modem up and keeps it up: power, SIM, network,
              data. FALSE stops bringing it up and stops recovering it; it
              does not power the module off - GSM_POWER does that. On a
              board, once the modem is stopped and quiet its serial link,
              buffers and service task are given back (about 7 kB of
              internal RAM), and taken again when CONNECT returns to TRUE.
APN           the access point the SIM's provider gives, e.g. 'internet' or
              'onomondo'. Up to 100 characters, the 3GPP maximum. Empty asks
              the network for its default, which some networks give and some
              refuse.
APN_USER      the APN's user name, when the provider gives one. Up to 127.
APN_PASSWORD  its password. Up to 127.
SIM_PIN       the SIM's PIN, when it has one. Offered ONCE: a PIN the SIM
              refuses is not tried again until this pin changes, because
              three wrong entries lock the card behind its PUK.
DEVICE        the Runtime only: the modem's serial port, e.g. '/dev/ttyUSB2'.
              Ignored on a board, where GSM_ARDUINO says which UART.
BAUD          the serial speed. 115200 is what both supported module
              families start at.
SOCKETS       how many sockets may be open at once - each GSM_SOCKET, and each
              MQTT client over the modem, holds one. 2 by default; the module's
              own limit (10 or 13) still applies.
SOCKET_BUFFER each socket's send and receive buffer, in bytes. 1500 by default,
              one full packet. Memory is SOCKETS x 2 x SOCKET_BUFFER.
AT_QUEUE      how many modem commands may wait at once. 12 by default; raise it
              only if LAST_ERROR shows the queue full with many GSM blocks.
              SOCKETS, SOCKET_BUFFER and AT_QUEUE are taken when the modem is
              opened, in PSRAM where the board has it; more than the board can
              hold stops the modem with "out of memory for the sockets" (or
              "... for the AT command queue") on LAST_ERROR.

READY         the modem has a data connection. Sockets, MQTT and everything
              that sends data wait for this.
REGISTERED    the network has accepted the SIM. SMS needs this, not READY.
STATE         where the bring-up is, for a diagnostic page.
ERROR         the modem is not READY and there is a reason.
STATUS        the reason. GSM_OK when READY.
LAST_ERROR    the reason in words - the module's own where it gave one.

---

  modem( CONNECT := TRUE, APN := 'internet' );

APN, APN_USER, APN_PASSWORD and SIM_PIN are ordinary inputs, so a program can
feed them from RETAIN variables and change them without a new download.
Changing one while the modem is up starts its bring-up again, which drops the
data connection for the seconds that takes.

NOTHING HERE WAITS. Every scan does a bounded amount of work and returns; the
bring-up, the retries and the recovery run across scans by themselves. Give
the block a task of 20 ms or faster: the modem is read in bites each scan, so
a slow task is a slow modem.

RECOVERY IS AUTOMATIC. A lost network, a lost data connection or a module that
stops answering is recovered without the program doing anything: resync,
restart, power-key cycle, then a retry on a growing back-off. STATE and
LAST_ERROR say what is happening.

ON A BOARD, the defaults suit the ModBee Node UIO with its GSM HAT: UART0 on
GPIO 44 (receive) and 43 (transmit), the power key on GPIO 10. GSM_ARDUINO
changes them. On the Node, switch the HAT on with node-uio's HAT_POWER.

ONE PER PLC. A second GSM_MODEM does not run the modem; it says so on ERROR.
The modem's link settings (GSM_ARDUINO, DEVICE, BAUD, SOCKETS, SOCKET_BUFFER,
AT_QUEUE) are read when the modem is first opened; changing them later is
reported on ERROR and takes effect at the next PLC start. *)

FUNCTION_BLOCK GSM_MODEM
  VAR_INPUT
    CONNECT : BOOL := TRUE;
    APN : STRING(100);
    APN_USER : STRING(127);
    APN_PASSWORD : STRING(127);
    SIM_PIN : STRING(8);
    DEVICE : STRING(48);
    BAUD : DINT := 115200;
    SOCKETS : USINT := 2;
    SOCKET_BUFFER : UINT := 1500;
    AT_QUEUE : USINT := 12;
  END_VAR
  VAR_OUTPUT
    READY : BOOL;
    REGISTERED : BOOL;
    STATE : GSM_STATE;
    ERROR : BOOL;
    STATUS : GSM_RESULT;
    LAST_ERROR : STRING(64);
  END_VAR
  VAR
    fbId : UDINT; (* this instance's number; the other blocks check it against the modem's owner *)
    fbSettled : BOOL;
    fbRunning : BOOL;
    fbPort : BYTE := 0; (* written by GSM_ARDUINO *)
    fbRxPin : INT := 44;
    fbTxPin : INT := 43;
    fbRxBuffer : DINT := 4096;
    fbKeyPin : INT := 10;
    fbRailPin : INT := -1;
    fbRadioMode : GSM_RADIO_MODE; (* written by GSM_RADIO *)
    fbOperator : STRING(7);
    fbCatMBands : STRING(64);
    fbNbIotBands : STRING(64);
  END_VAR

#include <ModBeeGsmPlc.h>

void setup()
{
    READY = false;
    REGISTERED = false;
    STATE = GSM_STATE::GSM_OFF;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
    LAST_ERROR = "";
    fbId = gsmplc::nextId();
    fbSettled = false;
    fbRunning = false;
}

void loop()
{
    // Another task is inside the modem - most likely an MQTT client in its
    // connect(), which pumps the modem itself. Stand back for a scan; the
    // outputs keep what they last said.
    gsmplc::TryHold hold;
    if (!hold.owned()) return;

    if (!gsmplc::claim((uint32_t)fbId)) {
        READY = false;
        REGISTERED = false;
        STATE = GSM_STATE::GSM_OFF;
        ERROR = true;
        STATUS = GSM_RESULT::GSM_INVALID_ARGUMENT;
        LAST_ERROR = "another GSM_MODEM runs the modem; a PLC has one";
        return;
    }

    // One scan's grace, so whatever GSM_ARDUINO and GSM_RADIO set has been
    // seen before the modem is opened on it.
    if (!(bool)fbSettled) {
        fbSettled = true;
        return;
    }

    // --- what the program asked for -----------------------------------------
    bool changed = false;
    if (gsmplc::apn(APN.c_str(), APN_USER.c_str(), APN_PASSWORD.c_str())) changed = true;
    if (gsmplc::pin(SIM_PIN.c_str())) changed = true;
    if (gsmplc::radio((GsmRadioPreference)(int)(GSM_RADIO_MODE)fbRadioMode,
                      fbOperator.c_str(), fbCatMBands.c_str(), fbNbIotBands.c_str())) {
        changed = true;
    }

    gsmplc::Link link;
#if defined(GSM_PLATFORM_ARDUINO)
    link.port = (int32_t)(uint8_t)fbPort;
    link.rxPin = (int32_t)(int16_t)fbRxPin;
    link.txPin = (int32_t)(int16_t)fbTxPin;
    link.rxBuffer = (int32_t)fbRxBuffer;
    link.keyPin = (int32_t)(int16_t)fbKeyPin;
    link.railPin = (int32_t)(int16_t)fbRailPin;
#else
    {
        const char* path = DEVICE.c_str();
        size_t n = 0;
        for (; n + 1 < sizeof link.path && path[n] != '\0'; n++) link.path[n] = path[n];
        link.path[n] = '\0';
    }
#endif
    link.baud = (int32_t)BAUD > 0 ? (uint32_t)(int32_t)BAUD : 115200u;
    link.sockets = (int32_t)(uint8_t)SOCKETS;
    link.socketBuffer = (int32_t)(uint16_t)SOCKET_BUFFER;
    link.atQueue = (int32_t)(uint8_t)AT_QUEUE;

    const bool want = (bool)CONNECT && !gsmplc::heldOff();
    GsmDevice& gsm = gsmplc::device();
    // Switched off, the modem gives its serial link and the RAM behind it
    // back once it is quiet (gsmplc::service()); switched on, it takes it again.
    gsmplc::want(want);

    // --- open once, then start and stop ---------------------------------------
    if (!gsmplc::isOpen()) {
        if (want) {
            const char* why = nullptr;
            if (!gsmplc::open(link, &why)) {
                READY = false;
                REGISTERED = false;
                STATE = GSM_STATE::GSM_OFF;
                ERROR = true;
                STATUS = GSM_RESULT::GSM_INVALID_ARGUMENT;
                LAST_ERROR = why != nullptr ? why : "the modem would not open";
                return;
            }
            fbRunning = true;
        }
    } else {
        if (want && !(bool)fbRunning) {
            const char* why = nullptr;
            if (!gsmplc::takeLink(&why)) {
                // Tried again next scan: fbRunning stays FALSE.
                READY = false;
                REGISTERED = false;
                STATE = GSM_STATE::GSM_OFF;
                ERROR = true;
                STATUS = GSM_RESULT::GSM_NOT_READY;
                LAST_ERROR = why != nullptr ? why : "the modem's serial link would not open";
                gsmplc::service();
                return;
            }
            gsm.start();
        } else if (!want && (bool)fbRunning) {
            gsm.stop();
        } else if (want && changed) {
            // A new APN, PIN or radio setting is read during bring-up, so the
            // bring-up runs again for it.
            gsm.stop();
            gsm.start();
        }
        fbRunning = want;
    }

    gsmplc::service();

    // --- what it is doing ----------------------------------------------------
    READY = gsm.isReady();
    REGISTERED = gsm.isRegistered();
    STATE = (GSM_STATE)(int)gsm.state();

    if ((bool)READY) {
        ERROR = false;
        STATUS = GSM_RESULT::GSM_OK;
        LAST_ERROR = "";
    } else if (!want) {
        ERROR = false;
        STATUS = gsmplc::heldOff() ? GSM_RESULT::GSM_POWERED_OFF : GSM_RESULT::GSM_NOT_READY;
        LAST_ERROR = gsmplc::heldOff() ? "powered off by GSM_POWER" : "CONNECT is FALSE";
    } else {
        const GsmResult why = gsm.lastError();
        if (why.isOk() || why.status() == GsmStatus::Queued) {
            ERROR = false;
            STATUS = GSM_RESULT::GSM_NOT_READY;
            LAST_ERROR = "";
        } else {
            ERROR = true;
            STATUS = (GSM_RESULT)(int)why.status();
            LAST_ERROR = gsmplc::describe(why);
        }
    }

    // Said, not silently ignored: the modem keeps running on what it opened
    // with, and the new settings wait for the next start.
    if (gsmplc::isOpen() && !gsmplc::sameLink(gsmplc::openedWith(), link)) {
        ERROR = true;
        STATUS = GSM_RESULT::GSM_INVALID_ARGUMENT;
        LAST_ERROR = "link settings changed; they apply at the next PLC start";
    }
}


END_FUNCTION_BLOCK