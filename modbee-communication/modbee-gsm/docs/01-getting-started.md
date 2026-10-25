# Getting started

A ModBee Node UIO with the GSM HAT, a SIM with data, and a program that brings
the modem up and shows its signal.

## 1. The hardware

- **The HAT** sits on the Node UIO's HAT header. It talks to the Node on the
  header's UART pins (the Node receives on GPIO 44 and transmits on GPIO 43),
  and the Node presses the module's power key on GPIO 10.
- **The HAT's supply** is switched by the Node on GPIO 9, which belongs to
  node-uio's `HAT_POWER` block. Put one in the program with `ENABLE := TRUE`.
- **The antenna** goes on the module's main (LTE) connector before power is
  applied. A module transmitting with no antenna can be damaged, and one with
  a poor antenna is the commonest reason a site will not stay connected.
- **The SIM** goes in with the Node powered off.

The Node's two RS485 channels use the other two UARTs, so the modem always
uses UART0 - which is the default.

## 2. The libraries

Add **node-uio** and **modbee-gsm** to the project in the Library Manager, and
**modbee-mqtt** if the PLC will publish to a broker.

## 3. The program

The modem in a fast task of its own, beside the board:

```
PROGRAM modem_prg
  VAR
    board  : UIO;
    hat    : HAT_POWER;
    modem  : GSM_MODEM;
    status : GSM_STATUS;
  END_VAR
  VAR RETAIN
    apn    : STRING(100) := 'internet';
  END_VAR

  board();
  hat(ENABLE := TRUE);
  modem(CONNECT := TRUE, APN := apn);
  status(MODEM := modem, REFRESH := T#30s);
END_PROGRAM
```

Run it in a task of **20 ms or faster**. The modem is read a little at a time
on every scan, so a slow task is a slow modem.

`APN` is the access point name your SIM's provider gives: `internet` is common,
an IoT SIM often has its own. A SIM with a PIN also needs `SIM_PIN`. Because
these are inputs, a `RETAIN` variable can carry them, and changing one takes
effect without a download.

## 4. What to watch

| Pin | What it means |
| --- | --- |
| `modem.STATE` | where the bring-up has got to: `GSM_SYNCING` (talking to the module), `GSM_SIM_WAIT`, `GSM_REGISTERING` (waiting for the network), `GSM_BEARER_UP` (opening data), `GSM_READY` |
| `modem.REGISTERED` | the network has accepted the SIM. Text messages work from here |
| `modem.READY` | the data connection is up. Sockets and MQTT work from here |
| `modem.LAST_ERROR` | why it is not up, in words |
| `status.RSSI` | signal strength in dBm. Better than -95 is good, below -105 is poor |
| `status.QUALITY` | the same, judged |

A first start takes from about twenty seconds to a few minutes, depending on
the network. After that the modem looks after itself: if the network or the
data connection goes, it is brought back without the program doing anything.

## 5. Changing the wiring

On another board, or a HAT wired differently, add `GSM_ARDUINO` beside the
modem:

```
board(MODEM := modem, PORT := 0, RX_PIN := 44, TX_PIN := 43, POWER_KEY_PIN := 10);
```

The link is opened once, so a change applies at the next PLC start.

## 6. On the Runtime

A USB modem on the OpenPLC Runtime needs only `GSM_MODEM`, with `DEVICE` set
to its serial port, usually `/dev/ttyUSB2` or `/dev/ttyACM0`:

```
modem(CONNECT := TRUE, APN := apn, DEVICE := '/dev/ttyUSB2');
```

A USB modem is powered by the USB port, so there is no power key; `GSM_ARDUINO`
says plainly that it has nothing to do there.

---

**Next:** [02 Block reference](02-block-reference.md)
