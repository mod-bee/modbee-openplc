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

The modem in a fast task of its own, beside the board. The GSM HAT carries an
A7670, so the block is `FB_GsmModemA7670`; a SIM7070 module takes
`FB_GsmModemSim7070`, which is the same in every pin and method.

```
PROGRAM modem_prg
  VAR
    board  : UIO;
    hat    : HAT_POWER;
    modem  : FB_GsmModemA7670;
    result : E_GsmResult;
    rssi   : INT;
    quality: E_GsmQuality;
  END_VAR
  VAR RETAIN
    apnName : STRING(100) := 'internet';
  END_VAR
  VAR
    apn    : ST_GsmApnConfig;
  END_VAR

  board();
  hat(ENABLE := TRUE);
  apn.sApn := apnName;
  modem(bConnect := TRUE, stApnConfig := apn);
  result := modem.Status(tRefresh := T#30s, nRssi => rssi, eQuality => quality);
END_PROGRAM
```

Run it in a task of **20 ms or faster**. The modem is read a little at a time
on every scan, so a slow task is a slow modem. Call the block before its
methods, every scan, and call the methods in the same task: a method called
from another task returns `E_GsmResult.WrongTask`.

`sApn` is the access point name your SIM's provider gives: `internet` is
common, an IoT SIM often has its own. A SIM with a PIN also needs `sSimPin`.
Because these are inputs, a `RETAIN` variable can carry them, and changing one
takes effect without a download.

## 4. What to watch

| Output | What it means |
| --- | --- |
| `modem.eConnectionState` | where the bring-up has got to: `Syncing` (talking to the module), `SimWait`, `Registering` (waiting for the network), `BearerUp` (opening data), `Ready` |
| `modem.bRegistered` | the network has accepted the SIM. Text messages work from here |
| `modem.bConnected` | the data connection is up. Sockets and MQTT work from here |
| `modem.sLastError` | why it is not up, in words; or which method call failed |
| `Status`'s `nRssi` | signal strength in dBm. Better than -95 is good, below -105 is poor |
| `Status`'s `eQuality` | the same, judged |

A first start takes from about twenty seconds to a few minutes, depending on
the network. After that the modem looks after itself: if the network or the
data connection goes, it is brought back without the program doing anything.

## 5. A text message

```
IF highLevel AND NOT highLevelWas THEN
  result := modem.SendSms(sTo := '+64 21 000 001, +64 21 000 002',
                          sText := modem.Format(sTemplate := 'Tank 3 high: {level:1} m',
                                                anyData := tank));
END_IF;
highLevelWas := highLevel;
```

`SendSms` queues one message to each number and returns at once: `Ok`, or
`InvalidArgument`, `QueueFull` or `RateLimited` with nothing queued. Call it
once per message, on the scan the program decides to send. The block sends
them one at a time once the network has the SIM, tries a failed one again,
and counts them on `nSmsSent`, `nSmsFailed`, `nSmsDropped` and `nSmsQueued`.
`stSmsConfig` sets the queue's depth, the most an hour (10 by default, every
number counted) and the retries. Every message costs money on most plans.

`Format` fills `{member}` placeholders from a STRUCT - `{level:1}` with one
decimal, `{run:hm}` as `2h00m`, `{mode|OFF|MANUAL|AUTO}` as a word - into at
most 160 characters.

To follow one message to the network instead, `SendSmsRequest(anyText,
sNumber, bExecute)` returns `Queued` until the network has it, then `Ok`.

Every request method (`SendSmsRequest`, `AtCommand`, `Power`, `Socket`) works
the same way: read its result only after its own `bExecute` edge. Before the
first edge nothing has run, and the result still reads its default, `Ok`. After
the edge it is `Queued` while busy, then `Ok` or the reason it failed.

## 6. Changing the wiring

On another board, or a HAT wired differently, set `stSerialConfig` and
`stPowerConfig`:

```
serial.nUart := 0; serial.nRxPin := 44; serial.nTxPin := 43;
power.nPowerKeyPin := 10; power.nRailPin := -1;
modem(bConnect := TRUE, stApnConfig := apn, stSerialConfig := serial,
      stPowerConfig := power);
```

The link is opened once, so a change applies at the next PLC start, and the
block says so on `bError`.

## 7. On the Runtime

A USB modem on the OpenPLC Runtime needs only `stSerialConfig.sDevice`, its
serial port, usually `/dev/ttyUSB2` or `/dev/ttyACM0`:

```
serial.sDevice := '/dev/ttyUSB2';
modem(bConnect := TRUE, stApnConfig := apn, stSerialConfig := serial);
```

A USB modem is powered by the USB port, so there is no power key, and the
board's pins are not used.

---

**Next:** [02 Block reference](02-block-reference.md)
