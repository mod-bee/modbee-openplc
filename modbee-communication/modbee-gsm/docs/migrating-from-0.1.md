# Migrating from 0.1

0.2.0 replaces the twelve blocks of 0.1.x with one block per modem module,
the work as its methods. A project on 0.1.x keeps running unchanged: pin it
(`openplc-cli library pin <project> modbee-gsm@0.1.3`) and move when you
choose. Nothing the modem does changes: the same bring-up, the same
recovery, the same SMS handling and deletes, the same MQTT over cellular.

## What changed, and why

- **One block per module.** `GSM_MODEM` linked both module drivers into every
  firmware. `FB_GsmModemA7670` links only the A76XX driver and
  `FB_GsmModemSim7070` only the SIM707x one: about 4 kB of flash saved on a
  Node UIO.
- **Settings are option structures.** `GSM_ARDUINO`, `GSM_RADIO` and the
  modem's own APN and capacity pins are `stSerialConfig`, `stPowerConfig`,
  `stRadioConfig`, `stApnConfig` and `stCapacityConfig`: set in the
  declaration or from an HMI, checked by the compiler, no `MODEM` pin to wire.
- **The work is methods.** A method call adds no instance and no debugger
  entries, which were half or more of a 0.1 block's flash.
- **Names** follow Beckhoff's TwinCAT conventions: `FB_`, `ST_`, `E_` types,
  `bExecute` / `bError` / `eErrorId` pins, PascalCase enumeration values
  written with their type (`E_GsmResult.Ok`).

## Blocks

| 0.1.x | 0.2.0 |
| --- | --- |
| `GSM_MODEM` | `FB_GsmModemA7670` or `FB_GsmModemSim7070`, by the module |
| `GSM_ARDUINO` | `stSerialConfig` (`nUart`, `nRxPin`, `nTxPin`, `nRxBufferSize`) and `stPowerConfig` (`nPowerKeyPin`, `nRailPin`) |
| `GSM_RADIO` | `stRadioConfig` (`eMode`, `sOperator`, `sCatMBands`, `sNbIotBands`); a setting it cannot read is the block's `bError` |
| `GSM_SMS_SEND` | `modem.SendSms(sTo, sText)`, queued to a list of numbers; or `modem.SendSmsRequest(anyText, sNumber, bExecute)`, one message followed to the network |
| (new) | `modem.Format(sTemplate, anyData, bTruncated =>)`: a message from a template and a STRUCT |
| `GSM_SMS_RECEIVE` | `modem.Inbox(bEnable, bReceived =>, sSender =>, sText =>, nIndex =>, dtSentAt =>, nReceivedCnt =>)` |
| `GSM_SMS_COMMAND` | `modem.SmsCommand(...)`; needs no `Inbox` call |
| `GSM_AT` | `modem.AtCommand(anyCommand, tTimeout, bExecute, sReply =>)` |
| `GSM_POWER` | `modem.Power(ePower, bExecute, bPowered =>, bBusy =>)` |
| `GSM_SOCKET` | `modem.Socket(anyRxData, sHost, nPort, eSecurity, bOpen, sTxData, bSend, ...)` |
| `GSM_STATUS` | `modem.Status(tRefresh, nRssi =>, ...)` |
| `GSM_TIME` | `modem.NetworkTime(tRefresh, bValid =>, dtUtc =>, ...)` |
| `GSM_GNSS` | `modem.Gnss(bEnable, tRefresh, bFix =>, ...)` |

`AT` and `TIME` are IEC keywords, so those two methods are `AtCommand` and
`NetworkTime`.

## Pins

