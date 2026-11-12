# Migrating from 0.1

modbee-mqtt 0.2.0 replaces the 28 blocks of 0.1.x with 6. Each connection is
one block; everything per topic, record or account is a method of it; the
configuration blocks are option structures on the client's inputs. Names
follow Beckhoff's TwinCAT 3 conventions: `FB_` blocks, `ST_` structures, `E_`
enumerations used qualified, pins with a type prefix (`bConnect`, `sHost`,
`nPort`).

**You do not have to move.** A project built on 0.1.x stays on 0.1.x and runs
unchanged: pin it (`openplc-cli library pin <project> modbee-mqtt@0.1.2`) and
it keeps building against the version it was written for. Move when you
choose. **The wire does not change**: the same configuration sends the same
topics, metric names, devices and births, so a SCADA system or a subscriber
sees no difference.

## The shape of a 0.2.0 program

```st
VAR
  mqtt : FB_MqttClient;
  sp   : FB_SparkplugNode;
END_VAR

mqtt(eTransport := E_MqttTransport.RuntimeTcp, sHost := '10.0.0.20',
     sClientId := 'plc-intake');
mqtt.Report(anyValue := rLevel, sTopic := 'plant/intake/level', tPeriod := T#1m);
sp(fbClient := mqtt, sGroupId := 'Plant1', sEdgeNodeId := 'intake');
sp.Record(anyData := STS, sSettings := '* = now');
```

was, in 0.1.x:

```
net  ( TRANSPORT := MQTT_RUNTIME_TCP, HOST := '10.0.0.20', CLIENT_ID := 'plc-intake' );
level( CLIENT := net, TOPIC := 'plant/intake/level', VALUE := rLevel, PERIOD := T#1m );
sp   ( CLIENT := net, GROUP := 'Plant1', NODE := 'intake' );
core ( NODE := sp, DATA := STS );
```

- **A method call has no instance.** Drop the 0.1.x instance (`level`,
  `core`) and call the method on its parent. A call is found again each scan
  by **the variable it is about** - its declared name and type - so one
  variable is one record per method. Two 0.1.x instances that published the
  same variable to two topics need two variables now.
- **The parent pin is gone**: `CLIENT := net` and `NODE := sp` are the method's
  instance. The Sparkplug blocks take their client on `fbClient`.
- **Each method returns an `E_MqttResult`.** The `ERROR`/`STATUS` pair of every
  0.1.x block is that result; `DONE` and `BUSY` are `Ok` and `Queued`.
- **Outputs are read with `=>`**: `mqtt.Subscribe(..., eQuality => q)`.
- **Enumerations are qualified**: `E_MqttResult.Ok`, not `MQTT_OK`. Each type is
  `{attribute 'qualified_only'}`, so a bare `Ok` does not compile.

## Blocks

