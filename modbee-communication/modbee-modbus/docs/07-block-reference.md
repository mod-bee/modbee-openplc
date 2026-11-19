# Block reference

Two blocks. `FB_ModbusNode` is one link - a serial line or a TCP connection,
as a client, a server or both - and everything per request, value, device or
mapped range is a **method** of it: `node.ReadHoldingRegisters(...)`,
`node.Watch(...)`, `node.Map(...)`. `FB_ModbusBridge` stands alone. Call each
block once every scan, in the network task; call the node's methods after it.

Every method returns an `E_ModbusResult`. A **request** (the `Read...` and
`Write...` methods, named for the Modbus function) starts on a rising edge of
`bExecute`, returns `Queued` while it runs and then holds its outcome until the
next edge. A **standing** method (`Watch`, `Point`, `Points`, `Device`, `Map`) is
called every scan while it is wanted and returns `Ok` while its record is valid.
A method's outputs are read with `=>`:
`r := node.Watch(..., eQuality => q);`. An input left out takes its default.

| Block | What it does | Methods |
| --- | --- | --- |
| [`FB_ModbusBridge`](#fb_modbusbridge) | Puts TCP clients in front of a serial segment, routed by unit id. |  |
| [`FB_ModbusNode`](#fb_modbusnode) | A Modbus link: one serial line or one TCP connection, as a client (it asks), a server (it answers) or both. | [`ReadCoils`](#fb_modbusnodereadcoils), [`ReadDiscreteInputs`](#fb_modbusnodereaddiscreteinputs), [`ReadHoldingRegisters`](#fb_modbusnodereadholdingregisters), [`ReadInputRegisters`](#fb_modbusnodereadinputregisters), [`WriteSingleCoil`](#fb_modbusnodewritesinglecoil), [`WriteSingleRegister`](#fb_modbusnodewritesingleregister), [`WriteMultipleCoils`](#fb_modbusnodewritemultiplecoils), [`WriteMultipleRegisters`](#fb_modbusnodewritemultipleregisters), [`MaskWriteRegister`](#fb_modbusnodemaskwriteregister), [`ReadWriteMultipleRegisters`](#fb_modbusnodereadwritemultipleregisters), [`ReadDeviceIdentification`](#fb_modbusnodereaddeviceidentification), [`Watch`](#fb_modbusnodewatch), [`Point`](#fb_modbusnodepoint), [`Points`](#fb_modbusnodepoints), [`Device`](#fb_modbusnodedevice), [`Map`](#fb_modbusnodemap), [`Statistics`](#fb_modbusnodestatistics) |

The option structures and enumerations are at the end: [Structures](#structures), [Enumerations](#enumerations).

---

## FB_ModbusBridge

```
Puts TCP clients in front of a serial segment, routed by unit id.

      SCADA -+
        HMI -+- TCP --> [ bridge ] --RS-485--> unit 1  unit 2  unit 17 ...
     laptop -+

Several clients on the network share one serial bus, which carries one
conversation at a time: the bridge turns the second into the first. Without
it, two SCADA packages polling one RS-485 segment talk over each other.

stSerialConfig  ST_ModbusSerialConfig, the segment behind. sDevice on the
           Runtime ('/dev/ttyUSB0'); nUart, nRxPin, nTxPin, nDriverEnablePin and tDriverEnableHold
           on a board; nBaudRate (0 = 19200) and eParity (Even, the Modbus
           default) on both. nServerUnitId is a node's and must stay 0 here: the
           bridge routes nFirstUnitId..nLastUnitId.
nLocalPort   the TCP port clients connect to. 0 for 502.
nFirstUnitId the lowest unit id out on the segment, 1..247.
nLastUnitId  the highest. Equal to nFirstUnitId routes one device.
nMaxClients  clients held at once. 0 = 8 on the Runtime, 2 on a board. A
           board that cannot hold that many says so on sLastError.
nMaxPendingOperations  transactions outstanding on the serial side at once. 0 = 8.
bForwardUnroutedUnits  forward a unit id not routed instead of answering "no such
           path". Off by default: with it on, a mistyped unit id becomes a
           timeout several hundred milliseconds long that blocks the whole
           segment. For a bus whose devices you do not know.
bConnect     TRUE (default) runs the bridge.

bLinkOpen    both ends are open.
nClientsConnected  clients connected.
nForwardedRequestCount  requests sent to the segment.
nGatewayPathUnavailableCount  requests refused with exception 0x0A: no route, or no room for
           another transaction. OUR problem - a range typed wrong, or
           nMaxPendingOperations too small.
nGatewayTargetFailedCount  requests answered with exception 0x0B: the route exists and the
           device did not answer. ITS problem - off, unplugged, another
           address. Two numbers worth two alarms: a plain timeout cannot say
           which end of the plant to walk to.
sFramingReason  how the segment finds frames, and why.
bError       it did not open, or has since failed.
eErrorId     why. E_ModbusResult.Ok when fine.
sLastError   in words: the operating system's own.

  segment : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200);

  bridge(stSerialConfig := segment, nLocalPort := 502, nFirstUnitId := 1, nLastUnitId := 32);

IT STANDS ALONE: no FB_ModbusNode, because a bridge is both ends of a wire.
Put it in the network task; it services both ends once per call. It does not
decode what it carries: a function code this library has never heard of
passes through byte for byte. On a board the TCP front is Wi-Fi, already
joined (by an FB_ModbusNode on ArduinoWiFi, or the board's own network
block).
```

**Inputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `stSerialConfig` | `ST_ModbusSerialConfig` |  | the segment behind: device or UART, baud, parity |
| `nLocalPort` | `UINT` |  | the TCP port clients connect to; 0 = 502 |
| `nFirstUnitId` | `BYTE` |  | the lowest unit id on the segment, 1..247 |
| `nLastUnitId` | `BYTE` |  | the highest |
| `nMaxClients` | `BYTE` |  | clients held at once; 0 = 8 on the Runtime, 2 on a board |
| `nMaxPendingOperations` | `BYTE` |  | transactions outstanding on the segment; 0 = 8 |
| `bForwardUnroutedUnits` | `BOOL` |  | forward a unit id not routed instead of refusing it |
| `bConnect` | `BOOL` | `TRUE` | TRUE runs the bridge |

**Outputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bLinkOpen` | `BOOL` |  | both ends are open |
| `nClientsConnected` | `INT` |  | clients connected |
| `nForwardedRequestCount` | `DINT` |  | requests sent to the segment |
| `nGatewayPathUnavailableCount` | `DINT` |  | refused: no route (exception 0x0A) |
| `nGatewayTargetFailedCount` | `DINT` |  | the device did not answer (exception 0x0B) |
| `sFramingReason` | `STRING(160)` |  | how the segment finds frames, and why |
| `bError` | `BOOL` |  | it did not open, or has since failed |
| `eErrorId` | `E_ModbusResult` |  | why; Ok when fine |
| `sLastError` | `STRING(64)` |  | why, in words |

---

## FB_ModbusNode

```
A Modbus link: one serial line or one TCP connection, as a client (it
asks), a server (it answers) or both. Call it once every scan, in the network
task. Every request, watch, point and map on that link is a method of this
block.

eTransport  where the bytes go. The target must have it; one it does not have
           is reported on bError and sLastError, never built.
             E_ModbusTransport.RuntimeSerial    the Runtime's serial device,
                                                stSerialConfig.sDevice
             E_ModbusTransport.RuntimeTcp       the Runtime's network
             E_ModbusTransport.ArduinoSerial    a board's UART,
                                                stSerialConfig.nUart
             E_ModbusTransport.ArduinoWiFi      a board's Wi-Fi, joined from
                                                stNetworkConfig
             E_ModbusTransport.ArduinoEthernet  a W5100/W5500 on SPI, from
                                                stNetworkConfig. Needs the
                                                MODBUS_ENABLE_ETHERNET build flag
eRole       E_ModbusRole.Client (default) asks: the Read and Write methods,
           Watch, Point, Points, Device. E_ModbusRole.Server answers: Map puts
           your variables at Modbus addresses. E_ModbusRole.Both is both.
sHostName   a TCP client: the device to connect to. Empty on a TCP node means
           be a server.
nTcpPort    the TCP port. 0 for 502.
bConnect    TRUE (default) opens the link and keeps it open. FALSE closes it -
           the port is released, the socket dropped - and keeps every
           record, watch and map for when it opens again.

stSerialConfig  ST_ModbusSerialConfig, a serial line. Ignored on TCP.
             sDevice      the Runtime's device, '/dev/ttyUSB0'
             nBaudRate    0 = 19200, the Modbus default
             eParity      Even (default, 8E1, the specification's), Odd,
                          None (8N2, per the specification), None8N1
             nServerUnitId  a serial SERVER: the unit id it answers to,
                          1..247. A TCP server answers any unit id
             nUart        a board: which hardware serial, 0 for the first.
                          One the board does not have is refused
             nRxPin       a board: receive pin, -1 for the board's own
             nTxPin       a board: transmit pin, -1 for the board's own
             nDriverEnablePin  a board: the RS-485 driver-enable pin, -1 for
                          none. On an ESP32 the UART drives it
             tDriverEnableHold  a board: how long DE is held after the last byte
                          where the UART cannot drive it. 0 = two characters
stTimingConfig  ST_ModbusTimingConfig, the link's timing and limits. Every
           member left at its default is right for most links.
             tTimeout     how long to wait for a reply. T#0s MEASURES IT PER
                          DEVICE, which is almost always better than one
                          figure for a slow drive and a fast I/O block alike
             nRetriesPerRequest  attempts after the first. 0 = the library's own
             tReconnectInterval  how often a dropped link is tried again.
                          T#0s = 2 s
             bAutoReconnect  TRUE (default) brings a dropped link back by
                          itself, and every watch is made due when it does.
                          FALSE leaves it down until bConnect is cycled
             eFraming     Auto (default): RTU on a serial line, MBAP on a
                          socket. Rtu on TCP for a serial-to-Ethernet
                          converter that sends raw RTU frames on port 502 or
                          4001; Ascii for a radio or modem that cannot hold
                          RTU's character timing. Ascii on TCP and Tcp on a
                          serial line are refused
             tWriterLossAfter  a server: no client write for this long drives the
                          addresses Map gave eActionOnWriterLoss. T#0s = never
             tCloseIdleClientAfter  a TCP server: close a connection unused this long,
                          which a client that vanished without closing
                          leaves. T#0s = 60 s
             nMaxClients  a TCP server: connections held at once. 0 = 8 on
                          the Runtime, 2 on a board. A board that cannot hold
                          that many says so instead of holding fewer
             nMaxPendingOperations  requests that may wait at once. 0 = 64 on the
                          Runtime, 16 on a board. Past it: QueueFull
             nMaxPendingWriteBytes  bytes the waiting writes share. 0 = 16192 on
                          the Runtime, 1024 on a board
stIdentityConfig  ST_ModbusIdentityConfig, a server's nameplate: what it
           answers function code 43 with (sVendorName, sProductCode, sMajorMinorRevision).
           Empty: no answer, as most devices.
stNetworkConfig  ST_ModbusNetworkConfig, what only a board has. Refused on
           the Runtime, which uses its machine's network.
             sSsid        ArduinoWiFi: the network to join
             sWiFiPassword  its password, up to 63 characters (WPA2)
             sMacAddress  ArduinoEthernet: this board's MAC,
                          'DE:AD:BE:EF:FE:ED'. Each board needs its own
             sIpAddress   this node's fixed address; empty = DHCP, bounded to
                          1 s an attempt. A server is best given a fixed one,
                          so its clients can find it
             sGatewayAddress  empty = the address ending .1
             sSubnetMask  empty = 255.255.255.0

bLinkOpen   the link is open.
bConnected  there is something at the other end: a TCP client's socket is
           up, a server is listening, a serial line is open.
nClientsConnected  a TCP server: clients connected.
bError      something failed: the link, or a method call (named on
           sLastError until that call succeeds).
eErrorId    why. E_ModbusResult.Ok when fine.
sLastError  in words: the operating system's ("No such file or directory",
           "Address already in use", "Permission denied" - a user not in the
           dialout group), the node's ("a server needs a Map call"), or the
           failing method call ("ReadHoldingRegisters aSpeeds: Timeout").

METHODS

Each call is found again by what it is about: its variable's declared name
and type, and the method. A call with no variable (WriteSingleCoil,
WriteSingleRegister, MaskWriteRegister, Device) is found by its unit and
address. So one variable is one record per method; the same local in two
instances of one function block is two. A node holds up to 256 records, one per variable per method; past that a method returns E_ModbusResult.QueueFull. Every method
runs in this block's task and returns E_ModbusResult.WrongTask in any other.

A REQUEST (the Read and Write methods) starts on a rising edge of bExecute and
takes its inputs at that edge; changing them while it runs has no effect. It
returns E_ModbusResult.Queued while it runs, then its outcome - Ok, Timeout,
Refused (the device raised an exception), ... - held until the next edge. The
link not open at the edge: E_ModbusResult.LinkDown at once, never queued for
later. A read lands in anyData when the answer arrives. A write's values are
copied at the edge.

nQuantity is how many values to move; 0 (default) takes the variable's own
count, so ARRAY[0..9] OF WORD reads ten without the 10 typed anywhere. More
than the variable holds, or more than one request carries (2000 bits, 125
registers), is InvalidArgument before anything reaches the wire. Unit 0
broadcasts a write: every device performs it and none answers, so Ok means
sent.

  node.ReadCoils(anyData, nUnitId, nStartAddress, nQuantity, bExecute)
  node.ReadDiscreteInputs(anyData, nUnitId, nStartAddress, nQuantity, bExecute)
     function codes 1 and 2, into a BOOL or an array of BOOL.
  node.ReadHoldingRegisters(anyData, nUnitId, nStartAddress, nQuantity, eWordOrder,
                            bExecute)
  node.ReadInputRegisters(anyData, nUnitId, nStartAddress, nQuantity, eWordOrder,
                          bExecute)
     function codes 3 and 4. WORD, INT and UINT take a register each; REAL,
     DINT, UDINT, DWORD take two and LREAL, LINT, ULINT, LWORD four, laid
     out by eWordOrder (ABCD, CDAB, BADC, DCBA). A flow rate reading 4.6e-41
     instead of 1234.5 is the wrong eWordOrder, not the wrong address.
  node.WriteSingleCoil(bValue, nUnitId, nAddress, bExecute)          FC 5
  node.WriteSingleRegister(nValue, nUnitId, nAddress, bExecute)      FC 6
  node.WriteMultipleCoils(anyData, nUnitId, nStartAddress, nQuantity,
                          bExecute)                                  FC 15
  node.WriteMultipleRegisters(anyData, nUnitId, nStartAddress, nQuantity, eWordOrder,
                              bExecute)                              FC 16
     the wide types as the reads; a set of values that only mean anything
     together goes as one request and cannot half-arrive.
  node.MaskWriteRegister(nAndMask, nOrMask, nUnitId, nAddress,
                         bExecute)                                   FC 22
     the only atomic read-modify-write Modbus has: the device keeps
     (current AND nAndMask) OR (nOrMask AND NOT nAndMask). Bit 3 alone:
     nAndMask := 16#FFF7, nOrMask := 16#0008.
  node.ReadWriteMultipleRegisters(anyReadData, anyWriteData, nUnitId,
                                  nReadStartAddress, nReadQuantity, nWriteStartAddress,
                                  nWriteQuantity, bExecute)          FC 23
     one transaction, the write first: a command and its result together.
     WORD, INT or UINT only.
  node.ReadDeviceIdentification(nUnitId, bExecute, sVendorName =>, sProductCode =>,
                                sMajorMinorRevision =>)                        FC 43
     the device's nameplate, what a handheld tool shows. A device without
     one answers with an exception: Refused, not worth an alarm.

A STANDING METHOD (Watch, Point, Points, Device, Map) is called every scan
while it is wanted, and its inputs may change while it runs. E_ModbusResult.Ok
means the record is valid; E_ModbusResult.LinkDown while the link is not
open, the record kept.

  node.Watch(anyData, nUnitId, eTable, nStartAddress, tReadInterval, nQuantity, eWordOrder,
             nDeadband, bEnable, eQuality =>, bValueEverReceived =>, tValueAge =>,
             nConsecutiveFailureCount =>, bValueChanged =>)
     keeps anyData up to date every tReadInterval (T#0s = 1 s) and says how much
     to believe it. Returns the last read's result. eQuality: Good within
     tReadInterval, Uncertain a little late, Bad stale or failed, Unknown never
     read - a commissioning fault (wrong address, device not fitted), where
     Bad is a running one (cable, power). Interlock on eQuality, not the
     value. A read still out when the next falls due is not stacked, and a
     dead device is backed off to one attempt in sixteen. nUnitId, eTable,
     nStartAddress and eWordOrder may change while running: the watch is re-aimed and
     starts again at Unknown. bValueChanged is TRUE for one call when
     anyData has moved by more than nDeadband since the last change it
     reported (a bit: any change); the first value counts as one.
  node.Point(anyValue, nUnitId, eFunctionCode, nStartAddress, eDataType, eWordOrder, nBitNumber,
             fScale, fOffset, tUpdateInterval, tLostAfter, tTimeout, bEnable,
             bGood =>, eQuality =>, tValueAge =>, nConsecutiveFailureCount =>)
     one value on a field device defined entirely by settings, every input
     read every scan. A read point writes raw x fScale + fOffset into
     anyValue (REAL, LREAL, an integer or a BOOL) once it has answered, and
     holds the last good value while it is lost - never a made-up 0. A write
     point sends anyValue when it changes and again every tUpdateInterval. bGood is
     FALSE before the first answer and after tLostAfter (T#0s = 3 x tUpdateInterval)
     without one: interlock on it. Returns the last attempt's result;
     InvalidArgument for settings that cannot work (Float32 with
     WriteSingleRegister, nBitNumber above 15, a RegisterBit write).
  node.Points(anyPointSettings, anyPointStatus, bEnable, nGoodPoints =>, nLostPoints =>,
              nFirstLostPoint =>, sStatusText =>)
     a table of points: anyPointSettings an ARRAY OF ST_ModbusPointConfig
     (retain it - it is the site's configuration), anyPointStatus an ARRAY OF
     ST_ModbusPointStatus of the same length (not retained; fWriteValue is
     your logic's, the rest is status). Each row behaves as a Point and is
     re-read every scan. Returns Ok while every enabled row is ok, else the
     first lost row's result; sStatusText names it for a panel ('pt 3 unit 5
     lost', 'pt 2 unit 9 no answer', 'pt 4 bad settings').
  node.Device(nUnitId, tDiagnosticPollInterval, tNotAnsweringAfter, bAnswering =>, bEverAnswered =>, tSinceLastHeard =>,
              tRoundTrip =>)
     how one device is doing, read off the traffic already going to it:
     bAnswering within tNotAnsweringAfter (T#0s = 5 s), bEverAnswered ever, tSinceLastHeard since,
     tRoundTrip measured. bEverAnswered FALSE is a device never fitted or wrongly
     addressed (found at the desk); bEverAnswered with bAnswering FALSE is one that
     has died (found in the plant). tDiagnosticPollInterval asks it (function code 8, which
     touches no register) for a device nothing else talks to; an exception
     still counts as answering. Returns Ok while valid.
  node.Map(anyData, eTable, nStartAddress, eActionOnWriterLoss, nSafeValue, bWrittenByClient =>,
           bSafeValueApplied =>)
     puts anyData at Modbus addresses for clients to read and write, in
     place: the variable IS the register, nothing is copied. A BOOL or array
     of BOOL in Coil or DiscreteInput, a WORD, INT or UINT (or an array) in
     HoldingRegister or InputRegister; a REAL or DINT is refused, because a
     client could read half an old value and half a new one - publish a
     scaled integer. An array's lower bound maps to nStartAddress. Put what a
     client must not change in a read-only table. eActionOnWriterLoss ResetToValue
     drives a single writable address to nSafeValue after
     stTimingConfig.tWriterLossAfter without a client write. bWrittenByClient: a client
     wrote this range since the last call. A server needs at least one Map.

  node.Statistics(bResetCounters, nPendingOperations =>, nFrameSentCount =>, nFrameReceivedCount =>,
                  nChecksumErrorCount =>, nFramingErrorCount =>, nNoiseByteCount =>,
                  nReconnectCount =>, sFramingReason =>)
     the link's counters; a rising edge of bResetCounters zeroes them. Checksum
     errors climbing: noise, a baud mismatch or no termination. Noise bytes:
     a floating bus, fit the bias resistors. Framing errors: another
     protocol on the bus, or frames split - sFramingReason says which rule
     finds frames on this link, and why.

  serial : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200);

  node(eTransport := E_ModbusTransport.RuntimeSerial, stSerialConfig := serial);
  eLastResult := node.ReadHoldingRegisters(anyData := aSpeeds, nUnitId := 2,
                                       nStartAddress := 40, bExecute := bRead);
  node.Watch(anyData := nLevel, nUnitId := 2,
             eTable := E_ModbusTable.InputRegister, nStartAddress := 30,
             tReadInterval := T#2s, eQuality => eLevelQuality);

ONE TASK. This block and its methods run in one task, the network task, at a
higher rate than the machine's: T#1ms on the Runtime, T#50ms on a board to
start with. The node is what touches the wire - it transmits, receives,
retries and times out once per call - so its period is the floor on how fast
anything happens. The machine's program trades values with it through
globals. A method called from another task returns E_ModbusResult.WrongTask
and does nothing.
```

**Inputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `eTransport` | `E_ModbusTransport` |  | RuntimeSerial, RuntimeTcp, ArduinoSerial, ArduinoWiFi, ArduinoEthernet |
| `eRole` | `E_ModbusRole` |  | Client (default), Server or Both |
| `sHostName` | `STRING(48)` |  | a TCP client: the device; empty = a TCP server |
| `nTcpPort` | `UINT` |  | the TCP port; 0 = 502 |
| `bConnect` | `BOOL` | `TRUE` | TRUE opens the link and keeps it open |
| `stSerialConfig` | `ST_ModbusSerialConfig` |  | device, baud, parity, the node's own unit id, a board's UART pins |
| `stTimingConfig` | `ST_ModbusTimingConfig` |  | timeout, retries, reconnect, framing, failsafe, limits |
| `stIdentityConfig` | `ST_ModbusIdentityConfig` |  | a server's nameplate, function code 43 |
| `stNetworkConfig` | `ST_ModbusNetworkConfig` |  | a board's Wi-Fi or Ethernet |

**Outputs**

| Pin | Type | Default | Notes |
| --- | --- | --- | --- |
| `bLinkOpen` | `BOOL` |  | the link is open |
| `bConnected` | `BOOL` |  | link ready: client socket up, server listening, or serial line open |
| `nClientsConnected` | `INT` |  | a TCP server: clients connected |
| `bError` | `BOOL` |  | the link or a method call failed |
| `eErrorId` | `E_ModbusResult` |  | why; Ok when fine |
| `sLastError` | `STRING(64)` |  | why, in words |

### FB_ModbusNode.ReadCoils

```
result := node.ReadCoils(anyData := ..., nUnitId := ...,
                         nStartAddress := ..., nQuantity := ...,
                         bExecute := ...);
```

Returns `E_ModbusResult`.
Reads coils (function code 1) into anyData on a rising edge of bExecute. Queued until the answer, then Ok or why not, until the next edge.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a BOOL or an array of BOOL |
| `nUnitId` | `BYTE` |  | the device, 1..247 |
| `nStartAddress` | `UINT` |  | the first coil |
| `nQuantity` | `UINT` |  | how many; 0 = the variable's count |
| `bExecute` | `BOOL` |  | rising edge reads |

### FB_ModbusNode.ReadDiscreteInputs

```
result := node.ReadDiscreteInputs(anyData := ..., nUnitId := ...,
                                  nStartAddress := ..., nQuantity := ...,
                                  bExecute := ...);
```

Returns `E_ModbusResult`.
Reads discrete inputs (function code 2) into anyData on a rising edge of bExecute.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a BOOL or an array of BOOL |
| `nUnitId` | `BYTE` |  | the device, 1..247 |
| `nStartAddress` | `UINT` |  | the first input |
| `nQuantity` | `UINT` |  | how many; 0 = the variable's count |
| `bExecute` | `BOOL` |  | rising edge reads |

### FB_ModbusNode.ReadHoldingRegisters

```
result := node.ReadHoldingRegisters(anyData := ..., nUnitId := ...,
                                    nStartAddress := ..., nQuantity := ...,
                                    eWordOrder := ..., bExecute := ...);
```

Returns `E_ModbusResult`.
Reads holding registers (function code 3) into anyData on a rising edge of bExecute. 32- and 64-bit types take two or four registers in eWordOrder.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a WORD, INT, UINT, REAL, DINT, LREAL... or an array of one |
| `nUnitId` | `BYTE` |  | the device, 1..247 |
| `nStartAddress` | `UINT` |  | the first register |
| `nQuantity` | `UINT` |  | how many values; 0 = the variable's count |
| `eWordOrder` | `E_ModbusOrder` |  | a wide value's word order: ABCD (default), CDAB, BADC, DCBA |
| `bExecute` | `BOOL` |  | rising edge reads |

### FB_ModbusNode.ReadInputRegisters

```
result := node.ReadInputRegisters(anyData := ..., nUnitId := ...,
                                  nStartAddress := ..., nQuantity := ...,
                                  eWordOrder := ..., bExecute := ...);
```

Returns `E_ModbusResult`.
Reads input registers (function code 4) into anyData on a rising edge of bExecute. 32- and 64-bit types take two or four registers in eWordOrder.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a WORD, INT, UINT, REAL, DINT, LREAL... or an array of one |
| `nUnitId` | `BYTE` |  | the device, 1..247 |
| `nStartAddress` | `UINT` |  | the first register |
| `nQuantity` | `UINT` |  | how many values; 0 = the variable's count |
| `eWordOrder` | `E_ModbusOrder` |  | a wide value's word order: ABCD (default), CDAB, BADC, DCBA |
| `bExecute` | `BOOL` |  | rising edge reads |

### FB_ModbusNode.WriteSingleCoil

```
result := node.WriteSingleCoil(bValue := ..., nUnitId := ...,
                               nAddress := ..., bExecute := ...);
```

Returns `E_ModbusResult`.
Writes one coil (function code 5) on a rising edge of bExecute.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bValue` | `BOOL` |  | the value, taken at the edge |
| `nUnitId` | `BYTE` |  | the device, 1..247; 0 broadcasts |
| `nAddress` | `UINT` |  | the coil |
| `bExecute` | `BOOL` |  | rising edge writes |

### FB_ModbusNode.WriteSingleRegister

```
result := node.WriteSingleRegister(nValue := ..., nUnitId := ...,
                                   nAddress := ..., bExecute := ...);
```

Returns `E_ModbusResult`.
Writes one holding register (function code 6) on a rising edge of bExecute.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nValue` | `WORD` |  | the value, taken at the edge |
| `nUnitId` | `BYTE` |  | the device, 1..247; 0 broadcasts |
| `nAddress` | `UINT` |  | the register |
| `bExecute` | `BOOL` |  | rising edge writes |

### FB_ModbusNode.WriteMultipleCoils

```
result := node.WriteMultipleCoils(anyData := ..., nUnitId := ...,
                                  nStartAddress := ..., nQuantity := ...,
                                  bExecute := ...);
```

Returns `E_ModbusResult`.
Writes coils (function code 15) from anyData on a rising edge of bExecute.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a BOOL or an array of BOOL, copied at the edge |
| `nUnitId` | `BYTE` |  | the device, 1..247; 0 broadcasts |
| `nStartAddress` | `UINT` |  | the first coil |
| `nQuantity` | `UINT` |  | how many; 0 = the variable's count |
| `bExecute` | `BOOL` |  | rising edge writes |

### FB_ModbusNode.WriteMultipleRegisters

```
result := node.WriteMultipleRegisters(anyData := ..., nUnitId := ...,
                                      nStartAddress := ..., nQuantity := ...,
                                      eWordOrder := ..., bExecute := ...);
```

Returns `E_ModbusResult`.
Writes holding registers (function code 16) from anyData on a rising edge of bExecute. 32- and 64-bit types take two or four registers in eWordOrder.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a WORD, INT, UINT, REAL, DINT, LREAL... or an array, copied at the edge |
| `nUnitId` | `BYTE` |  | the device, 1..247; 0 broadcasts |
| `nStartAddress` | `UINT` |  | the first register |
| `nQuantity` | `UINT` |  | how many values; 0 = the variable's count |
| `eWordOrder` | `E_ModbusOrder` |  | a wide value's word order: ABCD (default), CDAB, BADC, DCBA |
| `bExecute` | `BOOL` |  | rising edge writes |

### FB_ModbusNode.MaskWriteRegister

```
result := node.MaskWriteRegister(nAndMask := ..., nOrMask := ...,
                                 nUnitId := ..., nAddress := ...,
                                 bExecute := ...);
```

Returns `E_ModbusResult`.
Changes some bits of one holding register atomically (function code 22) on a rising edge of bExecute: (current AND nAndMask) OR (nOrMask AND NOT nAndMask).

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nAndMask` | `WORD` |  | the bits to keep |
| `nOrMask` | `WORD` |  | the bits to set |
| `nUnitId` | `BYTE` |  | the device, 1..247 |
| `nAddress` | `UINT` |  | the register |
| `bExecute` | `BOOL` |  | rising edge writes |

### FB_ModbusNode.ReadWriteMultipleRegisters

```
result := node.ReadWriteMultipleRegisters(anyReadData := ...,
                                          anyWriteData := ...,
                                          nUnitId := ...,
                                          nReadStartAddress := ...,
                                          nReadQuantity := ...,
                                          nWriteStartAddress := ...,
                                          nWriteQuantity := ...,
                                          bExecute := ...);
```

Returns `E_ModbusResult`.
Writes anyWriteData and then reads into anyReadData in one transaction (function code 23), on a rising edge of bExecute.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyReadData` | `ANY` |  | a WORD, INT or UINT, or an array: what is read |
| `anyWriteData` | `ANY` |  | a WORD, INT or UINT, or an array: what is written, copied at the edge |
| `nUnitId` | `BYTE` |  | the device, 1..247 |
| `nReadStartAddress` | `UINT` |  | the first register read |
| `nReadQuantity` | `UINT` |  | how many read; 0 = anyReadData's count |
| `nWriteStartAddress` | `UINT` |  | the first register written |
| `nWriteQuantity` | `UINT` |  | how many written; 0 = anyWriteData's count |
| `bExecute` | `BOOL` |  | rising edge starts it |

### FB_ModbusNode.ReadDeviceIdentification

```
result := node.ReadDeviceIdentification(nUnitId := ..., bExecute := ...,
                                        sVendorName => ...,
                                        sProductCode => ...,
                                        sMajorMinorRevision => ...);
```

Returns `E_ModbusResult`.
Reads a device's nameplate (function code 43, basic objects) on a rising edge of bExecute. Queued, then Ok with the three strings, or why not.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nUnitId` | `BYTE` |  | the device, 1..247 |
| `bExecute` | `BOOL` |  | rising edge reads |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `sVendorName` | `STRING(32)` |  | who made it |
| `sProductCode` | `STRING(32)` |  | what it is |
| `sMajorMinorRevision` | `STRING(32)` |  | which version |

### FB_ModbusNode.Watch

```
result := node.Watch(anyData := ..., nUnitId := ..., eTable := ...,
                     nStartAddress := ..., tReadInterval := ...,
                     nQuantity := ..., eWordOrder := ..., nDeadband := ...,
                     bEnable := ..., eQuality => ...,
                     bValueEverReceived => ..., tValueAge => ...,
                     nConsecutiveFailureCount => ..., bValueChanged => ...);
```

Returns `E_ModbusResult`.
Keeps anyData up to date from a device every tReadInterval, called every scan. Returns the last read's result; eQuality says how much to believe it.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | the variable kept up to date: BOOL for bits, WORD, REAL... for registers |
| `nUnitId` | `BYTE` |  | the device, 1..247 |
| `eTable` | `E_ModbusTable` |  | what is read: Coil, DiscreteInput, HoldingRegister (default), InputRegister |
| `nStartAddress` | `UINT` |  | the first address |
| `tReadInterval` | `TIME` |  | how often; T#0s = 1 s |
| `nQuantity` | `UINT` |  | how many values; 0 = the variable's count. Fixed at the first call |
| `eWordOrder` | `E_ModbusOrder` |  | a wide value's word order |
| `nDeadband` | `UINT` |  | how far the value must move before bValueChanged reports it; 0 = any change |
| `bEnable` | `BOOL` | `TRUE` | FALSE stops it, keeping the record |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `eQuality` | `E_ModbusQuality` |  | Unknown never read, Good, Uncertain late, Bad stale or failed |
| `bValueEverReceived` | `BOOL` |  | a value has arrived at least once |
| `tValueAge` | `TIME` |  | since it last arrived; T#0s before the first |
| `nConsecutiveFailureCount` | `UINT` |  | reads that failed in a row |
| `bValueChanged` | `BOOL` |  | TRUE for one call when the value has moved by more than nDeadband since the last change reported |

### FB_ModbusNode.Point

```
result := node.Point(anyValue := ..., nUnitId := ..., eFunctionCode := ...,
                     nStartAddress := ..., eDataType := ...,
                     eWordOrder := ..., nBitNumber := ..., fScale := ...,
                     fOffset := ..., tUpdateInterval := ...,
                     tLostAfter := ..., tTimeout := ..., bEnable := ...,
                     bGood => ..., eQuality => ..., tValueAge => ...,
                     nConsecutiveFailureCount => ...);
```

Returns `E_ModbusResult`.
One value on a field device defined entirely by settings, called every scan. A read point writes the value in engineering units into anyValue; a write point sends anyValue. Returns the last attempt's result.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyValue` | `ANY` |  | REAL, LREAL, an integer or a BOOL: the point |
| `nUnitId` | `BYTE` |  | the device, 1..247 |
| `eFunctionCode` | `E_ModbusPointFunction` |  | how it is reached: ReadCoils .. ReadInputRegisters, WriteSingleCoil, WriteSingleRegister, WriteMultipleRegisters |
| `nStartAddress` | `UINT` |  | the register or coil, numbered from 0 as the manual's table |
| `eDataType` | `E_ModbusPointType` |  | Bit, Int16, UInt16 (default), Int32, UInt32, Float32, RegisterBit |
| `eWordOrder` | `E_ModbusOrder` |  | the word order of a 32-bit value |
| `nBitNumber` | `USINT` |  | RegisterBit: which bit, 0..15 |
| `fScale` | `REAL` | `1.0` | value = raw x fScale + fOffset |
| `fOffset` | `REAL` |  | added after scaling, in engineering units |
| `tUpdateInterval` | `TIME` |  | how often to read it or send it again; T#0s = 1 s |
| `tLostAfter` | `TIME` |  | no good answer for this long = lost; T#0s = 3 x tUpdateInterval |
| `tTimeout` | `TIME` |  | how long this device may take; leave T#0s = measured |
| `bEnable` | `BOOL` | `TRUE` | FALSE = not fitted: never asked, never ok |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bGood` | `BOOL` |  | the value is good or a little late: interlock on this |
| `eQuality` | `E_ModbusQuality` |  | Unknown never answered, Good, Uncertain late, Bad lost |
| `tValueAge` | `TIME` |  | since the last good answer |
| `nConsecutiveFailureCount` | `UINT` |  | failed attempts in a row |

### FB_ModbusNode.Points

```
result := node.Points(anyPointSettings := ..., anyPointStatus := ...,
                      bEnable := ..., nGoodPoints => ..., nLostPoints => ...,
                      nFirstLostPoint => ..., sStatusText => ...);
```

Returns `E_ModbusResult`.
A table of points from settings, one row each, called every scan. Returns Ok while every enabled row is ok, else the first lost row's result.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyPointSettings` | `ANY` |  | ARRAY OF ST_ModbusPointConfig; retain it |
| `anyPointStatus` | `ANY` |  | ARRAY OF ST_ModbusPointStatus, the same length; not retained |
| `bEnable` | `BOOL` | `TRUE` | FALSE stops asking |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nGoodPoints` | `INT` |  | enabled rows that are ok |
| `nLostPoints` | `INT` |  | enabled rows that are not |
| `nFirstLostPoint` | `INT` |  | the first such row, counted from 1; 0 when none |
| `sStatusText` | `STRING(30)` |  | that row in a few words, for a panel |

### FB_ModbusNode.Device

```
result := node.Device(nUnitId := ..., tDiagnosticPollInterval := ...,
                      tNotAnsweringAfter := ..., bAnswering => ...,
                      bEverAnswered => ..., tSinceLastHeard => ...,
                      tRoundTrip => ...);
```

Returns `E_ModbusResult`.
How one device is doing, from the traffic already going to it, called every scan. Ok while valid; LinkDown while the link is not open.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nUnitId` | `BYTE` |  | the device, 1..247 |
| `tDiagnosticPollInterval` | `TIME` |  | ask it this often (function code 8); T#0s = only watch the traffic |
| `tNotAnsweringAfter` | `TIME` |  | silent this long = not answering; T#0s = 5 s |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bAnswering` | `BOOL` |  | it has answered within tNotAnsweringAfter |
| `bEverAnswered` | `BOOL` |  | it has answered at least once |
| `tSinceLastHeard` | `TIME` |  | since it last answered; T#0s before it ever has |
| `tRoundTrip` | `TIME` |  | how long it takes to reply, measured |

### FB_ModbusNode.Map

```
result := node.Map(anyData := ..., eTable := ..., nStartAddress := ...,
                   eActionOnWriterLoss := ..., nSafeValue := ...,
                   bWrittenByClient => ..., bSafeValueApplied => ...);
```

Returns `E_ModbusResult`.
Puts anyData at Modbus addresses for clients to read and write, in place, called every scan. Ok while bound; LinkDown while the link is not open.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `anyData` | `ANY` |  | a BOOL, WORD, INT or UINT, or a fixed-bounds array of one |
| `eTable` | `E_ModbusTable` |  | Coil, DiscreteInput, HoldingRegister (default), InputRegister |
| `nStartAddress` | `UINT` |  | the first address; an array's lower bound lands here |
| `eActionOnWriterLoss` | `E_ModbusFailsafe` |  | a writable single address after tWriterLossAfter without a write: HoldLastValue (default) or ResetToValue |
| `nSafeValue` | `DINT` |  | the value ResetToValue drives it to |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bWrittenByClient` | `BOOL` |  | a client wrote this range since the last call |
| `bSafeValueApplied` | `BOOL` |  | the safe value was applied since the last call |

### FB_ModbusNode.Statistics

```
result := node.Statistics(bResetCounters := ..., nPendingOperations => ...,
                          nFrameSentCount => ..., nFrameReceivedCount => ...,
                          nChecksumErrorCount => ...,
                          nFramingErrorCount => ..., nNoiseByteCount => ...,
                          nReconnectCount => ..., sFramingReason => ...);
```

Returns `E_ModbusResult`.
The link's counters. A rising edge of bResetCounters zeroes them.

**Inputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `bResetCounters` | `BOOL` |  | rising edge zeroes the counters |

**Outputs**

| Parameter | Type | Default | Notes |
| --- | --- | --- | --- |
| `nPendingOperations` | `INT` |  | requests queued and not yet concluded |
| `nFrameSentCount` | `DINT` |  | frames transmitted |
| `nFrameReceivedCount` | `DINT` |  | frames received |
| `nChecksumErrorCount` | `DINT` |  | frames that arrived corrupt |
| `nFramingErrorCount` | `DINT` |  | frames that were structurally impossible |
| `nNoiseByteCount` | `DINT` |  | bytes discarded hunting for a frame |
| `nReconnectCount` | `DINT` |  | times the link dropped and came back |
| `sFramingReason` | `STRING(160)` |  | how this link finds frames, and why |

---

## Structures

Option structures are inputs of a block, set in the declaration or from an
HMI and read every scan. A member left at its default is the right answer
for most links; `0` and `T#0s` mean the library's default.

### ST_ModbusIdentityConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `sVendorName` | `STRING(32)` |  | who made it; empty = no answer to function code 43 |
| `sProductCode` | `STRING(32)` |  | what it is |
| `sMajorMinorRevision` | `STRING(32)` |  | which version |

### ST_ModbusNetworkConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `sSsid` | `STRING(48)` |  | E_ModbusTransport.ArduinoWiFi: the network to join |
| `sWiFiPassword` | `STRING(63)` |  | its password, up to the 63 characters WPA2 allows |
| `sMacAddress` | `STRING(32)` |  | E_ModbusTransport.ArduinoEthernet: the board's MAC, 'DE:AD:BE:EF:FE:ED' |
| `sIpAddress` | `STRING(32)` |  | this node's fixed address; empty = DHCP |
| `sGatewayAddress` | `STRING(32)` |  | empty = the address ending .1 |
| `sSubnetMask` | `STRING(32)` |  | empty = 255.255.255.0 |

### ST_ModbusPointConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `nUnitId` | `BYTE` |  | the device's address, 1..247 |
| `eFunctionCode` | `E_ModbusPointFunction` |  | how: ReadCoils..ReadInputRegisters read; WriteSingleCoil, WriteSingleRegister, WriteMultipleRegisters write |
| `nStartAddress` | `UINT` |  | the register or coil, as the device manual numbers it from 0 |
| `eDataType` | `E_ModbusPointType` |  | what it holds: Bit, Int16, UInt16, Int32, UInt32, Float32, RegisterBit |
| `eWordOrder` | `E_ModbusOrder` |  | word order of a 32-bit value, from the manual |
| `nBitNumber` | `USINT` |  | RegisterBit only: which bit of the register, 0..15 |
| `fScale` | `REAL` | `1.0` | engineering value = raw x fScale + fOffset (0 is taken as 1) |
| `fOffset` | `REAL` |  | added after scaling, in engineering units |
| `tUpdateInterval` | `TIME` | `T#1s` | how often to read it, or to send it again |
| `tLostAfter` | `TIME` |  | no answer for this long = lost (Bad); T#0s = 3 x tUpdateInterval |
| `tTimeout` | `TIME` |  | this device's answer time limit (seconds over radio); leave T#0s = measured |
| `bEnable` | `BOOL` | `TRUE` | FALSE = not fitted: never asked, never ok |

### ST_ModbusPointStatus

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `fWriteValue` | `REAL` |  | your logic: the value to write (write points), in engineering units |
| `fValue` | `REAL` |  | the value in engineering units; the last good one is held while not ok |
| `bValue` | `BOOL` |  | fValue <> 0, for a bit |
| `bGood` | `BOOL` |  | fValue is good or a little late; FALSE before the first answer and once lost |
| `eQuality` | `E_ModbusQuality` |  | Unknown never answered, Good, Uncertain late, Bad lost |
| `tValueAge` | `TIME` |  | since the last good answer |
| `nConsecutiveFailureCount` | `UINT` |  | failed attempts in a row |
| `eLastResult` | `E_ModbusResult` |  | the last attempt's result |

### ST_ModbusSerialConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `sDevice` | `STRING(48)` |  | the Runtime's serial device, '/dev/ttyUSB0' |
| `nBaudRate` | `DINT` |  | 0 = 19200, the Modbus default |
| `eParity` | `E_ModbusParity` |  | Even (default, 8E1), Odd, None (8N2: two stop bits, per the specification), None8N1 |
| `nServerUnitId` | `BYTE` |  | a serial server: the unit id this node answers to, 1..247 |
| `nUart` | `BYTE` |  | a board: which hardware serial, 0 for the first |
| `nRxPin` | `INT` | `-1` | a board: receive pin, -1 = the board's own (ESP32 only) |
| `nTxPin` | `INT` | `-1` | a board: transmit pin, -1 = the board's own (ESP32 only) |
| `nDriverEnablePin` | `INT` | `-1` | a board: the RS-485 driver-enable pin, -1 = none |
| `tDriverEnableHold` | `LTIME` |  | a board: driver hold after the last byte where the UART cannot drive DE; 0 = two characters |

### ST_ModbusTimingConfig

| Member | Type | Default | Notes |
| --- | --- | --- | --- |
| `tTimeout` | `TIME` |  | how long to wait for a reply; leave T#0s = measured per device |
| `nRetriesPerRequest` | `BYTE` |  | attempts after the first; 0 = the library's own |
| `tReconnectInterval` | `TIME` |  | how often to retry a dropped link; T#0s = 2 s |
| `bAutoReconnect` | `BOOL` | `TRUE` | retry a dropped link by itself; FALSE = down until bConnect is cycled |
| `eFraming` | `E_ModbusFraming` |  | Auto (default): RTU on a serial line, MBAP on a socket; Rtu over TCP for a converter; Ascii |
| `tWriterLossAfter` | `TIME` |  | a server: no client write for this long drives Map's eActionOnWriterLoss; T#0s = never |
| `tCloseIdleClientAfter` | `TIME` |  | a TCP server: close a connection unused this long; T#0s = 60 s |
| `nMaxClients` | `BYTE` |  | a TCP server: connections held at once; 0 = 8 on the Runtime, 2 on a board |
| `nMaxPendingOperations` | `UINT` |  | requests that may wait at once; 0 = 64 on the Runtime, 16 on a board |
| `nMaxPendingWriteBytes` | `UINT` |  | bytes the waiting writes share; 0 = 16192 on the Runtime, 1024 on a board |

## Enumerations

Each is `{attribute 'qualified_only'}`, so a value is always written with its type: `E_ModbusTable.HoldingRegister`, `E_ModbusResult.Ok`. A bare `Ok` does not compile.

| Enumeration | Values, in order | Default |
| --- | --- | --- |
| `E_ModbusFailsafe` | `HoldLastValue`, `ResetToValue` | `HoldLastValue` |
| `E_ModbusFraming` | `Auto`, `Rtu`, `Ascii`, `Tcp` | `Auto` |
| `E_ModbusOrder` | `ABCD`, `CDAB`, `BADC`, `DCBA` | `ABCD` |
| `E_ModbusParity` | `Even`, `Odd`, `None`, `None8N1` | `Even` |
| `E_ModbusPointFunction` | `ReadCoils`, `ReadDiscreteInputs`, `ReadHoldingRegisters`, `ReadInputRegisters`, `WriteSingleCoil`, `WriteSingleRegister`, `WriteMultipleRegisters` | `ReadHoldingRegisters` |
| `E_ModbusPointType` | `Bit`, `Int16`, `UInt16`, `Int32`, `UInt32`, `Float32`, `RegisterBit` | `UInt16` |
| `E_ModbusQuality` | `Unknown`, `Good`, `Uncertain`, `Bad` | `Unknown` |
| `E_ModbusResult` | `Queued`, `Ok`, `NotInitialised`, `InvalidArgument`, `NotMapped`, `Duplicate`, `QueueFull`, `UnknownUnit`, `Superseded`, `Cancelled`, `Timeout`, `Refused`, `Acknowledged`, `Busy`, `GatewayPathUnavailable`, `GatewayTargetFailed`, `LinkDown`, `ChecksumError`, `ProtocolError`, `WrongTask` | `Ok` |
| `E_ModbusRole` | `Client`, `Server`, `Both` | `Client` |
| `E_ModbusTable` | `Coil`, `DiscreteInput`, `HoldingRegister`, `InputRegister` | `HoldingRegister` |
| `E_ModbusTransport` | `RuntimeSerial`, `RuntimeTcp`, `ArduinoSerial`, `ArduinoWiFi`, `ArduinoEthernet` | `RuntimeSerial` |

[06 Diagnostics](06-diagnostics.md) explains every `E_ModbusResult` value.

---

**Next:** [08 Patterns](08-patterns.md)
