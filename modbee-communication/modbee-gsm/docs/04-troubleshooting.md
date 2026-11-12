# Troubleshooting

By what you are seeing. The modem block's `sLastError` usually names the
reason in words; start there. A failing method call is named there too, by
its method and record: `SendSms sAlarm: NotReady`.

## eConnectionState stays at Syncing

The PLC cannot hear the module.

- **The HAT is not powered.** On the Node UIO, `HAT_POWER` with `ENABLE :=
  TRUE` must be in the program, and `UIO` must run.
- **The module is off.** The library presses the power key itself when the
  module does not answer, but only if it knows which GPIO that is
  (`stPowerConfig.nPowerKeyPin`, 10 on the Node). A board without one needs the
  module switched on some other way.
- **The wiring is crossed or on other pins.** `stSerialConfig.nRxPin` is where
  the PLC receives - the module's transmit line.
- **The speed is wrong.** `stSerialConfig.nBaudRate`; both supported module
  families start at 115200.

## eConnectionState reaches Failed with NotSupportedByModule

The module answered, and it is not the family the block was built for: an
`FB_GsmModemA7670` holds only the A76XX driver, an `FB_GsmModemSim7070` only
the SIM707x one. Use the block for the module on the board.

## eConnectionState stays at SimWait, or sLastError mentions the SIM

- `the SIM wants a PIN; set sSimPin` - give it on the modem block.
- `the SIM refused sSimPin` - the PIN is wrong. **It is not tried again**
  until `sSimPin` changes, because a third wrong PIN locks the card. Correct
  it and the next attempt uses the new one.
- `the SIM is PUK-locked` - it needs its PUK, entered in a phone, on site.
- `SIM not inserted` - seat the card with the power off.

## eConnectionState stays at Registering

The module is searching for, or being refused by, a network.

- **Signal.** `Status`'s `nRssi` below about -105 dBm is too weak to hold a
  connection. Check the antenna and its cable first; move it up and away from
  metal.
- **The SIM is not allowed on any network here.** A roaming IoT SIM needs a
  contract with a local network. `eRegistration` shows
  `E_GsmRegistration.Denied`.
- **The wrong technology or bands** in `stRadioConfig`. Leave it at its
  defaults and let the module search everything.
- **A low-power module searching slowly.** An LTE-M or NB-IoT module can take
  minutes on its first search; `stRadioConfig.sCatMBands` narrows it.

## bRegistered is TRUE but bConnected never comes

The network has the SIM and will not give it a data connection: almost always
the **APN**. Check `stApnConfig`'s `sApn`, `sUserName` and `sPassword` against
the provider's details. Text messages already work at this point, which is a
useful test.

## bConnected comes and goes

`Status`'s `nBearerLossCnt` and `nRecoveryCnt` climbing by the hour mean a
marginal connection: usually the antenna, sometimes a supply that sags when the
module transmits. The modem recovers each time by itself; the counters are how
you find out it is happening.

## A method returns WrongTask

Methods run in the task the block's own call runs in. Call the block and its
methods from one program, in one task.

## A method returns QueueFull

A modem block keeps up to 64 records: one per variable per method. A literal
or an expression has no name and is found by its text instead (`SendSms` by
its number), so an `AtCommand` given a `CONCAT(...)` that changes makes a new
record for every new text. Give it a STRING variable.

## bError says "another modem block runs the modem; a PLC has one"

A PLC has one modem and one modem block. Remove the second; its methods return
`NotInitialised`.

## MQTT does not connect

- `E_MqttTransport.Cellular needs a modbee-gsm modem block` - add the library
  to the project, and a modem block to the program.
- `no modem block has opened the modem` - the library is there but no modem
  block runs, or its `bConnect` is FALSE.
- `the modem has no data connection (...)` - wait for the block's
  `bConnected`; the bracket says where the modem is up to.
- The client connects and drops at once: check the broker's port, and that it
  accepts the client's login.
- A socket or MQTT client never gets a socket while others are open: each one
  holds a socket, and `stCapacityConfig.nSocketCnt` is 2 by default. Raise it.