| 0.1.x | 0.2.0 |
| --- | --- |
| `MQTT_CLIENT` | `FB_MqttClient` |
| `MQTT_CONFIG` | `FB_MqttClient.stSessionConfig : ST_MqttSessionConfig` |
| `MQTT_TLS` | `FB_MqttClient.stTlsConfig : ST_MqttTlsConfig` |
| `MQTT_ARDUINO` | `FB_MqttClient.stNetworkConfig : ST_MqttNetworkConfig` |
| `MQTT_PRESENCE` | `FB_MqttClient.stWillConfig : ST_MqttWillConfig` |
| `MQTT_PUBLISH` | `mqtt.Publish` |
| `MQTT_REPORT` | `mqtt.Report` |
| `MQTT_SUBSCRIBE` | `mqtt.Subscribe` |
| `MQTT_STRUCT_PUBLISH` | `mqtt.PublishStruct` |
| `MQTT_STRUCT_SUBSCRIBE` | `mqtt.SubscribeStruct` |
| `MQTT_REQUEST` | `mqtt.Request` |
| (new) | `mqtt.Response` - answers another device's MQTT 5 request |
| `MQTT_MESSAGE` | `mqtt.Message` |
| `MQTT_PROVISION` | `mqtt.Provision` |
| `MQTT_STATUS` | `mqtt.Statistics`; `CONNECTED` and `STATE` are the client's `bConnected` and `eConnectionState` |
| `SPARKPLUG_NODE` | `FB_SparkplugNode` |
| `SPARKPLUG_STRUCT` | `sp.Record` |
| `SPARKPLUG_MEMBER` | the point list, `sSettings` of `sp.Record` |
| `SPARKPLUG_METRIC` | `sp.Metric` |
| `SPARKPLUG_DEVICE` | `sp.Device` |
| `SPARKPLUG_COMMAND` | `sp.Command` |
| `SPARKPLUG_HISTORY` | `sp.History` |
| `SPARKPLUG_DAY_TOTALS` | `sp.DayTotals` |
| `SPARKPLUG_DAY` | `ST_SparkplugDay` |
| (new) | `ST_SparkplugReportConfig`, the node's `stReportConfig` |
| `SPARKPLUG_HOST` | `FB_SparkplugHost` |
| `SPARKPLUG_SUBSCRIBE` | `host.Watch` |
| `SPARKPLUG_WRITE` | `host.Write` |
| `MQTT_BROKER` | `FB_MqttBroker` |
| `MQTT_BROKER_USER` | `broker.User` |
| `MQTT_BRIDGE` | `FB_MqttBridge` |
| `MQTT_CLOCK` | `FB_MqttClock` |

## Enumerations

| 0.1.x | 0.2.0 | values |
| --- | --- | --- |
| `MQTT_RESULT` | `E_MqttResult` | `MQTT_OK` is `E_MqttResult.Ok`, `MQTT_QUEUED` `Queued`, `MQTT_NOT_CONNECTED` `NotConnected`, `MQTT_WRONG_TASK` `WrongTask` ... - every value the same name in PascalCase, same order |
| `MQTT_LINK` | `E_MqttTransport` | `MQTT_RUNTIME_TCP` `RuntimeTcp`, `MQTT_ARDUINO_WIFI` `ArduinoWiFi`, `MQTT_ARDUINO_ETHERNET` `ArduinoEthernet`, `MQTT_CELLULAR` `Cellular`, `MQTT_LINK_EXTERNAL` `External` |
| `MQTT_SECURITY` | `E_MqttSecurity` | `Plain`, `TlsVerify`, `TlsPinned`, `TlsInsecure` |
| `MQTT_PROTOCOL` | `E_MqttProtocol` | `V5`, `V311`, `V5ThenV311` |
| `MQTT_STATE` | `E_MqttState` | `Idle`, `Connecting`, `AwaitingConnAck`, `Authenticating`, `Connected`, `Disconnecting`, `Reconnecting` |
| `MQTT_QUALITY` | `E_MqttQuality` | `Unknown`, `Bad`, `Uncertain`, `Good` |
| `MQTT_TRIGGER` | `E_MqttTrigger` | `OnChange`, `OnInterval`, `OnRequest`, `ChangedEvery` |
| `MQTT_DIRECTION` | `E_MqttDirection` | `Out`, `In`, `Both` |
| `MQTT_BRIDGE_STATE` | `E_MqttBridgeState` | `Idle`, `Connecting`, `Up`, `Degraded` |
| a `QOS : BYTE` of 0, 1, 2 | `E_MqttQos` | `AtMostOnceDelivery`, `AtLeastOnceDelivery`, `ExactlyOnceDelivery` |

## Pins

### MQTT_CLIENT and its helpers

