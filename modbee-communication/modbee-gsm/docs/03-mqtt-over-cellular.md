# MQTT over cellular

`MQTT_CLIENT` from `modbee-mqtt` sends over the modem with one setting:

```
mqtt(TRANSPORT := MQTT_CELLULAR, HOST := 'broker.example.com', PORT := 1883,
     CLIENT_ID := 'pump-station-4');
```

Everything else about MQTT - publishing, subscribing, the will, the
configuration blocks - is exactly as it is over WiFi. The modem is the one
`GSM_MODEM` runs; the MQTT block finds it by itself, so there is no pin to
wire between them.

## What it needs

| | |
| --- | --- |
| the modbee-gsm library in the project | `MQTT_CELLULAR` switches on when it is there. Without it the client says `MQTT_CELLULAR needs the modbee-gsm library and a GSM_MODEM` |
| a `GSM_MODEM` in the program | the client connects once `GSM_MODEM.READY` is TRUE; until then it says why on `LAST_ERROR` and keeps trying |
| a board | `MQTT_CELLULAR` runs on a board. On the Runtime the client says `that transport needs a board, not the Runtime` |

## Security

| `SECURITY` | over cellular |
| --- | --- |
| `MQTT_PLAIN` | no encryption. Port 1883 |
| `MQTT_TLS_INSECURE` | encrypted by the modem itself, port 8883. The modem does **not** check the broker's certificate |
| `MQTT_TLS_VERIFY` | refused: the modem cannot check a certificate, and the client will not pretend it did |
| `MQTT_TLS_PINNED` | refused, for the same reason |

`MQTT_TLS_INSECURE` keeps the traffic private on the way but does not prove
who answered. Use a broker login (`MQTT_CONFIG`) as well, and keep anything
that can operate the plant behind more than the connection itself.

## Opening the connection holds the client's task

Everything the MQTT block does is non-blocking except opening the connection,
which waits for the modem to say yes or no: about 1.5 s for a plain connection
and 5 s for TLS, and never longer than `CONNECT_TIMEOUT` on `MQTT_CONFIG`
(20 s when it is not set). It happens when the client connects and each time
it reconnects - not every scan.

So **put `MQTT_CLIENT` in a task of its own**, at a lower priority than the
task that runs the machine. On an ESP32 each task runs by itself, so while the
client waits only its own task waits. `GSM_MODEM` and the other GSM blocks in
other tasks carry on; they simply skip the modem for the scans the client is
using it.

Data use is small: an MQTT connection costs a few hundred bytes to open and
about a hundred bytes a minute to keep alive at the default sixty-second
keepalive. Every message costs its topic, its payload and a few bytes more.

## A complete program

The modem in a fast task, the client in a slower one of its own:

```
PROGRAM modem_prg              (* task: 10 ms, priority 1 *)
  VAR
    board  : UIO;
    hat    : HAT_POWER;
    modem  : GSM_MODEM;
    status : GSM_STATUS;
  END_VAR
  VAR RETAIN
    apn    : STRING(100) := 'internet';
  END_VAR
  VAR_EXTERNAL
    gRssi  : REAL;
  END_VAR

  board();
  hat(ENABLE := TRUE);
  modem(CONNECT := TRUE, APN := apn);
  status(MODEM := modem, REFRESH := T#30s);
  gRssi := INT_TO_REAL(status.RSSI);
END_PROGRAM

PROGRAM net_prg                (* task: 50 ms, priority 5 *)
  VAR
    mqtt  : MQTT_CLIENT;
    pub   : MQTT_PUBLISH;
    every : TON;
  END_VAR
  VAR_EXTERNAL
    gRssi : REAL;
  END_VAR

  mqtt(TRANSPORT := MQTT_CELLULAR, HOST := 'broker.example.com', PORT := 1883,
       CLIENT_ID := 'pump-station-4');
  every(IN := NOT every.Q, PT := T#60s);
  pub(CLIENT := mqtt, REQ := every.Q AND mqtt.CONNECTED,
      TOPIC := 'site/pump-station-4/rssi', VALUE := gRssi, QOS := 1);
END_PROGRAM
```

## Sockets

The modem has two connections at a time, shared between `MQTT_CLIENT` and
`GSM_SOCKET`, and at most two of them encrypted. One client and one socket fit;
a second client does not.

---

**Next:** [04 Troubleshooting](04-troubleshooting.md)
