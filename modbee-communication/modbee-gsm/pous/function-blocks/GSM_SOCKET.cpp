(* A TCP connection over the modem, plain or TLS, for a program that talks to a
server itself. MQTT does not need this block - MQTT_CLIENT reaches the modem
on its own.

MODEM       which modem. Must be wired.
OPEN        TRUE opens the connection and keeps it open, reopening it five
            seconds after it fails. FALSE closes it.
HOST        the server: a name or an address. Up to 63 characters.
PORT        the server's port.
SECURITY    GSM_PLAIN, or GSM_TLS for TLS done by the module itself. The
            module encrypts and does not check the server's certificate.
SEND        rising edge sends TX_DATA.
TX_DATA     the text to send, up to 254 characters.

CONNECTED   the connection is open.
SENT        one scan, when all of TX_DATA has left for the server.
RECEIVED    one scan, when RX_DATA holds bytes that just arrived.
RX_DATA     what arrived - up to 254 characters a scan; more waits for the
            next scan.
ERROR       the connection failed, or SEND came while it was not open.
STATUS      why. GSM_OK when fine.
LAST_ERROR  the reason in words.

---

  link( MODEM := modem, OPEN := modem.READY, HOST := 'telemetry.example.com',
        PORT := 9000, SEND := tick, TX_DATA := line );

NOTHING WAITS. Opening is started and CONNECTED says when it arrived; sending
is handed over and SENT says when it has gone. Receiving is a look at what has
already come in. A scan does a bounded amount of work, connection or not.

TEXT, NOT BYTES. TX_DATA and RX_DATA are STRINGs, so a byte of value zero ends
them. Use it for line protocols - a reading, a command, a reply.

A MODEM HAS FEW SOCKETS: two are open at most, shared with MQTT_CLIENT, and a
module carries at most two TLS sessions. One that cannot be had is
GSM_NO_SOCKET_AVAILABLE. *)

FUNCTION_BLOCK GSM_SOCKET
  VAR_INPUT
    OPEN : BOOL;
    HOST : STRING(63);
    PORT : UINT;
    SECURITY : GSM_SECURITY;
    SEND : BOOL;
    TX_DATA : STRING(254);
  END_VAR
  VAR_OUTPUT
    CONNECTED : BOOL;
    SENT : BOOL;
    RECEIVED : BOOL;
    RX_DATA : STRING(254);
    ERROR : BOOL;
    STATUS : GSM_RESULT;
    LAST_ERROR : STRING(64);
  END_VAR
  VAR_IN_OUT
    MODEM : GSM_MODEM;
  END_VAR
  VAR
    fbSocket : __XWORD;
    fbLastSend : BOOL;
    fbSendAsked : BOOL;
    fbTx : STRING(254);
    fbTxAt : DINT;
    fbTxPending : BOOL;
    fbTxFlushing : BOOL;
    fbRetryAt : UDINT;
    fbRetrying : BOOL;
  END_VAR

#include <ModBeeGsmPlc.h>

void setup()
{
    CONNECTED = false;
    SENT = false;
    RECEIVED = false;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
    LAST_ERROR = "";
    fbSocket = 0;
    fbTxPending = false;
    fbTxFlushing = false;
    fbRetrying = false;
}