| 0.1.x | 0.2.0 |
| --- | --- |
| `TRANSPORT`, `SECURITY`, `HOST`, `PORT`, `CLIENT_ID`, `PROTOCOL`, `EXTERNAL_LINK`, `CONNECT`, `TRUST_NEW` | `eTransport`, `eSecurity`, `sHost`, `nPort`, `sClientId`, `eProtocol`, `nExternalLink`, `bConnect`, `bTrustNew` |
| `LINK_UP`, `CONNECTED`, `HEARD_AGO`, `SESSION_PRESENT`, `ASSIGNED_ID`, `STATE`, `ERROR`, `STATUS`, `LAST_ERROR`, `BROKER_KEY` | `bLinkUp`, `bConnected`, `tHeardAgo`, `bSessionPresent`, `sAssignedId`, `eConnectionState`, `bError`, `eErrorId`, `sLastError`, `sBrokerKey` |
| `MQTT_CONFIG`: `KEEP_ALIVE`, `CLEAN_START`, `KEEP_SESSION`, `USERNAME`, `PASSWORD` | `stSessionConfig`: `tKeepAlive`, `bCleanStart`, `tSessionExpiry`, `sUserName`, `sUserPassword` |
| `MAX_PENDING`, `MAX_MESSAGE_IN`, `MAX_MESSAGE_OUT` | `nMaxPending`, `nMaxMsgIn`, `nMaxMsgOut` |
| `RECONNECT`, `RECONNECT_MAX`, `CONNECT_TIMEOUT`, `MAX_SILENCE`, `AUTO_RECONNECT`, `RETRY_REJECTED_CREDENTIAL` | `tReconnect`, `tReconnectMax`, `tConnectTimeout`, `tMaxSilence`, `bAutoReconnect`, `bRetryRejectedCredential` |
| `MQTT_TLS`: `CA_FILE`, `CERT_FILE`, `KEY_FILE` | `stTlsConfig`: `sCaFile`, `sCertFile`, `sKeyFile` |
| `MQTT_ARDUINO`: `SSID`, `WIFI_PASSWORD`, `MAC`, `IP`, `GATEWAY`, `SUBNET` | `stNetworkConfig`: `sSsid`, `sWiFiPassword`, `sMac`, `sIp`, `sGateway`, `sSubnet` |
| `MQTT_PRESENCE`: `TOPIC`, `ONLINE`, `OFFLINE`, `RETAINED`, `QOS`, `DELAY` | `stWillConfig`: `sTopic`, `sOnline`, `sOffline`, `bRetain`, `eQos`, `tDelay` |
| the helpers' `APPLIED`, `ERROR`, `STATUS`; `MQTT_PRESENCE.SENT` | gone: a structure that cannot be used is reported on the client's `bError`, `eErrorId`, `sLastError` |

### Publishing and subscribing

| 0.1.x | 0.2.0 method parameter |
| --- | --- |
| `VALUE` (`MQTT_PUBLISH`, `_REPORT`, `_SUBSCRIBE`, `_REQUEST`) | `anyValue` |
| `DATA` (the STRUCT blocks) | `anyData` |
| `TOPIC`, `BASE`, `REPLY_TOPIC` | `sTopic`, `sBase`, `sReplyTopic` |
| `QOS : BYTE` | `eQos : E_MqttQos` |
| `RETAINED` | `bRetain` |
| `REQ` | `bExecute` |
| `ENABLE` | `bEnable` |
| `MODE` | `eTrigger` |
| `DEADBAND`, `PERIOD`, `EXPECT`, `TIMEOUT` | `fDeadband`, `tPeriod`, `tExpect`, `tTimeout` |
| `BUSY`, `DONE`, `ERROR`, `STATUS` | the result: `Queued`, `Ok`, anything else |
| `SENT`, `AGE`, `SUBSCRIBED`, `QUALITY`, `SEEN`, `RECEIVED`, `MALFORMED`, `NEW_VALUE` | `nSent`, `tAge`, `bSubscribed`, `eQuality`, `bSeen`, `nReceived`, `nMalformed`, `bNewValue` |
| `POINTS`, `SKIPPED`, `CHANGED`, `OLDEST`, `NEW_VALUES` | `nPoints`, `nSkipped`, `nChanged`, `tOldest`, `nNewValues` |
| `MQTT_REQUEST`: `REPLY`, `REPLY_LENGTH` | `sReply`, `nReplyLen` |
| `MQTT_MESSAGE`: `PAYLOAD` (an output) | `anyPayload`, an input: **your own STRING variable**, of any length |
| `MQTT_MESSAGE`: `LENGTH`, `TRUNCATED`, `NEW_MESSAGE` | `nLen`, `bTruncated`, `bNewMessage` |
| `MQTT_PROVISION`: `KEY`, `FORGET` | `sKey`, `bForget` |
| `PROVISIONED`, `PENDING`, `REFUSED`, `USERNAME`, `GROUP`, `PREFIX`, `REASON` | `bProvisioned`, `bPending`, `bRefused`, `sUserName`, `sGroup`, `sPrefix`, `sReason` |
| `MQTT_STATUS`: `VERSION`, `CONNECTS`, `DISCONNECTS`, `RECONNECTS`, `PUBLISHED`, `RECEIVED`, `PUBLISH_FAILURES`, `PROTOCOL_ERRORS`, `PENDING`, `REASON_CODE` | `nVersion`, `nConnects`, `nDisconnects`, `nReconnects`, `nPublished`, `nReceived`, `nPublishFailures`, `nProtocolErrors`, `nPending`, `nReasonCode` |

