# OTA

Updates a ModBee node's firmware over MQTT from inside the PLC program. The
node pulls the new firmware a piece at a time, checks it, switches to it and
reboots. If the new firmware does not come back on MQTT, the board goes back
to the old one by itself.

One block, `FB_OtaNode`, on the `FB_MqttClient` of the MQTT library
(modbee-mqtt 0.2.0):

| | Does |
|---|---|
| `FB_OtaNode` | The updater. One per board, wired to an `FB_MqttClient` |
| `stSigningConfig : ST_OtaSigningConfig` | Optional: only firmware signed with your key installs |
| `FB_OtaNode.Sparkplug` | Optional: the update as Sparkplug metrics, run from SCADA |

## Getting started

1. Enable the **MQTT** and **OTA** libraries in the project.
2. In the comms task (T#50ms or slower), next to the `FB_MqttClient`:

   ```
   ota(fbClient := mqtt, sBaseTopic := 'modbee/pump-01/ota', sVersion := '1.4.0');
   ```

   `sVersion` is this program's version. Raise it for every release: an
   update for the same version is refused, and an older one unless
   `bAllowDowngrade`.
3. Publish the update from the PC with `modbee_ota.py`, from the `tools/`
   folder of the [modbee-ota](https://github.com/mod-bee/modbee-ota) repository:

   ```
   python modbee_ota.py push firmware.bin --broker <broker> \
       --base modbee/pump-01/ota --board modbee-node-uio --version 1.4.1 --retain
   ```

   `firmware.bin` is the program the editor built for the board.
   `--retain` lets a node that is offline now take the update when it comes
   back, and lets a node that lost power carry on where it stopped.

## Choosing when

Firmware updates restart the PLC. Let the program decide the moment:

| Pin | Then |
|---|---|
| `bAutoAccept := FALSE` | `eState` waits at `E_OtaState.Offered`. `bAccept` starts the download, `bReject` refuses it |
| `bAutoApply := FALSE` | `eState` waits at `E_OtaState.Ready` with the update checked. `bApply` reboots into it |
| `bAbort` | stops an update at any point before the reboot |

Each command acts on its rising edge. While an update downloads, each 4 kB
written to flash can delay a fast task by one release. Accepting only while
the machine is stopped avoids it.

## After the reboot

The new firmware is on trial (`eState = E_OtaState.Testing`) until
`eConfirmMode` says it is good:

| `eConfirmMode` | Kept when |
|---|---|
| `E_OtaConfirmMode.OnLinkUp` (default) | MQTT is back |
| `E_OtaConfirmMode.Manual` | `bConfirm` rises in the program |
| `E_OtaConfirmMode.OnBoot` | straight away |

If it is not confirmed within `tConfirmTimeout` (2 minutes), or the board
restarts three times on trial, the old firmware comes back and `eResult` says
`E_OtaResult.NotConfirmed` or `E_OtaResult.RolledBack`.

## Signing

Without a key the node checks that an update arrived whole and is for this
board, not who made it. With `stSigningConfig.sPublicKey` set, only firmware
signed with your private key installs, and an unsigned one is refused:

```
python modbee_ota.py keygen ota-key.pem        (once; keep it off the boards)
python modbee_ota.py pubkey ota-key.pem        (sPublicKey, without commas and 0x)
python modbee_ota.py push ... --key ota-key.pem
```

```
VAR
  signing : ST_OtaSigningConfig := (sPublicKey := '9f3c...', bRequireSigned := TRUE);  (* 128 hex characters *)
END_VAR
ota(fbClient := mqtt, sBaseTopic := 'modbee/pump-01/ota', sVersion := '1.4.0',
    stSigningConfig := signing);
```

| `ST_OtaSigningConfig` | |
|---|---|
| `sPublicKey` | the P-256 public key, 128 hex characters; empty: no check |
| `bRequireSigned` | refuse every update until `sPublicKey` holds a valid key - for a key that arrives after the first scan |

`bSigned` says the key is in use. A key that is not 128 hex characters sets
`bError` with `eErrorId = E_OtaResult.InvalidArgument`; the updater keeps
running, and `bRequireSigned` decides whether anything installs meanwhile. The
check takes about 160 ms on a Node UIO, on the background task, never in a scan.

## Over Sparkplug

The image always travels on `sBaseTopic`'s own topics - Sparkplug has no file
transfer - over the same `FB_MqttClient` connection an `FB_SparkplugNode`
rides on. The standing method `Sparkplug`, called every scan, adds what a
SCADA host needs to run the update from its own screens:

```
sp (fbClient := mqtt, sGroupId := 'Plant1', sEdgeNodeId := 'pump-01');
ota(fbClient := mqtt, sBaseTopic := 'modbee/pump-01/ota', sVersion := '1.4.0',
    bAutoApply := FALSE);
otaSp := ota.Sparkplug(fbNode := sp);
```

The node then reports `Firmware/Version`, `Firmware/State`, `Firmware/Progress`
(whole percent, as it moves), `Firmware/Offered` and `Firmware/Status` (the JSON
status), and takes `Node Control/Firmware Accept`, `Reject`, `Apply`, `Abort`,
`Confirm` and `Rollback` - Booleans the host writes TRUE, reported FALSE again.

| `Sparkplug` | |
|---|---|
| `fbNode` (in-out) | the `FB_SparkplugNode` to report on: on the same `FB_MqttClient`, or another in the same task |
| `eCmdResult` (out) | the updater's answer to the last host command; a refused one also in the block's `sLastError` |
| `nCmdCnt` (out) | host commands taken |
| result | `Ok` while the metrics are declared and the node is born; `NotReady` while either block is still starting; `WrongTask`, `NoMemory` or `InvalidArgument` (a second `FB_OtaNode` on one node, or `fbNode` changed while running) |

A program that never calls `Sparkplug` carries none of its code.

## Where it runs

- **In the same task as its `FB_MqttClient`**, with its `Sparkplug` call and
  the `FB_SparkplugNode`. The update arrives inside the client's scan; in
  another task the block does nothing and says `E_OtaResult.WrongTask`.
- **Not in a logic task.** While a download runs, the comms task's scans
  stretch to tens of milliseconds.
- **ESP32 boards only.** On the Runtime the block reports
  `E_OtaResult.Unsupported`.

## Status

| Pin | Means |
|---|---|
| `bActive` | running and listening |
| `eState` | `Idle`, `Checking`, `Offered`, `Downloading`, `Verifying`, `Ready`, `Applying`, `Testing` |
| `nProgress`, `nReceived`, `nSize` | how far |
| `nJob`, `sOffered` | the server's number for the update, and its version |
| `eOutcome`, `eResult` | how the last update ended, and why |
| `bError`, `eErrorId`, `sLastError` | the block cannot run, or the key cannot be used; in words, also a command the updater refused |

## 0.1.x → 0.2.0

0.2.0 follows the naming of the MQTT library 0.2.0 and needs it. A project on
0.1.x stays on it (`openplc-cli library pin`) until its owner moves it. Topics,
payloads, Sparkplug metric names and Node Control commands are unchanged.

| 0.1.x | 0.2.0 |
|---|---|
| `OTA_NODE` | `FB_OtaNode` |
| `CLIENT : MQTT_CLIENT` | `fbClient : FB_MqttClient` |
| `ENABLE`, `BASE`, `BOARD`, `VERSION` | `bEnable`, `sBaseTopic`, `sBoard`, `sVersion` |
| `AUTO_ACCEPT`, `AUTO_APPLY`, `ALLOW_DOWNGRADE` | `bAutoAccept`, `bAutoApply`, `bAllowDowngrade` |
| `CONFIRM_MODE`, `CONFIRM_TIME` | `eConfirmMode`, `tConfirmTimeout` |
| `BUFFER`, `STALL_TIME`, `RESUME_EVERY` | `nBufferSize`, `tStallTimeout`, `nResumeEvery` |
| `ACCEPT`, `REJECT`, `APPLY`, `ABORT`, `CONFIRM` | `bAccept`, `bReject`, `bApply`, `bAbort`, `bConfirm` |
| `ACTIVE`, `STATE`, `PROGRESS`, `RECEIVED`, `SIZE`, `JOB`, `OFFERED` | `bActive`, `eState`, `nProgress`, `nReceived`, `nSize`, `nJob`, `sOffered` |
| `OUTCOME`, `RESULT`, `ERROR`, `LAST_ERROR` | `eOutcome`, `eResult`, `bError`, `sLastError`; new `eErrorId` |
| `REQUIRE_SIGNED` | `stSigningConfig.bRequireSigned` |
| `OTA_SIGNING` (`NODE`, `KEY`) | `stSigningConfig.sPublicKey`; its `ACTIVE` is `bSigned`, its `ERROR`/`STATUS` the block's `bError`/`eErrorId` |
| `OTA_SPARKPLUG` (`NODE`, `SPARKPLUG`) | `ota.Sparkplug(fbNode := sp)`; its `ACTIVE` is the result `Ok`, its `LAST_ERROR` the block's `sLastError` |
| `OTA_STATE` (`OTA_IDLE`, ...) | `E_OtaState` (`Idle`, ...) |
| `OTA_RESULT` (`OTA_OK`, ...) | `E_OtaResult` (`Ok`, ...), same order; new last value `WrongTask` |
| `OTA_OUTCOME` (`OTA_NONE`, ...) | `E_OtaOutcome` (`None`, `Success`, `Failed`) |
| `OTA_CONFIRM` (`OTA_CONFIRM_LINK`, `_PROGRAM`, `_BOOT`) | `E_OtaConfirmMode` (`OnLinkUp`, `Manual`, `OnBoot`) |
| a block in the wrong task: `RESULT = OTA_NOT_READY` | `eErrorId = E_OtaResult.WrongTask` (`eResult` still `NotReady`) |