## MQTT over cellular stalls or is slow

The client stays connected but nothing arrives, or a download crawls. On an
ESP32 the modem's UART is driven from an interrupt in IRAM that fills a small
internal-RAM ring (1 kB, twice a flash sector erase at 115200 baud), so no
bytes are lost while the board erases or writes flash (the HAT has no RTS/CTS,
and the Arduino core's own UART interrupt stops during flash work). A small
task services the modem between scans and moves the bytes on into the
`stSerialConfig.nRxBufferSize` ring in PSRAM, so an AT exchange does not wait
for the next scan. Should a data notice or part of a reply still be lost, the
library asks the module for unannounced data within two seconds, and a reply
cut short ends the socket so the client reconnects at once. A stall longer
than that is something else - check `Status`'s `nBearerLossCnt` and
`nRecoveryCnt`.

## Wi-Fi will not join after switching from cellular

On an ESP32, the modem block gives its serial link, buffers and service task
(about 7 kB of internal RAM, which Wi-Fi needs to join) back once `bConnect`
is FALSE and the modem is quiet, and takes them again when `bConnect` returns
to TRUE.

## A text message does not arrive

- `Inbox` (or `SmsCommand`) must be called with `bEnable` TRUE, and the
  block's `bRegistered` TRUE. Messages that arrive while neither is enabled
  stay on the SIM.
- A message sent before the PLC started arrives when the network delivers it,
  usually within a minute of `bRegistered`.

## A text-message command is not acted on

`SmsCommand`'s `nRefusedCnt` and `sLastRefused` say why: `not an allowed
number` (check `sAllowed`; a portal's name is matched whole), `wrong PIN`,
`needs the admin PIN`, `too many this hour` (`nMaxPerHour`). A message that
names none of the commands is ignored, and not counted.

## SendSms returns ModuleError

`sLastError` carries the network's reason. The usual ones: the number is not in
international form (`+64...`), the SIM has no SMS on its plan, or the text has
characters outside the plain GSM set.

## Gnss returns NotSupportedByModule

The module has no satellite receiver; some variants of each family do not.
Nothing will change that but a module that has one.

## NetworkTime is never bValid

The network the SIM is on does not send the time. It is read again on every
`tRefresh`, so it becomes valid by itself on a network that does.

## sLastError says "out of memory for the sockets"

The board has no room for `nSocketCnt` x 2 x `nSocketBufferSize` bytes (or,
for "... for the AT command queue", for `nAtQueueLen`). Lower them in
`stCapacityConfig` and restart the PLC: they are taken once, when the modem is
opened.

## E_GsmResult, every value

| Value | Meaning |
| --- | --- |
| `Queued` | a request is under way |
| `Ok` | done, or the outputs are valid |
| `NotInitialised` | the block is not the one running the modem, or there was no memory for the call |
| `InvalidArgument` | a setting or parameter that cannot be used; `sLastError` names it |
| `NotReady` | the modem cannot do it yet: not registered (SMS), not connected (Socket), the module not answered yet (AtCommand, Status) |
| `NoBearer` | registered, but no data connection |
| `NoSocketAvailable` | every socket is in use; raise `nSocketCnt` |
| `QueueFull` | too many commands waiting, or more than 64 records |
| `Superseded`, `Cancelled` | a command replaced or abandoned, usually by a stop |
| `TooLarge` | a text over its limit: 160 characters for SMS, 127 for an AT command |
| `NotSupportedByModule` | the module cannot: no receiver, no TLS, or the other family |
| `Error` | the module said ERROR and gave no reason |
| `ModuleError` | the module or network gave a reason; it is on `sLastError` |
| `Timeout` | no answer in time |
| `SocketClosed`, `BearerLost` | the connection, or the whole data connection, went |
| `Unresponsive` | the module stopped answering; it is being recovered |
| `PoweredOff` | switched off by `Power` |
| `RegistrationDenied` | the network refused the SIM |
| `WrongTask` | a method called from another task than the block's |

---

**Back to:** [the index](README.md)