### Sparkplug

| 0.1.x | 0.2.0 |
| --- | --- |
| `SPARKPLUG_NODE`: `GROUP`, `NODE`, `PRIMARY_HOST`, `REBIRTH_HOLDOFF`, `ENABLE`, `CLIENT` | `sGroupId`, `sEdgeNodeId`, `sPrimaryHostId`, `tRebirthHoldoff`, `bEnable`, `fbClient` |
| `LINK_UP`, `BORN`, `SEQ`, `BDSEQ`, `POINTS`, `ERROR`, `STATUS`, `LAST_ERROR`, `CLOCK_SET` | `bLinkUp`, `bBorn`, `nSeq`, `nBdSeq`, `nPoints`, `bError`, `eErrorId`, `sLastError`, `bClockSet` |
| `BROKER`, `PORT`, `SECURITY`, `USER`, `PASSWORD`, `PROTOCOL`, `TRUST_NEW`, `CA_FILE`, `CERT_FILE`, `KEY_FILE`, `KEEP_ALIVE`, `LINK`, `TRANSPORT`, `SERVER`, `BROKER_KEY` | gone: the connection is the client's - set them on `FB_MqttClient` |
| (new) | `stReportConfig`, `anyUnits`, `bViewed`, `sDemand` |
| `SPARKPLUG_STRUCT`: `DATA`, `PREFIX`, `SETTINGS` | `Record`: `anyData`, `sPrefix`, `sSettings` (a point list, page 15) |
| `MODE`, `PERIOD`, `REQ`, `WRITABLE`, `ENABLE`, `DEADBAND`, `DEADBAND_PCT`, `DEVICE` | the class and options of each clause, and `stReportConfig` - see below |
| `POINTS`, `BAD_SETTING` | `nMetricCnt`, `nBadClause` |
| `SKIPPED`, `SENT`, `CHANGED`, `WRITTEN`, `REFUSED`, `LOST` | gone |
| `SPARKPLUG_METRIC`: `NAME`, `VALUE`, `DEVICE`, `UNITS`, `QUALITY`, `WRITABLE`, `PUBLISH`, `ENABLE`, `DEADBAND` | `Metric`: `sMetricName`, `anyValue`, `sDeviceId`, `sUnits`, `eQuality`, `bWritable`, `bPublish`, `bUpdate`, `fDeadband` |
| `ALIAS`, `WRITTEN`, `LOST` | `nAlias`, `nWrittenCnt`, `nLostCnt` |
| `SPARKPLUG_DEVICE`: `DEVICE`, `ONLINE`; `IS_ONLINE`, `BIRTHS`, `DEATHS` | `Device`: `sDeviceId`, `bOnline`; `bDeviceOnline`, `nBirthCnt`, `nDeathCnt`. `ENABLE` is gone: stop calling it |
| `SPARKPLUG_COMMAND`: `NAME`, `DEVICE`, `ACK` | `Command`: `sMetricName`, `sDeviceId`, `bAck` |
| `PENDING`, `VALUE`, `IS_TRUE`, `TEXT`, `COUNT`, `REFUSED`, `LOST` | `bPending`, `fValue`, `bValue`, `sText`, `nCmdCnt`, `nRefusedCnt`, `nLostCnt` |
| `SPARKPLUG_HISTORY`: `ADD`, `SOURCE`, `CODE`, `VALUE`, `NAME`, `DEPTH`, `BATCH`, `PERIOD` | `History`: `bAdd`, `nSource`, `nCode`, `fValue`, `sMetricPrefix`, `nDepth`, `nBatch`, `tPeriod` |
| `STORED`, `LOST`, `SENT`, `REPLAYING` | `nStoredCnt`, `nLostCnt`, `nSentCnt`, `bReplaying` |
| `SPARKPLUG_DAY_TOTALS`: `TABLE`, `NAME`, `VALUE`, `CLOCK`, `SAVE_EVERY` | `DayTotals`: `anyDays`, `sMetricName`, `fValue`, `dtClock`, `tSaveEvery` |
| `DAYS`, `SENT` | `nDays`, `nSentCnt` |
| `SPARKPLUG_DAY`: `DAY`, `TOTAL` | `ST_SparkplugDay`: `dDay`, `fTotal` |
| `SPARKPLUG_HOST`: `HOST_ID`, `GROUP`, `PRIMARY`, `REORDER`, `ENABLE`, `CLIENT` | `sHostId`, `sGroupId`, `bPrimary`, `tReorder`, `bEnable`, `fbClient` |
| `LINK_UP`, `BORN`, `NODES`, `ONLINE`, `GAPS`, `REBIRTHS`, `ERROR`, `STATUS`, `LAST_ERROR` | `bLinkUp`, `bBorn`, `nNodes`, `nOnline`, `nGaps`, `nRebirths`, `bError`, `eErrorId`, `sLastError` |
| `SPARKPLUG_SUBSCRIBE`: `NAME`, `VALUE`, `NODE_ID`, `GROUP`, `DEVICE` | `Watch`: `sMetricName`, `anyValue`, `sEdgeNodeId`, `sNodeGroupId`, `sDeviceId` |
| `VALID`, `TYPE_OK`, `FRESH`, `AGE`, `READS` | `bValid`, `bTypeOk`, `bFresh`, `nAge`, `nReadCnt` |
| `SPARKPLUG_WRITE`: `NAME`, `VALUE`, `REQ`, `NODE_ID`, `GROUP`, `DEVICE` | `Write`: `sMetricName`, `anyValue`, `bExecute`, `sEdgeNodeId`, `sNodeGroupId`, `sDeviceId` |
| `SENT`, `COUNT` | the result `Ok`; `nSentCnt` |
| `ENABLE` on `SPARKPLUG_SUBSCRIBE`, `SPARKPLUG_WRITE`, `SPARKPLUG_METRIC` | gone: a method runs while it is called |

