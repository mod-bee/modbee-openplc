(* A cellular modem: a SIMCom SIM7070, SIM7080 or SIM7090
(LTE-M and NB-IoT). One block runs it - power, SIM,
network, data - and recovers it by itself; everything else the modem does is
a method of this block. Call it once every scan, in the task that calls its
methods. Only the SIM707x driver is linked; a module of another family is
refused by name (FB_GsmModemA7670 drives the A76XX family).

THE SIM707X FAMILY is low-power LTE: LTE-M (Cat-M) and NB-IoT, with 2G
on the SIM7070G. Checked against recorded module sessions; not yet run on
a live network. Its power key is pressed for half a second.
stRadioConfig MATTERS HERE: a fresh module searches every band it
supports - dozens of slow scans - and searching a technology that is not
on air never registers and never says why. Set eMode to the one the
SIM's network runs (CatM or NbIot) and the one or two bands the country
uses, and minutes become seconds.

ON A BOARD, the defaults are the ModBee Node UIO's HAT header: UART0 on
GPIO 44 (receive) and 43 (transmit), the power key on GPIO 10. On the
Node, switch the HAT on with node-uio's HAT_POWER.

bConnect     TRUE brings the modem up and keeps it up: power, SIM, network,
             data. FALSE stops bringing it up and stops recovering it; it does
             not power the module off - Power does that. On a board, once the
             modem is stopped and quiet its serial link, buffers and service
             task are given back (about 7 kB of internal RAM), and taken again
             when bConnect returns to TRUE.
sSimPin      the SIM's PIN, when it has one. Offered ONCE: a PIN the SIM
             refuses is not tried again until this changes, because three
             wrong entries lock the card behind its PUK.
stApnConfig  ST_GsmApnConfig, the data connection the SIM's provider gives.
               sApn       'internet', 'onomondo'. Up to 100 characters, the
                          3GPP maximum. Empty asks the network for its
                          default, which some networks give and some refuse
               sUserName  the APN's user name, when the provider gives one
               sPassword  its password
stSerialConfig  ST_GsmSerialConfig, how the PLC talks to the module.
               sDevice        the Runtime: the modem's serial port,
                              '/dev/ttyUSB2'. Not used on a board
               nBaudRate      115200, what both module families start at
               nUart          a board: the UART peripheral, 0 to 2, not a pin.
                              On the Node UIO keep 0 - UART1 and UART2 are its
                              RS485 channels
               nRxPin         a board: the GPIO it receives on (the module's
                              TX), -1 for the UART's own. Node UIO: 44
               nTxPin         a board: the GPIO it transmits on, -1 for the
                              UART's own. Node UIO: 43
               nRxBufferSize  a board: bytes of receive buffer, 256 to 32768.
                              Node UIO: 4096. The HAT header carries no RTS or
                              CTS, so an overflow scrambles the conversation
                              with the modem; the library reads no more at
                              once than this holds
stPowerConfig  ST_GsmPowerConfig, a board's power lines. Not used on the
             Runtime.
               nPowerKeyPin  the GPIO that presses the module's power key,
                             HIGH pressed; -1 none. Node UIO: 10. Pressed only
                             when the module does not answer, for exactly as
                             long as its datasheet asks
               nRailPin      the GPIO that switches the module's supply, HIGH
                             on; -1 when something else owns it. Node UIO: -1,
                             because the HAT rail is node-uio's HAT_POWER
stRadioConfig  ST_GsmRadioConfig, which radio, bands and network. Leave it
             alone unless you know the site: pinning a controller to one
             technology or network means a site where that one is missing
             never connects, and nothing explains itself.
               eMode        E_GsmRadioMode.Auto (default) leaves the module's
                            own setting; GsmOnly, LteOnly, GsmAndLte, CatM,
                            NbIot, CatMAndNbIot
               sOperator    the one network, MCC and MNC: '53001'. Empty lets
                            the module choose
               sCatMBands   LTE-M bands to search: '3, 28'. Empty searches all
               sNbIotBands  NB-IoT bands, the same way
             A setting that cannot be read is refused on bError, and the
             modem keeps the one it had.
stCapacityConfig  ST_GsmCapacityConfig, what the modem holds. Taken when the
             modem is first opened, in PSRAM where the board has it; more than
             the board can hold stops the modem with "out of memory for the
             sockets" (or "... for the AT command queue") on sLastError.
               nSocketCnt         sockets open at once - each Socket record
                                  and each MQTT client over the modem holds
                                  one. 2 by default; the module's own limit
                                  (10 or 13) still applies
               nSocketBufferSize  each socket's send and receive buffer, bytes.
                                  1500 by default. Memory is nSocketCnt x 2 x
                                  nSocketBufferSize
               nAtQueueLen        modem commands that may wait at once. 12 by
                                  default; raise it only if sLastError shows
                                  the queue full

bConnected   the modem has a data connection. Sockets and MQTT wait for it.
bRegistered  the network has accepted the SIM. SMS needs this, not
             bConnected.
eConnectionState  where the bring-up is: Off, PoweringUp, Syncing,
             Identifying, Configuring, SimWait, ReadingIdentity, NetworkSetup,
             Registering, BearerUp, Ready, Recovering, Failed.
bError       something failed: the modem is not connected and there is a
             reason, a setting was refused, or a method call failed.
eErrorId     why. E_GsmResult.Ok when fine.
sLastError   in words - the module's own where it gave one. A failing method
             call is named by its method and record: "SendSms sAlarm:
             NotReady".

---

  modem(bConnect := TRUE, stApnConfig := apn);

APN, user, password and sSimPin are ordinary inputs, so a program can feed
them from RETAIN variables and change them without a new download. Changing
one, or stRadioConfig, while the modem is up starts its bring-up again, which
drops the data connection for the seconds that takes. stSerialConfig,
stPowerConfig and stCapacityConfig are read when the modem is first opened;
a change later is reported on bError and takes effect at the next PLC start.

NOTHING HERE WAITS. Every scan does a bounded amount of work and returns; the
bring-up, the retries and the recovery run across scans by themselves. Give
the block a task of 20 ms or faster: the modem is read in bites each scan, so
a slow task is a slow modem.

RECOVERY IS AUTOMATIC. A lost network, a lost data connection or a module that
stops answering is recovered without the program doing anything: resync,
restart, power-key cycle, then a retry on a growing back-off.
eConnectionState and sLastError say what is happening.

ONE PER PLC. A second modem block does not run the modem; it says so on
bError, and its methods return E_GsmResult.NotInitialised. MQTT over the
modem needs no method: FB_MqttClient with eTransport :=
E_MqttTransport.Cellular reaches this modem by itself.

METHODS

Each returns an E_GsmResult. A method runs in this block's task and returns
E_GsmResult.WrongTask in any other. A call is found again by what it is
about: its ANY's declared name and type, or for a literal its text (SendSms:
the number). So one variable is one record per method. Up to 64 records.

