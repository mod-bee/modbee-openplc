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
on air never registers and never says why. Set eRadioMode to the one the
SIM's network runs (CatM or NbIot) and the one or two bands the country
uses, and minutes become seconds.

ON A BOARD, the defaults are the ModBee Node UIO's HAT header: UART0 on
GPIO 44 (receive) and 43 (transmit), the power key on GPIO 10. On the
Node, switch the HAT on with node-uio's FB_HatPower.

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
               sApn       'internet'. Up to 100 characters, the
                          3GPP maximum. Empty asks the network for its
                          default, which some networks give and some refuse
               sUserName  the APN's user name, when the provider gives one
               sUserPassword  its password
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
               nReceiveBufferSize  a board: bytes of receive buffer, 256 to 32768.
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
               nSupplySwitchPin  the GPIO that switches the module's supply, HIGH
                             on; -1 when something else owns it. Node UIO: -1,
                             because the HAT rail is node-uio's FB_HatPower
stRadioConfig  ST_GsmRadioConfig, which radio, bands and network. Leave it
             alone unless you know the site: pinning a controller to one
             technology or network means a site where that one is missing
             never connects, and nothing explains itself.
               eRadioMode   E_GsmRadioMode.Auto (default) leaves the module's
                            own setting; GsmOnly, LteOnly, GsmAndLte, CatM,
                            NbIot, CatMAndNbIot
               sOperatorCode  the one network, MCC and MNC: '53001'. Empty lets
                            the module choose
               sCatMBands   LTE-M bands to search: '3, 28'. Empty searches all
               sNbIotBands  NB-IoT bands, the same way
             A setting that cannot be read is refused on bError, and the
             modem keeps the one it had.
stCapacityConfig  ST_GsmCapacityConfig, what the modem holds. Taken when the
             modem is first opened, in PSRAM where the board has it; more than
             the board can hold stops the modem with "out of memory for the
             sockets" (or "... for the AT command queue") on sLastError.
               nSockets           sockets open at once - each Socket record
                                  and each MQTT client over the modem holds
                                  one. 2 by default; the module's own limit
                                  (10 or 13) still applies
               nSocketBufferSize  each socket's send and receive buffer, bytes.
                                  1500 by default. Memory is nSockets x 2 x
                                  nSocketBufferSize
               nMaxPendingAtCommands  modem commands that may wait at once. 12 by
                                  default; raise it only if sLastError shows
                                  the queue full
stSmsConfig  ST_GsmSmsConfig, SendSms's queue. Not retained: the hour
             restarts at boot.
               nMaxPendingSms  messages (a number and its text) waiting, 1 to 64.
                            8 by default
               nMaxSmsPerHour  messages queued an hour, every number counted; past
                            it SendSms returns RateLimited. 10 by default; 0
                            no limit
               nRetriesBeforeDrop  a failed send is tried again this many times,
                            then dropped. 1 by default
               tRetryAfter  how long before it is. T#60s by default

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
             call is named by its method and record, the variable wired to
             its ANY: "AtCommand sQuery: Timeout".
nSmsSentCount, nSmsSendFailureCount, nSmsDroppedCount, nPendingSms, sSmsLastError
             SendSms's queue: messages the network took, sends that failed
             (each try), messages dropped (queue full, the hour's limit,
             retries spent), messages waiting, and why the last send failed
             with its number: 'send +6421000001: <why>'.

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

Each returns an E_GsmResult, but Format, which returns its text. A method
runs in this block's task and returns E_GsmResult.WrongTask in any other. A
call is found again by what it is about: its ANY's declared name and type, or
for a literal its text (SendSmsRequest: the number). So one variable is one
record per method: call each method with its own variable. Up to 64
records.

SendSms QUEUES: every call is one message to each number, accepted or refused
at once. Call it on the scan the program decides to send, not every scan.

A REQUEST (SendSmsRequest, AtCommand, Power) starts on a rising edge of
bExecute and takes its inputs at that edge; changing them while it runs has
no effect. It
returns E_GsmResult.Queued while it runs, then its outcome, held until the
next edge. A modem that cannot take it at the edge refuses at once (NotReady)
rather than queueing it for later.