### Broker, bridge, clock

| 0.1.x | 0.2.0 |
| --- | --- |
| `MQTT_BROKER`: `ENABLE`, `LISTEN_ON`, `PORT`, `MAX_CLIENTS`, `MAX_RETAINED`, `SECURITY`, `CERT_FILE`, `KEY_FILE`, `MAX_SUBSCRIPTIONS`, `MAX_QUEUED`, `MAX_MESSAGE`, `MAX_SESSION_EXPIRY` | `bEnable`, `sListenOn`, `nPort`, `nMaxClients`, `nMaxRetained`, `eSecurity`, `sCertFile`, `sKeyFile`, `nMaxSubscriptions`, `nMaxQueued`, `nMaxMsgSize`, `tMaxSessionExpiry` |
| `LISTENING`, `CLIENTS`, `SESSIONS`, `ACCEPTED`, `ADMITTED`, `REFUSED`, `FROM_CLIENTS`, `TO_CLIENTS`, `DROPPED`, `TAKEOVERS`, `ERROR`, `STATUS`, `BROKER_KEY` | `bListening`, `nClients`, `nSessions`, `nAccepted`, `nAdmitted`, `nRefused`, `nFromClients`, `nToClients`, `nDropped`, `nTakeovers`, `bError`, `eErrorId`, `sBrokerKey` |
| `MQTT_BROKER_USER`: `BROKER`, `USERNAME`, `PASSWORD`, `ENABLE`; `ACTIVE`, `LOGINS`, `REFUSED` | `broker.User`: `sUserName`, `sUserPassword`, `bAllow`; `bActive`, `nLoginCnt`, `nRefusedCnt` |
| `MQTT_BRIDGE`: `ENABLE`, `LOCAL_HOST`, `LOCAL_PORT`, `LOCAL_SECURITY`, `REMOTE_HOST`, `REMOTE_PORT`, `REMOTE_SECURITY`, `REMOTE_USER`, `REMOTE_PASSWORD`, `BRIDGE_NAME`, `TOPIC`, `DIRECTION`, `QOS`, `LOCAL_PREFIX`, `REMOTE_PREFIX`, `FORWARD_RETAINED` | `bEnable`, `sLocalHost`, `nLocalPort`, `eLocalSecurity`, `sRemoteHost`, `nRemotePort`, `eRemoteSecurity`, `sRemoteUserName`, `sRemoteUserPassword`, `sBridgeName`, `sTopic`, `eDirection`, `eQos`, `sLocalPrefix`, `sRemotePrefix`, `bForwardRetained` |
| `STATE`, `LOCAL_UP`, `REMOTE_UP`, `FORWARDED_OUT`, `FORWARDED_IN`, `REFUSED_OUT`, `REFUSED_IN`, `ERROR`, `STATUS` | `eBridgeState`, `bLocalUp`, `bRemoteUp`, `nForwardedOut`, `nForwardedIn`, `nRefusedOut`, `nRefusedIn`, `bError`, `eErrorId` |
| `MQTT_CLOCK`: `TRANSPORT`, `SERVER`, `REFRESH`, `UTC_IN`, `UTC_IN_VALID`, `ENABLE` | `eTransport`, `sServer`, `tRefresh`, `dtUtcIn`, `bUtcInValid`, `bEnable` |
| `SYNCED`, `UTC`, `AGE`, `ERROR`, `LAST_ERROR` | `bSynced`, `dtUtc`, `tAge`, `bError`, `sLastError` |