A REQUEST (SendSms, AtCommand, Power) starts on a rising edge of bExecute and takes
its inputs at that edge; changing them while it runs has no effect. It
returns E_GsmResult.Queued while it runs, then its outcome, held until the
next edge. A modem that cannot take it at the edge refuses at once (NotReady)
rather than queueing it for later.

A STANDING METHOD (Inbox, SmsCommand, Socket, Status, NetworkTime,
Gnss) is called
every scan while it is wanted, and its inputs may change while it runs.
E_GsmResult.Ok means its outputs are valid; NotReady while the modem cannot
give them yet.

  modem.SendSms(anyText, sNumber, bExecute)
     ONE TEXT MESSAGE, up to 160 characters, on a rising edge. anyText is a
     STRING or a literal; sNumber international, '+6421...'. SMS needs
     bRegistered, not bConnected: it works on a SIM with no data plan.
     Queued until the network has accepted it, then Ok. NotReady (the network
     has not accepted the SIM), InvalidArgument (no number or text), TooLarge,
     or the network's refusal (ModuleError, with its words on sLastError).
     Every message costs money on most plans: put bExecute behind an edge.

  modem.Inbox(bEnable, bReceived =>, sSender =>, sText =>, nIndex =>,
              dtSentAt =>, nReceivedCnt =>)
     TEXT MESSAGES ARRIVING AT THE SIM, one at a time. bReceived is TRUE on
     the one call that takes a message; the rest hold the last message.
     dtSentAt is the message centre's time, in UTC. Every message is deleted
     from the SIM once read (a full SIM is refused new messages, silently),
     one that cannot be decoded too. CHECK sSender: anybody who knows the
     number can send to it. bEnable FALSE leaves arriving messages on the SIM.
     Ok, or NotReady until the network has accepted the SIM.

  modem.SmsCommand(sCommands, sAllowed, nPin, sAdminCommands, nAdminPin,
                   tPulse, nReply, sReplyText, nMaxPerHour, bEnable,
                   bCmd =>, nCmd =>, sMatched =>, sArg =>, fValue =>,
                   bValueOk =>, tDuration =>, bDurationOk =>, bAdmin =>,
                   sSentBy =>, nCmdCnt =>, nRefusedCnt =>, sLastRefused =>)
     TEXT-MESSAGE COMMANDS: a message from an allowed number that says one of
     sCommands' words sets bCmd for tPulse (T#0s: one call), and nCmd says
     which, from 1 in sCommands' order, then sAdminCommands'. The message is
     looked at FIRST, before anything that waits for the modem, so a command
     is never lost to a busy modem; only the reply waits. Needs no Inbox call.
       sCommands       'START, STOP, SET TIME'; upper or lower case, extra
                       spaces all the same. The record is found by this text
       sAllowed        numbers separated by commas or semicolons, matched on
                       their last 8 digits ('+64 21 123 4567' = '021 123
                       4567'); a name or short code ('PTT NZ', '2001') is
                       matched whole. Empty: nobody. '*': anybody - only with
                       a PIN
       nPin            0: none; above 0 the message starts with it: '1111 START'
       sAdminCommands  commands that need nAdminPin ('9999 REBOOT')
       nAdminPin       0: no admin level; it works for sCommands too
       nReply          0 never answer; 1 an accepted command ('OK REBOOT');
                       2 also say why a message was refused - only ever to a
                       number on sAllowed
       sReplyText      the answer instead of 'OK <command> <argument>'
       nMaxPerHour     the most it acts in an hour; 0 no limit
     sArg is what followed the command; fValue it as a number (bValueOk);
     tDuration it as a time - '3H30M10S', '90M', '1.5H' (bDurationOk).
     nRefusedCnt and sLastRefused count and say why messages were refused.
     Ok; NotReady while the modem is not open; a reply's failure until the
     next reply goes.

  modem.AtCommand(anyCommand, tTimeout, bExecute, sReply =>)
     ONE AT COMMAND of your own, the escape hatch: 'AT+CPSI?'. It joins the
     modem's own queue and concludes exactly once. tTimeout T#5s by default,
     at most T#180s. sReply is every line before the OK or ERROR, up to 254
     characters. Ok, NotReady (the module has not answered yet), Timeout,
     ModuleError ('+CME ERROR: 10, SIM not inserted' on sLastError), Error.
     A command that turns the radio off or closes the data connection does
     exactly that, and the block recovers from it as from any other fault.

  modem.Power(ePower, bExecute, bPowered =>, bBusy =>)
     THE MODULE OFF, ON AGAIN, OR RESTARTED, on a rising edge.
     E_GsmPower.SwitchOff shuts it down properly - its own power-down command
     first, then its supply where the board switches one - and keeps it off;
     SwitchOn lets it run again; Restart resets it with its own command and
     brings it back up. bPowered is FALSE from SwitchOff until SwitchOn.
     Queued, then Ok; NotReady (Restart before the module has answered, or
     SwitchOn with bConnect FALSE), Timeout. The library already restarts and
     power-cycles a module that stops answering, so this is for the program's
     own reasons: a solar site's night, a scheduled restart.

  modem.Socket(anyRxData, sHost, nPort, eSecurity, bOpen, sTxData, bSend,
               bSocketConnected =>, bSent =>, bReceived =>, nRxLen =>)
     A TCP CONNECTION over the modem, for a program that talks to a server
     itself. bOpen TRUE opens it and keeps it open, reopening it five seconds
     after it fails; FALSE closes it. eSecurity E_GsmSecurity.Tls is the
     module's own TLS, which encrypts and checks no certificate. A rising
     edge of bSend sends sTxData; bSent is TRUE on the call it has all left.
     What arrives is written into anyRxData, a STRING, up to its length a
     call; bReceived and nRxLen on that call. Text, not bytes: a zero byte
     ends a STRING. The record is anyRxData's. Ok while connected; NotReady
     while opening or with no data connection, NoSocketAvailable,
     SocketClosed, BearerLost, InvalidArgument.

  modem.Status(tRefresh, nRssi =>, nRsrp =>, nRsrq =>, eQuality =>,
               eRegistration =>, eTechnology =>, sOperator =>, sIpAddr =>,
               sImei =>, sIccid =>, sModule =>, sFirmware =>,
               nSocketsFree =>, nBringUpCnt =>, nRecoveryCnt =>,
               nBearerLossCnt =>, nRegistrationLossCnt =>)
     WHAT THE MODEM KNOWS, for a diagnostic page. Reading costs nothing; only
     tRefresh (T#30s; T#0s never) asks the module for its signal and
     registration. nRssi dBm (-113 nothing, -51 excellent; -32768 never
     read), nRsrp and nRsrq LTE's, eQuality Good above -95 dBm, Uncertain to
     -105, Bad below. A counter that keeps climbing is the thing to watch: one
     bring-up and no recoveries is a healthy site. Ok once the module has
     answered; NotReady before.

  modem.NetworkTime(tRefresh, bValid =>, dtUtc =>, dtLocal =>,
                    nUtcOffset =>, tAge =>)
     THE TIME FROM THE MOBILE NETWORK, at no data cost, read every tRefresh
     (T#1h) and carried forward on the PLC's clock between. nUtcOffset is the
     network's offset in minutes (780: New Zealand summer time). Not every
     network sends the time: there bValid stays FALSE. Ok when valid,
     NotReady before, NotSupportedByModule.

  modem.Gnss(bEnable, tRefresh, bSupported =>, bFix =>, fLatitude =>,
             fLongitude =>, fAltitude =>, nSatellites =>, tAge =>)
     WHERE THE MODULE IS, from its own satellite receiver where it has one.
     bEnable TRUE powers the receiver and reads it every tRefresh (T#5s);
     FALSE powers it down. tAge is the pin to alarm on, not bFix: a receiver
     that loses the sky keeps its last position. From cold a first fix takes
     a minute or more; the receiver needs its own antenna. Ok while the
     receiver runs, NotSupportedByModule on a module without one. *)

FUNCTION_BLOCK FB_GsmModemSim7070
  VAR_INPUT
    bConnect : BOOL := TRUE;                  (* TRUE brings the modem up and keeps it up *)
    sSimPin : STRING(8);                      (* the SIM's PIN, offered once *)
    stApnConfig : ST_GsmApnConfig;            (* the APN, its user name and password *)
    stSerialConfig : ST_GsmSerialConfig;      (* the serial device or the board's UART and pins *)
    stPowerConfig : ST_GsmPowerConfig;        (* a board's power key and supply rail *)
    stRadioConfig : ST_GsmRadioConfig;        (* radio mode, operator and bands *)
    stCapacityConfig : ST_GsmCapacityConfig;  (* sockets, socket buffers and the command queue *)
  END_VAR
  VAR_OUTPUT
    bConnected : BOOL;                (* the modem has a data connection *)
    bRegistered : BOOL;               (* the network has accepted the SIM *)
    eConnectionState : E_GsmState;    (* where the bring-up is *)
    bError : BOOL;                    (* something failed *)
    eErrorId : E_GsmResult;           (* why; Ok when fine *)
    sLastError : STRING(64);          (* why, in words *)
  END_VAR
  VAR
    nId : UDINT;                      (* this instance's number; the modem's owner is one *)
    nTask : __XWORD;                  (* the task this block runs in, for its methods *)
    bRunning : BOOL;                  (* the modem was started *)
  END_VAR

(* Sends anyText to sNumber once, on a rising edge of bExecute. Returns
   E_GsmResult.Queued until the network has accepted it, then Ok or the
   reason, until the next edge. *)
METHOD PUBLIC SendSms : E_GsmResult
  VAR_INPUT
    anyText : ANY;              (* the message: a STRING or a literal, up to 160 characters *)
    sNumber : STRING(20);       (* who to, international: '+6421...' *)
    bExecute : BOOL;            (* rising edge sends *)
  END_VAR
END_METHOD

(* Text messages arriving at the SIM, one a call, called every scan. Each is
   deleted from the SIM once read. *)
METHOD PUBLIC Inbox : E_GsmResult
  VAR_INPUT
    bEnable : BOOL := TRUE;     (* FALSE leaves arriving messages on the SIM *)
  END_VAR
  VAR_OUTPUT
    bReceived : BOOL;           (* this call took a message *)
    sSender : STRING(23);       (* who sent it: '+6421...', or a name *)
    sText : STRING(160);        (* what it says *)
    nIndex : UINT;              (* where the SIM had stored it; already deleted *)
    dtSentAt : DT;              (* when the message centre took it, UTC *)
    nReceivedCnt : UDINT;       (* messages taken since the PLC started *)
  END_VAR
END_METHOD

(* Text-message commands from allowed numbers, called every scan: bCmd is TRUE
   for tPulse when a message said one of sCommands or sAdminCommands, and nCmd
   says which. Found by sCommands. *)
METHOD PUBLIC SmsCommand : E_GsmResult
  VAR_INPUT
    sCommands : STRING(160);        (* the commands, comma separated: 'START, STOP' *)
    sAllowed : STRING(200);         (* who may send them; empty nobody, '*' anybody *)
    nPin : DINT;                    (* the operator PIN; 0 none *)
    sAdminCommands : STRING(160);   (* commands that need nAdminPin *)
    nAdminPin : DINT;               (* the admin PIN; 0 no admin level *)
    tPulse : TIME;                  (* how long bCmd stays TRUE; T#0s one call *)
    nReply : USINT := 1;            (* 0 never answer, 1 an accepted command, 2 also a refusal *)
    sReplyText : STRING(140);       (* the answer instead of 'OK <command> <argument>' *)
    nMaxPerHour : UINT := 10;       (* the most it acts in an hour; 0 no limit *)
    bEnable : BOOL := TRUE;         (* FALSE ignores every message *)
  END_VAR
  VAR_OUTPUT
    bCmd : BOOL;                    (* TRUE for tPulse after an accepted command *)
    nCmd : INT;                     (* which, from 1 in sCommands' order, then sAdminCommands' *)
    sMatched : STRING(32);          (* its words, upper case *)
    sArg : STRING(64);              (* what followed the command *)
    fValue : REAL;                  (* sArg as a number *)
    bValueOk : BOOL;                (* sArg was a number *)
    tDuration : TIME;               (* sArg as a time: '3H30M', '90M' *)
    bDurationOk : BOOL;             (* sArg was a time *)
    bAdmin : BOOL;                  (* it came with nAdminPin *)
    sSentBy : STRING(23);           (* who sent it *)
    nCmdCnt : UDINT;                (* commands accepted *)
    nRefusedCnt : UDINT;            (* messages that named a command and were refused *)
    sLastRefused : STRING(64);      (* why, and from whom *)
  END_VAR
END_METHOD

(* Sends one AT command of your own on a rising edge of bExecute and hands back
   the reply. Queued until the module answers, then Ok or the reason, until
   the next edge. *)
METHOD PUBLIC AtCommand : E_GsmResult
  VAR_INPUT
    anyCommand : ANY;           (* the command, a STRING or a literal: 'AT+CSQ' *)
    tTimeout : TIME := T#5s;    (* how long the module has; at most T#180s *)
    bExecute : BOOL;            (* rising edge sends *)
  END_VAR
  VAR_OUTPUT
    sReply : STRING(254);       (* the module's lines before its OK or ERROR *)
  END_VAR
END_METHOD

(* Powers the module off, on again, or restarts it, on a rising edge of
   bExecute. Queued while it runs, then Ok or the reason. *)
METHOD PUBLIC Power : E_GsmResult
  VAR_INPUT
    ePower : E_GsmPower;        (* SwitchOff, SwitchOn or Restart *)
    bExecute : BOOL;            (* rising edge starts it *)
  END_VAR
  VAR_OUTPUT
    bPowered : BOOL;            (* FALSE from SwitchOff until SwitchOn *)
    bBusy : BOOL;               (* an operation is under way *)
  END_VAR
END_METHOD

(* A TCP connection over the modem, called every scan. bOpen keeps it open;
   what arrives is written into anyRxData. Found by anyRxData. *)
METHOD PUBLIC Socket : E_GsmResult
  VAR_INPUT
    anyRxData : ANY;            (* a STRING: what arrived is written here *)
    sHost : STRING(63);         (* the server: a name or an address *)
    nPort : UINT;               (* its port *)
    eSecurity : E_GsmSecurity;  (* Plain, or Tls done by the module *)
    bOpen : BOOL;               (* TRUE opens it and keeps it open; FALSE closes it *)
    sTxData : STRING(254);      (* sent on a rising edge of bSend *)
    bSend : BOOL;               (* rising edge sends sTxData *)
  END_VAR
  VAR_OUTPUT
    bSocketConnected : BOOL;    (* the connection is open *)
    bSent : BOOL;               (* this call: all of sTxData has left *)
    bReceived : BOOL;           (* this call: anyRxData holds what just arrived *)
    nRxLen : INT;               (* characters written into anyRxData *)
  END_VAR
END_METHOD

(* What the modem knows about itself and its network, called every scan.
   Reading costs nothing; tRefresh asks the module for its signal. *)
METHOD PUBLIC Status : E_GsmResult
  VAR_INPUT
    tRefresh : TIME := T#30s;   (* how often to ask for signal and registration; T#0s never *)
  END_VAR
  VAR_OUTPUT
    nRssi : INT;                (* signal strength, dBm; -32768 never read *)
    nRsrp : INT;                (* LTE reference signal power, dBm, or -32768 *)
    nRsrq : INT;                (* LTE reference signal quality, dB, or -32768 *)
    eQuality : E_GsmQuality;    (* Good above -95 dBm, Uncertain to -105, Bad below *)
    eRegistration : E_GsmRegistration;  (* what the network says about the SIM *)
    eTechnology : E_GsmTechnology;      (* the radio in use *)
    sOperator : STRING(32);     (* the network's name *)
    sIpAddr : STRING(46);       (* the address the network gave the modem *)
    sImei : STRING(20);         (* the module's serial number *)
    sIccid : STRING(24);        (* the SIM's serial number, as printed on it *)
    sModule : STRING(16);       (* the module family the library recognised *)
    sFirmware : STRING(48);     (* the module's firmware revision *)
    nSocketsFree : USINT;       (* sockets still free *)
    nBringUpCnt : UDINT;        (* bring-ups since the PLC started *)
    nRecoveryCnt : UDINT;       (* times the library recovered it *)
    nBearerLossCnt : UDINT;     (* times the data connection dropped *)
    nRegistrationLossCnt : UDINT;  (* times the network dropped the SIM *)
  END_VAR
END_METHOD

(* The time from the mobile network, called every scan. Costs no data. *)
METHOD PUBLIC NetworkTime : E_GsmResult
  VAR_INPUT
    tRefresh : TIME := T#1h;    (* how often to read the module's clock *)
  END_VAR
  VAR_OUTPUT
    bValid : BOOL;              (* the network has set the clock, and it has been read *)
    dtUtc : DT;                 (* the time now, UTC *)
    dtLocal : DT;               (* the time now, in the network's time zone *)
    nUtcOffset : INT;           (* the network's offset from UTC, minutes *)
    tAge : TIME;                (* since the module's clock was last read *)
  END_VAR
END_METHOD

(* Where the module is, from its own satellite receiver, called every scan. *)
METHOD PUBLIC Gnss : E_GsmResult
  VAR_INPUT
    bEnable : BOOL := TRUE;     (* TRUE powers the receiver and reads it; FALSE powers it down *)
    tRefresh : TIME := T#5s;    (* how often to read the fix *)
  END_VAR
  VAR_OUTPUT
    bSupported : BOOL;          (* the module has a receiver *)
    bFix : BOOL;                (* a position is known and current *)
    fLatitude : LREAL;          (* degrees, north positive *)
    fLongitude : LREAL;         (* degrees, east positive *)
    fAltitude : REAL;           (* metres above sea level *)
    nSatellites : USINT;        (* satellites in view *)
    tAge : TIME;                (* since the fix was last confirmed; T#0s before the first *)
  END_VAR
END_METHOD

#include <ModBeeGsmPlc.h>
#include <GsmPlcMethods.h>

void setup()
{
    bConnected = false;
    bRegistered = false;
    eConnectionState = E_GSMSTATE::OFF;
    bError = false;
    eErrorId = E_GSMRESULT::OK;
    sLastError = "";
    nId = gsmplc::nextId();
    nTask = (strucpp::XWORD_t)0;
    bRunning = false;
}

void loop()
{
    nTask = (strucpp::XWORD_t)gsmplc::currentTask();

    // Another task is inside the modem - most likely an MQTT client in its
    // connect(), which pumps the modem itself. Stand back for a scan; the
    // outputs keep what they last said.
    gsmplc::TryHold hold;
    if (!hold.owned()) return;

    if (!gsmplc::claim((uint32_t)nId)) {
        bConnected = false;
        bRegistered = false;
        eConnectionState = E_GSMSTATE::OFF;
        bError = true;
        eErrorId = E_GSMRESULT::INVALIDARGUMENT;
        sLastError = "another modem block runs the modem; a PLC has one";
        return;
    }
    // Holding only this module's driver: the other family is never linked.
    if (!gsmplc::makeDevice<GsmDeviceWith<GsmDriverSIM707x>>("SIM707x")) {
        bError = true;
        eErrorId = E_GSMRESULT::NOTINITIALISED;
        sLastError = "out of memory for the modem";
        return;
    }

    // --- what the program asked for -----------------------------------------
    gsmplc::Link link;
    link.port = (int32_t)(uint8_t)stSerialConfig.NUART;
    link.rxPin = (int32_t)(int16_t)stSerialConfig.NRXPIN;
    link.txPin = (int32_t)(int16_t)stSerialConfig.NTXPIN;
    link.rxBuffer = (int32_t)stSerialConfig.NRXBUFFERSIZE;
    link.keyPin = (int32_t)(int16_t)stPowerConfig.NPOWERKEYPIN;
    link.railPin = (int32_t)(int16_t)stPowerConfig.NRAILPIN;
    {
        const char* path = stSerialConfig.SDEVICE.c_str();
        size_t n = 0;
        for (; n + 1 < sizeof link.path && path[n] != '\0'; n++) link.path[n] = path[n];
        link.path[n] = '\0';
    }
    link.baud = (int32_t)stSerialConfig.NBAUDRATE > 0 ? (uint32_t)(int32_t)stSerialConfig.NBAUDRATE
                                                      : 115200u;
    link.sockets = (int32_t)(uint8_t)stCapacityConfig.NSOCKETCNT;
    link.socketBuffer = (int32_t)(uint16_t)stCapacityConfig.NSOCKETBUFFERSIZE;
    link.atQueue = (int32_t)(uint8_t)stCapacityConfig.NATQUEUELEN;
#if !defined(GSM_PLATFORM_ARDUINO)
    // The Runtime has no board pins: they are not compared, so a change to
    // them is no change.
    link.port = 0; link.rxPin = 44; link.txPin = 43; link.rxBuffer = 4096;
    link.keyPin = 10; link.railPin = -1;
#endif
    const char* linkRefused = gsmplc::checkLink(link);
    const int radioMode = (int)(strucpp::E_GSMRADIOMODE)stRadioConfig.EMODE;
    const char* radioRefused = gsmplc::checkRadio(radioMode, stRadioConfig.SOPERATOR.c_str(),
                                                  stRadioConfig.SCATMBANDS.c_str(),
                                                  stRadioConfig.SNBIOTBANDS.c_str());

    bool changed = false;
    if (gsmplc::apn(stApnConfig.SAPN.c_str(), stApnConfig.SUSERNAME.c_str(),
                    stApnConfig.SPASSWORD.c_str())) changed = true;
    if (gsmplc::pin(sSimPin.c_str())) changed = true;
    // A radio setting that cannot be read is refused whole: the modem keeps
    // the one it had rather than half of the new one.
    if (radioRefused == nullptr &&
        gsmplc::radio((GsmRadioPreference)radioMode, stRadioConfig.SOPERATOR.c_str(),
                      stRadioConfig.SCATMBANDS.c_str(), stRadioConfig.SNBIOTBANDS.c_str())) {
        changed = true;
    }

    const bool want = (bool)bConnect && !gsmplc::heldOff();
    GsmDeviceBase& gsm = gsmplc::device();
    // Switched off, the modem gives its serial link and the RAM behind it
    // back once it is quiet (gsmplc::service()); switched on, it takes it again.
    gsmplc::want(want);

    // --- open once, then start and stop ---------------------------------------
    if (!gsmplc::isOpen()) {
        if (want) {
            const char* why = linkRefused;
            if (why != nullptr || !gsmplc::open(link, &why)) {
                bConnected = false;
                bRegistered = false;
                eConnectionState = E_GSMSTATE::OFF;
                bError = true;
                eErrorId = E_GSMRESULT::INVALIDARGUMENT;
                sLastError = why != nullptr ? why : "the modem would not open";
                return;
            }
            bRunning = true;
        }
    } else {
        if (want && !(bool)bRunning) {
            const char* why = nullptr;
            if (!gsmplc::takeLink(&why)) {
                // Tried again next scan: bRunning stays FALSE.
                bConnected = false;
                bRegistered = false;
                eConnectionState = E_GSMSTATE::OFF;
                bError = true;
                eErrorId = E_GSMRESULT::NOTREADY;
                sLastError = why != nullptr ? why : "the modem's serial link would not open";
                gsmplc::service();
                gsmplc::tickCalls((uint32_t)nId);
                return;
            }
            gsm.start();
        } else if (!want && (bool)bRunning) {
            gsm.stop();
        } else if (want && changed) {
            // A new APN, PIN or radio setting is read during bring-up, so the
            // bring-up runs again for it.
            gsm.stop();
            gsm.start();
        }
        bRunning = want;
    }

    gsmplc::service();
    gsmplc::tickCalls((uint32_t)nId);

    // --- what it is doing ----------------------------------------------------
    bConnected = gsm.isReady();
    bRegistered = gsm.isRegistered();
    eConnectionState = (E_GSMSTATE)(int)gsm.state();

    if ((bool)bConnected) {
        bError = false;
        eErrorId = E_GSMRESULT::OK;
        sLastError = "";
    } else if (!want) {
        bError = false;
        eErrorId = gsmplc::heldOff() ? E_GSMRESULT::POWEREDOFF : E_GSMRESULT::NOTREADY;
        sLastError = gsmplc::heldOff() ? "switched off by Power" : "bConnect is FALSE";
    } else {
        const GsmResult why = gsm.lastError();
        if (why.isOk() || why.status() == GsmStatus::Queued) {
            bError = false;
            eErrorId = E_GSMRESULT::NOTREADY;
            sLastError = "";
        } else {
            bError = true;
            eErrorId = (E_GSMRESULT)(int)why.status();
            sLastError = gsmplc::describe(why);
        }
    }

    // Said, not silently ignored: the modem keeps running on what it opened
    // with, and the new settings wait for the next start.
    if (gsmplc::isOpen() && !gsmplc::sameLink(gsmplc::openedWith(), link)) {
        bError = true;
        eErrorId = E_GSMRESULT::INVALIDARGUMENT;
        sLastError = "link settings changed; they apply at the next PLC start";
    }
    if (radioRefused != nullptr) {
        bError = true;
        eErrorId = E_GSMRESULT::INVALIDARGUMENT;
        sLastError = radioRefused;
    }

    // A method call that failed, by method and record, where the modem itself
    // has nothing to report.
    int failed = 0;
    const char* callFailed = gsmplc::callError(&failed);
    if (callFailed != nullptr && !(bool)bError) {
        bError = true;
        eErrorId = (E_GSMRESULT)failed;
        sLastError = callFailed;
    }
}

// =============================================================================
// THE METHODS - each moves its parameters into gsmplc's and its outputs back
// =============================================================================

E_GSMRESULT SendSms()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    call.name = anyText.NAME;
    call.type = anyText.TYPENAME;
    call.key = sNumber.c_str();      // a literal text is found by its number
    const char* text = nullptr;
    size_t length = 0;
    if (anyText.wired() && anyText.TYPECLASS == strucpp::TYPE_STRING) {
        text = (const char*)anyText.PVALUE;
        while (length < (size_t)anyText.DISIZE && text[length] != '\0') length++;
    }
    return (E_GSMRESULT)gsmplc::sendSmsCall(call, text, length, sNumber.c_str(), (bool)bExecute);
}

E_GSMRESULT Inbox()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    gsmplc::InboxView view;
    const int result = gsmplc::inboxCall(call, (bool)bEnable, view);
    bReceived = view.received;
    sSender = view.sender;
    sText = view.text;
    nIndex = view.index;
    dtSentAt = view.sentAtNs;
    nReceivedCnt = view.count;
    return (E_GSMRESULT)result;
}

E_GSMRESULT SmsCommand()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    call.key = sCommands.c_str();
    gsmplc::CommandSpec spec;
    spec.commands = sCommands.c_str();
    spec.allowed = sAllowed.c_str();
    spec.pin = (int32_t)nPin;
    spec.adminCommands = sAdminCommands.c_str();
    spec.adminPin = (int32_t)nAdminPin;
    spec.pulseMs = gsmplc::millisOf(tPulse.get());
    spec.reply = (uint8_t)nReply;
    spec.replyText = sReplyText.c_str();
    spec.maxPerHour = (uint16_t)nMaxPerHour;
    spec.enable = (bool)bEnable;
    gsmplc::CommandView view;
    const int result = gsmplc::smsCommandCall(call, spec, view);
    bCmd = view.active;
    nCmd = view.which;
    sMatched = view.matched;
    sArg = view.arg;
    fValue = view.value;
    bValueOk = view.valueOk;
    tDuration = view.durationNs;
    bDurationOk = view.durationOk;
    bAdmin = view.admin;
    sSentBy = view.sentBy;
    nCmdCnt = view.count;
    nRefusedCnt = view.refused;
    sLastRefused = view.lastRefused;
    return (E_GSMRESULT)result;
}

E_GSMRESULT AtCommand()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    call.name = anyCommand.NAME;
    call.type = anyCommand.TYPENAME;
    const char* command = nullptr;
    size_t length = 0;
    if (anyCommand.wired() && anyCommand.TYPECLASS == strucpp::TYPE_STRING) {
        command = (const char*)anyCommand.PVALUE;
        while (length < (size_t)anyCommand.DISIZE && command[length] != '\0') length++;
    }
    call.key = command != nullptr ? command : "";   // a literal command is found by its text
    const char* reply = "";
    const int result = gsmplc::atCall(call, command, length, gsmplc::millisOf(tTimeout.get()),
                                      (bool)bExecute, &reply);
    sReply = reply;
    return (E_GSMRESULT)result;
}

E_GSMRESULT Power()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    gsmplc::PowerView view;
    const int result = gsmplc::powerCall(call, (int)(E_GSMPOWER)ePower, (bool)bExecute, view);
    bPowered = view.powered;
    bBusy = view.busy;
    return (E_GSMRESULT)result;
}

E_GSMRESULT Socket()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    call.name = anyRxData.NAME;
    call.type = anyRxData.TYPENAME;
    call.key = sHost.c_str();
    gsmplc::SocketSpec spec;
    spec.host = sHost.c_str();
    spec.port = (uint16_t)nPort;
    spec.tls = (E_GSMSECURITY)eSecurity == E_GSMSECURITY::TLS;
    spec.open = (bool)bOpen;
    spec.tx = sTxData.c_str();
    spec.txLength = sTxData.length();
    spec.send = (bool)bSend;
    if (anyRxData.wired() && anyRxData.TYPECLASS == strucpp::TYPE_STRING) {
        spec.rx = (char*)anyRxData.PVALUE;
        spec.rxCapacity = (size_t)anyRxData.DISIZE;
    }
    gsmplc::SocketView view;
    int result = gsmplc::socketCall(call, spec, view);
    if (spec.rx == nullptr && (bool)bOpen && result == (int)E_GSMRESULT::OK) {
        result = (int)E_GSMRESULT::INVALIDARGUMENT;   // nowhere to put what arrives
    }
    bSocketConnected = view.connected;
    bSent = view.sent;
    bReceived = view.received;
    nRxLen = (int16_t)view.rxLength;
    return (E_GSMRESULT)result;
}

E_GSMRESULT Status()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    const gsmplc::StatusView* view = nullptr;
    const int result = gsmplc::statusCall(call, gsmplc::millisOf(tRefresh.get()), &view);
    nRssi = view->rssi;
    nRsrp = view->rsrp;
    nRsrq = view->rsrq;
    eQuality = (E_GSMQUALITY)view->quality;
    eRegistration = (E_GSMREGISTRATION)view->registration;
    eTechnology = (E_GSMTECHNOLOGY)view->technology;
    sOperator = view->operatorName;
    sIpAddr = view->ipAddress;
    sImei = view->imei;
    sIccid = view->iccid;
    sModule = view->module;
    sFirmware = view->firmware;
    nSocketsFree = view->socketsFree;
    nBringUpCnt = view->bringUps;
    nRecoveryCnt = view->recoveries;
    nBearerLossCnt = view->bearerLosses;
    nRegistrationLossCnt = view->registrationLosses;
    return (E_GSMRESULT)result;
}

E_GSMRESULT NetworkTime()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    gsmplc::TimeView view;
    const int result = gsmplc::timeCall(call, gsmplc::millisOf(tRefresh.get()), view);
    bValid = view.valid;
    dtUtc = view.utcNs;
    dtLocal = view.localNs;
    nUtcOffset = view.zoneMinutes;
    tAge = view.ageNs;
    return (E_GSMRESULT)result;
}

E_GSMRESULT Gnss()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    gsmplc::GnssView view;
    const int result = gsmplc::gnssCall(call, (bool)bEnable, gsmplc::millisOf(tRefresh.get()),
                                        view);
    bSupported = view.supported;
    bFix = view.fix;
    fLatitude = view.latitude;
    fLongitude = view.longitude;
    fAltitude = view.altitude;
    nSatellites = view.satellites;
    tAge = view.ageNs;
    return (E_GSMRESULT)result;
}

END_FUNCTION_BLOCK