A STANDING METHOD (Inbox, SmsCommand, Socket, Status, NetworkTime, Gnss) is
called every scan while it is wanted, and its inputs may change while it runs.
E_GsmResult.Ok means its outputs are valid; NotReady while the modem cannot
give them yet.

  modem.SendSms(anyPhoneNumbers, anyMessageText)
     TEXT MESSAGES, QUEUED: anyMessageText to every number of anyPhoneNumbers ('+6421000001,
     +6421000002'; ',' or ';' between them, spaces ignored), one message to
     each, all queued or none. Call it ONCE per message, on the scan the
     program decides to send: every call queues. Both are a STRING of any
     length or a literal. Returns at once:
       Ok               all queued
       InvalidArgument  an empty list, a number with letters or other
                        characters ('MyTelco' cannot be texted), a text that
                        is empty, over 160 GSM characters (an escaped one,
                        such as { } [ ] ~ ^ | or the euro sign, counts two)
                        or has a character the GSM alphabet lacks. Never
                        cut, never split into parts. sLastError says which
       QueueFull        stSmsConfig.nMaxPendingSms would be passed: none queued
       RateLimited      stSmsConfig.nMaxSmsPerHour would be passed (every number
                        counts; the hour restarts at boot): none queued
     The block sends them one at a time, once the network has the SIM - SMS
     needs bRegistered, not bConnected, so a SIM with no data plan sends -
     and a send that fails is tried again after tRetryAfter, nRetriesBeforeDrop times, then
     dropped. nSmsSentCount, nSmsSendFailureCount (each try), nSmsDroppedCount (queue full, the
     limit, retries spent), nPendingSms and sSmsLastError ('send +6421000001:
     ...') follow them. A call is never lost to another task holding the
     modem: the queue is the block's, and only sending needs the modem.

  modem.SendSmsRequest(anyMessageText, sPhoneNumber, bExecute)
     ONE TEXT MESSAGE, FOLLOWED, on a rising edge, for a program that has to
     know it went: Queued until the network has accepted it, then Ok, held
     until the next edge. NotReady (the network has not accepted the SIM),
     InvalidArgument (no number or text), TooLarge, or the network's refusal
     (ModuleError, with its words on sLastError). Not queued, not limited by
     stSmsConfig, never retried.

  modem.Format(sTemplate, anyData, bTruncated =>)
     A TEXT FROM A TEMPLATE, for SendSms: {path} placeholders filled from the
     STRUCT anyData, members by name ({irr.left}, {pump[2].hours}, arrays
     from 1):
       {x}            its natural form: 12.4, 42, TRUE, the text, 1h30m,
                      2026-11-12 10:00:00; an enumeration as its member's
                      name when its type is declared {attribute 'to_string'}
                      (Running), otherwise as its number
       {x:1} {x:0}    a REAL or LREAL with that many decimals
       {x:hm}         a TIME as hours and minutes: '2h00m', '48m'
       {x:16}         a STRING cut to 16 characters
       {x|OFF|MANUAL|AUTO}  the word an integer, BOOL or enumeration
                      indexes, from 0 - words of your own for each value
     A placeholder that names nothing stays as written, so the mistake shows
     in the message; everything else passes through, $N line breaks
     included. At most 160 characters: cut there, bTruncated TRUE. Needs no
     modem and no lock; it can be called anywhere.

  modem.Inbox(bEnable, bMessageReceived =>, sSender =>, sMessageText =>, nSimStorageIndex =>,
              dtSentAt =>, nMessageReceivedCount =>)
     TEXT MESSAGES ARRIVING AT THE SIM, one at a time. bMessageReceived is TRUE on
     the one call that takes a message; the rest hold the last message.
     dtSentAt is the message centre's time, in UTC. Every message is deleted
     from the SIM once read (a full SIM is refused new messages, silently),
     one that cannot be decoded too. CHECK sSender: anybody who knows the
     number can send to it. bEnable FALSE leaves arriving messages on the SIM.
     Ok, or NotReady until the network has accepted the SIM.

  modem.SmsCommand(sCommands, sAllowedNumbers, nOperatorPin, sAdminCommands, nAdminPin,
                   tPulseLength, nReplyMode, sReplyText, nMaxCommandsPerHour, bEnable,
                   bCommandReceived =>, nCommandNumber =>, sMatchedCommand =>, sArgument =>, fArgumentValue =>,
                   bArgumentIsNumber =>, tArgumentDuration =>, bArgumentIsDuration =>, bAdminPinUsed =>,
                   sSender =>, nCommandAcceptedCount =>, nCommandRefusedCount =>, sLastRefusalReason =>)
     TEXT-MESSAGE COMMANDS: a message from an allowed number that says one of
     sCommands' words sets bCommandReceived for tPulseLength (T#0s: one call), and nCommandNumber says
     which, from 1 in sCommands' order, then sAdminCommands'. The message is
     looked at FIRST, before anything that waits for the modem, so a command
     is never lost to a busy modem; only the reply waits. Needs no Inbox call.
       sCommands       'START, STOP, SET TIME'; upper or lower case, extra
                       spaces all the same. The record is found by this text
       sAllowedNumbers  numbers separated by commas or semicolons, matched on
                       their last 8 digits ('+64 21 123 4567' = '021 123
                       4567'); a name or short code ('MyTelco', '2001') is
                       matched whole. Empty: nobody. '*': anybody - only with
                       a PIN
       nOperatorPin    0: none; above 0 the message starts with it: '1111 START'
       sAdminCommands  commands that need nAdminPin ('9999 REBOOT')
       nAdminPin       0: no admin level; it works for sCommands too
       nReplyMode      0 never answer; 1 an accepted command ('OK REBOOT');
                       2 also say why a message was refused - only ever to a
                       number on sAllowedNumbers
       sReplyText      the answer instead of 'OK <command> <argument>'
       nMaxCommandsPerHour  the most it acts in an hour; 0 no limit
     sArgument is what followed the command; fArgumentValue it as a number (bArgumentIsNumber);
     tArgumentDuration it as a time - '3H30M10S', '90M', '1.5H' (bArgumentIsDuration).
     nCommandRefusedCount and sLastRefusalReason count and say why messages were refused.
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

  modem.Power(ePowerAction, bExecute, bModulePowered =>, bBusy =>)
     THE MODULE OFF, ON AGAIN, OR RESTARTED, on a rising edge.
     E_GsmPower.SwitchOff shuts it down properly - its own power-down command
     first, then its supply where the board switches one - and keeps it off;
     SwitchOn lets it run again; Restart resets it with its own command and
     brings it back up. bModulePowered is FALSE from SwitchOff until SwitchOn.
     Queued, then Ok; NotReady (Restart before the module has answered, or
     SwitchOn with bConnect FALSE), Timeout. The library already restarts and
     power-cycles a module that stops answering, so this is for the program's
     own reasons: a solar site's night, a scheduled restart.

  modem.Socket(anyReceiveBuffer, sHostName, nHostPort, eSecurity, bOpen, sSendData, bSend,
               bSocketConnected =>, bSent =>, bDataReceived =>, nReceivedLength =>)
     A TCP CONNECTION over the modem, for a program that talks to a server
     itself. bOpen TRUE opens it and keeps it open, reopening it five seconds
     after it fails; FALSE closes it. eSecurity E_GsmSecurity.Tls is the
     module's own TLS, which encrypts and checks no certificate. A rising
     edge of bSend sends sSendData; bSent is TRUE on the call it has all left.
     What arrives is written into anyReceiveBuffer, a STRING, up to its length a
     call; bDataReceived and nReceivedLength on that call. Text, not bytes: a zero byte
     ends a STRING. The record is anyReceiveBuffer's. Ok while connected; NotReady
     while opening or with no data connection, NoSocketAvailable,
     SocketClosed, BearerLost, InvalidArgument.

  modem.Status(tReadInterval, nSignalStrengthDbm =>, nLteSignalPowerDbm =>, nLteSignalQualityDb =>, eSignalQuality =>,
               eRegistrationState =>, eAccessTechnology =>, sOperatorName =>, sIpAddress =>,
               sImei =>, sIccid =>, sModuleFamily =>, sFirmwareVersion =>,
               nSocketsFree =>, nBringUpCount =>, nRecoveryCount =>,
               nDataConnectionDropCount =>, nRegistrationDropCount =>)
     WHAT THE MODEM KNOWS, for a diagnostic page. Reading costs nothing; only
     tReadInterval (T#30s; T#0s never) asks the module for its signal and
     registration. nSignalStrengthDbm dBm (-113 nothing, -51 excellent; -32768 never
     read), nLteSignalPowerDbm and nLteSignalQualityDb LTE's, eSignalQuality Good above -95 dBm, Uncertain to
     -105, Bad below. A counter that keeps climbing is the thing to watch: one
     bring-up and no recoveries is a healthy site. Ok once the module has
     answered; NotReady before.

  modem.NetworkTime(tReadInterval, bValid =>, dtClockUtc =>, dtLocalTime =>,
                    nUtcOffsetMinutes =>, tValueAge =>)
     THE TIME FROM THE MOBILE NETWORK, at no data cost, read every tReadInterval
     (T#1h) and carried forward on the PLC's clock between. nUtcOffsetMinutes is the
     network's offset in minutes (780: New Zealand summer time). Not every
     network sends the time: there bValid stays FALSE. Ok when valid,
     NotReady before, NotSupportedByModule.

  modem.Gnss(bEnable, tReadInterval, bReceiverFitted =>, bValid =>, fLatitude =>,
             fLongitude =>, fAltitudeMetres =>, nSatellitesInView =>, tValueAge =>)
     WHERE THE MODULE IS, from its own satellite receiver where it has one.
     bEnable TRUE powers the receiver and reads it every tReadInterval (T#5s);
     FALSE powers it down. tValueAge is the pin to alarm on, not bValid: a receiver
     that loses the sky keeps its last position. From cold a first fix takes
     a minute or more; the receiver needs its own antenna. Ok while the
     receiver runs, NotSupportedByModule on a module without one. *)

FUNCTION_BLOCK FB_GsmModemSim7070
  VAR_INPUT
    bConnect : BOOL := TRUE;                  (* TRUE brings the modem up and keeps it up; FALSE stops (use Power to switch it off) *)
    sSimPin : STRING(8);                      (* the SIM's PIN, offered once per change: three wrong PINs lock the SIM *)
    stApnConfig : ST_GsmApnConfig;            (* the APN, its user name and password *)
    stSerialConfig : ST_GsmSerialConfig;      (* the serial device or the board's UART and pins *)
    stPowerConfig : ST_GsmPowerConfig;        (* a board's power key and supply rail *)
    stRadioConfig : ST_GsmRadioConfig;        (* radio mode, operator and bands *)
    stCapacityConfig : ST_GsmCapacityConfig;  (* sockets, socket buffers and the command queue *)
    stSmsConfig : ST_GsmSmsConfig;            (* SendSms's queue, hourly limit and retries *)
  END_VAR
  VAR_OUTPUT
    bConnected : BOOL;                (* the modem has a data connection *)
    bRegistered : BOOL;               (* the network has accepted the SIM *)
    eConnectionState : E_GsmState;    (* where the bring-up is *)
    bError : BOOL;                    (* something failed *)
    eErrorId : E_GsmResult;           (* why; Ok when fine *)
    sLastError : STRING(64);          (* why, in words *)
    nSmsSentCount : UDINT; (* SendSms messages the network took *)
    nSmsSendFailureCount : UDINT; (* SendSms sends that failed, each try *)
    nSmsDroppedCount : UDINT; (* SendSms messages dropped: queue full, the hour's limit, retries spent *)
    nPendingSms : INT; (* SendSms messages waiting *)
    sSmsLastError : STRING(64); (* why the last send failed, with its number *)
  END_VAR
  VAR
    nId : UDINT;                      (* this instance's number; the modem's owner is one *)
    nTask : __XWORD;                  (* the task this block runs in, for its methods *)
    bRunning : BOOL;                  (* the modem was started *)
  END_VAR
(* Queues anyMessageText for every number of anyPhoneNumbers, all or none, called once per
   message: Ok (queued), InvalidArgument, QueueFull or RateLimited. The block
   sends them one at a time once the network has the SIM, retrying a failed
   one; nSmsSentCount, nSmsSendFailureCount, nSmsDroppedCount, nPendingSms and sSmsLastError count
   them. Never waits. *)
METHOD PUBLIC SendSms : E_GsmResult
  VAR_INPUT
    anyPhoneNumbers : ANY;                  (* a STRING or a literal: numbers separated by ',' or ';', spaces ignored *)
    anyMessageText : ANY;                (* a STRING or a literal: one message, 160 GSM characters at most *)
  END_VAR
END_METHOD

(* Sends anyMessageText to sPhoneNumber once, on a rising edge of bExecute, and follows
   it: E_GsmResult.Queued until the network has accepted it, then Ok or the
   reason, until the next edge. *)
METHOD PUBLIC SendSmsRequest : E_GsmResult
  VAR_INPUT
    anyMessageText : ANY;              (* the message: a STRING or a literal, up to 160 characters *)
    sPhoneNumber : STRING(20);       (* who to, international: '+6421...' *)
    bExecute : BOOL;            (* rising edge sends *)
  END_VAR
END_METHOD

(* A text from sTemplate with {member} placeholders filled from the STRUCT
   anyData: {x} its natural form, {x:1} decimals, {x:hm} a TIME as '2h00m',
   {x:16} a STRING cut, {x|OFF|ON} the word an integer or enumeration indexes.
   At most 160 characters; bTruncated when more would have followed. Needs no
   modem. *)
METHOD PUBLIC Format : STRING(160)
  VAR_INPUT
    sTemplate : STRING(254);    (* the text, with {member.path} placeholders *)
    anyData : ANY;              (* the STRUCT the placeholders name *)
  END_VAR
  VAR_OUTPUT
    bTruncated : BOOL;          (* the text was cut at 160 characters *)
  END_VAR
END_METHOD

(* Text messages arriving at the SIM, one a call, called every scan. Each is
   deleted from the SIM once read. *)
METHOD PUBLIC Inbox : E_GsmResult
  VAR_INPUT
    bEnable : BOOL := TRUE;     (* FALSE leaves arriving messages on the SIM *)
  END_VAR
  VAR_OUTPUT
    bMessageReceived : BOOL;           (* this call took a message *)
    sSender : STRING(23);       (* who sent it: '+6421...', or a name *)
    sMessageText : STRING(160);        (* what it says *)
    nSimStorageIndex : UINT;              (* where the SIM had stored it; already deleted *)
    dtSentAt : DT;              (* when the message centre took it, UTC *)
    nMessageReceivedCount : UDINT;       (* messages taken since the PLC started *)
  END_VAR
END_METHOD

(* Text-message commands from allowed numbers, called every scan: bCommandReceived is TRUE
   for tPulseLength when a message said one of sCommands or sAdminCommands, and nCommandNumber
   says which. Found by sCommands. *)
METHOD PUBLIC SmsCommand : E_GsmResult
  VAR_INPUT
    sCommands : STRING(160);        (* the commands, comma separated: 'START, STOP' *)
    sAllowedNumbers : STRING(200);         (* who may send them; empty nobody, '*' anybody *)
    nOperatorPin : DINT;                    (* the operator PIN; 0 none *)
    sAdminCommands : STRING(160);   (* commands that need nAdminPin *)
    nAdminPin : DINT;               (* the admin PIN; 0 no admin level *)
    tPulseLength : TIME;                  (* how long bCommandReceived stays TRUE; T#0s one call *)
    nReplyMode : USINT := 1;            (* 0 never answer, 1 an accepted command, 2 also a refusal *)
    sReplyText : STRING(140);       (* the answer instead of 'OK <command> <argument>' *)
    nMaxCommandsPerHour : UINT := 10;       (* the most it acts in an hour; 0 no limit *)
    bEnable : BOOL := TRUE;         (* FALSE ignores every message *)
  END_VAR
  VAR_OUTPUT
    bCommandReceived : BOOL;                    (* TRUE for tPulseLength after an accepted command *)
    nCommandNumber : INT;                     (* which, from 1 in sCommands' order, then sAdminCommands' *)
    sMatchedCommand : STRING(32);          (* its words, upper case *)
    sArgument : STRING(64);              (* what followed the command *)
    fArgumentValue : REAL;                  (* sArgument as a number *)
    bArgumentIsNumber : BOOL;                (* sArgument was a number *)
    tArgumentDuration : TIME;               (* sArgument as a time: '3H30M', '90M' *)
    bArgumentIsDuration : BOOL;             (* sArgument was a time *)
    bAdminPinUsed : BOOL;                  (* it came with nAdminPin *)
    sSender : STRING(23);           (* who sent it *)
    nCommandAcceptedCount : UDINT;                (* commands accepted *)
    nCommandRefusedCount : UDINT;            (* messages that named a command and were refused *)
    sLastRefusalReason : STRING(64);      (* why, and from whom *)
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
    ePowerAction : E_GsmPower;        (* SwitchOff, SwitchOn or Restart *)
    bExecute : BOOL;            (* rising edge starts it *)
  END_VAR
  VAR_OUTPUT
    bModulePowered : BOOL;            (* FALSE from SwitchOff until SwitchOn *)
    bBusy : BOOL;               (* an operation is under way *)
  END_VAR
END_METHOD

(* A TCP connection over the modem, called every scan. bOpen keeps it open;
   what arrives is written into anyReceiveBuffer. Found by anyReceiveBuffer. *)
METHOD PUBLIC Socket : E_GsmResult
  VAR_INPUT
    anyReceiveBuffer : ANY;            (* a STRING: what arrived is written here *)
    sHostName : STRING(63);         (* the server: a name or an address *)
    nHostPort : UINT;               (* its port *)
    eSecurity : E_GsmSecurity;  (* Plain, or Tls done by the module *)
    bOpen : BOOL;               (* TRUE opens it and keeps it open; FALSE closes it *)
    sSendData : STRING(254);      (* sent on a rising edge of bSend *)
    bSend : BOOL;               (* rising edge sends sSendData *)
  END_VAR
  VAR_OUTPUT
    bSocketConnected : BOOL;    (* the connection is open *)
    bSent : BOOL;               (* this call: all of sSendData has left *)
    bDataReceived : BOOL;           (* this call: anyReceiveBuffer holds what just arrived *)
    nReceivedLength : INT;               (* characters written into anyReceiveBuffer *)
  END_VAR
END_METHOD

(* What the modem knows about itself and its network, called every scan.
   Reading costs nothing; tReadInterval asks the module for its signal. *)
METHOD PUBLIC Status : E_GsmResult
  VAR_INPUT
    tReadInterval : TIME := T#30s;   (* how often to ask for signal and registration; T#0s never *)
  END_VAR
  VAR_OUTPUT
    nSignalStrengthDbm : INT;                (* signal strength (RSSI), dBm: -113 nothing, -51 excellent; -32768 never read *)
    nLteSignalPowerDbm : INT;                (* LTE reference signal power, dBm, or -32768 *)
    nLteSignalQualityDb : INT;                (* LTE reference signal quality, dB, or -32768 *)
    eSignalQuality : E_GsmQuality;    (* Good above -95 dBm, Uncertain to -105, Bad below *)
    eRegistrationState : E_GsmRegistration;  (* what the network says about the SIM *)
    eAccessTechnology : E_GsmTechnology;      (* the radio in use *)
    sOperatorName : STRING(32);     (* the network's name *)
    sIpAddress : STRING(46);       (* the address the network gave the modem *)
    sImei : STRING(20);         (* the module's serial number *)
    sIccid : STRING(24);        (* the SIM's serial number, as printed on it *)
    sModuleFamily : STRING(16);       (* the module family the library recognised *)
    sFirmwareVersion : STRING(48);     (* the module's firmware revision *)
    nSocketsFree : USINT;       (* sockets still free *)
    nBringUpCount : UDINT;        (* bring-ups since the PLC started *)
    nRecoveryCount : UDINT;       (* times the library recovered it *)
    nDataConnectionDropCount : UDINT;     (* times the data connection dropped *)
    nRegistrationDropCount : UDINT;  (* times the network dropped the SIM *)
  END_VAR
END_METHOD

(* The time from the mobile network, called every scan. Costs no data. *)
METHOD PUBLIC NetworkTime : E_GsmResult
  VAR_INPUT
    tReadInterval : TIME := T#1h;    (* how often to read the module's clock *)
  END_VAR
  VAR_OUTPUT
    bValid : BOOL;              (* the network has set the clock, and it has been read *)
    dtClockUtc : DT;                 (* the time now, UTC *)
    dtLocalTime : DT;               (* the time now, in the network's time zone *)
    nUtcOffsetMinutes : INT;           (* the network's offset from UTC, minutes *)
    tValueAge : TIME;                (* since the module's clock was last read *)
  END_VAR
END_METHOD

(* Where the module is, from its own satellite receiver, called every scan. *)
METHOD PUBLIC Gnss : E_GsmResult
  VAR_INPUT
    bEnable : BOOL := TRUE;     (* TRUE powers the receiver and reads it; FALSE powers it down *)
    tReadInterval : TIME := T#5s;    (* how often to read the fix *)
  END_VAR
  VAR_OUTPUT
    bReceiverFitted : BOOL;          (* the module has a receiver *)
    bValid : BOOL;                (* a position is known and current *)
    fLatitude : LREAL;          (* degrees, north positive *)
    fLongitude : LREAL;         (* degrees, east positive *)
    fAltitudeMetres : REAL;           (* metres above sea level *)
    nSatellitesInView : USINT;        (* satellites in view *)
    tValueAge : TIME;                (* since the fix was last confirmed; T#0s before the first *)
  END_VAR
END_METHOD

#include <ModBeeGsmPlc.h>
#include <GsmPlcMethods.h>
#include <GsmPlcFormat.h>

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
    nSmsSentCount = 0;
    nSmsSendFailureCount = 0;
    nSmsDroppedCount = 0;
    nPendingSms = 0;
    sSmsLastError = "";
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
    link.rxBuffer = (int32_t)stSerialConfig.NRECEIVEBUFFERSIZE;
    link.keyPin = (int32_t)(int16_t)stPowerConfig.NPOWERKEYPIN;
    link.railPin = (int32_t)(int16_t)stPowerConfig.NSUPPLYSWITCHPIN;
    {
        const char* path = stSerialConfig.SDEVICE.c_str();
        size_t n = 0;
        for (; n + 1 < sizeof link.path && path[n] != '\0'; n++) link.path[n] = path[n];
        link.path[n] = '\0';
    }
    link.baud = (int32_t)stSerialConfig.NBAUDRATE > 0 ? (uint32_t)(int32_t)stSerialConfig.NBAUDRATE
                                                      : 115200u;
    link.sockets = (int32_t)(uint8_t)stCapacityConfig.NSOCKETS;
    link.socketBuffer = (int32_t)(uint16_t)stCapacityConfig.NSOCKETBUFFERSIZE;
    link.atQueue = (int32_t)(uint8_t)stCapacityConfig.NMAXPENDINGATCOMMANDS;
#if !defined(GSM_PLATFORM_ARDUINO)
    // The Runtime has no board pins: they are not compared, so a change to
    // them is no change.
    link.port = 0; link.rxPin = 44; link.txPin = 43; link.rxBuffer = 4096;
    link.keyPin = 10; link.railPin = -1;
#endif
    const char* linkRefused = gsmplc::checkLink(link);
    const int radioMode = (int)(strucpp::E_GSMRADIOMODE)stRadioConfig.ERADIOMODE;
    const char* radioRefused = gsmplc::checkRadio(radioMode, stRadioConfig.SOPERATORCODE.c_str(),
                                                  stRadioConfig.SCATMBANDS.c_str(),
                                                  stRadioConfig.SNBIOTBANDS.c_str());

    bool changed = false;
    if (gsmplc::apn(stApnConfig.SAPN.c_str(), stApnConfig.SUSERNAME.c_str(),
                    stApnConfig.SUSERPASSWORD.c_str())) changed = true;
    if (gsmplc::pin(sSimPin.c_str())) changed = true;
    // A radio setting that cannot be read is refused whole: the modem keeps
    // the one it had rather than half of the new one.
    if (radioRefused == nullptr &&
        gsmplc::radio((GsmRadioPreference)radioMode, stRadioConfig.SOPERATORCODE.c_str(),
                      stRadioConfig.SCATMBANDS.c_str(), stRadioConfig.SNBIOTBANDS.c_str())) {
        changed = true;
    }

    gsmplc::SmsConfig smsConfig;
    smsConfig.queueDepth = (int16_t)stSmsConfig.NMAXPENDINGSMS;
    smsConfig.maxPerHour = (int16_t)stSmsConfig.NMAXSMSPERHOUR;
    smsConfig.retries = (int16_t)stSmsConfig.NRETRIESBEFOREDROP;
    smsConfig.retryMs = gsmplc::millisOf(stSmsConfig.TRETRYAFTER.get());

    const bool want = (bool)bConnect && !gsmplc::heldOff();
    GsmDevice& gsm = gsmplc::device();
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
                gsmplc::tickCalls((uint32_t)nId, smsConfig);
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
    gsmplc::tickCalls((uint32_t)nId, smsConfig);
    if (const gsmplc::OutboxView* outbox = gsmplc::outboxView()) {
        nSmsSentCount = outbox->sent;
        nSmsSendFailureCount = outbox->failed;
        nSmsDroppedCount = outbox->dropped;
        nPendingSms = outbox->queued;
        sSmsLastError = outbox->lastError;
    }

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
    // has nothing to report. Stood down, eErrorId says why (PoweredOff,
    // NotReady) and stays so.
    int failed = 0;
    const char* callFailed = gsmplc::callError(&failed);
    if (callFailed != nullptr && !(bool)bError && want) {
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
    // Both a STRING of any length or a literal: read up to their declared length.
    const char* to = nullptr;
    size_t toLength = 0;
    if (anyPhoneNumbers.wired() && anyPhoneNumbers.TYPECLASS == strucpp::TYPE_STRING) {
        to = (const char*)anyPhoneNumbers.PVALUE;
        while (toLength < (size_t)anyPhoneNumbers.DISIZE && to[toLength] != '\0') toLength++;
    }
    const char* text = nullptr;
    size_t textLength = 0;
    if (anyMessageText.wired() && anyMessageText.TYPECLASS == strucpp::TYPE_STRING) {
        text = (const char*)anyMessageText.PVALUE;
        while (textLength < (size_t)anyMessageText.DISIZE && text[textLength] != '\0') textLength++;
    }
    return (E_GSMRESULT)gsmplc::queueSmsCall(call, to, toLength, text, textLength);
}

strucpp::IECStringVar<160> Format()
{
    char text[161];
    bool cut = false;
    gsmplc::format::fill(sTemplate.c_str(), anyData, text, 160, &cut);
    bTruncated = cut;
    strucpp::IECStringVar<160> out;
    out = text;
    return out;
}

E_GSMRESULT SendSmsRequest()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    call.name = anyMessageText.NAME;
    call.type = anyMessageText.TYPENAME;
    call.key = sPhoneNumber.c_str();      // a literal text is found by its number
    const char* text = nullptr;
    size_t length = 0;
    if (anyMessageText.wired() && anyMessageText.TYPECLASS == strucpp::TYPE_STRING) {
        text = (const char*)anyMessageText.PVALUE;
        while (length < (size_t)anyMessageText.DISIZE && text[length] != '\0') length++;
    }
    return (E_GSMRESULT)gsmplc::sendSmsCall(call, text, length, sPhoneNumber.c_str(), (bool)bExecute);
}

E_GSMRESULT Inbox()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    gsmplc::InboxView view;
    const int result = gsmplc::inboxCall(call, (bool)bEnable, view);
    bMessageReceived = view.received;
    sSender = view.sender;
    sMessageText = view.text;
    nSimStorageIndex = view.index;
    dtSentAt = view.sentAtNs;
    nMessageReceivedCount = view.count;
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
    spec.allowed = sAllowedNumbers.c_str();
    spec.pin = (int32_t)nOperatorPin;
    spec.adminCommands = sAdminCommands.c_str();
    spec.adminPin = (int32_t)nAdminPin;
    spec.pulseMs = gsmplc::millisOf(tPulseLength.get());
    spec.reply = (uint8_t)nReplyMode;
    spec.replyText = sReplyText.c_str();
    spec.maxPerHour = (uint16_t)nMaxCommandsPerHour;
    spec.enable = (bool)bEnable;
    gsmplc::CommandView view;
    const int result = gsmplc::smsCommandCall(call, spec, view);
    bCommandReceived = view.active;
    nCommandNumber = view.which;
    sMatchedCommand = view.matched;
    sArgument = view.arg;
    fArgumentValue = view.value;
    bArgumentIsNumber = view.valueOk;
    tArgumentDuration = view.durationNs;
    bArgumentIsDuration = view.durationOk;
    bAdminPinUsed = view.admin;
    sSender = view.sentBy;
    nCommandAcceptedCount = view.count;
    nCommandRefusedCount = view.refused;
    sLastRefusalReason = view.lastRefused;
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
    const int result = gsmplc::powerCall(call, (int)(E_GSMPOWER)ePowerAction, (bool)bExecute, view);
    bModulePowered = view.powered;
    bBusy = view.busy;
    return (E_GSMRESULT)result;
}

E_GSMRESULT Socket()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    call.name = anyReceiveBuffer.NAME;
    call.type = anyReceiveBuffer.TYPENAME;
    call.key = sHostName.c_str();
    gsmplc::SocketSpec spec;
    spec.host = sHostName.c_str();
    spec.port = (uint16_t)nHostPort;
    spec.tls = (E_GSMSECURITY)eSecurity == E_GSMSECURITY::TLS;
    spec.open = (bool)bOpen;
    spec.tx = sSendData.c_str();
    spec.txLength = sSendData.length();
    spec.send = (bool)bSend;
    if (anyReceiveBuffer.wired() && anyReceiveBuffer.TYPECLASS == strucpp::TYPE_STRING) {
        spec.rx = (char*)anyReceiveBuffer.PVALUE;
        spec.rxCapacity = (size_t)anyReceiveBuffer.DISIZE;
    }
    gsmplc::SocketView view;
    int result = gsmplc::socketCall(call, spec, view);
    if (spec.rx == nullptr && (bool)bOpen && result == (int)E_GSMRESULT::OK) {
        result = (int)E_GSMRESULT::INVALIDARGUMENT;   // nowhere to put what arrives
    }
    bSocketConnected = view.connected;
    bSent = view.sent;
    bDataReceived = view.received;
    nReceivedLength = (int16_t)view.rxLength;
    return (E_GSMRESULT)result;
}

E_GSMRESULT Status()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    const gsmplc::StatusView* view = nullptr;
    const int result = gsmplc::statusCall(call, gsmplc::millisOf(tReadInterval.get()), &view);
    nSignalStrengthDbm = view->rssi;
    nLteSignalPowerDbm = view->rsrp;
    nLteSignalQualityDb = view->rsrq;
    eSignalQuality = (E_GSMQUALITY)view->quality;
    eRegistrationState = (E_GSMREGISTRATION)view->registration;
    eAccessTechnology = (E_GSMTECHNOLOGY)view->technology;
    sOperatorName = view->operatorName;
    sIpAddress = view->ipAddress;
    sImei = view->imei;
    sIccid = view->iccid;
    sModuleFamily = view->module;
    sFirmwareVersion = view->firmware;
    nSocketsFree = view->socketsFree;
    nBringUpCount = view->bringUps;
    nRecoveryCount = view->recoveries;
    nDataConnectionDropCount = view->bearerLosses;
    nRegistrationDropCount = view->registrationLosses;
    return (E_GSMRESULT)result;
}

E_GSMRESULT NetworkTime()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    gsmplc::TimeView view;
    const int result = gsmplc::timeCall(call, gsmplc::millisOf(tReadInterval.get()), view);
    bValid = view.valid;
    dtClockUtc = view.utcNs;
    dtLocalTime = view.localNs;
    nUtcOffsetMinutes = view.zoneMinutes;
    tValueAge = view.ageNs;
    return (E_GSMRESULT)result;
}

E_GSMRESULT Gnss()
{
    gsmplc::Call call;
    call.block = (uint32_t)nId;
    call.task = (uintptr_t)(strucpp::XWORD_t)nTask;
    gsmplc::GnssView view;
    const int result = gsmplc::gnssCall(call, (bool)bEnable, gsmplc::millisOf(tReadInterval.get()),
                                        view);
    bReceiverFitted = view.supported;
    bValid = view.fix;
    fLatitude = view.latitude;
    fLongitude = view.longitude;
    fAltitudeMetres = view.altitude;
    nSatellitesInView = view.satellites;
    tValueAge = view.ageNs;
    return (E_GSMRESULT)result;
}

END_FUNCTION_BLOCK