## SPARKPLUG_STRUCT becomes Record

A `SPARKPLUG_STRUCT` had one mode for the whole STRUCT. `Record` gives each
member a **class** in a point list (page 15), so one call does what several
struct blocks with different modes did:

```st
sp.Record(anyData := PUMP1, sPrefix := 'pump1/',
          sSettings := 'sts = now; tot = log, db = 0.1, u = h; det = live; cmd = cmd, pulse = 500');
```

| 0.1.x | 0.2.0 |
| --- | --- |
| `MODE := E_MqttTrigger.OnChange` | `now` |
| `WRITABLE := TRUE` | `cmd`, and `stReportConfig.bRemoteControl := TRUE`. `WRITABLE` going FALSE at run time is `bRemoteControl := FALSE` |
| `MODE := E_MqttTrigger.ChangedEvery`, `PERIOD := T#15m` | `log`; the interval is the node's `tLogInterval`, at most 15 minutes |
| a `ChangedEvery` set with a short `PERIOD` and `ENABLE` wired to "someone is viewing" | `view` (node metrics) or `live` (device `live`); Live Demand does the wiring |
| `MODE := E_MqttTrigger.OnInterval`, `PERIOD := T#1m` | `every:T#1m` |
| `MODE := E_MqttTrigger.OnRequest`, `REQ := bGo` | `onreq`, with Record's `bSend := bGo` |
| `DEVICE := 'live'` or `'cfg-...'` | the `live` and `set:<page>` classes |
| `DEVICE := 'skid2'`, a device of your own | `dev=skid2` on the clause, and `sp.Device(sDeviceId := 'skid2', bOnline := ...)` to bring it on and off line |
| `DEADBAND`, `DEADBAND_PCT` | `db=` and `pct=` on the clause; `stReportConfig.fDeadbandPct` for the log class |
| `SETTINGS : ARRAY OF SPARKPLUG_MEMBER` | the clauses: `NAME` is the members, `UNITS` `u=`, `DEADBAND` `db=`, `DEADBAND_PCT` `pct=`, `LOW`/`HIGH` `lo=`/`hi=`, `PULSE := T#500ms` `pulse=500` |
| `SKIP := TRUE` | leave the member out of every clause |
| `BAD_SETTING` | `nBadClause` |

