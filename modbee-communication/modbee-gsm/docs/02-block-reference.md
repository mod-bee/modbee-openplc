# Block reference

Every block but `GSM_MODEM` takes the modem on a `MODEM` in-out pin.
**That pin must be assigned at every call — leaving it out is a compile
error.** A PLC has one `GSM_MODEM`.

`BUSY` is a level. `DONE`, `SENT`, `RECEIVED`, and `ERROR` on the blocks that
send something, are **one scan wide**, so latch them if a slower task has to
see one. `STATUS` is a `GSM_RESULT`: `GSM_OK` when all is well.

| Block | What it does |
| --- | --- |
| [`GSM_ARDUINO`](#gsm_arduino) | The wiring only a board has. |
| [`GSM_AT`](#gsm_at) | Sends one AT command of your own and hands back the reply. |
| [`GSM_GNSS`](#gsm_gnss) | Where the module is, from its own satellite receiver - where it has one. |
| [`GSM_MODEM`](#gsm_modem) | Runs the cellular modem and hands itself to every other GSM block. |
| [`GSM_POWER`](#gsm_power) | Powers the module off, on again, or restarts it - each an operation that concludes once. |
| [`GSM_RADIO`](#gsm_radio) | Which radio, which bands, which operator. |
| [`GSM_SMS_RECEIVE`](#gsm_sms_receive) | Text messages arriving at the SIM, one at a time. |
| [`GSM_SMS_SEND`](#gsm_sms_send) | Sends one text message when you ask. |
| [`GSM_SOCKET`](#gsm_socket) | A TCP connection over the modem, plain or TLS, for a program that talks to a server itself. |
| [`GSM_STATUS`](#gsm_status) | What the modem knows about itself and its network, for a diagnostic page. |
| [`GSM_TIME`](#gsm_time) | The time, from the mobile network. |

---

## GSM_ARDUINO

```
The wiring only a board has. Optional: without it GSM_MODEM uses the ModBee
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
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `MODEM` | `GSM_MODEM` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `PORT` | `BYTE` | `0` |
| `RX_PIN` | `INT` | `44` |
| `TX_PIN` | `INT` | `43` |
| `RX_BUFFER` | `DINT` | `4096` |
| `POWER_KEY_PIN` | `INT` | `10` |
| `RAIL_PIN` | `INT` | `-1` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `APPLIED` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `GSM_RESULT` |  |

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
already running is never switched off by mistake.

---

## GSM_AT

```
Sends one AT command of your own and hands back the reply. The escape hatch
for the module command nothing else here covers.

MODEM       which modem. Must be wired.
REQ         rising edge sends COMMAND.
COMMAND     the command, without the line ending: 'AT+CSQ'. Up to 127
            characters.
TIMEOUT     how long the module has to answer. Default T#5s; the module's
            manual gives each command's own limit, up to minutes for a
            network scan. At most T#180s.

BUSY        a level: the command is queued or with the module.
DONE        one scan, when the module answered OK.
ERROR       one scan, when it answered ERROR, gave no answer in time, or
            could not be sent.
REPLY       every line the module answered before its OK or ERROR, one line
            to a line, up to 254 characters.
STATUS      why. GSM_OK when fine.
LAST_ERROR  the reason in words - '+CME ERROR: 10, SIM not inserted' rather
            than a number.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `MODEM` | `GSM_MODEM` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `REQ` | `BOOL` |  |
| `COMMAND` | `STRING(127)` |  |
| `TIMEOUT` | `TIME` | `T#5s` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `BUSY` | `BOOL` |  |
| `DONE` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `REPLY` | `STRING(254)` |  |
| `STATUS` | `GSM_RESULT` |  |
| `LAST_ERROR` | `STRING(64)` |  |

ask( MODEM := modem, REQ := askNow, COMMAND := 'AT+CPSI?' );
  IF ask.DONE THEN servingCell := ask.REPLY; END_IF;

THE COMMAND JOINS THE MODEM'S OWN QUEUE. It waits its turn behind whatever
the library is doing, is timed like everything else, and concludes exactly
once. Nothing blocks.

IT CAN UNDO THE LIBRARY. A command that turns the radio off, changes the
serial speed or closes the data connection does exactly that, and the modem
block then recovers from it as from any other fault. Reading is safe; writing
settings is your responsibility.

A command the library sends itself works too, and costs nothing extra.

---

## GSM_GNSS

```
Where the module is, from its own satellite receiver - where it has one.

MODEM       which modem. Must be wired.
ENABLE      TRUE powers the receiver and reads it. FALSE powers it down.
REFRESH     how often to read the fix. Default T#5s.

SUPPORTED   the module has a receiver and accepted the request. FALSE on a
            module without one, which is said here and on STATUS rather
            than by a fix that never comes.
FIX         a position is known and current.
LATITUDE    degrees, north positive.
LONGITUDE   degrees, east positive.
ALTITUDE    metres above sea level.
SATELLITES  satellites the receiver can see.
AGE         how long ago the fix was last confirmed. T#0s before the first.
ERROR       the module refused, or MODEM is not a running GSM_MODEM.
STATUS      why. GSM_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `MODEM` | `GSM_MODEM` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `ENABLE` | `BOOL` |  |
| `REFRESH` | `TIME` | `T#5s` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `SUPPORTED` | `BOOL` |  |
| `FIX` | `BOOL` |  |
| `LATITUDE` | `LREAL` |  |
| `LONGITUDE` | `LREAL` |  |
| `ALTITUDE` | `REAL` |  |
| `SATELLITES` | `USINT` |  |
| `AGE` | `TIME` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `GSM_RESULT` |  |

where( MODEM := modem, ENABLE := TRUE );

AGE IS THE PIN TO ALARM ON, NOT FIX. A receiver that loses the sky keeps its
last position, and a position an hour old looks exactly like a current one.

A FIRST FIX TAKES TIME. From cold, with a clear view of the sky, expect a
minute or more; indoors, perhaps never. The receiver needs its own antenna on
the module's GNSS connector - the cellular antenna does not serve it.

Reading the receiver costs nothing on the SIM. Some modules share one radio
between the network and the receiver, and a fix there can interrupt data for
a moment while the receiver is powered.

If the module restarts - which the modem block may do on its own to recover -
the receiver is powered again by itself.

---

## GSM_MODEM

```
Runs the cellular modem and hands itself to every other GSM block. Call it
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
```

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `CONNECT` | `BOOL` | `TRUE` |
| `APN` | `STRING(100)` |  |
| `APN_USER` | `STRING(127)` |  |
| `APN_PASSWORD` | `STRING(127)` |  |
| `SIM_PIN` | `STRING(8)` |  |
| `DEVICE` | `STRING(48)` |  |
| `BAUD` | `DINT` | `115200` |
| `SOCKETS` | `USINT` | `2` |
| `SOCKET_BUFFER` | `UINT` | `1500` |
| `AT_QUEUE` | `USINT` | `12` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `READY` | `BOOL` |  |
| `REGISTERED` | `BOOL` |  |
| `STATE` | `GSM_STATE` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `GSM_RESULT` |  |
| `LAST_ERROR` | `STRING(64)` |  |

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
reported on ERROR and takes effect at the next PLC start.

---

## GSM_POWER

```
Powers the module off, on again, or restarts it - each an operation that
concludes once.

MODEM      which modem. Must be wired.
POWER_OFF  rising edge: shut the module down properly - its own power-down
           command first, then its supply, if the board switches one - and
           keep it off.
POWER_ON   rising edge: let it run again. GSM_MODEM brings it back up,
           pressing the power key if it does not answer.
RESTART    rising edge: restart the module with its own reset command, then
           bring it back up.

POWERED    FALSE from POWER_OFF until POWER_ON. Kept across nothing: a PLC
           restart powers the module up again.
BUSY       a level: an operation is under way.
DONE       one scan, when it has finished.
ERROR      one scan, when it could not.
STATUS     why. GSM_OK when fine.
LAST_ERROR the reason in words.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `MODEM` | `GSM_MODEM` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `POWER_OFF` | `BOOL` |  |
| `POWER_ON` | `BOOL` |  |
| `RESTART` | `BOOL` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `POWERED` | `BOOL` | `TRUE` |
| `BUSY` | `BOOL` |  |
| `DONE` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `GSM_RESULT` |  |
| `LAST_ERROR` | `STRING(64)` |  |

power( MODEM := modem, POWER_OFF := quietHours, POWER_ON := NOT quietHours );

The library already restarts and power-cycles the module by itself when it
stops answering, so this is not needed to keep a site connected. It is for
the program's own reasons: saving power on a solar site, or a scheduled
restart.

POWER_OFF NEVER CUTS A RUNNING MODULE. The supply goes only after the module
has acknowledged its own power-down command or had its manual's time to
settle: cutting power while it writes to its flash can damage it.

POWER_ON concludes when the module answers - not when it has a data
connection, which GSM_MODEM.READY says. If CONNECT is FALSE on GSM_MODEM the
module stays down and POWER_ON says so.

---

## GSM_RADIO

```
Which radio, which bands, which operator. Optional: without it the module
searches everything it supports and the network chooses.

MODEM         which modem. Must be wired.
MODE          which technology to search for.
                GSM_RADIO_AUTO        leave the module's own setting alone
                GSM_RADIO_GSM_ONLY    2G
                GSM_RADIO_LTE_ONLY    4G
                GSM_RADIO_GSM_AND_LTE either
                GSM_RADIO_CAT_M       LTE-M (a low-power module only)
                GSM_RADIO_NB_IOT      NB-IoT (a low-power module only)
                GSM_RADIO_CAT_M_AND_NB_IOT  both
OPERATOR      the one network to use, as its numeric code (MCC and MNC, five
              or six digits, e.g. '53001'). Empty lets the module choose.
CAT_M_BANDS   LTE-M bands to search, as a list: '3, 28'. Empty searches all.
NB_IOT_BANDS  NB-IoT bands to search, the same way.

APPLIED       the settings reached the modem block.
ERROR         a value was not understood; nothing was changed.
STATUS        why. GSM_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `MODEM` | `GSM_MODEM` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `MODE` | `GSM_RADIO_MODE` |  |
| `OPERATOR` | `STRING(7)` |  |
| `CAT_M_BANDS` | `STRING(64)` |  |
| `NB_IOT_BANDS` | `STRING(64)` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `APPLIED` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `GSM_RESULT` |  |

radio( MODEM := modem, MODE := GSM_RADIO_CAT_M, CAT_M_BANDS := '3, 28' );

LEAVE IT ALONE UNLESS YOU KNOW THE SITE. A controller on a pole has to take
what it can get: pinning it to one technology or one network means a site
where that one is missing never connects, and nothing about that failure
explains itself.

THE BANDS ARE THE SETTING THAT SAVES TIME on a low-power (LTE-M / NB-IoT)
module. A fresh one searches every band it supports - dozens of slow scans -
and naming the one or two a country uses turns minutes into seconds. They do
nothing on an ordinary 4G (Cat-1) module such as the A7670.

The settings are read during the modem's bring-up. A change while the modem
is up starts the bring-up again, which drops the data connection for the
seconds that takes.

---

## GSM_SMS_RECEIVE

```
Text messages arriving at the SIM, one at a time.

MODEM       which modem. Must be wired.
ENABLE      TRUE takes messages as they arrive. FALSE leaves them on the SIM.

RECEIVED    one scan, when SENDER, TEXT, INDEX and SENT_AT describe a message
            that has just arrived.
SENDER      who sent it, as the network gives it: '+6400000000'.
TEXT        what it says, up to 160 characters.
INDEX       where the SIM had stored it. Informational: the message has
            already been deleted from the SIM.
SENT_AT     when the network's message centre took it, in UTC. DT#1970-01-01
            when the network gave no time.
COUNT       messages received since the PLC started.
ERROR       MODEM is not a running GSM_MODEM.
STATUS      why. GSM_OK when fine; GSM_NOT_READY until the network has
            accepted the SIM.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `MODEM` | `GSM_MODEM` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `ENABLE` | `BOOL` | `TRUE` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `RECEIVED` | `BOOL` |  |
| `SENDER` | `STRING(23)` |  |
| `TEXT` | `STRING(160)` |  |
| `INDEX` | `UINT` |  |
| `SENT_AT` | `DT` |  |
| `COUNT` | `UDINT` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `GSM_RESULT` |  |

inbox( MODEM := modem );
  IF inbox.RECEIVED AND inbox.SENDER = oncall AND inbox.TEXT = 'RESET' THEN
      resetAlarms := TRUE;
  END_IF;

EVERY MESSAGE IS DELETED FROM THE SIM once it has been read. A SIM holds a few
dozen; one that is full is refused new messages by the network, silently, and
on a remote site nobody notices until a command does not arrive. A message the
library cannot decode is deleted too, so it cannot hold a slot for ever.

RECEIVED IS ONE SCAN WIDE, and each scan hands over at most one message, so
several arriving together come out on successive scans. Act on the message in
the same scan, or copy it.

CHECK SENDER. Anybody who knows the number can send to it, and SENDER is the
only thing that says who did. A message carrying a command should be checked
against a list, and SENT_AT against the clock if an old message must not act.

Use ONE of these per PLC. A long message the sender's phone split into parts
arrives as its parts, each with its own RECEIVED.

Messages that arrive while ENABLE is FALSE stay on the SIM, unread.

---

## GSM_SMS_SEND

```
Sends one text message when you ask. Acted on the rising edge of REQ.

MODEM       which modem. Must be wired.
REQ         rising edge sends. Holding it TRUE does not send again.
NUMBER      who to, in international form: '+6400000000'. A national number
            is read by whichever network carries the message, which on a
            roaming IoT SIM may not be the country you meant.
TEXT        the message, up to 160 characters. Plain GSM characters - letters,
            digits, common punctuation - fit 160; anything else may not send.

BUSY        a level: the message is with the modem and not yet concluded.
DONE        one scan, when the network has accepted it.
ERROR       one scan, when it failed.
STATUS      why. GSM_OK when fine.
LAST_ERROR  the reason in words - the network's own where it gave one.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `MODEM` | `GSM_MODEM` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `REQ` | `BOOL` |  |
| `NUMBER` | `STRING(20)` |  |
| `TEXT` | `STRING(160)` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `BUSY` | `BOOL` |  |
| `DONE` | `BOOL` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `GSM_RESULT` |  |
| `LAST_ERROR` | `STRING(64)` |  |

alarmSms( MODEM := modem, REQ := highLevel, NUMBER := oncall,
            TEXT := 'Tank 3 high level' );

SMS NEEDS REGISTERED, NOT READY: a message goes over the network's signalling,
not the data connection, so it works on a SIM with no data plan and while the
data connection is down. A REQ before the network has accepted the SIM fails
at once with GSM_NOT_READY rather than waiting.

ONE AT A TIME. A rising edge while BUSY is not a second message; send it after
DONE or ERROR. Every message costs money on most plans, so a REQ wired to a
value that flickers is worth putting behind an R_TRIG and a timer.

DONE and ERROR are one scan wide, so latch them if a slower task has to see
one. BUSY is a level and is the pin to gate a sequence on.

---

## GSM_SOCKET

```
A TCP connection over the modem, plain or TLS, for a program that talks to a
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
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `MODEM` | `GSM_MODEM` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `OPEN` | `BOOL` |  |
| `HOST` | `STRING(63)` |  |
| `PORT` | `UINT` |  |
| `SECURITY` | `GSM_SECURITY` |  |
| `SEND` | `BOOL` |  |
| `TX_DATA` | `STRING(254)` |  |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `CONNECTED` | `BOOL` |  |
| `SENT` | `BOOL` |  |
| `RECEIVED` | `BOOL` |  |
| `RX_DATA` | `STRING(254)` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `GSM_RESULT` |  |
| `LAST_ERROR` | `STRING(64)` |  |

link( MODEM := modem, OPEN := modem.READY, HOST := 'telemetry.example.com',
        PORT := 9000, SEND := tick, TX_DATA := line );

NOTHING WAITS. Opening is started and CONNECTED says when it arrived; sending
is handed over and SENT says when it has gone. Receiving is a look at what has
already come in. A scan does a bounded amount of work, connection or not.

TEXT, NOT BYTES. TX_DATA and RX_DATA are STRINGs, so a byte of value zero ends
them. Use it for line protocols - a reading, a command, a reply.

A MODEM HAS FEW SOCKETS: two are open at most, shared with MQTT_CLIENT, and a
module carries at most two TLS sessions. One that cannot be had is
GSM_NO_SOCKET_AVAILABLE.

---

## GSM_STATUS

```
What the modem knows about itself and its network, for a diagnostic page.

MODEM          which modem. Must be wired.
REFRESH        how often to ask the module for its signal and registration.
               T#0s never asks; the values then change only when the module
               reports something by itself. Default T#30s.

RSSI           received signal strength, dBm. -113 is nothing, -51 is
               excellent. -32768 until the first reading.
RSRP           LTE reference signal power, dBm (-140 to -44), or -32768 when
               the module does not report it.
RSRQ           LTE reference signal quality, dB (-20 to -3), or -32768.
QUALITY        the signal judged: GSM_QUALITY_GOOD above -95 dBm,
               GSM_QUALITY_UNCERTAIN down to -105, GSM_QUALITY_BAD below.
REGISTRATION   what the network says about the SIM: home, roaming, searching,
               denied.
TECHNOLOGY     the radio in use: GSM_TECH_LTE, GSM_TECH_CAT_M and the rest.
OPERATOR       the network's name as the module reports it.
IP             the address the network gave this modem.
IMEI           the module's serial number.
ICCID          the SIM's serial number - the one printed on the card.
MODULE         the module family the library recognised, e.g. 'A76XX'.
FIRMWARE       the module's firmware revision.
SOCKETS_FREE   sockets still free for GSM_SOCKET and MQTT.
BRING_UPS      times the modem has been brought up since the PLC started.
RECOVERIES     times the library has had to recover it.
BEARER_LOSSES  times the data connection dropped.
REGISTRATION_LOSSES  times the network dropped the SIM.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `MODEM` | `GSM_MODEM` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `REFRESH` | `TIME` | `T#30s` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `RSSI` | `INT` | `-32768` |
| `RSRP` | `INT` | `-32768` |
| `RSRQ` | `INT` | `-32768` |
| `QUALITY` | `GSM_QUALITY` |  |
| `REGISTRATION` | `GSM_REGISTRATION` |  |
| `TECHNOLOGY` | `GSM_TECHNOLOGY` |  |
| `OPERATOR` | `STRING(32)` |  |
| `IP` | `STRING(46)` |  |
| `IMEI` | `STRING(20)` |  |
| `ICCID` | `STRING(24)` |  |
| `MODULE` | `STRING(16)` |  |
| `FIRMWARE` | `STRING(48)` |  |
| `SOCKETS_FREE` | `USINT` |  |
| `BRING_UPS` | `UDINT` |  |
| `RECOVERIES` | `UDINT` |  |
| `BEARER_LOSSES` | `UDINT` |  |
| `REGISTRATION_LOSSES` | `UDINT` |  |

status( MODEM := modem );

Reading this block costs nothing: the values are the ones the modem block
already holds. Only REFRESH sends anything to the module - three short
queries, and a query still waiting is replaced rather than repeated, so a
short REFRESH cannot build a backlog. Nothing here uses data on the SIM.

A COUNTER THAT KEEPS CLIMBING IS THE THING TO WATCH. One bring-up and no
recoveries is a healthy site. RECOVERIES or BEARER_LOSSES rising by the hour
is an antenna, a marginal signal or a network that is moving the SIM about -
usually visible as RSSI near -105 and QUALITY GSM_QUALITY_BAD.

---

## GSM_TIME

```
The time, from the mobile network. Costs no data: the network sets the
module's clock when it registers.

MODEM      which modem. Must be wired.
REFRESH    how often to read the module's clock. Default T#1h; between reads
           the time is carried forward on the PLC's own clock.

VALID      the network has set the clock, and it has been read.
UTC        the time now, in UTC.
LOCAL      the time now, as the network's time zone has it.
ZONE       the network's offset from UTC, in minutes: 780 is New Zealand
           summer time, 720 its winter.
AGE        how long ago the module's clock was last read.
ERROR      the module could not be asked, or MODEM is not a running
           GSM_MODEM.
STATUS     why. GSM_OK when fine.
```

**In-out**

| Pin | Type | Default |
| --- | --- | --- |
| `MODEM` | `GSM_MODEM` |  |

**Inputs**

| Pin | Type | Default |
| --- | --- | --- |
| `REFRESH` | `TIME` | `T#1h` |

**Outputs**

| Pin | Type | Default |
| --- | --- | --- |
| `VALID` | `BOOL` |  |
| `UTC` | `DT` |  |
| `LOCAL` | `DT` |  |
| `ZONE` | `INT` |  |
| `AGE` | `TIME` |  |
| `ERROR` | `BOOL` |  |
| `STATUS` | `GSM_RESULT` |  |

clock( MODEM := modem );
  IF clock.VALID THEN stamp := clock.UTC; END_IF;

NOT EVERY NETWORK SENDS THE TIME. The module learns it only from a network
that broadcasts it, and some never do - on those VALID stays FALSE, because a
clock still at the module's factory date is not a time. It is read again on
every REFRESH, so a SIM that roams onto a network that does send it becomes
VALID by itself.

It is accurate to about a second: good for timestamps, schedules and a
time-of-day interlock, not for anything that needs better.

---

**Next:** [03 MQTT over cellular](03-mqtt-over-cellular.md)