void loop()
{
    SENT = false;
    RECEIVED = false;

    // The edge is taken before the lock, so a scan spent standing back for
    // another task cannot lose it.
    const bool rising = (bool)SEND && !(bool)fbLastSend;
    fbLastSend = SEND;
    if (rising) fbSendAsked = true;

    gsmplc::TryHold hold;
    if (!hold.owned()) return;

    GsmSocket* socket = (GsmSocket*)(uintptr_t)(strucpp::XWORD_t)fbSocket;
    GsmDevice& gsm = gsmplc::device();

    if (!gsmplc::isOwner((uint32_t)MODEM.FBID) || !gsmplc::isOpen()) {
        if (socket != nullptr) gsm.close(socket);
        fbSocket = 0;
        CONNECTED = false;
        ERROR = (bool)OPEN;
        STATUS = GSM_RESULT::GSM_NOT_INITIALISED;
        LAST_ERROR = "MODEM is not a running GSM_MODEM";
        fbSendAsked = false;
        return;
    }

    if (!(bool)OPEN) {
        if (socket != nullptr) gsm.close(socket);
        fbSocket = 0;
        CONNECTED = false;
        ERROR = false;
        STATUS = GSM_RESULT::GSM_OK;
        LAST_ERROR = "";
        fbRetrying = false;
        fbTxPending = false;
        fbTxFlushing = false;
        if ((bool)fbSendAsked) {
            fbSendAsked = false;
            ERROR = true;
            STATUS = GSM_RESULT::GSM_NOT_READY;
            LAST_ERROR = "SEND while OPEN is FALSE";
        }
        return;
    }

    const uint32_t now = gsm_millis();

    // --- open ------------------------------------------------------------------
    if (socket == nullptr) {
        CONNECTED = false;
        if ((bool)fbSendAsked) {
            fbSendAsked = false;
            ERROR = true;
            STATUS = GSM_RESULT::GSM_NOT_READY;
            LAST_ERROR = "SEND while not connected";
            return;
        }
        if (!gsm.isReady()) {
            if (!(bool)fbRetrying) {
                ERROR = false;
                STATUS = GSM_RESULT::GSM_NOT_READY;
                LAST_ERROR = "waiting for the modem's data connection";
            }
            return;
        }
        if ((bool)fbRetrying && gsm_isFuture(now, (uint32_t)fbRetryAt)) return;
        fbRetrying = false;

        if (HOST.length() == 0 || (uint16_t)PORT == 0) {
            ERROR = true;
            STATUS = GSM_RESULT::GSM_INVALID_ARGUMENT;
            LAST_ERROR = "set HOST and PORT";
            return;
        }
        const GsmSecurity security = (GSM_SECURITY)SECURITY == GSM_SECURITY::GSM_TLS
            ? GsmSecurity::Module : GsmSecurity::Plain;
        socket = gsm.sockets().open(HOST.c_str(), (uint16_t)PORT, GsmSocketKind::Tcp, security);
        if (socket == nullptr) {
            ERROR = true;
            STATUS = GSM_RESULT::GSM_NO_SOCKET_AVAILABLE;
            LAST_ERROR = security == GsmSecurity::Module
                ? "no free socket, or no TLS session left"
                : "no free socket";
            fbRetrying = true;
            fbRetryAt = now + 5000u;
            return;
        }
        if (!socket->begin()) {
            const GsmResult why = socket->lastError();
            socket->end();
            ERROR = true;
            STATUS = (GSM_RESULT)(int)why.status();
            LAST_ERROR = gsmplc::describe(why);
            fbRetrying = true;
            fbRetryAt = now + 5000u;
            return;
        }
        fbSocket = (strucpp::XWORD_t)(uintptr_t)socket;
        fbTxPending = false;
        fbTxFlushing = false;
    }

    // --- running ---------------------------------------------------------------
    const GsmSocketState state = socket->state();

    if (state == GsmSocketState::Failed || state == GsmSocketState::Closed) {
        const GsmResult why = socket->lastError();
        socket->end();
        fbSocket = 0;
        CONNECTED = false;
        ERROR = true;
        STATUS = why.isOk() ? GSM_RESULT::GSM_SOCKET_CLOSED : (GSM_RESULT)(int)why.status();
        LAST_ERROR = why.isOk() ? "the connection closed" : gsmplc::describe(why);
        fbTxPending = false;
        fbTxFlushing = false;
        fbSendAsked = false;
        fbRetrying = true;
        fbRetryAt = now + 5000u;
        return;
    }

    if (state != GsmSocketState::Open) {
        CONNECTED = false;     // still opening
        if ((bool)fbSendAsked) {
            fbSendAsked = false;
            ERROR = true;
            STATUS = GSM_RESULT::GSM_NOT_READY;
            LAST_ERROR = "SEND while not connected";
        }
        return;
    }

    CONNECTED = true;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
    LAST_ERROR = "";

    if ((bool)fbSendAsked && !(bool)fbTxPending && !(bool)fbTxFlushing) {
        fbSendAsked = false;
        fbTx = TX_DATA;
        fbTxAt = 0;
        fbTxPending = fbTx.length() > 0;
    }

    // Handed over as the socket's buffer takes it; the rest next scan.
    if ((bool)fbTxPending) {
        const size_t length = fbTx.length();
        const size_t at = (size_t)(int32_t)fbTxAt;
        const size_t taken = socket->write((const uint8_t*)fbTx.c_str() + at, length - at);
        fbTxAt = (int32_t)(at + taken);
        if (at + taken >= length) {
            fbTxPending = false;
            fbTxFlushing = true;
        }
    }
    if ((bool)fbTxFlushing && socket->pendingOut() == 0) {
        fbTxFlushing = false;
        SENT = true;
    }

    const size_t waiting = socket->readable();
    if (waiting > 0) {
        char buffer[255];
        const size_t got = socket->read((uint8_t*)buffer, waiting < 254 ? waiting : 254);
        buffer[got] = '\0';
        RX_DATA = buffer;
        RECEIVED = got > 0;
    }
}


END_FUNCTION_BLOCK