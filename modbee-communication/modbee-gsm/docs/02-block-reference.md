# Block reference

Two blocks, one per modem module, so a program links only its module's
driver: `FB_GsmModemA7670` (SIMCom A76XX, LTE Cat-1) and `FB_GsmModemSim7070`
(SIMCom SIM707x, LTE-M and NB-IoT). They are the same block over a different
driver. A PLC has one modem: call its block once every scan, then its methods:
`modem.SendSms(...)`, `modem.Status(...)`.

Every method returns an `E_GsmResult`. A **request** (`SendSms`, `AtCommand`,
`Power`) starts on a rising edge of `bExecute`, returns `Queued` while it runs
and then holds its outcome until the next edge. A **standing** method is called
every scan while it is wanted and returns `Ok` while its outputs are valid. A
method's outputs are read with `=>`: `ok := modem.Status(nRssi => rssi);`. An
input left out takes its default.

> Generated from each block's own comment and declarations by
> `internal/tools/make-block-reference.py`; edit
> `internal/tools/modem-block.cpp.in`, not this page.

| Block | What it does | Methods |
| --- | --- | --- |
| [`FB_GsmModemA7670`](#fb_gsmmodema7670) | A cellular modem: a SIMCom A7670, A7672, A7678 or A7608 (LTE Cat-1), as on the ModBee GSM HAT. | [`SendSms`](#fb_gsmmodema7670sendsms), [`SendSmsRequest`](#fb_gsmmodema7670sendsmsrequest), [`Format`](#fb_gsmmodema7670format), [`Inbox`](#fb_gsmmodema7670inbox), [`SmsCommand`](#fb_gsmmodema7670smscommand), [`AtCommand`](#fb_gsmmodema7670atcommand), [`Power`](#fb_gsmmodema7670power), [`Socket`](#fb_gsmmodema7670socket), [`Status`](#fb_gsmmodema7670status), [`NetworkTime`](#fb_gsmmodema7670networktime), [`Gnss`](#fb_gsmmodema7670gnss) |
| [`FB_GsmModemSim7070`](#fb_gsmmodemsim7070) | A cellular modem: a SIMCom SIM7070, SIM7080 or SIM7090 (LTE-M and NB-IoT). | [`SendSms`](#fb_gsmmodemsim7070sendsms), [`SendSmsRequest`](#fb_gsmmodemsim7070sendsmsrequest), [`Format`](#fb_gsmmodemsim7070format), [`Inbox`](#fb_gsmmodemsim7070inbox), [`SmsCommand`](#fb_gsmmodemsim7070smscommand), [`AtCommand`](#fb_gsmmodemsim7070atcommand), [`Power`](#fb_gsmmodemsim7070power), [`Socket`](#fb_gsmmodemsim7070socket), [`Status`](#fb_gsmmodemsim7070status), [`NetworkTime`](#fb_gsmmodemsim7070networktime), [`Gnss`](#fb_gsmmodemsim7070gnss) |

The option structures and enumerations are at the end: [Structures](#structures), [Enumerations](#enumerations).

---

## FB_GsmModemA7670

```
A cellular modem: a SIMCom A7670, A7672, A7678 or A7608
(LTE Cat-1), as on the ModBee GSM HAT. One block runs it - power, SIM,
network, data - and recovers it by itself; everything else the modem does is
a method of this block. Call it once every scan, in the task that calls its
methods. Only the A76XX driver is linked; a module of another family is
refused by name (FB_GsmModemSim7070 drives the SIM707x family).

THE A76XX FAMILY is LTE Cat-1, an ordinary 4G module, with 2G where the
network still has it. Proven on an A7670G over a live network. Its power
key is pressed for 50 ms. stRadioConfig's band lists do nothing on it:
they are for low-power LTE-M and NB-IoT modules.

ON A BOARD, the defaults suit the ModBee Node UIO with its GSM HAT: UART0
on GPIO 44 (receive) and 43 (transmit), the power key on GPIO 10. On the
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
stSmsConfig  ST_GsmSmsConfig, SendSms's queue. Not retained: the hour
             restarts at boot.
               nQueueDepth  messages (a number and its text) waiting, 1 to 64.
                            8 by default
               nMaxPerHour  messages queued an hour, every number counted; past
                            it SendSms returns RateLimited. 10 by default; 0
                            no limit
               nRetries     a failed send is tried again this many times,
                            then dropped. 1 by default
               tRetry       how long before it is. T#60s by default

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
             call is named by its method and record: "AtCommand sCmd:
             Timeout".
nSmsSent, nSmsFailed, nSmsDropped, nSmsQueued, sSmsLastError
             SendSms's queue: messages the network took, sends that failed
             (each try), messages dropped (queue full, the hour's limit,
             retries spent), messages waiting, and why the last send failed
             with its number: 'send +6421000001: <why>'.
```

**Inputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bConnect` | `BOOL` | `TRUE` | TRUE brings the modem up and keeps it up |
| `sSimPin` | `STRING(8)` |  | the SIM's PIN, offered once |
| `stApnConfig` | `ST_GsmApnConfig` |  | the APN, its user name and password |
| `stSerialConfig` | `ST_GsmSerialConfig` |  | the serial device or the board's UART and pins |
| `stPowerConfig` | `ST_GsmPowerConfig` |  | a board's power key and supply rail |
| `stRadioConfig` | `ST_GsmRadioConfig` |  | radio mode, operator and bands |
| `stCapacityConfig` | `ST_GsmCapacityConfig` |  | sockets, socket buffers and the command queue |
| `stSmsConfig` | `ST_GsmSmsConfig` |  | SendSms's queue, hourly limit and retries |

**Outputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bConnected` | `BOOL` |  | the modem has a data connection |
| `bRegistered` | `BOOL` |  | the network has accepted the SIM |
| `eConnectionState` | `E_GsmState` |  | where the bring-up is |
| `bError` | `BOOL` |  | something failed |
| `eErrorId` | `E_GsmResult` |  | why; Ok when fine |
| `sLastError` | `STRING(64)` |  | why, in words |
| `nSmsSent` | `UDINT` |  | SendSms messages the network took |
| `nSmsFailed` | `UDINT` |  | SendSms sends that failed, each try |
| `nSmsDropped` | `UDINT` |  | SendSms messages dropped: queue full, the hour's limit, retries spent |
| `nSmsQueued` | `INT` |  | SendSms messages waiting |
| `sSmsLastError` | `STRING(64)` |  | why the last send failed, with its number |

### FB_GsmModemA7670.SendSms

```
result := modem.SendSms(sTo := ..., sText := ...);
```

Returns `E_GsmResult`.
Queues sText for every number of sTo, all or none, called once per message: Ok (queued), InvalidArgument, QueueFull or RateLimited. The block sends them one at a time once the network has the SIM, retrying a failed one; nSmsSent, nSmsFailed, nSmsDropped, nSmsQueued and sSmsLastError count them. Never waits.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sTo` | `ANY` |  | a STRING or a literal: numbers separated by ',' or ';', spaces ignored |
| `sText` | `ANY` |  | a STRING or a literal: one message, 160 GSM characters at most |

### FB_GsmModemA7670.SendSmsRequest

```
result := modem.SendSmsRequest(anyText := ..., sNumber := ...,
                               bExecute := ...);
```

Returns `E_GsmResult`.
Sends anyText to sNumber once, on a rising edge of bExecute, and follows it: E_GsmResult.Queued until the network has accepted it, then Ok or the reason, until the next edge.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyText` | `ANY` |  | the message: a STRING or a literal, up to 160 characters |
| `sNumber` | `STRING(20)` |  | who to, international: '+6421...' |
| `bExecute` | `BOOL` |  | rising edge sends |

### FB_GsmModemA7670.Format

```
result := modem.Format(sTemplate := ..., anyData := ..., bTruncated => ...);
```

Returns `STRING(160)`.
A text from sTemplate with {member} placeholders filled from the STRUCT anyData: {x} its natural form, {x:1} decimals, {x:hm} a TIME as '2h00m', {x:16} a STRING cut, {x|OFF|ON} the word an integer or enumeration indexes. At most 160 characters; bTruncated when more would have followed. Needs no modem.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sTemplate` | `STRING(254)` |  | the text, with {member.path} placeholders |
| `anyData` | `ANY` |  | the STRUCT the placeholders name |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bTruncated` | `BOOL` |  | the text was cut at 160 characters |

### FB_GsmModemA7670.Inbox

```
result := modem.Inbox(bEnable := ..., bReceived => ..., sSender => ...,
                      sText => ..., nIndex => ..., dtSentAt => ...,
                      nReceivedCnt => ...);
```

Returns `E_GsmResult`.
Text messages arriving at the SIM, one a call, called every scan. Each is deleted from the SIM once read.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bEnable` | `BOOL` | `TRUE` | FALSE leaves arriving messages on the SIM |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bReceived` | `BOOL` |  | this call took a message |
| `sSender` | `STRING(23)` |  | who sent it: '+6421...', or a name |
| `sText` | `STRING(160)` |  | what it says |
| `nIndex` | `UINT` |  | where the SIM had stored it; already deleted |
| `dtSentAt` | `DT` |  | when the message centre took it, UTC |
| `nReceivedCnt` | `UDINT` |  | messages taken since the PLC started |

### FB_GsmModemA7670.SmsCommand

```
result := modem.SmsCommand(sCommands := ..., sAllowed := ..., nPin := ...,
                           sAdminCommands := ..., nAdminPin := ...,
                           tPulse := ..., nReply := ..., sReplyText := ...,
                           nMaxPerHour := ..., bEnable := ..., bCmd => ...,
                           nCmd => ..., sMatched => ..., sArg => ...,
                           fValue => ..., bValueOk => ..., tDuration => ...,
                           bDurationOk => ..., bAdmin => ..., sSentBy => ...,
                           nCmdCnt => ..., nRefusedCnt => ...,
                           sLastRefused => ...);
```

Returns `E_GsmResult`.
Text-message commands from allowed numbers, called every scan: bCmd is TRUE for tPulse when a message said one of sCommands or sAdminCommands, and nCmd says which. Found by sCommands.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sCommands` | `STRING(160)` |  | the commands, comma separated: 'START, STOP' |
| `sAllowed` | `STRING(200)` |  | who may send them; empty nobody, '*' anybody |
| `nPin` | `DINT` |  | the operator PIN; 0 none |
| `sAdminCommands` | `STRING(160)` |  | commands that need nAdminPin |
| `nAdminPin` | `DINT` |  | the admin PIN; 0 no admin level |
| `tPulse` | `TIME` |  | how long bCmd stays TRUE; T#0s one call |
| `nReply` | `USINT` | `1` | 0 never answer, 1 an accepted command, 2 also a refusal |
| `sReplyText` | `STRING(140)` |  | the answer instead of 'OK <command> <argument>' |
| `nMaxPerHour` | `UINT` | `10` | the most it acts in an hour; 0 no limit |
| `bEnable` | `BOOL` | `TRUE` | FALSE ignores every message |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bCmd` | `BOOL` |  | TRUE for tPulse after an accepted command |
| `nCmd` | `INT` |  | which, from 1 in sCommands' order, then sAdminCommands' |
| `sMatched` | `STRING(32)` |  | its words, upper case |
| `sArg` | `STRING(64)` |  | what followed the command |
| `fValue` | `REAL` |  | sArg as a number |
| `bValueOk` | `BOOL` |  | sArg was a number |
| `tDuration` | `TIME` |  | sArg as a time: '3H30M', '90M' |
| `bDurationOk` | `BOOL` |  | sArg was a time |
| `bAdmin` | `BOOL` |  | it came with nAdminPin |
| `sSentBy` | `STRING(23)` |  | who sent it |
| `nCmdCnt` | `UDINT` |  | commands accepted |
| `nRefusedCnt` | `UDINT` |  | messages that named a command and were refused |
| `sLastRefused` | `STRING(64)` |  | why, and from whom |

### FB_GsmModemA7670.AtCommand

```
result := modem.AtCommand(anyCommand := ..., tTimeout := ...,
                          bExecute := ..., sReply => ...);
```

Returns `E_GsmResult`.
Sends one AT command of your own on a rising edge of bExecute and hands back the reply. Queued until the module answers, then Ok or the reason, until the next edge.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyCommand` | `ANY` |  | the command, a STRING or a literal: 'AT+CSQ' |
| `tTimeout` | `TIME` | `T#5s` | how long the module has; at most T#180s |
| `bExecute` | `BOOL` |  | rising edge sends |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sReply` | `STRING(254)` |  | the module's lines before its OK or ERROR |

### FB_GsmModemA7670.Power

```
result := modem.Power(ePower := ..., bExecute := ..., bPowered => ...,
                      bBusy => ...);
```

Returns `E_GsmResult`.
Powers the module off, on again, or restarts it, on a rising edge of bExecute. Queued while it runs, then Ok or the reason.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `ePower` | `E_GsmPower` |  | SwitchOff, SwitchOn or Restart |
| `bExecute` | `BOOL` |  | rising edge starts it |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bPowered` | `BOOL` |  | FALSE from SwitchOff until SwitchOn |
| `bBusy` | `BOOL` |  | an operation is under way |

### FB_GsmModemA7670.Socket

```
result := modem.Socket(anyRxData := ..., sHost := ..., nPort := ...,
                       eSecurity := ..., bOpen := ..., sTxData := ...,
                       bSend := ..., bSocketConnected => ..., bSent => ...,
                       bReceived => ..., nRxLen => ...);
```

Returns `E_GsmResult`.
A TCP connection over the modem, called every scan. bOpen keeps it open; what arrives is written into anyRxData. Found by anyRxData.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyRxData` | `ANY` |  | a STRING: what arrived is written here |
| `sHost` | `STRING(63)` |  | the server: a name or an address |
| `nPort` | `UINT` |  | its port |
| `eSecurity` | `E_GsmSecurity` |  | Plain, or Tls done by the module |
| `bOpen` | `BOOL` |  | TRUE opens it and keeps it open; FALSE closes it |
| `sTxData` | `STRING(254)` |  | sent on a rising edge of bSend |
| `bSend` | `BOOL` |  | rising edge sends sTxData |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bSocketConnected` | `BOOL` |  | the connection is open |
| `bSent` | `BOOL` |  | this call: all of sTxData has left |
| `bReceived` | `BOOL` |  | this call: anyRxData holds what just arrived |
| `nRxLen` | `INT` |  | characters written into anyRxData |

### FB_GsmModemA7670.Status

```
result := modem.Status(tRefresh := ..., nRssi => ..., nRsrp => ...,
                       nRsrq => ..., eQuality => ..., eRegistration => ...,
                       eTechnology => ..., sOperator => ..., sIpAddr => ...,
                       sImei => ..., sIccid => ..., sModule => ...,
                       sFirmware => ..., nSocketsFree => ...,
                       nBringUpCnt => ..., nRecoveryCnt => ...,
                       nBearerLossCnt => ..., nRegistrationLossCnt => ...);
```

Returns `E_GsmResult`.
What the modem knows about itself and its network, called every scan. Reading costs nothing; tRefresh asks the module for its signal.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `tRefresh` | `TIME` | `T#30s` | how often to ask for signal and registration; T#0s never |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nRssi` | `INT` |  | signal strength, dBm; -32768 never read |
| `nRsrp` | `INT` |  | LTE reference signal power, dBm, or -32768 |
| `nRsrq` | `INT` |  | LTE reference signal quality, dB, or -32768 |
| `eQuality` | `E_GsmQuality` |  | Good above -95 dBm, Uncertain to -105, Bad below |
| `eRegistration` | `E_GsmRegistration` |  | what the network says about the SIM |
| `eTechnology` | `E_GsmTechnology` |  | the radio in use |
| `sOperator` | `STRING(32)` |  | the network's name |
| `sIpAddr` | `STRING(46)` |  | the address the network gave the modem |
| `sImei` | `STRING(20)` |  | the module's serial number |
| `sIccid` | `STRING(24)` |  | the SIM's serial number, as printed on it |
| `sModule` | `STRING(16)` |  | the module family the library recognised |
| `sFirmware` | `STRING(48)` |  | the module's firmware revision |
| `nSocketsFree` | `USINT` |  | sockets still free |
| `nBringUpCnt` | `UDINT` |  | bring-ups since the PLC started |
| `nRecoveryCnt` | `UDINT` |  | times the library recovered it |
| `nBearerLossCnt` | `UDINT` |  | times the data connection dropped |
| `nRegistrationLossCnt` | `UDINT` |  | times the network dropped the SIM |

### FB_GsmModemA7670.NetworkTime

```
result := modem.NetworkTime(tRefresh := ..., bValid => ..., dtUtc => ...,
                            dtLocal => ..., nUtcOffset => ..., tAge => ...);
```

Returns `E_GsmResult`.
The time from the mobile network, called every scan. Costs no data.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `tRefresh` | `TIME` | `T#1h` | how often to read the module's clock |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bValid` | `BOOL` |  | the network has set the clock, and it has been read |
| `dtUtc` | `DT` |  | the time now, UTC |
| `dtLocal` | `DT` |  | the time now, in the network's time zone |
| `nUtcOffset` | `INT` |  | the network's offset from UTC, minutes |
| `tAge` | `TIME` |  | since the module's clock was last read |

### FB_GsmModemA7670.Gnss

```
result := modem.Gnss(bEnable := ..., tRefresh := ..., bSupported => ...,
                     bFix => ..., fLatitude => ..., fLongitude => ...,
                     fAltitude => ..., nSatellites => ..., tAge => ...);
```

Returns `E_GsmResult`.
Where the module is, from its own satellite receiver, called every scan.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bEnable` | `BOOL` | `TRUE` | TRUE powers the receiver and reads it; FALSE powers it down |
| `tRefresh` | `TIME` | `T#5s` | how often to read the fix |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bSupported` | `BOOL` |  | the module has a receiver |
| `bFix` | `BOOL` |  | a position is known and current |
| `fLatitude` | `LREAL` |  | degrees, north positive |
| `fLongitude` | `LREAL` |  | degrees, east positive |
| `fAltitude` | `REAL` |  | metres above sea level |
| `nSatellites` | `USINT` |  | satellites in view |
| `tAge` | `TIME` |  | since the fix was last confirmed; T#0s before the first |

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
record per method. Up to 64 records.

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

  modem.SendSms(sTo, sText)
     TEXT MESSAGES, QUEUED: sText to every number of sTo ('+6421000001,
     +6421000002'; ',' or ';' between them, spaces ignored), one message to
     each, all queued or none. Call it ONCE per message, on the scan the
     program decides to send: every call queues. Both are a STRING of any
     length or a literal. Returns at once:
       Ok               all queued
       InvalidArgument  an empty list, a number with letters or other
                        characters ('PTT NZ' cannot be texted), a text that
                        is empty, over 160 GSM characters (an escaped one,
                        such as { } [ ] ~ ^ | or the euro sign, counts two)
                        or has a character the GSM alphabet lacks. Never
                        cut, never split into parts. sLastError says which
       QueueFull        stSmsConfig.nQueueDepth would be passed: none queued
       RateLimited      stSmsConfig.nMaxPerHour would be passed (every number
                        counts; the hour restarts at boot): none queued
     The block sends them one at a time, once the network has the SIM - SMS
     needs bRegistered, not bConnected, so a SIM with no data plan sends -
     and a send that fails is tried again after tRetry, nRetries times, then
     dropped. nSmsSent, nSmsFailed (each try), nSmsDropped (queue full, the
     limit, retries spent), nSmsQueued and sSmsLastError ('send +6421000001:
     ...') follow them. A call is never lost to another task holding the
     modem: the queue is the block's, and only sending needs the modem.

  modem.SendSmsRequest(anyText, sNumber, bExecute)
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
     receiver runs, NotSupportedByModule on a module without one.

---

## FB_GsmModemSim7070

```
A cellular modem: a SIMCom SIM7070, SIM7080 or SIM7090
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
stSmsConfig  ST_GsmSmsConfig, SendSms's queue. Not retained: the hour
             restarts at boot.
               nQueueDepth  messages (a number and its text) waiting, 1 to 64.
                            8 by default
               nMaxPerHour  messages queued an hour, every number counted; past
                            it SendSms returns RateLimited. 10 by default; 0
                            no limit
               nRetries     a failed send is tried again this many times,
                            then dropped. 1 by default
               tRetry       how long before it is. T#60s by default

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
             call is named by its method and record: "AtCommand sCmd:
             Timeout".
nSmsSent, nSmsFailed, nSmsDropped, nSmsQueued, sSmsLastError
             SendSms's queue: messages the network took, sends that failed
             (each try), messages dropped (queue full, the hour's limit,
             retries spent), messages waiting, and why the last send failed
             with its number: 'send +6421000001: <why>'.
```

**Inputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bConnect` | `BOOL` | `TRUE` | TRUE brings the modem up and keeps it up |
| `sSimPin` | `STRING(8)` |  | the SIM's PIN, offered once |
| `stApnConfig` | `ST_GsmApnConfig` |  | the APN, its user name and password |
| `stSerialConfig` | `ST_GsmSerialConfig` |  | the serial device or the board's UART and pins |
| `stPowerConfig` | `ST_GsmPowerConfig` |  | a board's power key and supply rail |
| `stRadioConfig` | `ST_GsmRadioConfig` |  | radio mode, operator and bands |
| `stCapacityConfig` | `ST_GsmCapacityConfig` |  | sockets, socket buffers and the command queue |
| `stSmsConfig` | `ST_GsmSmsConfig` |  | SendSms's queue, hourly limit and retries |

**Outputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bConnected` | `BOOL` |  | the modem has a data connection |
| `bRegistered` | `BOOL` |  | the network has accepted the SIM |
| `eConnectionState` | `E_GsmState` |  | where the bring-up is |
| `bError` | `BOOL` |  | something failed |
| `eErrorId` | `E_GsmResult` |  | why; Ok when fine |
| `sLastError` | `STRING(64)` |  | why, in words |
| `nSmsSent` | `UDINT` |  | SendSms messages the network took |
| `nSmsFailed` | `UDINT` |  | SendSms sends that failed, each try |
| `nSmsDropped` | `UDINT` |  | SendSms messages dropped: queue full, the hour's limit, retries spent |
| `nSmsQueued` | `INT` |  | SendSms messages waiting |
| `sSmsLastError` | `STRING(64)` |  | why the last send failed, with its number |

Its methods are `FB_GsmModemA7670`'s, the same in every parameter: [`SendSms`](#fb_gsmmodema7670sendsms), [`SendSmsRequest`](#fb_gsmmodema7670sendsmsrequest), [`Format`](#fb_gsmmodema7670format), [`Inbox`](#fb_gsmmodema7670inbox), [`SmsCommand`](#fb_gsmmodema7670smscommand), [`AtCommand`](#fb_gsmmodema7670atcommand), [`Power`](#fb_gsmmodema7670power), [`Socket`](#fb_gsmmodema7670socket), [`Status`](#fb_gsmmodema7670status), [`NetworkTime`](#fb_gsmmodema7670networktime), [`Gnss`](#fb_gsmmodema7670gnss).

### FB_GsmModemSim7070.SendSms

As [`FB_GsmModemA7670.SendSms`](#fb_gsmmodema7670sendsms).

### FB_GsmModemSim7070.SendSmsRequest

As [`FB_GsmModemA7670.SendSmsRequest`](#fb_gsmmodema7670sendsmsrequest).

### FB_GsmModemSim7070.Format

As [`FB_GsmModemA7670.Format`](#fb_gsmmodema7670format).

### FB_GsmModemSim7070.Inbox

As [`FB_GsmModemA7670.Inbox`](#fb_gsmmodema7670inbox).

### FB_GsmModemSim7070.SmsCommand

As [`FB_GsmModemA7670.SmsCommand`](#fb_gsmmodema7670smscommand).

### FB_GsmModemSim7070.AtCommand

As [`FB_GsmModemA7670.AtCommand`](#fb_gsmmodema7670atcommand).

### FB_GsmModemSim7070.Power

As [`FB_GsmModemA7670.Power`](#fb_gsmmodema7670power).

### FB_GsmModemSim7070.Socket

As [`FB_GsmModemA7670.Socket`](#fb_gsmmodema7670socket).

### FB_GsmModemSim7070.Status

As [`FB_GsmModemA7670.Status`](#fb_gsmmodema7670status).

### FB_GsmModemSim7070.NetworkTime

As [`FB_GsmModemA7670.NetworkTime`](#fb_gsmmodema7670networktime).

### FB_GsmModemSim7070.Gnss

As [`FB_GsmModemA7670.Gnss`](#fb_gsmmodema7670gnss).

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
record per method. Up to 64 records.

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

  modem.SendSms(sTo, sText)
     TEXT MESSAGES, QUEUED: sText to every number of sTo ('+6421000001,
     +6421000002'; ',' or ';' between them, spaces ignored), one message to
     each, all queued or none. Call it ONCE per message, on the scan the
     program decides to send: every call queues. Both are a STRING of any
     length or a literal. Returns at once:
       Ok               all queued
       InvalidArgument  an empty list, a number with letters or other
                        characters ('PTT NZ' cannot be texted), a text that
                        is empty, over 160 GSM characters (an escaped one,
                        such as { } [ ] ~ ^ | or the euro sign, counts two)
                        or has a character the GSM alphabet lacks. Never
                        cut, never split into parts. sLastError says which
       QueueFull        stSmsConfig.nQueueDepth would be passed: none queued
       RateLimited      stSmsConfig.nMaxPerHour would be passed (every number
                        counts; the hour restarts at boot): none queued
     The block sends them one at a time, once the network has the SIM - SMS
     needs bRegistered, not bConnected, so a SIM with no data plan sends -
     and a send that fails is tried again after tRetry, nRetries times, then
     dropped. nSmsSent, nSmsFailed (each try), nSmsDropped (queue full, the
     limit, retries spent), nSmsQueued and sSmsLastError ('send +6421000001:
     ...') follow them. A call is never lost to another task holding the
     modem: the queue is the block's, and only sending needs the modem.

  modem.SendSmsRequest(anyText, sNumber, bExecute)
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
     receiver runs, NotSupportedByModule on a module without one.

---

## Structures

Option structures are inputs of a block, set in the declaration or from an
HMI and read every scan. A member left at its default is the right answer
for most sites; `0` and `T#0s` mean the library's default.

### ST_GsmApnConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `sApn` | `STRING(100)` |  | the access point the SIM's provider gives: 'internet'; empty asks the network for its default |
| `sUserName` | `STRING(127)` |  | the APN's user name, when the provider gives one |
| `sPassword` | `STRING(127)` |  | its password |

### ST_GsmCapacityConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `nSocketCnt` | `USINT` | `2` | sockets open at once: each Socket call and each MQTT client over the modem holds one |
| `nSocketBufferSize` | `UINT` | `1500` | each socket's send and receive buffer, bytes |
| `nAtQueueLen` | `USINT` | `12` | modem commands that may wait at once |

### ST_GsmPowerConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `nPowerKeyPin` | `INT` | `10` | a board: the GPIO that presses the module's power key, HIGH pressed; -1 none |
| `nRailPin` | `INT` | `-1` | a board: the GPIO that switches the module's supply, HIGH on; -1 none |

### ST_GsmRadioConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `eMode` | `E_GsmRadioMode` |  | which technology to search for; Auto leaves the module's own setting |
| `sOperator` | `STRING(7)` |  | the one network to use, MCC and MNC: '53001'; empty lets the module choose |
| `sCatMBands` | `STRING(64)` |  | LTE-M bands to search: '3, 28'; empty searches all |
| `sNbIotBands` | `STRING(64)` |  | NB-IoT bands to search, the same way |

### ST_GsmSerialConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `sDevice` | `STRING(48)` |  | the Runtime: the modem's serial port, '/dev/ttyUSB2' |
| `nBaudRate` | `DINT` | `115200` | the serial speed both module families start at |
| `nUart` | `BYTE` | `0` | a board: the UART peripheral, 0 to 2, not a pin. Node UIO: 0 |
| `nRxPin` | `INT` | `44` | a board: the GPIO it receives on (the module's TX); -1 the UART's own |
| `nTxPin` | `INT` | `43` | a board: the GPIO it transmits on (the module's RX); -1 the UART's own |
| `nRxBufferSize` | `DINT` | `4096` | a board: bytes of receive buffer, 256 to 32768 |

### ST_GsmSmsConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `nQueueDepth` | `INT` | `8` | SendSms's queue: messages (a number and its text) waiting, 1 to 64 |
| `nMaxPerHour` | `INT` | `10` | messages SendSms queues an hour, every number counted; 0 = no limit |
| `nRetries` | `INT` | `1` | a failed send is tried again this many times, then dropped |
| `tRetry` | `TIME` | `T#60s` | how long before it is tried again |

## Enumerations

Each is `{attribute 'qualified_only'}`, so a value is always written with its type: `E_GsmResult.Ok`, `E_GsmRadioMode.CatM`. A bare `Ok` does not compile.

| Enumeration | Values, in order | Default |
| --- | --- | --- |
| `E_GsmPower` | `SwitchOff`, `SwitchOn`, `Restart` | `SwitchOff` |
| `E_GsmQuality` | `Unknown`, `Bad`, `Uncertain`, `Good` | `Unknown` |
| `E_GsmRadioMode` | `Auto`, `GsmOnly`, `LteOnly`, `GsmAndLte`, `CatM`, `NbIot`, `CatMAndNbIot` | `Auto` |
| `E_GsmRegistration` | `NotSearching`, `Home`, `Searching`, `Denied`, `Unknown`, `Roaming`, `SmsOnlyHome`, `SmsOnlyRoaming`, `EmergencyOnly`, `CsfbNotPreferredHome`, `CsfbNotPreferredRoaming` | `NotSearching` |
| `E_GsmResult` | `Queued`, `Ok`, `NotInitialised`, `InvalidArgument`, `NotReady`, `NoBearer`, `NoSocketAvailable`, `QueueFull`, `Superseded`, `Cancelled`, `TooLarge`, `NotSupportedByModule`, `Error`, `ModuleError`, `Timeout`, `SocketClosed`, `BearerLost`, `Unresponsive`, `PoweredOff`, `RegistrationDenied`, `WrongTask`, `RateLimited` | `Ok` |
| `E_GsmSecurity` | `Plain`, `Tls` | `Plain` |
| `E_GsmState` | `Off`, `PoweringUp`, `Syncing`, `Identifying`, `Configuring`, `SimWait`, `ReadingIdentity`, `NetworkSetup`, `Registering`, `BearerUp`, `Ready`, `Recovering`, `Failed` | `Off` |
| `E_GsmTechnology` | `Unknown`, `Gsm`, `Edge`, `Umts`, `Hspa`, `Lte`, `NbIot`, `CatM` | `Unknown` |

[04 Troubleshooting](04-troubleshooting.md) explains every `E_GsmResult` value.

---

**Next:** [03 MQTT over cellular](03-mqtt-over-cellular.md)