## Behaviour that changed

**The host's `Write` is refused when not connected, instead of retried.** In
0.1.x `SPARKPLUG_WRITE` held a command while its client was not connected and
sent it when the link came back - which could be long after the operator meant
it. `host.Write` returns `NotConnected` at the rising edge of `bExecute` and
queues nothing; raise the edge again when `mqtt.bConnected` is back. It still
waits, while `bExecute` stays TRUE, for a node not heard from yet. `Publish`
and `Request` follow the same rule, and judge it by `bConnected`: a link that
is open but not yet acknowledged by the broker is not connected.

**`Report` compares text by fingerprint.** A `STRING` (or anything without a
number) is "changed" when a 32-bit fingerprint of its text changes, not by a
full comparison. In practice the same; it keeps no copy of the text.

**The bridge starts.** In 0.1.x `MQTT_BRIDGE` took its own successful start
(`Queued`) for a failure: it set `ERROR` with `STATUS = MQTT_QUEUED` and never
forwarded. `FB_MqttBridge` starts and forwards.

**`Metric`'s `eQuality` defaults to `Good`.** `SPARKPLUG_METRIC.QUALITY` defaulted
to the enumeration's first value, `UNKNOWN`, which went to the host as bad
unless it was set. A metric whose quality you never set is now good.

**`History` and `DayTotals` follow node births, not device births.** In 0.1.x a
device's birth also counted: the day totals were sent again on every DBIRTH,
and an event batch in flight could be taken as confirmed by one. Now the
closed days go on every **node** birth and every close, and an event is
confirmed only by the node staying born on the same NBIRTH. With Live Demand
bringing devices on and off line every few minutes, that is the difference
between one copy of the day totals and dozens.

**Devices `live` and `cfg-...` belong to Live Demand.** A 0.1.x project that
used `SPARKPLUG_DEVICE` to bring a `live` or `cfg-<page>` device on line
itself - the viewer contract built by hand - leaves that to the node: put
those members in a record with the `live` and `set:<page>` classes, and the
node offers `Node Control/Live Demand` and births the devices while a host
demands them. `Device` and `Metric` refuse those names.

**A metric declared after the birth rebirths the node.** A `Record` or
`Metric` first called once the node is born makes it birth again, so the host
has a birth for every name it receives data for.

**`MQTT_MESSAGE.PAYLOAD` is your variable.** It was a `STRING(254)` output; it
is now `anyPayload`, a `STRING` of your own of any width, and `bTruncated`
says when a message did not fit.

**Every method runs in its block's task.** As in 0.1.x a block in another task
than its client did nothing; now a method called from another task returns
`WrongTask`.

**Limits.** A client holds 256 method records, a Sparkplug node 1024
`Metric`, `Device`, `Command`, `History` and `DayTotals` calls; past that,
`QueueFull`. Records of `Record` grow with memory.

## Moving a project

1. Pin the project to 0.1.x and keep a copy that builds.
2. Change the library to 0.2.0.
3. Rename each block instance's type and pins with the tables above. Delete
   the helper instances (`MQTT_CONFIG`, `MQTT_TLS`, `MQTT_ARDUINO`,
   `MQTT_PRESENCE`) and move their pins into the client's structures.
4. Replace each per-topic instance by a method call on its client or node,
   and delete the instance. Give every call its own variable.
5. Replace each `SPARKPLUG_STRUCT` group by one `Record` per record with a
   point list.
6. `openplc-cli check <project> --lint`, then compare the metric list a host
   sees with the 0.1.x one: the names and births should be the same.

**Back to** [the index](README.md).
