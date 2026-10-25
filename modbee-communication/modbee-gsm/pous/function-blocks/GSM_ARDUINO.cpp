(* The wiring only a board has. Optional: without it GSM_MODEM uses the ModBee
Node UIO's. Ignored on the Runtime.

MODEM          which modem. Must be wired.
PORT           which UART peripheral talks to the modem: 0, 1 or 2. Not a pin.
               On the Node UIO keep 0 - UART1 and UART2 are its RS485 channels.
RX_PIN         the GPIO the board receives on (the module's TX). -1 for the
               UART's own pin. Node UIO: 44.
TX_PIN         the GPIO the board transmits on (the module's RX). -1 for the
               UART's own pin. Node UIO: 43.
RX_BUFFER      bytes of receive buffer, 256 to 32768. Node UIO: 4096.
POWER_KEY_PIN  the GPIO that presses the module's power key, HIGH pressed;
               -1 when the board has none. Node UIO: 10.
RAIL_PIN       a GPIO that switches the module's supply, HIGH on; -1 when
               something else owns the supply. Node UIO: -1, because the HAT
               rail is node-uio's HAT_POWER.

APPLIED        the settings reached the modem block.
ERROR          they did not: a value out of range, the Runtime, or a modem
               already opened on other settings.
STATUS         why. GSM_OK when fine.

---

  board( MODEM := modem, PORT := 0, RX_PIN := 44, TX_PIN := 43 );

Put it beside GSM_MODEM. The modem block waits a scan before it opens the
link, so what this sets has been seen in time. The link is opened once; a
change made after that applies at the next PLC start, and GSM_MODEM says so.

RX_BUFFER IS NOT A TUNING KNOB. The HAT header carries no RTS or CTS, so the
module cannot be told to wait, and a receive buffer that overflows does not
lose a reading - it scrambles the conversation with the modem. The library
reads no more at once than the buffer it was given really holds, so the
number set here is both the size and the promise.

THE POWER KEY IS A BUTTON, NOT A SWITCH. The library presses it for exactly
as long as the module's datasheet asks - 50 ms on an A7670, half a second on
a SIM7070 - and only when the module does not answer, so a module that is
already running is never switched off by mistake. *)

FUNCTION_BLOCK GSM_ARDUINO
  VAR_INPUT
    PORT : BYTE := 0;
    RX_PIN : INT := 44;
    TX_PIN : INT := 43;
    RX_BUFFER : DINT := 4096;
    POWER_KEY_PIN : INT := 10;
    RAIL_PIN : INT := -1;
  END_VAR
  VAR_OUTPUT
    APPLIED : BOOL;
    ERROR : BOOL;
    STATUS : GSM_RESULT;
  END_VAR
  VAR_IN_OUT
    MODEM : GSM_MODEM;
  END_VAR

#include <ModBeeGsmPlc.h>

void setup()
{
    APPLIED = false;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
}

void loop()
{
#if defined(GSM_PLATFORM_HOST)
    // Said plainly rather than silently ignored: every pin here describes
    // hardware the Runtime does not have. GSM_MODEM.DEVICE is its setting.
    APPLIED = false;
    ERROR = true;
    STATUS = GSM_RESULT::GSM_INVALID_ARGUMENT;
#else
    const int32_t rx = (int32_t)(int16_t)RX_PIN;
    const int32_t tx = (int32_t)(int16_t)TX_PIN;
    const int32_t key = (int32_t)(int16_t)POWER_KEY_PIN;
    const int32_t rail = (int32_t)(int16_t)RAIL_PIN;
    const int32_t buffer = (int32_t)RX_BUFFER;
    const bool pinsOk = rx >= -1 && rx <= 63 && tx >= -1 && tx <= 63 &&
                        key >= -1 && key <= 63 && rail >= -1 && rail <= 63;
    if ((uint8_t)PORT > 2 || !pinsOk || buffer < 256 || buffer > 32768 ||
        (key >= 0 && (key == rx || key == tx)) ||
        (rail >= 0 && (rail == rx || rail == tx || rail == key))) {
        APPLIED = false;
        ERROR = true;
        STATUS = GSM_RESULT::GSM_INVALID_ARGUMENT;
        return;
    }

    MODEM.FBPORT = PORT;
    MODEM.FBRXPIN = RX_PIN;
    MODEM.FBTXPIN = TX_PIN;
    MODEM.FBRXBUFFER = RX_BUFFER;
    MODEM.FBKEYPIN = POWER_KEY_PIN;
    MODEM.FBRAILPIN = RAIL_PIN;

    // Opened on something else already: the modem keeps that until the PLC
    // restarts, so these did NOT land.
    bool landed = true;
    {
        gsmplc::TryHold hold;
        if (hold.owned() && gsmplc::isOpen()) {
            const gsmplc::Link& opened = gsmplc::openedWith();
            landed = opened.port == (int32_t)(uint8_t)PORT && opened.rxPin == rx &&
                     opened.txPin == tx && opened.rxBuffer == buffer &&
                     opened.keyPin == key && opened.railPin == rail;
        } else if (!hold.owned()) {
            landed = (bool)APPLIED;     // unknown this scan; keep what it was
        }
    }
    APPLIED = landed;
    ERROR = !landed;
    STATUS = landed ? GSM_RESULT::GSM_OK : GSM_RESULT::GSM_INVALID_ARGUMENT;
#endif
}


END_FUNCTION_BLOCK