| 0.1.x | 0.2.0 |
| --- | --- |
| `GSM_MODEM.CONNECT` | `bConnect` |
| `APN`, `APN_USER`, `APN_PASSWORD` | `stApnConfig.sApn`, `.sUserName`, `.sPassword` |
| `SIM_PIN` | `sSimPin` |
| `DEVICE`, `BAUD` | `stSerialConfig.sDevice`, `.nBaudRate` |
| `SOCKETS`, `SOCKET_BUFFER`, `AT_QUEUE` | `stCapacityConfig.nSocketCnt`, `.nSocketBufferSize`, `.nAtQueueLen` |
| `READY`, `REGISTERED`, `STATE` | `bConnected`, `bRegistered`, `eConnectionState` |
| `ERROR`, `STATUS`, `LAST_ERROR` | `bError`, `eErrorId`, `sLastError` |
| `GSM_ARDUINO.PORT`, `RX_PIN`, `TX_PIN`, `RX_BUFFER` | `stSerialConfig.nUart`, `.nRxPin`, `.nTxPin`, `.nRxBufferSize` |
| `GSM_ARDUINO.POWER_KEY_PIN`, `RAIL_PIN` | `stPowerConfig.nPowerKeyPin`, `.nRailPin` |
| `GSM_RADIO.MODE`, `OPERATOR`, `CAT_M_BANDS`, `NB_IOT_BANDS` | `stRadioConfig.eMode`, `.sOperator`, `.sCatMBands`, `.sNbIotBands` |
| `GSM_SMS_SEND.REQ`, `NUMBER`, `TEXT` | `SendSmsRequest`'s `bExecute`, `sNumber`, `anyText`; or a `SendSms(sTo, sText)` call on the edge |
| `GSM_SMS_SEND.BUSY`, `DONE`, `ERROR` | `SendSmsRequest`'s result (`Queued`, then `Ok` or the reason); for `SendSms` the block's `nSmsQueued`, `nSmsSent`, `nSmsFailed`, `nSmsDropped`, `sSmsLastError` |
| `GSM_SMS_RECEIVE.ENABLE`, `RECEIVED`, `SENDER`, `TEXT`, `INDEX`, `SENT_AT`, `COUNT` | `Inbox`'s `bEnable`, `bReceived`, `sSender`, `sText`, `nIndex`, `dtSentAt`, `nReceivedCnt` |
| `GSM_SMS_COMMAND.COMMAND`, `ALLOWED`, `PIN`, `ADMIN_COMMAND`, `ADMIN_PIN`, `PULSE`, `REPLY`, `REPLY_TEXT`, `MAX_PER_HOUR`, `ENABLE` | `SmsCommand`'s `sCommands`, `sAllowed`, `nPin`, `sAdminCommands`, `nAdminPin`, `tPulse`, `nReply`, `sReplyText`, `nMaxPerHour`, `bEnable` |
| `GSM_SMS_COMMAND.Q`, `CMD`, `MATCHED`, `ARG`, `VALUE`, `VALUE_OK`, `DURATION`, `DURATION_OK`, `ADMIN`, `SENT_BY`, `COUNT`, `REFUSED`, `LAST_REFUSED` | `bCmd`, `nCmd`, `sMatched`, `sArg`, `fValue`, `bValueOk`, `tDuration`, `bDurationOk`, `bAdmin`, `sSentBy`, `nCmdCnt`, `nRefusedCnt`, `sLastRefused` |
| `GSM_AT.REQ`, `COMMAND`, `TIMEOUT`, `REPLY` | `AtCommand`'s `bExecute`, `anyCommand`, `tTimeout`, `sReply` |
| `GSM_POWER.POWER_OFF`, `POWER_ON`, `RESTART` | `Power`'s `ePower` (`E_GsmPower.SwitchOff`, `SwitchOn`, `Restart`) and one `bExecute` |
| `GSM_POWER.POWERED`, `BUSY` | `bPowered`, `bBusy` |
| `GSM_SOCKET.OPEN`, `HOST`, `PORT`, `SECURITY`, `SEND`, `TX_DATA` | `Socket`'s `bOpen`, `sHost`, `nPort`, `eSecurity`, `bSend`, `sTxData` |
| `GSM_SOCKET.CONNECTED`, `SENT`, `RECEIVED`, `RX_DATA` | `bSocketConnected`, `bSent`, `bReceived`, and the STRING given as `anyRxData` (`nRxLen` characters) |
| `GSM_STATUS.REFRESH`, `RSSI`, `RSRP`, `RSRQ`, `QUALITY`, `REGISTRATION`, `TECHNOLOGY`, `OPERATOR`, `IP`, `IMEI`, `ICCID`, `MODULE`, `FIRMWARE`, `SOCKETS_FREE` | `Status`'s `tRefresh`, `nRssi`, `nRsrp`, `nRsrq`, `eQuality`, `eRegistration`, `eTechnology`, `sOperator`, `sIpAddr`, `sImei`, `sIccid`, `sModule`, `sFirmware`, `nSocketsFree` |
| `GSM_STATUS.BRING_UPS`, `RECOVERIES`, `BEARER_LOSSES`, `REGISTRATION_LOSSES` | `nBringUpCnt`, `nRecoveryCnt`, `nBearerLossCnt`, `nRegistrationLossCnt` |
| `GSM_TIME.REFRESH`, `VALID`, `UTC`, `LOCAL`, `ZONE`, `AGE` | `NetworkTime`'s `tRefresh`, `bValid`, `dtUtc`, `dtLocal`, `nUtcOffset`, `tAge` |
| `GSM_GNSS.ENABLE`, `REFRESH`, `SUPPORTED`, `FIX`, `LATITUDE`, `LONGITUDE`, `ALTITUDE`, `SATELLITES`, `AGE` | `Gnss`'s `bEnable`, `tRefresh`, `bSupported`, `bFix`, `fLatitude`, `fLongitude`, `fAltitude`, `nSatellites`, `tAge` |

