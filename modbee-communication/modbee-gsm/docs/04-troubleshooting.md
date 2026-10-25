# Troubleshooting

By what you are seeing. `GSM_MODEM.LAST_ERROR` usually names the reason in
words; start there.

## STATE stays at GSM_SYNCING

The PLC cannot hear the module.

- **The HAT is not powered.** On the Node UIO, `HAT_POWER` with `ENABLE :=
  TRUE` must be in the program, and `UIO` must run.
- **The module is off.** The library presses the power key itself when the
  module does not answer, but only if it knows which GPIO that is
  (`POWER_KEY_PIN`, 10 on the Node). A board without one needs the module
  switched on some other way.
- **The wiring is crossed or on other pins.** `RX_PIN` is where the PLC
  receives - the module's transmit line. Check `GSM_ARDUINO`.
- **The speed is wrong.** `BAUD` on `GSM_MODEM`; both supported module
  families start at 115200.

## STATE stays at GSM_SIM_WAIT, or LAST_ERROR mentions the SIM

- `the SIM wants a PIN; set SIM_PIN` - give it on `GSM_MODEM`.
- `the SIM refused SIM_PIN` - the PIN is wrong. **It is not tried again**
  until `SIM_PIN` changes, because a third wrong PIN locks the card. Correct
  it and the next attempt uses the new one.
- `the SIM is PUK-locked` - it needs its PUK, entered in a phone, on site.
- `SIM not inserted` - seat the card with the power off.

## STATE stays at GSM_REGISTERING

The module is searching for, or being refused by, a network.

- **Signal.** `GSM_STATUS.RSSI` below about -105 dBm is too weak to hold a
  connection. Check the antenna and its cable first; move it up and away from
  metal.
- **The SIM is not allowed on any network here.** A roaming IoT SIM needs a
  contract with a local network. `REGISTRATION` shows `GSM_REG_DENIED`.
- **The wrong technology or bands** on `GSM_RADIO`, if it is in the program.
  Remove it and let the module search everything.
- **A low-power module searching slowly.** An LTE-M or NB-IoT module can take
  minutes on its first search; `CAT_M_BANDS` on `GSM_RADIO` narrows it.

## REGISTERED is TRUE but READY never comes

The network has the SIM and will not give it a data connection: almost always
the **APN**. Check it, and `APN_USER` / `APN_PASSWORD`, against the provider's
details. Text messages already work at this point, which is a useful test.

## READY comes and goes

`GSM_STATUS.BEARER_LOSSES` and `RECOVERIES` climbing by the hour mean a
marginal connection: usually the antenna, sometimes a supply that sags when the
module transmits. The modem recovers each time by itself; the counters are how
you find out it is happening.

## MQTT does not connect

- `MQTT_CELLULAR needs the modbee-gsm library and a GSM_MODEM` - add the
  library to the project, and a `GSM_MODEM` to the program.
- `no GSM_MODEM has opened the modem` - the library is there but no
  `GSM_MODEM` runs, or its `CONNECT` is FALSE.
- `the modem has no data connection (...)` - wait for `GSM_MODEM.READY`; the
  bracket says where the modem is up to.
- `the modem's TLS checks no certificate; use MQTT_TLS_INSECURE` - see
  [page 03](03-mqtt-over-cellular.md#security).
- The client connects and drops at once: check the broker's port, and that it
  accepts the client's login.
- A socket or MQTT client never gets a socket while others are open: each one
  holds a socket, and `GSM_MODEM`'s `SOCKETS` is 2 by default. Raise it.

## MQTT over cellular stalls or is slow

`CONNECTED` stays TRUE but nothing arrives, or a download crawls. On an ESP32
the modem's UART is driven from an interrupt in IRAM that fills a small
internal-RAM ring (1 kB, twice a flash sector erase at 115200 baud), so no
bytes are lost while the board erases or writes flash (the HAT has no RTS/CTS,
and the Arduino core's own UART interrupt stops during flash work). A small
task services the modem between scans and moves the bytes on into the
`RX_BUFFER` ring in PSRAM, so an AT exchange does not wait for the next COMMS
scan. Should a data notice or part of a reply
still be lost, the library asks the module for unannounced data within two
seconds, and a reply cut short ends the socket so `MQTT_CLIENT` reconnects at
once. A stall longer than that is something else - check `BEARER_LOSSES` and
`RECOVERIES` on `GSM_STATUS`.

## Wi-Fi will not join after switching from cellular

On an ESP32, `GSM_MODEM` gives its serial link, buffers and service task
(about 7 kB of internal RAM, which Wi-Fi needs to join) back once `CONNECT` is
FALSE and the modem is quiet, and takes them again when `CONNECT` returns to
TRUE. A library older than this held them for good once the modem had been
used: a board switched from cellular to Wi-Fi could be left too short of
internal RAM to join (`auth expired` drops, RSSI 0).

## A text message does not arrive

- `GSM_SMS_RECEIVE` must be in the program with `ENABLE` TRUE, and
  `GSM_MODEM.REGISTERED` TRUE. Messages that arrive while `ENABLE` is FALSE
  stay on the SIM.
- A message sent before the PLC started arrives when the network delivers it,
  usually within a minute of `REGISTERED`.

## GSM_SMS_SEND says GSM_MODULE_ERROR

`LAST_ERROR` carries the network's reason. The usual ones: the number is not in
international form (`+64...`), the SIM has no SMS on its plan, or the text has
characters outside the plain GSM set.

## GSM_GNSS says SUPPORTED FALSE

The module has no satellite receiver; some variants of each family do not.
Nothing will change that but a module that has one.

## GSM_TIME is never VALID

The network the SIM is on does not send the time. It is read again on every
`REFRESH`, so it becomes valid by itself on a network that does.

## GSM_MODEM says "out of memory for the sockets"

The board has no room for `SOCKETS` x 2 x `SOCKET_BUFFER` bytes (or, for
"... for the AT command queue", for `AT_QUEUE`). Lower them and restart the PLC:
they are taken once, when the modem is opened.

## GSM_MODEM says another GSM_MODEM runs the modem

A PLC has one modem and one `GSM_MODEM`. Remove the second, and wire the first
to every block's `MODEM` pin.

---

**Back to:** [the index](README.md)
