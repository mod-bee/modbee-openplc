# OTA

Updates a ModBee node's firmware over MQTT from inside the PLC program. The
node pulls the new firmware a piece at a time, checks it, switches to it and
reboots. If the new firmware does not come back on MQTT, the board goes back
to the old one by itself.

| Block | Does |
|---|---|
| `OTA_NODE` | The updater. One per board, wired to an `MQTT_CLIENT` |
| `OTA_SIGNING` | Optional: only firmware signed with your key installs |
| `OTA_SPARKPLUG` | Optional: the update as Sparkplug metrics, run from SCADA |

## Getting started

1. Enable the **MQTT** and **OTA** libraries in the project.
2. In the comms task (T#50ms or slower), next to the `MQTT_CLIENT`:

   ```
   ota(CLIENT := mqtt, BASE := 'modbee/pump-01/ota', VERSION := '1.4.0');
   ```

   `VERSION` is this program's version. Raise it for every release: an update
   for the same version is refused, and an older one unless `ALLOW_DOWNGRADE`.
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
| `AUTO_ACCEPT := FALSE` | `STATE` waits at `OTA_OFFERED`. `ACCEPT` starts the download, `REJECT` refuses it |
| `AUTO_APPLY := FALSE` | `STATE` waits at `OTA_READY` with the update checked. `APPLY` reboots into it |
| `ABORT` | stops an update at any point before the reboot |

While an update downloads, each 4 kB written to flash can delay a fast task
by one release. Accepting only while the machine is stopped avoids it.

## After the reboot

The new firmware is on trial (`STATE = OTA_TESTING`) until `CONFIRM_MODE`
says it is good:

| `CONFIRM_MODE` | Kept when |
|---|---|
| `OTA_CONFIRM_LINK` (default) | MQTT is back |
| `OTA_CONFIRM_PROGRAM` | `CONFIRM` is set by the program |
| `OTA_CONFIRM_BOOT` | straight away |

If it is not confirmed within `CONFIRM_TIME` (2 minutes), or the board
restarts three times on trial, the old firmware comes back and `RESULT` says
`OTA_NOT_CONFIRMED` or `OTA_ROLLED_BACK`.

## Signing

Without `OTA_SIGNING` the node checks that an update arrived whole and is for
this board, not who made it. With it, and `REQUIRE_SIGNED := TRUE` on the
node, only firmware signed with your private key installs:

```
python modbee_ota.py keygen ota-key.pem        (once; keep it off the boards)
python modbee_ota.py pubkey ota-key.pem        (the KEY, without commas and 0x)
python modbee_ota.py push ... --key ota-key.pem
```

## Over Sparkplug

The image always travels on `BASE`'s own topics - Sparkplug has no file
transfer - over the same `MQTT_CLIENT` connection a `SPARKPLUG_NODE` rides on.
`OTA_SPARKPLUG` adds what a SCADA host needs to run the update from its own
screens:

```
sp   (CLIENT := mqtt, GROUP := 'Plant1', NODE := 'pump-01');
ota  (CLIENT := mqtt, BASE := 'modbee/pump-01/ota', VERSION := '1.4.0',
      AUTO_APPLY := FALSE);
otasp(NODE := ota, SPARKPLUG := sp);
```

The node then reports `Firmware/Version`, `Firmware/State`, `Firmware/Progress`
(whole percent, as it moves), `Firmware/Offered` and `Firmware/Status` (the JSON
status), and takes `Node Control/Firmware Accept`, `Reject`, `Apply`, `Abort`,
`Confirm` and `Rollback` - Booleans the host writes TRUE, reported FALSE again.

## Where it runs

- **In the same task as its `MQTT_CLIENT`**, with `OTA_SIGNING` and
  `OTA_SPARKPLUG`. The update arrives inside the client's scan; in another task
  the block does nothing and says so on `ERROR`.
- **Not in a logic task.** While a download runs, the comms task's scans
  stretch to tens of milliseconds.
- **ESP32 boards only.** On the Runtime the block reports `OTA_UNSUPPORTED`.

## Status

| Pin | Means |
|---|---|
| `STATE` | `OTA_IDLE`, `OTA_CHECKING`, `OTA_OFFERED`, `OTA_DOWNLOADING`, `OTA_VERIFYING`, `OTA_READY`, `OTA_APPLYING`, `OTA_TESTING` |
| `PROGRESS`, `RECEIVED`, `SIZE` | how far |
| `OUTCOME`, `RESULT` | how the last update ended, and why |
| `ERROR`, `LAST_ERROR` | the block cannot run, in words |