## Behaviour that changed

- **DONE and ERROR are one result.** A 0.1 request block pulsed `DONE` or
  `ERROR` for one scan. A 0.2 request method returns `E_GsmResult.Queued`
  while it runs, then `Ok` or the reason, held until the next rising edge of
  `bExecute`. Gate a sequence on `result = E_GsmResult.Ok`, no latch needed.
- **A request the modem cannot take is refused at once**, not queued: a
  `SendSmsRequest` before the network has the SIM returns `NotReady` at the
  edge. `SendSms` is the queued form: its messages wait for the network,
  within `stSmsConfig`'s depth and hourly limit, and are retried.
- **One task.** Methods run in the task the block's own call runs in, and
  return `WrongTask` elsewhere. 0.1 blocks could sit in any task.
- **Records.** A method call is found again by its ANY's declared name, or a
  literal's text (`SendSms`: its number). Two calls on one variable are one
  record: give each its own variable.
- **SmsCommand needs no Inbox.** The block itself takes each arriving message,
  one a scan, and every `Inbox` and `SmsCommand` call sees it. A command is
  looked at before anything that waits for the modem, so another task holding
  the modem never loses one (0.1.4's fix, kept).
- **Gnss's bEnable defaults to TRUE**, as a method is called while it is
  wanted. 0.1's `ENABLE` defaulted to FALSE.
- **Power is one request**: `ePower` says which, `bExecute` starts it. 0.1's
  "off wins over restart over on" for edges arriving together is gone.
- **A failing call is named on the block**: `bError`, `eErrorId` and
  `sLastError` ("AtCommand sAtCmd: ModuleError (...)") until the same call
  succeeds, where the modem itself has nothing to report.
- **GSM_ARDUINO's own APPLIED and ERROR** are gone: a board setting that
  cannot be used is the block's `bError`, and the modem is not opened on it.
- **E_GsmResult gains WrongTask and RateLimited** at its end; every other
  value keeps its ordinal.
- **Enumeration values** are PascalCase and qualified: `GSM_OK` is
  `E_GsmResult.Ok`, `GSM_READY` is `E_GsmState.Ready`, `GSM_RADIO_CAT_M` is
  `E_GsmRadioMode.CatM`, `GSM_TLS` is `E_GsmSecurity.Tls`, `GSM_REG_HOME` is
  `E_GsmRegistration.Home`, `GSM_TECH_LTE` is `E_GsmTechnology.Lte`,
  `GSM_QUALITY_GOOD` is `E_GsmQuality.Good`. The order of every enumeration
  is unchanged, with `E_GsmResult.WrongTask` and `RateLimited` added at the end.

## modbee-mqtt

`FB_MqttClient` with `eTransport := E_MqttTransport.Cellular` (0.1:
`MQTT_CLIENT` with `TRANSPORT := MQTT_CELLULAR`) reaches the modem block of
either module by itself, as before. Move both libraries together: modbee-mqtt
0.2.0 with modbee-gsm 0.2.0.

## Before and after

```
(* 0.1.x *)
modem(CONNECT := TRUE, APN := 'internet');
radio(MODEM := modem, MODE := GSM_RADIO_CAT_M, CAT_M_BANDS := '3, 28');
status(MODEM := modem, REFRESH := T#30s);
alarm(MODEM := modem, REQ := high, NUMBER := oncall, TEXT := 'Tank high');
inbox(MODEM := modem);
cmds(INBOX := inbox, COMMAND := 'START, STOP', ALLOWED := numbers, PIN := pin);

(* 0.2.0 *)
apn.sApn := 'internet';
radio.eMode := E_GsmRadioMode.CatM;
radio.sCatMBands := '3, 28';
modem(bConnect := TRUE, stApnConfig := apn, stRadioConfig := radio);
r := modem.Status(tRefresh := T#30s, nRssi => rssi);
IF high AND NOT highWas THEN
  r := modem.SendSms(sTo := oncall, sText := 'Tank high');
END_IF;
highWas := high;
r := modem.SmsCommand(sCommands := 'START, STOP', sAllowed := numbers, nPin := pin,
                      bCmd => started, nCmd => which);
```
