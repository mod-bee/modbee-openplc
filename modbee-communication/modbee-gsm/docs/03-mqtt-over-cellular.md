# MQTT over cellular

`FB_MqttClient` from `modbee-mqtt` sends over the modem with one setting:

```
mqtt(eTransport := E_MqttTransport.Cellular, sHost := 'broker.example.com',
     nPort := 1883, sClientId := 'pump-station-4');
```

Everything else about MQTT - publishing, subscribing, the Will, Sparkplug - is
exactly as it is over Wi-Fi. The modem is the one the modem block runs; the
client finds it by itself, so there is nothing to wire between them and no
method of the modem block to call.

## What it needs

| | |
| --- | --- |
| the modbee-gsm library in the project | `E_MqttTransport.Cellular` switches on when it is there. Without it the client says `E_MqttTransport.Cellular needs a modbee-gsm modem block` |
| a modem block in the program | `FB_GsmModemA7670` or `FB_GsmModemSim7070`. The client connects once the block's `bConnected` is TRUE; until then it says why on `sLastError` (`no modem block has opened the modem`, `the modem has no data connection (Registering)`) and keeps trying |
| a board | `Cellular` runs on a board. On the Runtime the client says `that transport needs a board, not the Runtime` |

The client may be called before the modem block in a scan, or in another
task: it binds to the modem at its first connection, whenever that is.

## Security

On an ESP32 - the Node and every other ESP32 board - the modem opens a plain
connection and the TLS runs on the controller, so **every `eSecurity` works over
cellular** exactly as over Wi-Fi: `TlsVerify` checks the broker's chain and
name, `TlsPinned` trusts one key. modbee-mqtt's page 03 has the detail.

A board without mbedTLS falls back to the modem's own TLS, which encrypts and
checks no certificate: only `E_MqttSecurity.TlsInsecure` is accepted there,
and `TlsVerify` and `TlsPinned` are refused rather than quietly downgraded.

## Opening the connection

Opening a connection waits for the modem to say yes or no: about 1.5 s for a
plain socket. On an ESP32 it runs on a short task of the client's own, below
the PLC's tasks, so no scan waits for it; it never takes longer than
`stSessionConfig.tConnectTimeout` (20 s when it is not set). It happens when
the client connects and each time it reconnects - not every scan. While it
runs it holds the modem, and the modem block and its methods skip the modem
for those scans; nothing is lost.

Set `stSessionConfig.tMaxSilence` on cellular - three keep-alives - so a link
that the network has silently dropped is found and reconnected.

Data use is small: an MQTT connection costs a few hundred bytes to open and
about a hundred bytes a minute to keep alive at a sixty-second keep-alive.
Every message costs its topic, its payload and a few bytes more.

## A complete program

The modem and the client in the network task:

```
PROGRAM net_prg                (* task: 20 ms *)
  VAR
    board  : UIO;
    hat    : HAT_POWER;
    modem  : FB_GsmModemA7670;
    mqtt   : FB_MqttClient;
    every  : TON;
    rssi   : INT;
    result : E_GsmResult;
    sent   : E_MqttResult;
  END_VAR
  VAR RETAIN
    apn    : ST_GsmApnConfig;
  END_VAR

  board();
  hat(ENABLE := TRUE);
  modem(bConnect := TRUE, stApnConfig := apn);
  result := modem.Status(tRefresh := T#30s, nRssi => rssi);

  mqtt(eTransport := E_MqttTransport.Cellular, sHost := 'broker.example.com',
       nPort := 1883, sClientId := 'pump-station-4');
  every(IN := NOT every.Q, PT := T#60s);
  sent := mqtt.Publish(anyValue := rssi, sTopic := 'site/pump-station-4/rssi',
                       eQos := E_MqttQos.AtLeastOnceDelivery, bExecute := every.Q);
END_PROGRAM
```

## Sockets

Every MQTT client over the modem holds one of its sockets, as each `Socket`
record does. `stCapacityConfig.nSocketCnt` is 2 by default: one client and
one socket fit; a second client needs it raised.

---

**Next:** [04 Troubleshooting](04-troubleshooting.md)
