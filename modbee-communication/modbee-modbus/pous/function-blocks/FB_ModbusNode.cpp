(* A Modbus link: one serial line or one TCP connection, as a client (it
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
sHost       a TCP client: the device to connect to. Empty on a TCP node means
           be a server.
nPort       the TCP port. 0 for 502.
bConnect    TRUE (default) opens the link and keeps it open. FALSE closes it -
           the port is released, the socket dropped - and keeps every
           record, watch and map for when it opens again.

stSerialConfig  ST_ModbusSerialConfig, a serial line. Ignored on TCP.
             sDevice      the Runtime's device, '/dev/ttyUSB0'
             nBaudRate    0 = 19200, the Modbus default
             eParity      Even (default, 8E1, the specification's), Odd,
                          None (8N2, per the specification), None8N1
             nUnitId      a serial SERVER: the unit id it answers to,
                          1..247. A TCP server answers any unit id
             nUart        a board: which hardware serial, 0 for the first.
                          One the board does not have is refused
             nRxPin       a board: receive pin, -1 for the board's own
             nTxPin       a board: transmit pin, -1 for the board's own
             nDePin       a board: the RS-485 driver-enable pin, -1 for
                          none. On an ESP32 the UART drives it
             tDeHold      a board: how long DE is held after the last byte
                          where the UART cannot drive it. 0 = two characters
stTimingConfig  ST_ModbusTimingConfig, the link's timing and limits. Every
           member left at its default is right for most links.
             tTimeout     how long to wait for a reply. T#0s MEASURES IT PER
                          DEVICE, which is almost always better than one
                          figure for a slow drive and a fast I/O block alike
             nRetries     attempts after the first. 0 = the library's own
             tReconnect   how often a dropped link is tried again.
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
             tFailsafe    a server: no client write for this long drives the
                          addresses Map gave eOnLoss. T#0s = never
             tIdle        a TCP server: close a connection unused this long,
                          which a client that vanished without closing
                          leaves. T#0s = 60 s
             nMaxClients  a TCP server: connections held at once. 0 = 8 on
                          the Runtime, 2 on a board. A board that cannot hold
                          that many says so instead of holding fewer
             nMaxPending  requests that may wait at once. 0 = 64 on the
                          Runtime, 16 on a board. Past it: QueueFull
             nMaxPendingBytes  bytes the waiting writes share. 0 = 16192 on
                          the Runtime, 1024 on a board
stIdentityConfig  ST_ModbusIdentityConfig, a server's nameplate: what it
           answers function code 43 with (sVendor, sProduct, sRevision).
           Empty: no answer, as most devices.
stNetworkConfig  ST_ModbusNetworkConfig, what only a board has. Refused on
           the Runtime, which uses its machine's network.
             sSsid        ArduinoWiFi: the network to join
             sWiFiPassword  its password, up to 63 characters (WPA2)
             sMac         ArduinoEthernet: this board's MAC,
                          'DE:AD:BE:EF:FE:ED'. Each board needs its own
             sIp          this node's fixed address. REQUIRED: a server must
                          be findable, and DHCP on Ethernet blocks the scan.
                          'dhcp' asks a server anyway, bounded to 1 s an
                          attempt
             sGateway     empty = the address ending .1
             sSubnet      empty = 255.255.255.0

bLinkUp     the link is open.
bConnected  there is something at the other end: a TCP client's socket is
           up, a server is listening, a serial line is open.
nClients    a TCP server: clients connected.
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
instances of one function block is two. A node holds up to 256 records; past that a method returns E_ModbusResult.QueueFull. Every method
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

  node.ReadCoils(anyData, nUnitId, nAddress, nQuantity, bExecute)
  node.ReadDiscreteInputs(anyData, nUnitId, nAddress, nQuantity, bExecute)
     function codes 1 and 2, into a BOOL or an array of BOOL.
  node.ReadHoldingRegisters(anyData, nUnitId, nAddress, nQuantity, eOrder,
                            bExecute)
  node.ReadInputRegisters(anyData, nUnitId, nAddress, nQuantity, eOrder,
                          bExecute)
     function codes 3 and 4. WORD, INT and UINT take a register each; REAL,
     DINT, UDINT, DWORD take two and LREAL, LINT, ULINT, LWORD four, laid
     out by eOrder (ABCD, CDAB, BADC, DCBA). A flow rate reading 4.6e-41
     instead of 1234.5 is the wrong eOrder, not the wrong address.
  node.WriteSingleCoil(bValue, nUnitId, nAddress, bExecute)          FC 5
  node.WriteSingleRegister(nValue, nUnitId, nAddress, bExecute)      FC 6
  node.WriteMultipleCoils(anyData, nUnitId, nAddress, nQuantity,
                          bExecute)                                  FC 15
  node.WriteMultipleRegisters(anyData, nUnitId, nAddress, nQuantity, eOrder,
                              bExecute)                              FC 16
     the wide types as the reads; a set of values that only mean anything
     together goes as one request and cannot half-arrive.
  node.MaskWriteRegister(nAndMask, nOrMask, nUnitId, nAddress,
                         bExecute)                                   FC 22
     the only atomic read-modify-write Modbus has: the device keeps
     (current AND nAndMask) OR (nOrMask AND NOT nAndMask). Bit 3 alone:
     nAndMask := 16#FFF7, nOrMask := 16#0008.
  node.ReadWriteMultipleRegisters(anyReadData, anyWriteData, nUnitId,
                                  nReadAddress, nReadQuantity, nWriteAddress,
                                  nWriteQuantity, bExecute)          FC 23
     one transaction, the write first: a command and its result together.
     WORD, INT or UINT only.
  node.ReadDeviceIdentification(nUnitId, bExecute, sVendor =>, sProduct =>,
                                sRevision =>)                        FC 43
     the device's nameplate, what a handheld tool shows. A device without
     one answers with an exception: Refused, not worth an alarm.

A STANDING METHOD (Watch, Point, Points, Device, Map) is called every scan
while it is wanted, and its inputs may change while it runs. E_ModbusResult.Ok
means the record is valid; E_ModbusResult.LinkDown while the link is not
open, the record kept.

  node.Watch(anyData, nUnitId, eTable, nAddress, tPeriod, nQuantity, eOrder,
             nDeadband, bEnable, eQuality =>, bSeen =>, tAge =>,
             nFailures =>)
     keeps anyData up to date every tPeriod (T#0s = 1 s) and says how much
     to believe it. Returns the last read's result. eQuality: Good within
     tPeriod, Uncertain a little late, Bad stale or failed, Unknown never
     read - a commissioning fault (wrong address, device not fitted), where
     Bad is a running one (cable, power). Interlock on eQuality, not the
     value. A read still out when the next falls due is not stacked, and a
     dead device is backed off to one attempt in sixteen. nUnitId, eTable,
     nAddress and eOrder may change while running: the watch is re-aimed and
     starts again at Unknown.
  node.Point(anyValue, nUnitId, eFunction, nAddress, eType, eOrder, nBit,
             fScale, fOffset, tPeriod, tStale, tTimeout, bEnable,
             bOk =>, eQuality =>, tAge =>, nFailures =>)
     one value on a field device defined entirely by settings, every input
     read every scan. A read point writes raw x fScale + fOffset into
     anyValue (REAL, LREAL, an integer or a BOOL) once it has answered, and
     holds the last good value while it is lost - never a made-up 0. A write
     point sends anyValue when it changes and again every tPeriod. bOk is
     FALSE before the first answer and after tStale (T#0s = 3 x tPeriod)
     without one: interlock on it. Returns the last attempt's result;
     InvalidArgument for settings that cannot work (Float32 with
     WriteSingleRegister, nBit above 15, a RegisterBit write).
  node.Points(anySettings, anyPoints, bEnable, nGoodCnt =>, nLostCnt =>,
              nFirstLost =>, sStatusText =>)
     a table of points: anySettings an ARRAY OF ST_ModbusPointConfig
     (retain it - it is the site's configuration), anyPoints an ARRAY OF
     ST_ModbusPointStatus of the same length (not retained; fWriteValue is
     your logic's, the rest is status). Each row behaves as a Point and is
     re-read every scan. Returns Ok while every enabled row is ok, else the
     first lost row's result; sStatusText names it for a panel ('pt 3 unit 5
     lost', 'pt 2 unit 9 no answer', 'pt 4 bad settings').
  node.Device(nUnitId, tPoll, tGone, bAnswering =>, bSeen =>, tSilent =>,
              tRoundTrip =>)
     how one device is doing, read off the traffic already going to it:
     bAnswering within tGone (T#0s = 5 s), bSeen ever, tSilent since,
     tRoundTrip measured. bSeen FALSE is a device never fitted or wrongly
     addressed (found at the desk); bSeen with bAnswering FALSE is one that
     has died (found in the plant). tPoll asks it (function code 8, which
     touches no register) for a device nothing else talks to; an exception
     still counts as answering. Returns Ok while valid.
  node.Map(anyData, eTable, nAddress, eOnLoss, nSafeValue, bWritten =>,
           bSafeApplied =>)
     puts anyData at Modbus addresses for clients to read and write, in
     place: the variable IS the register, nothing is copied. A BOOL or array
     of BOOL in Coil or DiscreteInput, a WORD, INT or UINT (or an array) in
     HoldingRegister or InputRegister; a REAL or DINT is refused, because a
     client could read half an old value and half a new one - publish a
     scaled integer. An array's lower bound maps to nAddress. Put what a
     client must not change in a read-only table. eOnLoss ResetToValue
     drives a single writable address to nSafeValue after
     stTimingConfig.tFailsafe without a client write. bWritten: a client
     wrote this range since the last call. A server needs at least one Map.

  node.Statistics(bReset, nPending =>, nSent =>, nReceived =>,
                  nChecksumErrors =>, nFramingErrors =>, nNoiseBytes =>,
                  nReconnects =>, sFramingReason =>)
     the link's counters; a rising edge of bReset zeroes them. Checksum
     errors climbing: noise, a baud mismatch or no termination. Noise bytes:
     a floating bus, fit the bias resistors. Framing errors: another
     protocol on the bus, or frames split - sFramingReason says which rule
     finds frames on this link, and why.

  serial : ST_ModbusSerialConfig := (sDevice := '/dev/ttyUSB0', nBaudRate := 19200);

  node(eTransport := E_ModbusTransport.RuntimeSerial, stSerialConfig := serial);
  eResult := node.ReadHoldingRegisters(anyData := aSpeeds, nUnitId := 2,
                                       nAddress := 40, bExecute := bRead);
  node.Watch(anyData := nLevel, nUnitId := 2,
             eTable := E_ModbusTable.InputRegister, nAddress := 30,
             tPeriod := T#2s, eQuality => eLevelQuality);

ONE TASK. This block and its methods run in one task, the network task, at a
higher rate than the machine's: T#1ms on the Runtime, T#50ms on a board to
start with. The node is what touches the wire - it transmits, receives,
retries and times out once per call - so its period is the floor on how fast
anything happens. The machine's program trades values with it through
globals. A method called from another task returns E_ModbusResult.WrongTask
and does nothing. *)

FUNCTION_BLOCK FB_ModbusNode
  VAR_INPUT
    eTransport       : E_ModbusTransport;        (* RuntimeSerial, RuntimeTcp, ArduinoSerial, ArduinoWiFi, ArduinoEthernet *)
    eRole            : E_ModbusRole;             (* Client (default), Server or Both *)
    sHost            : STRING(48);               (* a TCP client: the device; empty = a TCP server *)
    nPort            : UINT;                     (* the TCP port; 0 = 502 *)
    bConnect         : BOOL := TRUE;             (* TRUE opens the link and keeps it open *)
    stSerialConfig   : ST_ModbusSerialConfig;    (* device, baud, parity, the node's own unit id, a board's UART pins *)
    stTimingConfig   : ST_ModbusTimingConfig;    (* timeout, retries, reconnect, framing, failsafe, limits *)
    stIdentityConfig : ST_ModbusIdentityConfig;  (* a server's nameplate, function code 43 *)
    stNetworkConfig  : ST_ModbusNetworkConfig;   (* a board's Wi-Fi or Ethernet *)
  END_VAR
  VAR_OUTPUT
    bLinkUp          : BOOL;                     (* the link is open *)
    bConnected       : BOOL;                     (* there is something at the other end *)
    nClients         : INT;                      (* a TCP server: clients connected *)
    bError           : BOOL;                     (* the link or a method call failed *)
    eErrorId         : E_ModbusResult;           (* why; Ok when fine *)
    sLastError       : STRING(64);               (* why, in words *)
  END_VAR
  VAR
    nApi             : __XWORD;                  (* the link (ModbusAPI) *)
    (* The server half (mbb_serve), handed over by Map. Zero in a program that
       only asks, which then links none of it. *)
    nServe           : __XWORD;
    nKind            : BYTE;
    bSettled         : BOOL;
    bTried           : BOOL;
    nRetryAt         : DINT;
    (* What the live settings were last applied as. *)
    nAppliedTimeout  : DINT;
    nAppliedRetries  : BYTE;
    nIdentityKey     : UDINT;
    bResetSeen       : BOOL;
    nNotice          : BYTE;                     (* an input the target does not use, reported *)
    nTask            : __XWORD;                  (* the task this block runs in, for its methods *)
    nMethods         : __XWORD;                  (* the methods' records *)
  END_VAR

(* Reads coils (function code 1) into anyData on a rising edge of bExecute.
   Queued until the answer, then Ok or why not, until the next edge. *)
METHOD PUBLIC ReadCoils : E_ModbusResult
  VAR_INPUT
    anyData          : ANY;                      (* a BOOL or an array of BOOL *)
    nUnitId          : BYTE;                     (* the device, 1..247 *)
    nAddress         : UINT;                     (* the first coil *)
    nQuantity        : UINT;                     (* how many; 0 = the variable's count *)
    bExecute         : BOOL;                     (* rising edge reads *)
  END_VAR
END_METHOD

(* Reads discrete inputs (function code 2) into anyData on a rising edge of
   bExecute. *)
METHOD PUBLIC ReadDiscreteInputs : E_ModbusResult
  VAR_INPUT
    anyData          : ANY;                      (* a BOOL or an array of BOOL *)
    nUnitId          : BYTE;                     (* the device, 1..247 *)
    nAddress         : UINT;                     (* the first input *)
    nQuantity        : UINT;                     (* how many; 0 = the variable's count *)
    bExecute         : BOOL;                     (* rising edge reads *)
  END_VAR
END_METHOD

(* Reads holding registers (function code 3) into anyData on a rising edge of
   bExecute. 32- and 64-bit types take two or four registers in eOrder. *)
METHOD PUBLIC ReadHoldingRegisters : E_ModbusResult
  VAR_INPUT
    anyData          : ANY;                      (* a WORD, INT, UINT, REAL, DINT, LREAL... or an array of one *)
    nUnitId          : BYTE;                     (* the device, 1..247 *)
    nAddress         : UINT;                     (* the first register *)
    nQuantity        : UINT;                     (* how many values; 0 = the variable's count *)
    eOrder           : E_ModbusOrder;            (* a wide value's word order: ABCD (default), CDAB, BADC, DCBA *)
    bExecute         : BOOL;                     (* rising edge reads *)
  END_VAR
END_METHOD

(* Reads input registers (function code 4) into anyData on a rising edge of
   bExecute. 32- and 64-bit types take two or four registers in eOrder. *)
METHOD PUBLIC ReadInputRegisters : E_ModbusResult
  VAR_INPUT
    anyData          : ANY;                      (* a WORD, INT, UINT, REAL, DINT, LREAL... or an array of one *)
    nUnitId          : BYTE;                     (* the device, 1..247 *)
    nAddress         : UINT;                     (* the first register *)
    nQuantity        : UINT;                     (* how many values; 0 = the variable's count *)
    eOrder           : E_ModbusOrder;            (* a wide value's word order: ABCD (default), CDAB, BADC, DCBA *)
    bExecute         : BOOL;                     (* rising edge reads *)
  END_VAR
END_METHOD

(* Writes one coil (function code 5) on a rising edge of bExecute. *)
METHOD PUBLIC WriteSingleCoil : E_ModbusResult
  VAR_INPUT
    bValue           : BOOL;                     (* the value, taken at the edge *)
    nUnitId          : BYTE;                     (* the device, 1..247; 0 broadcasts *)
    nAddress         : UINT;                     (* the coil *)
    bExecute         : BOOL;                     (* rising edge writes *)
  END_VAR
END_METHOD

(* Writes one holding register (function code 6) on a rising edge of
   bExecute. *)
METHOD PUBLIC WriteSingleRegister : E_ModbusResult
  VAR_INPUT
    nValue           : WORD;                     (* the value, taken at the edge *)
    nUnitId          : BYTE;                     (* the device, 1..247; 0 broadcasts *)
    nAddress         : UINT;                     (* the register *)
    bExecute         : BOOL;                     (* rising edge writes *)
  END_VAR
END_METHOD

(* Writes coils (function code 15) from anyData on a rising edge of
   bExecute. *)
METHOD PUBLIC WriteMultipleCoils : E_ModbusResult
  VAR_INPUT
    anyData          : ANY;                      (* a BOOL or an array of BOOL, copied at the edge *)
    nUnitId          : BYTE;                     (* the device, 1..247; 0 broadcasts *)
    nAddress         : UINT;                     (* the first coil *)
    nQuantity        : UINT;                     (* how many; 0 = the variable's count *)
    bExecute         : BOOL;                     (* rising edge writes *)
  END_VAR
END_METHOD

(* Writes holding registers (function code 16) from anyData on a rising edge
   of bExecute. 32- and 64-bit types take two or four registers in eOrder. *)
METHOD PUBLIC WriteMultipleRegisters : E_ModbusResult
  VAR_INPUT
    anyData          : ANY;                      (* a WORD, INT, UINT, REAL, DINT, LREAL... or an array, copied at the edge *)
    nUnitId          : BYTE;                     (* the device, 1..247; 0 broadcasts *)
    nAddress         : UINT;                     (* the first register *)
    nQuantity        : UINT;                     (* how many values; 0 = the variable's count *)
    eOrder           : E_ModbusOrder;            (* a wide value's word order: ABCD (default), CDAB, BADC, DCBA *)
    bExecute         : BOOL;                     (* rising edge writes *)
  END_VAR
END_METHOD

(* Changes some bits of one holding register atomically (function code 22) on
   a rising edge of bExecute: (current AND nAndMask) OR (nOrMask AND NOT
   nAndMask). *)
METHOD PUBLIC MaskWriteRegister : E_ModbusResult
  VAR_INPUT
    nAndMask         : WORD;                     (* the bits to keep *)
    nOrMask          : WORD;                     (* the bits to set *)
    nUnitId          : BYTE;                     (* the device, 1..247 *)
    nAddress         : UINT;                     (* the register *)
    bExecute         : BOOL;                     (* rising edge writes *)
  END_VAR
END_METHOD

(* Writes anyWriteData and then reads into anyReadData in one transaction
   (function code 23), on a rising edge of bExecute. *)
METHOD PUBLIC ReadWriteMultipleRegisters : E_ModbusResult
  VAR_INPUT
    anyReadData      : ANY;                      (* a WORD, INT or UINT, or an array: what is read *)
    anyWriteData     : ANY;                      (* a WORD, INT or UINT, or an array: what is written, copied at the edge *)
    nUnitId          : BYTE;                     (* the device, 1..247 *)
    nReadAddress     : UINT;                     (* the first register read *)
    nReadQuantity    : UINT;                     (* how many read; 0 = anyReadData's count *)
    nWriteAddress    : UINT;                     (* the first register written *)
    nWriteQuantity   : UINT;                     (* how many written; 0 = anyWriteData's count *)
    bExecute         : BOOL;                     (* rising edge starts it *)
  END_VAR
END_METHOD

(* Reads a device's nameplate (function code 43, basic objects) on a rising
   edge of bExecute. Queued, then Ok with the three strings, or why not. *)
METHOD PUBLIC ReadDeviceIdentification : E_ModbusResult
  VAR_INPUT
    nUnitId          : BYTE;                     (* the device, 1..247 *)
    bExecute         : BOOL;                     (* rising edge reads *)
  END_VAR
  VAR_OUTPUT
    sVendor          : STRING(32);               (* who made it *)
    sProduct         : STRING(32);               (* what it is *)
    sRevision        : STRING(32);               (* which version *)
  END_VAR
END_METHOD

(* Keeps anyData up to date from a device every tPeriod, called every scan.
   Returns the last read's result; eQuality says how much to believe it. *)
METHOD PUBLIC Watch : E_ModbusResult
  VAR_INPUT
    anyData          : ANY;                      (* the variable kept up to date: BOOL for bits, WORD, REAL... for registers *)
    nUnitId          : BYTE;                     (* the device, 1..247 *)
    eTable           : E_ModbusTable;            (* what is read: Coil, DiscreteInput, HoldingRegister (default), InputRegister *)
    nAddress         : UINT;                     (* the first address *)
    tPeriod          : TIME;                     (* how often; T#0s = 1 s *)
    nQuantity        : UINT;                     (* how many values; 0 = the variable's count. Fixed at the first call *)
    eOrder           : E_ModbusOrder;            (* a wide value's word order *)
    nDeadband        : UINT;                     (* how far a register must move to count as a change; 0 = any *)
    bEnable          : BOOL := TRUE;             (* FALSE stops it, keeping the record *)
  END_VAR
  VAR_OUTPUT
    eQuality         : E_ModbusQuality;          (* Unknown never read, Good, Uncertain late, Bad stale or failed *)
    bSeen            : BOOL;                     (* a value has arrived at least once *)
    tAge             : TIME;                     (* since it last arrived; T#0s before the first *)
    nFailures        : UINT;                     (* reads that failed in a row *)
  END_VAR
END_METHOD

(* One value on a field device defined entirely by settings, called every
   scan. A read point writes the value in engineering units into anyValue; a
   write point sends anyValue. Returns the last attempt's result. *)
METHOD PUBLIC Point : E_ModbusResult
  VAR_INPUT
    anyValue         : ANY;                      (* REAL, LREAL, an integer or a BOOL: the point *)
    nUnitId          : BYTE;                     (* the device, 1..247 *)
    eFunction        : E_ModbusPointFunction;    (* how it is reached: ReadCoils .. ReadInputRegisters, WriteSingleCoil, WriteSingleRegister, WriteMultipleRegisters *)
    nAddress         : UINT;                     (* the register or coil, numbered from 0 as the manual's table *)
    eType            : E_ModbusPointType;        (* Bit, Int16, UInt16 (default), Int32, UInt32, Float32, RegisterBit *)
    eOrder           : E_ModbusOrder;            (* the word order of a 32-bit value *)
    nBit             : USINT;                    (* RegisterBit: which bit, 0..15 *)
    fScale           : REAL := 1.0;              (* value = raw x fScale + fOffset *)
    fOffset          : REAL;
    tPeriod          : TIME;                     (* how often to read it or send it again; T#0s = 1 s *)
    tStale           : TIME;                     (* no good answer for this long = lost; T#0s = 3 x tPeriod *)
    tTimeout         : TIME;                     (* how long this device may take; T#0s = measured *)
    bEnable          : BOOL := TRUE;             (* FALSE = not fitted: never asked, never ok *)
  END_VAR
  VAR_OUTPUT
    bOk              : BOOL;                     (* the value is good or a little late: interlock on this *)
    eQuality         : E_ModbusQuality;          (* Unknown never answered, Good, Uncertain late, Bad lost *)
    tAge             : TIME;                     (* since the last good answer *)
    nFailures        : UINT;                     (* failed attempts in a row *)
  END_VAR
END_METHOD

(* A table of points from settings, one row each, called every scan. Returns
   Ok while every enabled row is ok, else the first lost row's result. *)
METHOD PUBLIC Points : E_ModbusResult
  VAR_INPUT
    anySettings      : ANY;                      (* ARRAY OF ST_ModbusPointConfig; retain it *)
    anyPoints        : ANY;                      (* ARRAY OF ST_ModbusPointStatus, the same length; not retained *)
    bEnable          : BOOL := TRUE;             (* FALSE stops asking *)
  END_VAR
  VAR_OUTPUT
    nGoodCnt         : INT;                      (* enabled rows that are ok *)
    nLostCnt         : INT;                      (* enabled rows that are not *)
    nFirstLost       : INT;                      (* the first such row, counted from 1; 0 when none *)
    sStatusText      : STRING(30);               (* that row in a few words, for a panel *)
  END_VAR
END_METHOD

(* How one device is doing, from the traffic already going to it, called
   every scan. Ok while valid; LinkDown while the link is not open. *)
METHOD PUBLIC Device : E_ModbusResult
  VAR_INPUT
    nUnitId          : BYTE;                     (* the device, 1..247 *)
    tPoll            : TIME;                     (* ask it this often (function code 8); T#0s = only watch the traffic *)
    tGone            : TIME;                     (* silent this long = not answering; T#0s = 5 s *)
  END_VAR
  VAR_OUTPUT
    bAnswering       : BOOL;                     (* it has answered within tGone *)
    bSeen            : BOOL;                     (* it has answered at least once *)
    tSilent          : TIME;                     (* since it last answered; T#0s before it ever has *)
    tRoundTrip       : TIME;                     (* how long it takes to reply, measured *)
  END_VAR
END_METHOD

(* Puts anyData at Modbus addresses for clients to read and write, in place,
   called every scan. Ok while bound; LinkDown while the link is not open. *)
METHOD PUBLIC Map : E_ModbusResult
  VAR_INPUT
    anyData          : ANY;                      (* a BOOL, WORD, INT or UINT, or a fixed-bounds array of one *)
    eTable           : E_ModbusTable;            (* Coil, DiscreteInput, HoldingRegister (default), InputRegister *)
    nAddress         : UINT;                     (* the first address; an array's lower bound lands here *)
    eOnLoss          : E_ModbusFailsafe;         (* a writable single address after tFailsafe without a write: HoldLastValue (default) or ResetToValue *)
    nSafeValue       : DINT;                     (* the value ResetToValue drives it to *)
  END_VAR
  VAR_OUTPUT
    bWritten         : BOOL;                     (* a client wrote this range since the last call *)
    bSafeApplied     : BOOL;                     (* the safe value was applied since the last call *)
  END_VAR
END_METHOD

(* The link's counters. A rising edge of bReset zeroes them. *)
METHOD PUBLIC Statistics : E_ModbusResult
  VAR_INPUT
    bReset           : BOOL;                     (* rising edge zeroes the counters *)
  END_VAR
  VAR_OUTPUT
    nPending         : INT;                      (* requests queued and not yet concluded *)
    nSent            : DINT;                     (* frames transmitted *)
    nReceived        : DINT;                     (* frames received *)
    nChecksumErrors  : DINT;                     (* frames that arrived corrupt *)
    nFramingErrors   : DINT;                     (* frames that were structurally impossible *)
    nNoiseBytes      : DINT;                     (* bytes discarded hunting for a frame *)
    nReconnects      : DINT;                     (* times the link dropped and came back *)
    sFramingReason   : STRING(160);              (* how this link finds frames, and why *)
  END_VAR
END_METHOD

#include <ModBeeModbus.h>

#include <new>
#include <string>
#include <vector>
#include <stdio.h>
#include <string.h>
#include <strings.h>

#if defined(MODBUS_PLATFORM_ARDUINO)
#include <Arduino.h>

// WI-FI IS DETECTED, ETHERNET IS ASKED FOR. WiFi.h ships inside the ESP32 core,
// so __has_include finds it. The Arduino Ethernet library is a user library,
// and arduino-cli puts one on the include path only when its dependency
// scanner sees a plain #include: behind __has_include it stays invisible and
// the path never builds (measured). So Ethernet needs MODBUS_ENABLE_ETHERNET
// in the project's build flags. MODBUS_NO_WIFI forces Wi-Fi off.
#if !defined(MODBUS_NO_WIFI) && defined(__has_include)
#if __has_include(<WiFi.h>)
#define MBB_HAS_WIFI 1
#include <WiFi.h>
#endif
#endif

#if defined(MODBUS_ENABLE_ETHERNET)
#define MBB_HAS_ETHERNET 1
#include <Ethernet.h>
#endif
#endif

#if defined(ESP_PLATFORM)
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#elif !defined(ARDUINO)
#include <pthread.h>
#endif

// =============================================================================
// ONE TASK PER NODE
// =============================================================================
//
// OpenPLC runs every task on a thread of its own, and the Modbus library is
// single-threaded. A method or a block given this node from another task would
// be inside the link while the node's own scan is. A lock would hold the
// machine's task for the network's scan, so the rule communication blocks have
// always had: the node and its methods run in one task. The node notes its
// task every scan; a method in another task returns WrongTask and does
// nothing. nTask is 0 before the node's first scan, which lets a method placed
// above the node run.
#if defined(ESP_PLATFORM)
strucpp::XWORD_t mbb_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)xTaskGetCurrentTaskHandle();
}
#elif !defined(ARDUINO)
strucpp::XWORD_t mbb_currentTask() {
    return (strucpp::XWORD_t)(uintptr_t)pthread_self();
}
#else
strucpp::XWORD_t mbb_currentTask() { return 1; }
#endif

bool mbb_inTask(strucpp::XWORD_t owner) {
    return owner == 0 || owner == mbb_currentTask();
}

// --- TIME pins ---------------------------------------------------------------
//
// TIME is signed nanoseconds here and unsigned milliseconds in CODESYS, so
// below zero is none at all. Rounded UP: 0 means "the default" everywhere in
// this library, so T#1us must not arrive as 0.
int32_t mbb_millisOf(const strucpp::IEC_TIME& t)
{
    const int64_t ns = TIME_TO_NS(t);
    if (ns <= 0) return 0;
    const int64_t ms = (ns + 999999LL) / 1000000LL;
    return ms > 2147483647LL ? 2147483647 : (int32_t)ms;
}

// The RS-485 hold is microseconds, finer than a CODESYS TIME: an LTIME.
int32_t mbb_microsOf(const strucpp::IEC_LTIME& t)
{
    const int64_t ns = t.get();
    if (ns <= 0) return 0;
    const int64_t us = (ns + 999LL) / 1000LL;
    return us > 2147483647LL ? 2147483647 : (int32_t)us;
}

// A duration reported on a pin. Negative ("never") is T#0s; the pin beside it
// says which zero it is.
strucpp::IEC_TIME mbb_timeOf(int32_t milliseconds)
{
    if (milliseconds <= 0) return strucpp::IEC_TIME((strucpp::TIME_t)0);
    return strucpp::IEC_TIME((strucpp::TIME_t)milliseconds * strucpp::NS_PER_MS);
}

// The enumerations the methods cast rather than translate, checked here
// because every program with this library has a node.
static_assert((int)strucpp::E_MODBUSRESULT::PROTOCOLERROR + 1 == MB_RESULT_COUNT,
              "E_ModbusResult must mirror ModbusResult member for member");
static_assert((int)strucpp::E_MODBUSTABLE::COIL == (int)ModbusTable::Coil &&
              (int)strucpp::E_MODBUSTABLE::INPUTREGISTER == (int)ModbusTable::InputRegister,
              "E_ModbusTable must mirror ModbusTable");
static_assert((int)strucpp::E_MODBUSORDER::ABCD == (int)ModbusOrder::ABCD &&
              (int)strucpp::E_MODBUSORDER::DCBA == (int)ModbusOrder::DCBA,
              "E_ModbusOrder must mirror ModbusOrder");
static_assert((int)strucpp::E_MODBUSQUALITY::UNKNOWN == (int)ModbusQuality::Unknown &&
              (int)strucpp::E_MODBUSQUALITY::BAD == (int)ModbusQuality::Bad,
              "E_ModbusQuality must mirror ModbusQuality");
static_assert((int)strucpp::E_MODBUSPARITY::EVEN == (int)ModbusParity::Even &&
              (int)strucpp::E_MODBUSPARITY::NONE8N1 == (int)ModbusParity::None8N1,
              "E_ModbusParity must mirror ModbusParity");
static_assert((int)strucpp::E_MODBUSPOINTFUNCTION::WRITEMULTIPLEREGISTERS ==
                  (int)ModbusPointFc::WriteRegisters,
              "E_ModbusPointFunction must mirror ModbusPointFc");
static_assert((int)strucpp::E_MODBUSPOINTTYPE::REGISTERBIT == (int)ModbusPointType::RegisterBit,
              "E_ModbusPointType must mirror ModbusPointType");

static inline strucpp::E_MODBUSRESULT mbb_result(ModbusResult r) {
    return (strucpp::E_MODBUSRESULT)(int32_t)(int)r;
}

// How wide one element of a generic pin is, in bits: 1 for a BOOL, then 16,
// 32 or 64. 0 for a type Modbus does not carry: BYTE and SINT are narrower
// than a register, and binding one would leave half a register pointing at
// whatever sits beside it.
uint8_t mbb_elementBits(uint32_t typeClass)
{
    switch (typeClass) {
        case strucpp::TYPE_CLASS::TYPE_BOOL:
        case strucpp::TYPE_CLASS::TYPE_BIT:    return 1;
        case strucpp::TYPE_CLASS::TYPE_WORD:
        case strucpp::TYPE_CLASS::TYPE_UINT:
        case strucpp::TYPE_CLASS::TYPE_INT:    return 16;
        case strucpp::TYPE_CLASS::TYPE_DWORD:
        case strucpp::TYPE_CLASS::TYPE_UDINT:
        case strucpp::TYPE_CLASS::TYPE_DINT:
        case strucpp::TYPE_CLASS::TYPE_REAL:   return 32;
        case strucpp::TYPE_CLASS::TYPE_LWORD:
        case strucpp::TYPE_CLASS::TYPE_ULINT:
        case strucpp::TYPE_CLASS::TYPE_LINT:
        case strucpp::TYPE_CLASS::TYPE_LREAL:  return 64;
        default: break;
    }
    return 0;
}

// Which wide type a 32- or 64-bit element is, so it is converted, not copied.
static ModbusWideType mbb_wideTypeOfClass(uint32_t typeClass)
{
    switch (typeClass) {
        case strucpp::TYPE_CLASS::TYPE_REAL:   return ModbusWideType::Float32;
        case strucpp::TYPE_CLASS::TYPE_DINT:   return ModbusWideType::Int32;
        case strucpp::TYPE_CLASS::TYPE_DWORD:
        case strucpp::TYPE_CLASS::TYPE_UDINT:  return ModbusWideType::UInt32;
        case strucpp::TYPE_CLASS::TYPE_LREAL:  return ModbusWideType::Float64;
        case strucpp::TYPE_CLASS::TYPE_LINT:   return ModbusWideType::Int64;
        case strucpp::TYPE_CLASS::TYPE_LWORD:
        case strucpp::TYPE_CLASS::TYPE_ULINT:  return ModbusWideType::UInt64;
        default: break;
    }
    return ModbusWideType::None;
}

// One value of an elementary class at `p`, as a number: a BOOL is 0 or 1, a
// TIME its nanoseconds, an enumeration its ordinal (`bits` wide). False for a
// class that is not a number.
static bool mbb_readClass(uint32_t cls, uint32_t bits, const uint8_t* p, double& out)
{
    switch (cls) {
        case strucpp::TYPE_CLASS::TYPE_BOOL:
        case strucpp::TYPE_CLASS::TYPE_BIT:   out = *(const bool*)p ? 1.0 : 0.0; return true;
        case strucpp::TYPE_CLASS::TYPE_SINT:  out = *(const int8_t*)p; return true;
        case strucpp::TYPE_CLASS::TYPE_BYTE:
        case strucpp::TYPE_CLASS::TYPE_USINT: out = *(const uint8_t*)p; return true;
        case strucpp::TYPE_CLASS::TYPE_INT:   out = *(const int16_t*)p; return true;
        case strucpp::TYPE_CLASS::TYPE_WORD:
        case strucpp::TYPE_CLASS::TYPE_UINT:  out = *(const uint16_t*)p; return true;
        case strucpp::TYPE_CLASS::TYPE_DINT:  out = *(const int32_t*)p; return true;
        case strucpp::TYPE_CLASS::TYPE_DWORD:
        case strucpp::TYPE_CLASS::TYPE_UDINT: out = *(const uint32_t*)p; return true;
        case strucpp::TYPE_CLASS::TYPE_LINT:  out = (double)*(const int64_t*)p; return true;
        case strucpp::TYPE_CLASS::TYPE_LWORD:
        case strucpp::TYPE_CLASS::TYPE_ULINT: out = (double)*(const uint64_t*)p; return true;
        case strucpp::TYPE_CLASS::TYPE_REAL:  out = *(const float*)p; return true;
        case strucpp::TYPE_CLASS::TYPE_LREAL: out = *(const double*)p; return true;
        case strucpp::TYPE_CLASS::TYPE_TIME:
        case strucpp::TYPE_CLASS::TYPE_LTIME: out = (double)*(const int64_t*)p; return true;
        case strucpp::TYPE_CLASS::TYPE_ENUM:
            if (bits == 8)  { out = *(const int8_t*)p;  return true; }
            if (bits == 16) { out = *(const int16_t*)p; return true; }
            if (bits == 32) { out = *(const int32_t*)p; return true; }
            if (bits == 64) { out = (double)*(const int64_t*)p; return true; }
            return false;
        default: break;
    }
    return false;
}

// And the way back: rounded to the nearest for an integer, held to its range.
static bool mbb_writeClass(uint32_t cls, uint32_t bits, uint8_t* p, double v)
{
    auto clamp = [](double x, double lo, double hi) {
        x = x < 0 ? x - 0.5 : x + 0.5;
        return x < lo ? lo : (x > hi ? hi : x);
    };
    switch (cls) {
        case strucpp::TYPE_CLASS::TYPE_BOOL:
        case strucpp::TYPE_CLASS::TYPE_BIT:   *(bool*)p = v != 0.0; return true;
        case strucpp::TYPE_CLASS::TYPE_SINT:  *(int8_t*)p = (int8_t)clamp(v, -128, 127); return true;
        case strucpp::TYPE_CLASS::TYPE_BYTE:
        case strucpp::TYPE_CLASS::TYPE_USINT: *(uint8_t*)p = (uint8_t)clamp(v, 0, 255); return true;
        case strucpp::TYPE_CLASS::TYPE_INT:   *(int16_t*)p = (int16_t)clamp(v, -32768, 32767); return true;
        case strucpp::TYPE_CLASS::TYPE_WORD:
        case strucpp::TYPE_CLASS::TYPE_UINT:  *(uint16_t*)p = (uint16_t)clamp(v, 0, 65535); return true;
        case strucpp::TYPE_CLASS::TYPE_DINT:
            *(int32_t*)p = (int32_t)clamp(v, -2147483648.0, 2147483647.0); return true;
        case strucpp::TYPE_CLASS::TYPE_DWORD:
        case strucpp::TYPE_CLASS::TYPE_UDINT:
            *(uint32_t*)p = (uint32_t)clamp(v, 0, 4294967295.0); return true;
        case strucpp::TYPE_CLASS::TYPE_LINT:
            *(int64_t*)p = (int64_t)clamp(v, -9.2e18, 9.2e18); return true;
        case strucpp::TYPE_CLASS::TYPE_LWORD:
        case strucpp::TYPE_CLASS::TYPE_ULINT:
            *(uint64_t*)p = (uint64_t)clamp(v, 0, 1.8e19); return true;
        case strucpp::TYPE_CLASS::TYPE_REAL:  *(float*)p = (float)v; return true;
        case strucpp::TYPE_CLASS::TYPE_LREAL: *(double*)p = v; return true;
        case strucpp::TYPE_CLASS::TYPE_TIME:
        case strucpp::TYPE_CLASS::TYPE_LTIME: *(int64_t*)p = (int64_t)v; return true;
        case strucpp::TYPE_CLASS::TYPE_ENUM:
            if (bits == 8)  { *(int8_t*)p = (int8_t)v;   return true; }
            if (bits == 16) { *(int16_t*)p = (int16_t)v; return true; }
            if (bits == 32) { *(int32_t*)p = (int32_t)v; return true; }
            return false;
        default: break;
    }
    return false;
}

// A scalar numeric or BOOL pin, for a point. False for anything else.
static bool mbb_numberOf(const strucpp::IEC_ANY& any, double& out)
{
    if (any.PVALUE == nullptr || any.DICOUNT != 1 ||
        (uint32_t)any.TYPECLASS == strucpp::TYPE_CLASS::TYPE_TIME ||
        (uint32_t)any.TYPECLASS == strucpp::TYPE_CLASS::TYPE_LTIME) return false;
    return mbb_readClass((uint32_t)any.TYPECLASS, (uint32_t)any.DISIZE * 8, any.PVALUE, out);
}

static bool mbb_storeNumber(const strucpp::IEC_ANY& any, double v)
{
    if (any.PVALUE == nullptr || any.DICOUNT != 1) return false;
    return mbb_writeClass((uint32_t)any.TYPECLASS, (uint32_t)any.DISIZE * 8, any.PVALUE, v);
}

#if defined(MODBUS_PLATFORM_ARDUINO)
// The line settings eParity asks for. RTU is 8E1 by specification and that is
// the default; a board that opened 8N1 would talk past every conforming device
// on the segment, which reads as noise rather than a mistake (MBX-001).
uint32_t mbb_serialConfig(uint8_t parity)
{
    switch ((ModbusParity)parity) {
        case ModbusParity::Odd:     return SERIAL_8O1;
        case ModbusParity::None:    return SERIAL_8N2;
        case ModbusParity::None8N1: return SERIAL_8N1;
        case ModbusParity::Even:
        default:                    return SERIAL_8E1;
    }
}

// The board's hardware serials by number. One it does not have is refused,
// never quietly opened on UART0: on the ModBee Node UART0 is the HAT port.
HardwareSerial* mbb_serialPort(uint8_t port)
{
    switch (port) {
        case 0:
#if defined(ARDUINO_ARCH_ESP32) && defined(ARDUINO_USB_CDC_ON_BOOT) && ARDUINO_USB_CDC_ON_BOOT
            // Serial is the USB CDC device on this core; Serial0 is UART0.
            return &Serial0;
#else
            return &Serial;
#endif
#if defined(HAVE_HWSERIAL1) || defined(ARDUINO_ARCH_ESP32)
        case 1: return &Serial1;
#endif
#if defined(HAVE_HWSERIAL2) || defined(ARDUINO_ARCH_ESP32)
        case 2: return &Serial2;
#endif
        default: return nullptr;
    }
}

#if defined(ARDUINO_ARCH_ESP32)
// AN RS-485 PORT THAT NEVER HOLDS THE SCAN. The core's default has no software
// transmit buffer, so write() blocked on the 128-byte FIFO, and the driver
// enable waited for the last byte to leave: together about 420 ms of scan for
// a 256-byte frame at 9600 baud. So the port gets a buffer that holds any
// frame, and with a DE pin the UART's own RS-485 half-duplex mode drives DE for
// exactly as long as bits leave. Returns the DE pin the transport should still
// drive: -1 when the UART does.
#define MBB_SERIAL_TX_BYTES 1024   // two of the largest frame, ASCII's 513
int mbb_serialBegin(HardwareSerial* port, uint32_t baud, uint32_t cfg,
                    int rxPin, int txPin, int dePin)
{
    port->end();                         // a buffer is only taken by begin()
    port->setTxBufferSize(MBB_SERIAL_TX_BYTES);
    if (rxPin >= 0 && txPin >= 0) {
        port->begin(baud, cfg, (int8_t)rxPin, (int8_t)txPin);
    } else {
        port->begin(baud, cfg);
    }
    if (dePin >= 0 && port->setPins(-1, -1, -1, (int8_t)dePin) &&
        port->setMode(UART_MODE_RS485_HALF_DUPLEX)) {
        return -1;
    }
    return dePin;
}
#endif

// 'dhcp', in any case: the way to say a server-assigned address was meant.
static bool mbb_wantsDhcp(const char* text)
{
    return text != nullptr && strcasecmp(text, "dhcp") == 0;
}

#if defined(MBB_HAS_WIFI) || defined(MBB_HAS_ETHERNET)
static IPAddress mbb_gatewayFor(const IPAddress& address, const char* given)
{
    IPAddress gateway;
    if (given && given[0] && gateway.fromString(given)) return gateway;
    return IPAddress(address[0], address[1], address[2], 1);
}

static IPAddress mbb_subnetFor(const char* given)
{
    IPAddress subnet;
    if (given && given[0] && subnet.fromString(given)) return subnet;
    return IPAddress(255, 255, 255, 0);
}
#endif

#if defined(MBB_HAS_ETHERNET)
// Six hex bytes with any separator.
static bool mbb_parseMac(const char* text, uint8_t out[6])
{
    if (!text) return false;
    int byteIndex = 0;
    unsigned value = 0;
    int digits = 0;
    for (const char* p = text; ; p++) {
        const char c = *p;
        if (c == ':' || c == '-' || c == '\0') {
            if (digits == 0 || byteIndex > 5) return false;
            out[byteIndex++] = (uint8_t)value;
            value = 0;
            digits = 0;
            if (c == '\0') break;
            continue;
        }
        int nibble;
        if (c >= '0' && c <= '9') nibble = c - '0';
        else if (c >= 'a' && c <= 'f') nibble = c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') nibble = c - 'A' + 10;
        else return false;
        if (++digits > 2) return false;
        value = (value << 4) | (unsigned)nibble;
    }
    return byteIndex == 6;
}
#endif

// One socket and transport per medium: WiFiClient and EthernetClient share no
// base, so the library binds to them by template.
#if defined(MBB_HAS_WIFI)
static WiFiClient* mbbWifiClient = nullptr;
static WiFiServer* mbbWifiServer = nullptr;
#endif
#if defined(MBB_HAS_ETHERNET)
static EthernetClient* mbbEthClient = nullptr;
static EthernetServer* mbbEthServer = nullptr;
#endif
static ModbusTransport* mbbArduinoTransport = nullptr;
static ModbusListener* mbbArduinoListener = nullptr;
#endif

// Which concrete link a node made, so a re-open takes the path the first took.
#define MBB_KIND_NONE  0
#define MBB_KIND_RTU   1
#define MBB_KIND_ASCII 2
#define MBB_KIND_TCP   3

// How long before a failed open is tried again. An absent serial device fails
// in microseconds; a 1 ms task retrying it every scan is a thousand identical
// failures a second.
#define MBB_REOPEN_MS  2000

// The records a node's methods may hold.
#ifndef MBB_MAX_RECORDS
#define MBB_MAX_RECORDS 256
#endif

// =============================================================================
// THE SERVER HALF
// =============================================================================
//
// Only a node that ANSWERS needs it: the unit id on a serial line, the
// listening socket on TCP. The node never names it; Map hands it over through
// nServe, so a program that only asks links none of it.
strucpp::E_MODBUSRESULT mbb_serve(ModbusAPI* mb, uint8_t kind, bool onWifi, uint16_t tcpPort,
                         uint8_t maxClients, mb_time_t idleMs, uint8_t unitId,
                         bool& opened, const char*& why)
{
    if (kind != MBB_KIND_TCP) {
        if (unitId < 1 || unitId > 247) {
            why = "a serial server needs stSerialConfig.nUnitId, 1 to 247";
            return strucpp::E_MODBUSRESULT::INVALIDARGUMENT;
        }
        if (kind == MBB_KIND_ASCII) ((ModbusASCII*)mb)->slave(unitId);
        else ((ModbusRTU*)mb)->slave(unitId);
        return strucpp::E_MODBUSRESULT::OK;
    }

    ModbusTCP* tcp = (ModbusTCP*)mb;
#if defined(MODBUS_PLATFORM_HOST)
    (void)onWifi;
    if (maxClients > 0) tcp->maxClients((size_t)maxClients);
    if (idleMs > 0) tcp->idleTimeout(idleMs);   // 0: the library's 60 s
    opened = tcp->listen(tcpPort);
#endif
#if defined(MODBUS_PLATFORM_ARDUINO)
    if (maxClients > 0) tcp->maxClients((size_t)maxClients);
    if (idleMs > 0) tcp->idleTimeout(idleMs);   // 0: the library's 60 s
    // 0 is the listener's own default (two). Any other figure is held in full
    // or refused out loud - never quietly fewer.
    const size_t limit = maxClients;
    bool roomForClients = true;
    if (!mbbArduinoListener) {
#if defined(MBB_HAS_WIFI)
        if (onWifi) {
            mbbWifiServer = new (std::nothrow) WiFiServer(tcpPort);
            if (mbbWifiServer) {
                ModbusArduinoServer<WiFiServer, WiFiClient>* server = new (std::nothrow)
                    ModbusArduinoServer<WiFiServer, WiFiClient>(*mbbWifiServer, limit);
                if (server && !server->ready()) { delete server; server = nullptr; roomForClients = false; }
                mbbArduinoListener = server;
            }
        }
#endif
#if defined(MBB_HAS_ETHERNET)
        if (!onWifi) {
            mbbEthServer = new (std::nothrow) EthernetServer(tcpPort);
            if (mbbEthServer) {
                ModbusArduinoServer<EthernetServer, EthernetClient>* server = new (std::nothrow)
                    ModbusArduinoServer<EthernetServer, EthernetClient>(*mbbEthServer, limit);
                if (server && !server->ready()) { delete server; server = nullptr; roomForClients = false; }
                mbbArduinoListener = server;
            }
        }
#endif
    }
    if (!mbbArduinoListener) {
        why = roomForClients ? "out of memory" : "out of memory for nMaxClients connections";
        return strucpp::E_MODBUSRESULT::NOTINITIALISED;
    }
    opened = tcp->listen(*mbbArduinoListener);
#endif
    return strucpp::E_MODBUSRESULT::OK;
}

typedef strucpp::E_MODBUSRESULT (*MbbServeFn)(ModbusAPI*, uint8_t, bool, uint16_t, uint8_t, mb_time_t,
                                     uint8_t, bool&, const char*&);

// =============================================================================
// THE METHODS' RECORDS
// =============================================================================
//
// A method has no instance of its own, so what it must remember between calls
// lives here, in the node: one record per call, found by the method and its
// variable's declared NAME and TYPENAME (an address moves, a name does not, and
// a name reads in a diagnostic). A call with no variable is found by its unit
// and address. The address is kept only as a cache.

namespace {

enum MbbKind : uint8_t {
    MBB_READ_COILS = 1, MBB_READ_INPUTS, MBB_READ_HOLDING, MBB_READ_INPUT_REGS,
    MBB_WRITE_COIL, MBB_WRITE_REGISTER, MBB_WRITE_COILS, MBB_WRITE_REGISTERS,
    MBB_MASK_WRITE, MBB_READ_WRITE, MBB_IDENTIFY, MBB_WATCH, MBB_POINT, MBB_POINTS, MBB_DEVICE, MBB_MAP
};

struct MbbRecord {
    uint8_t kind = 0;
    uint32_t key = 0;
    std::string name;
    std::string type;
    const void* cache = nullptr;
    uint32_t usedScan = 0;          // the node scan this record was last called in

    // A request: the edge, and the conclusion its completion handler brings.
    bool lastExecute = false;
    bool pending = false;
    bool concluded = false;
    uint32_t seq = 0;
    uint8_t outcome = 0;
    strucpp::E_MODBUSRESULT result = strucpp::E_MODBUSRESULT::OK;
    // ReadWriteMultipleRegisters: the reply lands packed here, then goes to
    // the variable through its own stride.
    uint16_t* bounce = nullptr;
    uint16_t bounceCount = 0;
    uint8_t* readDest = nullptr;
    uint16_t readStride = 0;

    // Watch, Point, Points, Map.
    size_t index = 0;               // the library's handle + 1; 0 = none yet
    size_t rows = 0;
    bool running = false;
    const void* storage = nullptr;
    uint8_t unit = 0;
    uint8_t table = 0;
    uint16_t address = 0;
    uint8_t order = 0;
    int32_t interval = 0;
    uint16_t deadband = 0;
    uint32_t seenWrites = 0;
    uint16_t seenFailsafe = 0;
    bool bound = false;

    // Device and ReadDeviceIdentification.
    uint8_t* reply = nullptr;       // a nameplate read in flight writes here
    bool polling = false;
    int32_t nextPoll = 0;
    std::string vendor, product, revision;

    MbbRecord() = default;
    MbbRecord(const MbbRecord&) = delete;
    MbbRecord& operator=(const MbbRecord&) = delete;
    ~MbbRecord() { delete[] bounce; delete[] reply; }
};

struct MbbMethods {
    std::vector<MbbRecord*> records;
    uint32_t scan = 1;              // counted by the node, once per call
    // The last method call that failed: the node's bError / sLastError name it
    // until that call succeeds.
    std::string failKey;
    std::string failText;
    uint8_t failResult = 0;
    ~MbbMethods() {
        for (size_t i = 0; i < records.size(); i++) delete records[i];
    }
};

// Every link and record table this program made, closed when it is unloaded.
// The Runtime swaps a new program into the SAME process: a link left open
// would hold its port, and the next download would find "could not bind" on a
// port nothing seems to use. Made on first use, so a program without a node
// links none of it; the links go first, while the records their completion
// handlers point at still exist.
struct MbbOwned {
    std::vector<ModbusAPI*> links;
    std::vector<MbbMethods*> methods;
    ~MbbOwned() {
        for (size_t i = 0; i < links.size(); i++) { links[i]->end(); delete links[i]; }
        for (size_t i = 0; i < methods.size(); i++) delete methods[i];
    }
};
MbbOwned& mbbOwned() {
    static MbbOwned owned;
    return owned;
}

uint32_t mbb_fingerprint(uint32_t h, const void* data, size_t length) {
    const uint8_t* p = (const uint8_t*)data;
    for (size_t i = 0; i < length; i++) { h ^= p[i]; h *= 16777619u; }
    return h;
}

}  // namespace

// `held` is the node's nMethods.
template <typename Held>
static MbbMethods* mbb_methodsOf(Held& held) {
    MbbMethods* m = (MbbMethods*)(uintptr_t)(strucpp::XWORD_t)held;
    if (m == nullptr) {
        m = new (std::nothrow) MbbMethods();
        if (m == nullptr) return nullptr;
        mbbOwned().methods.push_back(m);
        held = (strucpp::XWORD_t)(uintptr_t)m;
    }
    return m;
}

// The record of one call: by its variable when it has a name, else by `where`.
// Null past MBB_MAX_RECORDS or out of memory.
static MbbRecord* mbb_recordOf(MbbMethods* m, uint8_t kind, const strucpp::IEC_ANY* any,
                               const char* where) {
    if (m == nullptr) return nullptr;
    const bool named = any != nullptr && any->NAME != nullptr && any->NAME[0] != '\0';
    std::string unnamed;
    const char* name;
    if (named) {
        name = any->NAME;
    } else {
        unnamed = std::string("@") + (where ? where : "");
        name = unnamed.c_str();
    }
    const char* type = (named && any->TYPENAME) ? any->TYPENAME : "";
    uint32_t key = mbb_fingerprint(2166136261u, &kind, sizeof kind);
    key = mbb_fingerprint(key, name, strlen(name));
    key = mbb_fingerprint(key, type, strlen(type));

    // The same variable at the same address first. Then the same name and
    // type at another address: the variable moved - unless that record has
    // already been called this scan, when it is another variable of the same
    // spelling (the same local in two instances of one function block) and
    // gets a record of its own.
    if (named && any->PVALUE != nullptr) {
        for (size_t i = 0; i < m->records.size(); i++) {
            MbbRecord* r = m->records[i];
            if (r->kind == kind && r->key == key && r->cache == any->PVALUE) {
                r->usedScan = m->scan;
                return r;
            }
        }
    }
    for (size_t i = 0; i < m->records.size(); i++) {
        MbbRecord* r = m->records[i];
        if (r->kind != kind || r->key != key || r->name != name || r->type != type) continue;
        if (named && r->usedScan == m->scan) continue;
        if (named) r->cache = any->PVALUE;
        r->usedScan = m->scan;
        return r;
    }
    if (m->records.size() >= (size_t)MBB_MAX_RECORDS) return nullptr;
    MbbRecord* r = new (std::nothrow) MbbRecord();
    if (r == nullptr) return nullptr;
    r->kind = kind;
    r->key = key;
    r->name = name;
    r->type = type;
    r->cache = named ? any->PVALUE : nullptr;
    r->usedScan = m->scan;
    m->records.push_back(r);
    return r;
}

static const char* mbb_resultText(strucpp::E_MODBUSRESULT result) {
    if (result == strucpp::E_MODBUSRESULT::WRONGTASK) return "WrongTask";
    return mb_resultName((ModbusResult)(int)result);
}

// A method call's result, noted on the node: a failing call is named on the
// node's bError / sLastError ("ReadHoldingRegisters aSpeeds: Timeout") until
// the same call succeeds. Queued and LinkDown are states, not failures.
static strucpp::E_MODBUSRESULT mbb_noteCall(strucpp::XWORD_t held, const char* method,
                                   const MbbRecord* r, strucpp::E_MODBUSRESULT result) {
    MbbMethods* m = (MbbMethods*)(uintptr_t)held;
    if (m == nullptr) return result;
    std::string key = method;
    if (r != nullptr) {
        key += ' ';
        key += r->name;
    }
    const bool failed = result != strucpp::E_MODBUSRESULT::OK && result != strucpp::E_MODBUSRESULT::QUEUED &&
                        result != strucpp::E_MODBUSRESULT::LINKDOWN;
    if (failed) {
        m->failKey = key;
        m->failResult = (uint8_t)result;
        m->failText = key + ": " + mbb_resultText(result);
    } else if (m->failKey == key) {
        m->failKey.clear();
        m->failText.clear();
    }
    return result;
}

// A request's completion: the tag is the start it belongs to, so the late
// conclusion of an earlier start can never conclude a newer one.
static void mbb_requestDone(void* context, uintptr_t tag, ModbusResult result) {
    MbbRecord* r = (MbbRecord*)context;
    if ((uint32_t)tag != r->seq) return;
    if (result == ModbusResult::Ok && r->bounce != nullptr && r->readDest != nullptr) {
        for (uint16_t i = 0; i < r->bounceCount; i++) {
            *(uint16_t*)(r->readDest + (size_t)i * r->readStride) = r->bounce[i];
        }
    }
    r->outcome = (uint8_t)result;
    r->concluded = true;
}

static ModbusCompletionHandler mbb_handlerFor(MbbRecord* r) {
    return ModbusCompletionHandler(&mbb_requestDone, r, (uintptr_t)r->seq);
}

// How many values a request moves: nQuantity, or the variable's own count when
// it is 0. More than the variable holds is 0, which the caller refuses.
static int32_t mbb_countOf(const strucpp::IEC_ANY& any, uint16_t asked) {
    const int32_t held = any.DICOUNT;
    if (asked == 0) return held;
    return (int32_t)asked <= held ? (int32_t)asked : 0;
}

void setup()
{
    bLinkUp = false;
    bConnected = false;
    nClients = 0;
    bError = false;
    eErrorId = strucpp::E_MODBUSRESULT::OK;
    sLastError = "";
    nApi = (strucpp::XWORD_t)0;
    nServe = (strucpp::XWORD_t)0;
    nKind = MBB_KIND_NONE;
    bSettled = false;
    bTried = false;
    nRetryAt = 0;
    nAppliedTimeout = 0;
    nAppliedRetries = 0;
    nIdentityKey = 0;
    bResetSeen = false;
    nNotice = 0;
}

void loop()
{
    nTask = mbb_currentTask();   // the methods compare against it: ONE TASK, above
    if (MbbMethods* calls = (MbbMethods*)(uintptr_t)(strucpp::XWORD_t)nMethods) calls->scan++;
    ModbusAPI* mb = (ModbusAPI*)(uintptr_t)(strucpp::XWORD_t)nApi;

    // Standing down: the port released and the socket dropped, so something
    // else may use the converter. The link object stays, with every binding
    // and watch the methods made on it.
    if (!(bool)bConnect) {
        if (mb && (bool)bLinkUp) mb->end();
        bLinkUp = false;
        bConnected = false;
        nClients = 0;
        bTried = false;
        return;
    }

    auto fail = [&](strucpp::E_MODBUSRESULT why, const char* text) {
        bError = true;
        eErrorId = why;
        sLastError = text;
    };

    if (!(bool)bLinkUp) {
        // ONE SCAN BEFORE OPENING, so a Map called below this block in the same
        // program has handed the server half over first.
        if (!(bool)bSettled) {
            bSettled = true;
            return;
        }

        const mb_time_t now = mb_millis();
        if ((bool)bTried &&
            (int32_t)(now - (mb_time_t)(uint32_t)(int32_t)nRetryAt) < 0) {
            return;
        }
        bTried = true;
        nRetryAt = (int32_t)(uint32_t)(now + MBB_REOPEN_MS);

        const strucpp::E_MODBUSTRANSPORT link = (strucpp::E_MODBUSTRANSPORT)eTransport;
        const strucpp::E_MODBUSFRAMING frame = (strucpp::E_MODBUSFRAMING)stTimingConfig.EFRAMING;
        const strucpp::E_MODBUSROLE role = (strucpp::E_MODBUSROLE)eRole;

        const bool onSerial = link == strucpp::E_MODBUSTRANSPORT::RUNTIMESERIAL ||
                              link == strucpp::E_MODBUSTRANSPORT::ARDUINOSERIAL;
        const bool runtimeLink = link == strucpp::E_MODBUSTRANSPORT::RUNTIMESERIAL ||
                                 link == strucpp::E_MODBUSTRANSPORT::RUNTIMETCP;

#if defined(MODBUS_PLATFORM_HOST)
        if (!runtimeLink) {
            fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "that eTransport needs a board, not the Runtime");
            return;
        }
#else
        if (runtimeLink) {
            fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "that eTransport needs the Runtime, not a board");
            return;
        }
#endif
        // Framing the medium cannot carry is refused here rather than turned
        // into a silence at the far end.
        if (onSerial && frame == strucpp::E_MODBUSFRAMING::TCP) {
            fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "eFraming Tcp (MBAP) has no meaning on a serial line");
            return;
        }
        if (!onSerial && frame == strucpp::E_MODBUSFRAMING::ASCII) {
            fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "eFraming Ascii inside a TCP stream is not a Modbus transport");
            return;
        }

        const uint8_t wanted = onSerial
            ? (frame == strucpp::E_MODBUSFRAMING::ASCII ? MBB_KIND_ASCII : MBB_KIND_RTU)
            : MBB_KIND_TCP;

        // Built once and kept: a re-open reuses it, which is why the bindings
        // and watches survive the gap.
        if (!mb) {
            if (wanted == MBB_KIND_RTU)        mb = new (std::nothrow) ModbusRTU();
            else if (wanted == MBB_KIND_ASCII) mb = new (std::nothrow) ModbusASCII();
            else                               mb = new (std::nothrow) ModbusTCP();
            if (!mb) {
                // Arduino cores build without exceptions: an exhausted heap
                // stops the node, never the PLC.
                fail(strucpp::E_MODBUSRESULT::NOTINITIALISED, "out of memory");
                return;
            }
            nApi = (strucpp::XWORD_t)(uintptr_t)mb;
            nKind = wanted;
            mbbOwned().links.push_back(mb);
        } else if ((uint8_t)nKind != wanted) {
            // Rebuilding would drop every binding silently: refused out loud.
            fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "eTransport and eFraming cannot change once started");
            return;
        }

        // The node's own settings, before it opens, so the first request has
        // them.
        const int32_t timeoutMs = mbb_millisOf(stTimingConfig.TTIMEOUT);
        if (timeoutMs > 0) mb->timeout((mb_time_t)timeoutMs);
        if ((uint8_t)stTimingConfig.NRETRIES > 0) mb->retries((uint8_t)stTimingConfig.NRETRIES);
        nAppliedTimeout = timeoutMs;
        nAppliedRetries = (uint8_t)stTimingConfig.NRETRIES;
        const int32_t failsafeMs = mbb_millisOf(stTimingConfig.TFAILSAFE);
        if (failsafeMs > 0) mb->failsafeAfter((mb_time_t)failsafeMs);
        // Taken when the link opens; a figure the board cannot hold fails the
        // open with the reason on sLastError.
        if ((uint16_t)stTimingConfig.NMAXPENDING > 0 || (uint16_t)stTimingConfig.NMAXPENDINGBYTES > 0) {
            mb->queueSize((size_t)(uint16_t)stTimingConfig.NMAXPENDING,
                          (size_t)(uint16_t)stTimingConfig.NMAXPENDINGBYTES);
        }
        // Recovery is on by default, the library's two seconds: the far end of
        // a Modbus link is a device that gets rebooted.
        if (!(bool)stTimingConfig.BAUTORECONNECT) {
            mb->reconnectAfter(0);
        } else {
            const int32_t reconnectMs = mbb_millisOf(stTimingConfig.TRECONNECT);
            mb->reconnectAfter(reconnectMs > 0 ? (mb_time_t)reconnectMs : (mb_time_t)MBB_REOPEN_MS);
        }

        const uint32_t baud = ((int32_t)stSerialConfig.NBAUDRATE > 0)
            ? (uint32_t)(int32_t)stSerialConfig.NBAUDRATE : 19200u;
        const uint16_t tcpPort = ((uint16_t)nPort != 0) ? (uint16_t)nPort : MODBUS_TCP_PORT;
        const bool asServer = role == strucpp::E_MODBUSROLE::SERVER || role == strucpp::E_MODBUSROLE::BOTH;
        const bool asClient = role == strucpp::E_MODBUSROLE::CLIENT || role == strucpp::E_MODBUSROLE::BOTH;
        const uint8_t maxClients = (uint8_t)stTimingConfig.NMAXCLIENTS;
        const mb_time_t idleMs = (mb_time_t)mbb_millisOf(stTimingConfig.TIDLE);

        // A server with nothing to serve: said plainly, rather than answering
        // every request with an exception for a reason nobody can see.
        const MbbServeFn serve = (MbbServeFn)(uintptr_t)(strucpp::XWORD_t)nServe;
        if (asServer && !serve) {
            fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "a server needs a Map call");
            return;
        }

        bool opened = false;

#if defined(MODBUS_PLATFORM_HOST)
        if (onSerial) {
            if (stSerialConfig.SDEVICE.length() == 0) {
                fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "no stSerialConfig.sDevice named");
                return;
            }
            // The struct is a member of this instance, so its text outlives the
            // scan and the transport may hold it.
            const ModbusParity parity = (ModbusParity)(int)(strucpp::E_MODBUSPARITY)stSerialConfig.EPARITY;
            opened = (wanted == MBB_KIND_ASCII)
                ? ((ModbusASCII*)mb)->begin(stSerialConfig.SDEVICE.c_str(), baud, parity)
                : ((ModbusRTU*)mb)->begin(stSerialConfig.SDEVICE.c_str(), baud, parity);
        } else {
            ModbusTCP* tcp = (ModbusTCP*)mb;
            tcp->rtuOverTcp(frame == strucpp::E_MODBUSFRAMING::RTU);
            // sHost empty means be a server: the two impossible states - a
            // client with nowhere to connect, a server pointed at somebody -
            // stay unreachable.
            const bool wantsClient = asClient && sHost.length() > 0;
            if (asServer) {
                const char* why = "";
                const strucpp::E_MODBUSRESULT served =
                    serve(mb, wanted, false, tcpPort, maxClients, idleMs, 0, opened, why);
                if (served != strucpp::E_MODBUSRESULT::OK) {
                    fail(served, why);
                    return;
                }
            }
            if (wantsClient) opened = tcp->connect(sHost.c_str(), tcpPort) || opened;
            if (!asServer && !wantsClient) {
                fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "a TCP client needs sHost; leave it empty to be a server");
                return;
            }
        }
#endif

#if defined(MODBUS_PLATFORM_ARDUINO)
        if (onSerial) {
            HardwareSerial* port = mbb_serialPort((uint8_t)stSerialConfig.NUART);
            if (port == nullptr) {
                fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "stSerialConfig.nUart is not a hardware serial on this board");
                return;
            }
            const uint32_t cfg = mbb_serialConfig((uint8_t)(int)(strucpp::E_MODBUSPARITY)stSerialConfig.EPARITY);
#if defined(ARDUINO_ARCH_ESP32)
            const int de = mbb_serialBegin(port, baud, cfg, (int)(int16_t)stSerialConfig.NRXPIN,
                                           (int)(int16_t)stSerialConfig.NTXPIN,
                                           (int)(int16_t)stSerialConfig.NDEPIN);
#else
            port->begin(baud, cfg);
            const int de = (int)(int16_t)stSerialConfig.NDEPIN;
#endif
            const int32_t holdUs = mbb_microsOf(stSerialConfig.TDEHOLD);
            const uint32_t hold = holdUs > 0 ? (uint32_t)holdUs : 2000u;
            if (wanted == MBB_KIND_ASCII) {
                if (de >= 0) ((ModbusASCII*)mb)->directionPin(de, true, hold);
                opened = ((ModbusASCII*)mb)->begin(port, baud);
            } else {
                if (de >= 0) ((ModbusRTU*)mb)->directionPin(de, true, hold);
                opened = ((ModbusRTU*)mb)->begin(port, baud);
            }
        } else {
            // --- bring the network up: an OpenPLC program has no setup() of
            // its own, so the node does it from stNetworkConfig.
            const char* ip = stNetworkConfig.SIP.c_str();
            if (link == strucpp::E_MODBUSTRANSPORT::ARDUINOWIFI) {
#if defined(MBB_HAS_WIFI)
                if (stNetworkConfig.SIP.length() == 0) {
                    fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "set stNetworkConfig.sIp, or 'dhcp' to ask for one");
                    return;
                }
                if (WiFi.status() != WL_CONNECTED) {
                    // The address is set BEFORE joining: WiFi.config() after
                    // WiFi.begin() is a lease already taken and then argued with.
                    if (!mbb_wantsDhcp(ip)) {
                        IPAddress address;
                        if (!address.fromString(ip)) {
                            fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "stNetworkConfig.sIp is not an address");
                            return;
                        }
                        WiFi.config(address, mbb_gatewayFor(address, stNetworkConfig.SGATEWAY.c_str()),
                                    mbb_subnetFor(stNetworkConfig.SSUBNET.c_str()));
                    }
                    WiFi.begin(stNetworkConfig.SSSID.c_str(), stNetworkConfig.SWIFIPASSWORD.c_str());
                    // Not an error yet: joining takes seconds and does not
                    // block. The retry timer brings us back until it is up.
                    eErrorId = strucpp::E_MODBUSRESULT::LINKDOWN;
                    sLastError = "joining the network";
                    return;
                }
#else
                fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "this board has no WiFi");
                return;
#endif
            } else {
#if defined(MBB_HAS_ETHERNET)
                // The Arduino Ethernet library: a W5100 or W5500 on SPI. An
                // ESP32's built-in RMII PHY is the core's ETH library, not this.
                if (stNetworkConfig.SIP.length() == 0) {
                    fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "set stNetworkConfig.sIp, or 'dhcp' to ask for one");
                    return;
                }
                uint8_t mac[6] = { 0xDE, 0xAD, 0xBE, 0xEF, 0xFE, 0xED };
                mbb_parseMac(stNetworkConfig.SMAC.c_str(), mac);
                if (mbb_wantsDhcp(ip)) {
                    // DHCP blocks, sixty seconds by default: bounded to one
                    // second and retried on the node's timer.
                    if (Ethernet.begin(mac, 1000, 1000) == 0) {
                        eErrorId = strucpp::E_MODBUSRESULT::LINKDOWN;
                        sLastError = "no address from DHCP yet";
                        return;
                    }
                } else {
                    IPAddress address;
                    if (!address.fromString(ip)) {
                        fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "stNetworkConfig.sIp is not an address");
                        return;
                    }
                    // Static, and instant. The gateway serves as DNS too:
                    // nothing here resolves a name.
                    const IPAddress gateway = mbb_gatewayFor(address, stNetworkConfig.SGATEWAY.c_str());
                    Ethernet.begin(mac, address, gateway, gateway,
                                   mbb_subnetFor(stNetworkConfig.SSUBNET.c_str()));
                }
                if (Ethernet.hardwareStatus() == EthernetNoHardware) {
                    fail(strucpp::E_MODBUSRESULT::NOTINITIALISED, "no Ethernet controller found on SPI");
                    return;
                }
                if (Ethernet.linkStatus() == LinkOFF) {
                    eErrorId = strucpp::E_MODBUSRESULT::LINKDOWN;
                    sLastError = "Ethernet cable unplugged";
                    return;
                }
#else
                fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "define MODBUS_ENABLE_ETHERNET to build Ethernet in");
                return;
#endif
            }

            ModbusTCP* tcp = (ModbusTCP*)mb;
            tcp->rtuOverTcp(frame == strucpp::E_MODBUSFRAMING::RTU);
            const bool onWifi = (link == strucpp::E_MODBUSTRANSPORT::ARDUINOWIFI);

            if (asServer) {
                const char* why = "";
                const strucpp::E_MODBUSRESULT served =
                    serve(mb, wanted, onWifi, tcpPort, maxClients, idleMs, 0, opened, why);
                if (served != strucpp::E_MODBUSRESULT::OK) {
                    fail(served, why);
                    return;
                }
            } else {
                if (sHost.length() == 0) {
                    fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT, "a TCP client needs sHost");
                    return;
                }
                if (!mbbArduinoTransport) {
#if defined(MBB_HAS_WIFI)
                    if (onWifi) {
                        mbbWifiClient = new (std::nothrow) WiFiClient();
                        if (mbbWifiClient) {
                            mbbArduinoTransport = new (std::nothrow)
                                ModbusArduinoClientTransport<WiFiClient>(*mbbWifiClient,
                                                                         sHost.c_str(), tcpPort);
                        }
                    }
#endif
#if defined(MBB_HAS_ETHERNET)
                    if (!onWifi) {
                        mbbEthClient = new (std::nothrow) EthernetClient();
                        if (mbbEthClient) {
                            mbbArduinoTransport = new (std::nothrow)
                                ModbusArduinoClientTransport<EthernetClient>(*mbbEthClient,
                                                                             sHost.c_str(), tcpPort);
                        }
                    }
#endif
                }
                if (!mbbArduinoTransport) {
                    fail(strucpp::E_MODBUSRESULT::NOTINITIALISED, "out of memory");
                    return;
                }
                opened = tcp->connect(*mbbArduinoTransport);
            }
        }
#endif

        if (opened && onSerial && asServer) {
            const char* why = "";
            const strucpp::E_MODBUSRESULT served = serve(mb, wanted, false, tcpPort, 0, 0,
                                                (uint8_t)stSerialConfig.NUNITID, opened, why);
            if (served != strucpp::E_MODBUSRESULT::OK) {
                fail(served, why);
                return;
            }
        }

        if (!opened) {
            fail(strucpp::E_MODBUSRESULT::NOTINITIALISED, mb->lastError());
            return;
        }

        bLinkUp = true;
        bError = false;
        eErrorId = strucpp::E_MODBUSRESULT::OK;
        sLastError = "";
    }

    if (!mb) return;

    // Live settings: the timeout, the retries and the nameplate take effect
    // without reopening anything.
    const int32_t timeoutMs = mbb_millisOf(stTimingConfig.TTIMEOUT);
    if (timeoutMs != (int32_t)nAppliedTimeout) {
        nAppliedTimeout = timeoutMs;
        mb->timeout((mb_time_t)timeoutMs);
    }
    if ((uint8_t)stTimingConfig.NRETRIES != (uint8_t)nAppliedRetries) {
        nAppliedRetries = (uint8_t)stTimingConfig.NRETRIES;
        if ((uint8_t)nAppliedRetries > 0) mb->retries((uint8_t)nAppliedRetries);
    }
    {
        uint32_t h = 2166136261u;
        h = mbb_fingerprint(h, stIdentityConfig.SVENDOR.c_str(), stIdentityConfig.SVENDOR.length());
        h = mbb_fingerprint(h, "|", 1);
        h = mbb_fingerprint(h, stIdentityConfig.SPRODUCT.c_str(), stIdentityConfig.SPRODUCT.length());
        h = mbb_fingerprint(h, "|", 1);
        h = mbb_fingerprint(h, stIdentityConfig.SREVISION.c_str(), stIdentityConfig.SREVISION.length());
        if (h != (uint32_t)nIdentityKey) {
            nIdentityKey = h;
            if (stIdentityConfig.SVENDOR.length() > 0 || stIdentityConfig.SPRODUCT.length() > 0 ||
                stIdentityConfig.SREVISION.length() > 0) {
                mb->identity(stIdentityConfig.SVENDOR.c_str(), stIdentityConfig.SPRODUCT.c_str(),
                             stIdentityConfig.SREVISION.c_str());
            }
        }
    }

    // Once per call, from the block that owns the link: transmitting,
    // receiving, retrying and timing out happen here and nowhere else.
    mb->poll();

    bConnected = mb->connected();
    nClients = (int16_t)mb->clients();   // 0 on a serial line, which has a bus

    // A link open with nobody at the other end - a TCP client whose device
    // refused or dropped the connection - is LinkDown, in the operating
    // system's words, while it retries. Then the last failing method call,
    // then an input this target does not use.
    bError = false;
    eErrorId = strucpp::E_MODBUSRESULT::OK;
    sLastError = "";
    if (!(bool)bConnected) {
        const char* why = mb->lastError();
        fail(strucpp::E_MODBUSRESULT::LINKDOWN, (why && why[0]) ? why : "not connected");
    } else if (const MbbMethods* calls = (const MbbMethods*)(uintptr_t)(strucpp::XWORD_t)nMethods) {
        if (!calls->failKey.empty()) {
            bError = true;
            eErrorId = static_cast<strucpp::E_MODBUSRESULT>(calls->failResult);
            sLastError = calls->failText.c_str();
        }
    }
#if defined(MODBUS_PLATFORM_HOST)
    // Every input is used: what only a board has is reported on the Runtime,
    // never silently ignored.
    if (stNetworkConfig.SSSID.length() > 0 || stNetworkConfig.SMAC.length() > 0 ||
        stNetworkConfig.SIP.length() > 0) {
        fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT,
             "stNetworkConfig is for a board; the Runtime uses its machine's network");
    } else if ((uint8_t)stSerialConfig.NUART != 0 || (int16_t)stSerialConfig.NRXPIN != -1 ||
               (int16_t)stSerialConfig.NTXPIN != -1 || (int16_t)stSerialConfig.NDEPIN != -1) {
        fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT,
             "stSerialConfig nUart and the pins are a board's; the Runtime takes sDevice");
    }
#else
    if (stSerialConfig.SDEVICE.length() > 0) {
        fail(strucpp::E_MODBUSRESULT::INVALIDARGUMENT,
             "stSerialConfig.sDevice is the Runtime's; a board takes nUart");
    }
#endif
}

// =============================================================================
// THE METHODS
// =============================================================================
//
// Each runs in the node's task and is refused in any other. The record is found
// first, so a call that cannot start yet still keeps its record.

namespace {

// The shared shape of every request: the edge, the conclusion, Queued while
// busy, the outcome frozen until the next edge, and LinkDown at an edge with no
// link. `start` validates and submits; it returns what the library said.
template <typename Start>
strucpp::E_MODBUSRESULT mbb_request(MbbRecord* r, bool execute, bool linkUp, Start start) {
    const bool rising = execute && !r->lastExecute;
    r->lastExecute = execute;
    if (r->pending && r->concluded) {
        r->pending = false;
        r->result = mbb_result((ModbusResult)r->outcome);
    }
    if (!rising || r->pending) return r->result;
    if (!linkUp) {
        r->result = strucpp::E_MODBUSRESULT::LINKDOWN;
        return r->result;
    }
    r->seq++;
    r->concluded = false;
    const ModbusResult asked = start();
    if (!mb_accepted(asked)) {
        // Refused before the wire. Its handler still runs on the next poll; a
        // new start number keeps that from concluding anything.
        r->seq++;
        r->result = mbb_result(asked);
        return r->result;
    }
    r->pending = true;
    r->result = strucpp::E_MODBUSRESULT::QUEUED;
    return r->result;
}

}  // namespace

// The link a method may use: open and with a peer.
#define MBB_LINK() ((ModbusAPI*)(uintptr_t)(strucpp::XWORD_t)nApi)
#define MBB_UP() ((bool)bLinkUp && (bool)bConnected && MBB_LINK() != nullptr)

// The four reads share one body: bits or registers, and the wide types.
static ModbusResult mbb_startRead(ModbusAPI* mb, ModbusTable table, const strucpp::IEC_ANY& any,
                                  uint8_t unit, uint16_t address, uint16_t asked,
                                  ModbusOrder order, MbbRecord* r) {
    const int32_t count = mbb_countOf(any, asked);
    const uint8_t bits = mbb_elementBits((uint32_t)any.ELEMCLASS);
    // A zeroed descriptor reads as TYPE_BOOL (class 0), so an unwired pin is
    // caught by its storage, not its type.
    if (count <= 0 || count > 0xFFFF || bits == 0 || any.PVALUE == nullptr ||
        mb_tableIsBits(table) != (bits == 1)) {
        return ModbusResult::InvalidArgument;
    }
    // Each element carries its forced state beside its value, so they are not
    // adjacent: the protocol is given the gap and fills them in place.
    const uint16_t stride = (uint16_t)any.DISTRIDE;
    const uint16_t many = (uint16_t)count;
    ModbusClient& c = mb->client();
    if (bits == 1) {
        return table == ModbusTable::Coil
            ? c.readCoils(unit, address, (bool*)any.PVALUE, many, mbb_handlerFor(r), stride)
            : c.readDiscreteInputs(unit, address, (bool*)any.PVALUE, many, mbb_handlerFor(r), stride);
    }
    if (bits == 16) {
        return table == ModbusTable::HoldingRegister
            ? c.readHoldingRegisters(unit, address, (uint16_t*)any.PVALUE, many, mbb_handlerFor(r), stride)
            : c.readInputRegisters(unit, address, (uint16_t*)any.PVALUE, many, mbb_handlerFor(r), stride);
    }
    return c.readWideArray(unit, address, any.PVALUE, mbb_wideTypeOfClass((uint32_t)any.ELEMCLASS),
                           order, many, stride, mbb_handlerFor(r), table);
}

static char* mbb_where(char* out, size_t size, uint8_t unit, uint16_t address) {
    snprintf(out, size, "%u.%u", (unsigned)unit, (unsigned)address);
    return out;
}

strucpp::E_MODBUSRESULT ReadCoils()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_READ_COILS, &anyData, "");
    if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
    const strucpp::E_MODBUSRESULT result = mbb_request(r, (bool)bExecute, MBB_UP(), [&]() {
        return mbb_startRead(MBB_LINK(), ModbusTable::Coil, anyData, (uint8_t)nUnitId,
                             (uint16_t)nAddress, (uint16_t)nQuantity, ModbusOrder::ABCD, r);
    });
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "ReadCoils", r, result);
}

strucpp::E_MODBUSRESULT ReadDiscreteInputs()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_READ_INPUTS, &anyData, "");
    if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
    const strucpp::E_MODBUSRESULT result = mbb_request(r, (bool)bExecute, MBB_UP(), [&]() {
        return mbb_startRead(MBB_LINK(), ModbusTable::DiscreteInput, anyData, (uint8_t)nUnitId,
                             (uint16_t)nAddress, (uint16_t)nQuantity, ModbusOrder::ABCD, r);
    });
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "ReadDiscreteInputs", r, result);
}

strucpp::E_MODBUSRESULT ReadHoldingRegisters()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_READ_HOLDING, &anyData, "");
    if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
    const strucpp::E_MODBUSRESULT result = mbb_request(r, (bool)bExecute, MBB_UP(), [&]() {
        return mbb_startRead(MBB_LINK(), ModbusTable::HoldingRegister, anyData, (uint8_t)nUnitId,
                             (uint16_t)nAddress, (uint16_t)nQuantity,
                             (ModbusOrder)(int)(strucpp::E_MODBUSORDER)eOrder, r);
    });
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "ReadHoldingRegisters", r, result);
}

strucpp::E_MODBUSRESULT ReadInputRegisters()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_READ_INPUT_REGS, &anyData, "");
    if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
    const strucpp::E_MODBUSRESULT result = mbb_request(r, (bool)bExecute, MBB_UP(), [&]() {
        return mbb_startRead(MBB_LINK(), ModbusTable::InputRegister, anyData, (uint8_t)nUnitId,
                             (uint16_t)nAddress, (uint16_t)nQuantity,
                             (ModbusOrder)(int)(strucpp::E_MODBUSORDER)eOrder, r);
    });
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "ReadInputRegisters", r, result);
}

strucpp::E_MODBUSRESULT WriteSingleCoil()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    char where[16];
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_WRITE_COIL, nullptr,
                                mbb_where(where, sizeof where, (uint8_t)nUnitId, (uint16_t)nAddress));
    if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
    const strucpp::E_MODBUSRESULT result = mbb_request(r, (bool)bExecute, MBB_UP(), [&]() {
        return MBB_LINK()->client().writeCoil((uint8_t)nUnitId, (uint16_t)nAddress, (bool)bValue,
                                              mbb_handlerFor(r));
    });
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "WriteSingleCoil", r, result);
}

strucpp::E_MODBUSRESULT WriteSingleRegister()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    char where[16];
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_WRITE_REGISTER, nullptr,
                                mbb_where(where, sizeof where, (uint8_t)nUnitId, (uint16_t)nAddress));
    if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
    const strucpp::E_MODBUSRESULT result = mbb_request(r, (bool)bExecute, MBB_UP(), [&]() {
        return MBB_LINK()->client().writeRegister((uint8_t)nUnitId, (uint16_t)nAddress,
                                                  (uint16_t)nValue, mbb_handlerFor(r));
    });
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "WriteSingleRegister", r, result);
}

strucpp::E_MODBUSRESULT WriteMultipleCoils()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    char where[16];
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_WRITE_COILS, &anyData,
                                mbb_where(where, sizeof where, (uint8_t)nUnitId, (uint16_t)nAddress));
    if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
    const strucpp::E_MODBUSRESULT result = mbb_request(r, (bool)bExecute, MBB_UP(), [&]() {
        const int32_t count = mbb_countOf(anyData, (uint16_t)nQuantity);
        if (count <= 0 || count > 0xFFFF || anyData.PVALUE == nullptr ||
            mbb_elementBits((uint32_t)anyData.ELEMCLASS) != 1) {
            return ModbusResult::InvalidArgument;
        }
        // Copied now: a write never points back at the caller.
        return MBB_LINK()->client().writeCoils((uint8_t)nUnitId, (uint16_t)nAddress,
                                               (const bool*)anyData.PVALUE, (uint16_t)count,
                                               mbb_handlerFor(r), (uint16_t)anyData.DISTRIDE);
    });
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "WriteMultipleCoils", r, result);
}

strucpp::E_MODBUSRESULT WriteMultipleRegisters()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    char where[16];
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_WRITE_REGISTERS, &anyData,
                                mbb_where(where, sizeof where, (uint8_t)nUnitId, (uint16_t)nAddress));
    if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
    const strucpp::E_MODBUSRESULT result = mbb_request(r, (bool)bExecute, MBB_UP(), [&]() {
        const int32_t count = mbb_countOf(anyData, (uint16_t)nQuantity);
        const uint8_t bits = mbb_elementBits((uint32_t)anyData.ELEMCLASS);
        if (count <= 0 || count > 0xFFFF || anyData.PVALUE == nullptr || bits < 16) {
            return ModbusResult::InvalidArgument;
        }
        const uint16_t stride = (uint16_t)anyData.DISTRIDE;
        if (bits == 16) {
            return MBB_LINK()->client().writeRegisters((uint8_t)nUnitId, (uint16_t)nAddress,
                                                       (const uint16_t*)anyData.PVALUE,
                                                       (uint16_t)count, mbb_handlerFor(r), stride);
        }
        // Wider than a register: packed and sent as ONE request whatever the
        // count, so values that only mean anything together cannot half-arrive.
        return MBB_LINK()->client().writeWideArray(
            (uint8_t)nUnitId, (uint16_t)nAddress, anyData.PVALUE,
            mbb_wideTypeOfClass((uint32_t)anyData.ELEMCLASS),
            (ModbusOrder)(int)(strucpp::E_MODBUSORDER)eOrder, (uint16_t)count, stride, mbb_handlerFor(r));
    });
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "WriteMultipleRegisters", r, result);
}

strucpp::E_MODBUSRESULT MaskWriteRegister()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    char where[16];
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_MASK_WRITE, nullptr,
                                mbb_where(where, sizeof where, (uint8_t)nUnitId, (uint16_t)nAddress));
    if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
    const strucpp::E_MODBUSRESULT result = mbb_request(r, (bool)bExecute, MBB_UP(), [&]() {
        return MBB_LINK()->client().maskWriteRegister((uint8_t)nUnitId, (uint16_t)nAddress,
                                                      (uint16_t)nAndMask, (uint16_t)nOrMask,
                                                      mbb_handlerFor(r));
    });
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "MaskWriteRegister", r, result);
}

strucpp::E_MODBUSRESULT ReadWriteMultipleRegisters()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    char where[16];
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_READ_WRITE, &anyReadData,
                                mbb_where(where, sizeof where, (uint8_t)nUnitId, (uint16_t)nReadAddress));
    if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
    const strucpp::E_MODBUSRESULT result = mbb_request(r, (bool)bExecute, MBB_UP(), [&]() {
        const int32_t reads = mbb_countOf(anyReadData, (uint16_t)nReadQuantity);
        const int32_t writes = mbb_countOf(anyWriteData, (uint16_t)nWriteQuantity);
        // The function carries registers only: at most 125 read and 121
        // written, which the library checks.
        if (reads <= 0 || writes <= 0 || reads > 125 || writes > 121 ||
            anyReadData.PVALUE == nullptr || anyWriteData.PVALUE == nullptr ||
            mbb_elementBits((uint32_t)anyReadData.ELEMCLASS) != 16 ||
            mbb_elementBits((uint32_t)anyWriteData.ELEMCLASS) != 16) {
            return ModbusResult::InvalidArgument;
        }
        // The library takes packed registers both ways, and an IEC array is
        // not packed: the write is gathered here (copied now, as every write),
        // the reply lands in the record and is spread into the variable when
        // it arrives.
        if (r->bounce == nullptr) {
            r->bounce = new (std::nothrow) uint16_t[125];
            if (r->bounce == nullptr) return ModbusResult::QueueFull;
        }
        uint16_t values[121];
        const uint16_t writeStride = (uint16_t)anyWriteData.DISTRIDE;
        for (int32_t i = 0; i < writes; i++) {
            values[i] = *(const uint16_t*)(anyWriteData.PVALUE + (size_t)i * writeStride);
        }
        r->bounceCount = (uint16_t)reads;
        r->readDest = anyReadData.PVALUE;
        r->readStride = (uint16_t)anyReadData.DISTRIDE;
        return MBB_LINK()->client().readWriteRegisters(
            (uint8_t)nUnitId, (uint16_t)nReadAddress, r->bounce, (uint16_t)reads,
            (uint16_t)nWriteAddress, values, (uint16_t)writes, mbb_handlerFor(r));
    });
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "ReadWriteMultipleRegisters", r, result);
}

strucpp::E_MODBUSRESULT Watch()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_WATCH, &anyData, "");
    const strucpp::E_MODBUSRESULT result = [&]() -> strucpp::E_MODBUSRESULT {
        if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
        ModbusAPI* mb = MBB_LINK();
        if (mb == nullptr || !(bool)bLinkUp) {
            eQuality = strucpp::E_MODBUSQUALITY::UNKNOWN;
            return strucpp::E_MODBUSRESULT::LINKDOWN;
        }
        const int32_t periodMs = mbb_millisOf(tPeriod);
        const mb_time_t interval = periodMs > 0 ? (mb_time_t)periodMs : 1000u;
        const ModbusTable table = (ModbusTable)(int)(strucpp::E_MODBUSTABLE)eTable;
        const ModbusOrder order = (ModbusOrder)(int)(strucpp::E_MODBUSORDER)eOrder;

        if (r->index == 0) {
            const int32_t count = mbb_countOf(anyData, (uint16_t)nQuantity);
            const uint8_t bits = mbb_elementBits((uint32_t)anyData.ELEMCLASS);
            if (count <= 0 || count > 0xFFFF || bits == 0 || anyData.PVALUE == nullptr ||
                mb_tableIsBits(table) != (bits == 1)) {
                return strucpp::E_MODBUSRESULT::INVALIDARGUMENT;
            }
            const uint16_t stride = (uint16_t)anyData.DISTRIDE;
            const uint16_t many = (uint16_t)count;
            const uint8_t unit = (uint8_t)nUnitId;
            const uint16_t first = (uint16_t)nAddress;
            size_t made;
            if (bits == 1) {
                made = mb->poller().addBits(unit, first, (bool*)anyData.PVALUE, many, interval,
                                            table, stride);
            } else if (bits == 16) {
                made = mb->poller().addRegisters(unit, first, (uint16_t*)anyData.PVALUE, many,
                                                 interval, table, stride);
            } else {
                made = mb->poller().addWide(unit, first, anyData.PVALUE,
                                            mbb_wideTypeOfClass((uint32_t)anyData.ELEMCLASS),
                                            many, interval, order, table, stride);
            }
            if (made == (size_t)-1) return strucpp::E_MODBUSRESULT::INVALIDARGUMENT;
            r->index = made + 1;
            r->storage = anyData.PVALUE;
            r->running = true;
            r->interval = (int32_t)interval;
            r->deadband = (uint16_t)nDeadband;
            r->unit = unit;
            r->table = (uint8_t)table;
            r->address = first;
            r->order = (uint8_t)order;
            if (r->deadband > 0) mb->poller().setDeadband(made, r->deadband);
        }
        const size_t poll = r->index - 1;

        // A variable that moved would leave the poller writing where nothing
        // reads: stopped and refused.
        if (anyData.PVALUE != r->storage) {
            if (r->running) mb->poller().remove(poll);
            r->running = false;
            return strucpp::E_MODBUSRESULT::INVALIDARGUMENT;
        }
        // Stopped and started in place, never added again.
        const bool want = (bool)bEnable;
        if (want != r->running) {
            r->running = want;
            if (want) mb->poller().resume(poll);
            else mb->poller().remove(poll);
        }
        // The address follows the inputs: the same entry is re-aimed and
        // starts again from Unknown. The size stays the first call's.
        if ((uint8_t)nUnitId != r->unit || (uint8_t)table != r->table ||
            (uint16_t)nAddress != r->address || (uint8_t)order != r->order) {
            if (!mb->poller().retarget(poll, (uint8_t)nUnitId, (uint16_t)nAddress, table, order)) {
                // Bits asked of a register variable, or the reverse.
                return strucpp::E_MODBUSRESULT::INVALIDARGUMENT;
            }
            r->unit = (uint8_t)nUnitId;
            r->table = (uint8_t)table;
            r->address = (uint16_t)nAddress;
            r->order = (uint8_t)order;
        }
        if ((int32_t)interval != r->interval) {
            r->interval = (int32_t)interval;
            mb->poller().setInterval(poll, interval);
        }
        if ((uint16_t)nDeadband != r->deadband) {
            r->deadband = (uint16_t)nDeadband;
            mb->poller().setDeadband(poll, r->deadband);
        }

        eQuality = (strucpp::E_MODBUSQUALITY)(int32_t)(int)mb->poller().quality(poll);
        const mb_time_t age = mb->poller().age(poll);
        tAge = mbb_timeOf(age == ModbusPoller::NEVER ? 0 : (int32_t)age);
        bSeen = (age != ModbusPoller::NEVER);
        nFailures = (uint16_t)mb->poller().consecutiveFailures(poll);
        if (!r->running) return strucpp::E_MODBUSRESULT::OK;
        return mbb_result(mb->poller().lastResult(poll));
    }();
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "Watch", r, result);
}

// One point's settings as the library takes them.
static ModbusPointConfig mbb_pointConfig(uint8_t unit, int fc, uint16_t address, int type,
                                         int order, uint8_t bit, float scale, float offset,
                                         int32_t everyMs, int32_t staleMs, int32_t timeoutMs,
                                         bool enabled)
{
    ModbusPointConfig c;
    c.unit = unit;
    c.fc = (ModbusPointFc)(uint8_t)fc;
    c.address = address;
    c.type = (ModbusPointType)(uint8_t)type;
    c.order = (ModbusOrder)(uint8_t)order;
    c.bit = bit;
    c.scale = scale;
    c.offset = offset;
    c.everyMs = everyMs > 0 ? (mb_time_t)everyMs : 1000u;
    c.staleMs = staleMs > 0 ? (mb_time_t)staleMs : 0u;
    c.timeoutMs = timeoutMs > 0 ? (mb_time_t)timeoutMs : 0u;
    c.enabled = enabled;
    return c;
}

// Configures a point; false when the settings cannot work. A moved unit
// timeout is re-applied across the set.
static bool mbb_pointApply(ModbusAPI* mb, ModbusPoint* point, const ModbusPointConfig& wanted)
{
    const bool timeoutMoved = point->config().timeoutMs != wanted.timeoutMs ||
                              (wanted.timeoutMs != 0 && point->config().unit != wanted.unit);
    point->configure(wanted);
    if (timeoutMoved) mb->points().timeoutsChanged();
    return point->lastResult() != ModbusResult::InvalidArgument;
}

static bool mbb_isWritePoint(int fc) {
    return fc >= (int)ModbusPointFc::WriteCoil;
}

strucpp::E_MODBUSRESULT Point()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_POINT, &anyValue, "");
    const strucpp::E_MODBUSRESULT result = [&]() -> strucpp::E_MODBUSRESULT {
        if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
        bOk = false;
        ModbusAPI* mb = MBB_LINK();
        if (mb == nullptr || !(bool)bLinkUp) {
            eQuality = strucpp::E_MODBUSQUALITY::UNKNOWN;
            return strucpp::E_MODBUSRESULT::LINKDOWN;
        }
        double now = 0.0;
        if (!mbb_numberOf(anyValue, now)) return strucpp::E_MODBUSRESULT::INVALIDARGUMENT;
        if (r->index == 0) {
            const size_t made = mb->points().add(1);
            if (made == (size_t)-1) return strucpp::E_MODBUSRESULT::QUEUEFULL;
            r->index = made + 1;
        }
        ModbusPoint* point = mb->points().at(r->index - 1);
        if (point == nullptr) return strucpp::E_MODBUSRESULT::NOTINITIALISED;

        const int fc = (int)(strucpp::E_MODBUSPOINTFUNCTION)eFunction;
        const ModbusPointConfig wanted = mbb_pointConfig(
            (uint8_t)nUnitId, fc, (uint16_t)nAddress, (int)(strucpp::E_MODBUSPOINTTYPE)eType,
            (int)(strucpp::E_MODBUSORDER)eOrder, (uint8_t)nBit, (float)fScale, (float)fOffset,
            mbb_millisOf(tPeriod), mbb_millisOf(tStale), mbb_millisOf(tTimeout), (bool)bEnable);
        const bool valid = mbb_pointApply(mb, point, wanted);
        // A write point sends the variable; a read point fills it once the
        // device has answered, and holds the last good value after.
        if (mbb_isWritePoint(fc)) point->setWriteValue(now);
        else if (point->everGood()) mbb_storeNumber(anyValue, point->value());

        const mb_time_t t = mb_millis();
        eQuality = (strucpp::E_MODBUSQUALITY)(int32_t)(int)((bool)bEnable ? point->quality(t)
                                                                 : ModbusQuality::Unknown);
        bOk = valid && (bool)bEnable && point->ok(t);
        const mb_time_t age = point->age(t);
        tAge = mbb_timeOf(age == ModbusPoller::NEVER ? 0 : (int32_t)age);
        nFailures = point->failures();
        if (!valid) return strucpp::E_MODBUSRESULT::INVALIDARGUMENT;
        if (!(bool)bEnable) return strucpp::E_MODBUSRESULT::OK;
        return mbb_result(point->lastResult());
    }();
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "Point", r, result);
}

// An ARRAY OF that STRUCT, by its descriptor.
static bool mbb_isArrayOf(const strucpp::IEC_ANY& any, const char* type) {
    return any.PVALUE != nullptr && any.DICOUNT > 0 && any.TYPEDESC != nullptr &&
           any.TYPEDESC->NAME != nullptr && strcasecmp(any.TYPEDESC->NAME, type) == 0;
}

// The point tables are reached through their descriptors, member by name,
// never through the generated STRUCT types: a program that does not declare
// them gets no C++ type for them, and this file must still compile there.
namespace {
struct MbbMember {
    uint32_t offset = 0;
    uint32_t cls = 0;
    uint32_t bits = 0;
    bool found = false;
};
MbbMember mbb_member(const strucpp::TypeDesc* desc, const char* name) {
    MbbMember m;
    for (uint16_t i = 0; i < desc->MEMBERCOUNT; i++) {
        const strucpp::MemberDesc& d = desc->MEMBERS[i];
        if (d.NAME != nullptr && strcasecmp(d.NAME, name) == 0) {
            m.offset = d.BYTEOFFSET;
            m.cls = (uint32_t)d.TYPECLASS;
            m.bits = d.BITSIZE;
            m.found = true;
            break;
        }
    }
    return m;
}
double mbb_get(const uint8_t* row, const MbbMember& m) {
    double v = 0.0;
    if (m.found) mbb_readClass(m.cls, m.bits, row + m.offset, v);
    return v;
}
void mbb_set(uint8_t* row, const MbbMember& m, double v) {
    if (m.found) mbb_writeClass(m.cls, m.bits, row + m.offset, v);
}
int32_t mbb_getMs(const uint8_t* row, const MbbMember& m) {
    const double ns = mbb_get(row, m);
    if (ns <= 0) return 0;
    const double ms = (ns + 999999.0) / 1000000.0;
    return ms > 2147483647.0 ? 2147483647 : (int32_t)ms;
}
}  // namespace

strucpp::E_MODBUSRESULT Points()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_POINTS, &anySettings, "");
    const strucpp::E_MODBUSRESULT result = [&]() -> strucpp::E_MODBUSRESULT {
        if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
        if (!mbb_isArrayOf(anySettings, "ST_ModbusPointConfig") ||
            !mbb_isArrayOf(anyPoints, "ST_ModbusPointStatus")) {
            sStatusText = "not point tables";
            return strucpp::E_MODBUSRESULT::INVALIDARGUMENT;
        }
        const strucpp::TypeDesc* cd = anySettings.TYPEDESC;
        const strucpp::TypeDesc* sd = anyPoints.TYPEDESC;
        const MbbMember cUnit = mbb_member(cd, "nUnitId"), cFn = mbb_member(cd, "eFunction"),
                        cAddr = mbb_member(cd, "nAddress"), cType = mbb_member(cd, "eType"),
                        cOrder = mbb_member(cd, "eOrder"), cBit = mbb_member(cd, "nBit"),
                        cScale = mbb_member(cd, "fScale"), cOffset = mbb_member(cd, "fOffset"),
                        cPeriod = mbb_member(cd, "tPeriod"), cStale = mbb_member(cd, "tStale"),
                        cTimeout = mbb_member(cd, "tTimeout"), cEnable = mbb_member(cd, "bEnable");
        const MbbMember sWrite = mbb_member(sd, "fWriteValue"), sValue = mbb_member(sd, "fValue"),
                        sBit = mbb_member(sd, "bValue"), sOk = mbb_member(sd, "bOk"),
                        sQuality = mbb_member(sd, "eQuality"), sAge = mbb_member(sd, "tAge"),
                        sFailures = mbb_member(sd, "nFailures"), sResult = mbb_member(sd, "eResult");

        int64_t rows = anySettings.DICOUNT;
        if (anyPoints.DICOUNT < rows) rows = anyPoints.DICOUNT;

        ModbusAPI* mb = MBB_LINK();
        if (mb == nullptr || !(bool)bLinkUp) {
            for (int64_t k = 0; k < rows; k++) mbb_set(anyPoints.at((int32_t)k), sOk, 0.0);
            nGoodCnt = 0;
            nLostCnt = (int16_t)rows;
            nFirstLost = 0;
            sStatusText = "field bus down";
            return strucpp::E_MODBUSRESULT::LINKDOWN;
        }
        // One library point per row, made on the first call with the link up.
        if (r->index == 0 && rows > 0) {
            const size_t made = mb->points().add((size_t)rows);
            if (made == (size_t)-1) {
                sStatusText = "out of memory";
                return strucpp::E_MODBUSRESULT::QUEUEFULL;
            }
            r->index = made + 1;
            r->rows = (size_t)rows;
        }
        if ((int64_t)r->rows < rows) rows = (int64_t)r->rows;

        const mb_time_t now = mb_millis();
        int16_t good = 0, lost = 0;
        int64_t firstLost = -1;
        ModbusResult firstResult = ModbusResult::Ok;
        bool firstInvalid = false, firstNever = false;
        uint8_t firstUnit = 0;

        for (int64_t k = 0; k < rows; k++) {
            const uint8_t* cfg = anySettings.at((int32_t)k);
            uint8_t* sts = anyPoints.at((int32_t)k);
            ModbusPoint* point = mb->points().at(r->index - 1 + (size_t)k);
            if (point == nullptr) continue;
            const bool fitted = mbb_get(cfg, cEnable) != 0.0;
            const bool enabled = fitted && (bool)bEnable;
            const uint8_t unit = (uint8_t)mbb_get(cfg, cUnit);
            const ModbusPointConfig wanted = mbb_pointConfig(
                unit, (int)mbb_get(cfg, cFn), (uint16_t)mbb_get(cfg, cAddr), (int)mbb_get(cfg, cType),
                (int)mbb_get(cfg, cOrder), (uint8_t)mbb_get(cfg, cBit), (float)mbb_get(cfg, cScale),
                (float)mbb_get(cfg, cOffset), mbb_getMs(cfg, cPeriod), mbb_getMs(cfg, cStale),
                mbb_getMs(cfg, cTimeout), enabled);
            const bool valid = mbb_pointApply(mb, point, wanted);
            point->setWriteValue((double)(float)mbb_get(sts, sWrite));

            const ModbusQuality quality = enabled ? point->quality(now) : ModbusQuality::Unknown;
            const bool ok = valid && enabled && point->ok(now);
            mbb_set(sts, sQuality, (double)(int)quality);
            mbb_set(sts, sOk, ok ? 1.0 : 0.0);
            mbb_set(sts, sValue, (double)(float)point->value());
            mbb_set(sts, sBit, point->asBit() ? 1.0 : 0.0);
            const mb_time_t age = point->age(now);
            mbb_set(sts, sAge, age == ModbusPoller::NEVER ? 0.0 : (double)age * 1000000.0);
            mbb_set(sts, sFailures, (double)point->failures());
            const ModbusResult last = valid ? point->lastResult() : ModbusResult::InvalidArgument;
            mbb_set(sts, sResult, (double)(int)last);

            if (!fitted) continue;   // not fitted: neither good nor lost
            if (ok) {
                good++;
            } else {
                lost++;
                if (firstLost < 0) {
                    firstLost = k + 1;   // a row number from 1: 0 is none
                    firstResult = last;
                    firstInvalid = !valid;
                    firstNever = !point->everGood();
                    firstUnit = unit;
                }
            }
        }
        nGoodCnt = good;
        nLostCnt = lost;
        nFirstLost = firstLost > 0 ? (int16_t)firstLost : 0;

        // One short line for a panel; the codes are in each row.
        char text[31];
        if (anyPoints.DICOUNT != anySettings.DICOUNT) {
            snprintf(text, sizeof text, "tables differ");
        } else if (firstLost < 0) {
            text[0] = '\0';
        } else if (firstInvalid) {
            snprintf(text, sizeof text, "pt %d bad settings", (int)firstLost);
        } else if (!(bool)bEnable) {
            snprintf(text, sizeof text, "stopped");
        } else if (firstNever) {
            snprintf(text, sizeof text, "pt %d unit %u no answer", (int)firstLost, (unsigned)firstUnit);
        } else {
            snprintf(text, sizeof text, "pt %d unit %u lost", (int)firstLost, (unsigned)firstUnit);
        }
        sStatusText = text;
        if (firstLost < 0) return strucpp::E_MODBUSRESULT::OK;
        return firstInvalid ? strucpp::E_MODBUSRESULT::INVALIDARGUMENT : mbb_result(firstResult);
    }();
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "Points", r, result);
}

// One object out of a function code 43 response, bounded by what arrived
// rather than by what the device claims. The decoder strips the function code
// and the MEI type; one that keeps the MEI type (0x0E, where a read-device-id
// code is only ever 1 to 4) is read too.
static void mbb_identityObject(const uint8_t* data, uint16_t length, uint8_t wanted,
                               std::string& out)
{
    out.clear();
    if (!data || length < 6) return;
    uint16_t at = (data[0] == 0x0E) ? 1 : 0;
    if ((uint16_t)(at + 5) > length) return;
    uint16_t objects = data[at + 4];
    at = (uint16_t)(at + 5);
    while (objects-- > 0) {
        if ((uint16_t)(at + 2) > length) return;
        const uint8_t id = data[at];
        const uint8_t len = data[at + 1];
        at = (uint16_t)(at + 2);
        if ((uint32_t)at + len > length) return;
        if (id == wanted) {
            out.assign((const char*)data + at, len > 32 ? 32 : len);
            return;
        }
        at = (uint16_t)(at + len);
    }
}

#define MBB_NAMEPLATE_BYTES 128

strucpp::E_MODBUSRESULT ReadDeviceIdentification()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    char where[8];
    snprintf(where, sizeof where, "%u", (unsigned)(uint8_t)nUnitId);
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_IDENTIFY, nullptr, where);
    if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
    // Its completion is the record's own handler, never a status() by unit and
    // address: function code 43 has no address, and a read of coil 0 on the
    // same unit would answer the same question.
    const bool wasPending = r->pending;
    const strucpp::E_MODBUSRESULT result = mbb_request(r, (bool)bExecute, MBB_UP(), [&]() {
        if (r->reply == nullptr) {
            r->reply = new (std::nothrow) uint8_t[MBB_NAMEPLATE_BYTES];
            if (r->reply == nullptr) return ModbusResult::QueueFull;
        }
        memset(r->reply, 0, MBB_NAMEPLATE_BYTES);
        r->vendor.clear();
        r->product.clear();
        r->revision.clear();
        return MBB_LINK()->readDeviceId((uint8_t)nUnitId, r->reply, MBB_NAMEPLATE_BYTES,
                                        mbb_handlerFor(r));
    });
    if (wasPending && !r->pending && result == strucpp::E_MODBUSRESULT::OK && r->reply != nullptr) {
        mbb_identityObject(r->reply, MBB_NAMEPLATE_BYTES, 0x00, r->vendor);
        mbb_identityObject(r->reply, MBB_NAMEPLATE_BYTES, 0x01, r->product);
        mbb_identityObject(r->reply, MBB_NAMEPLATE_BYTES, 0x02, r->revision);
    }
    sVendor = r->vendor.c_str();
    sProduct = r->product.c_str();
    sRevision = r->revision.c_str();
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "ReadDeviceIdentification", r, result);
}

strucpp::E_MODBUSRESULT Device()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    char where[8];
    snprintf(where, sizeof where, "%u", (unsigned)(uint8_t)nUnitId);
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_DEVICE, nullptr, where);
    const strucpp::E_MODBUSRESULT result = [&]() -> strucpp::E_MODBUSRESULT {
        if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
        ModbusAPI* mb = MBB_LINK();
        if (mb == nullptr || !(bool)bLinkUp) {
            bAnswering = false;
            return strucpp::E_MODBUSRESULT::LINKDOWN;
        }
        const uint8_t unit = (uint8_t)nUnitId;
        // Read off the traffic already happening: a screen of these puts
        // nothing extra on the bus.
        const mb_time_t goneMs = mbb_millisOf(tGone) > 0 ? (mb_time_t)mbb_millisOf(tGone) : 5000u;
        const mb_time_t silence = mb->silenceFor(unit);
        if (silence == MB_NEVER_HEARD) {
            tSilent = mbb_timeOf(0);
            bSeen = false;
            bAnswering = false;
        } else {
            tSilent = mbb_timeOf((int32_t)silence);
            bSeen = true;
            bAnswering = silence <= goneMs;
        }
        tRoundTrip = mbb_timeOf((int32_t)mb->roundTrip(unit));
        // The link test, for a device nothing else talks to. Refused as a
        // duplicate while one is out, so a short tPoll cannot stack them.
        const int32_t pollEvery = mbb_millisOf(tPoll);
        if (pollEvery > 0) {
            const mb_time_t now = mb_millis();
            if (!r->polling || (int32_t)(now - (mb_time_t)(uint32_t)r->nextPoll) >= 0) {
                r->polling = true;
                r->nextPoll = (int32_t)(uint32_t)(now + (mb_time_t)pollEvery);
                mb->ping(unit);
            }
        }
        return strucpp::E_MODBUSRESULT::OK;
    }();
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "Device", r, result);
}

strucpp::E_MODBUSRESULT Map()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    // Before anything else: the node opens a scan after it first runs, and
    // needs the server half by then.
    nServe = (strucpp::XWORD_t)(uintptr_t)&mbb_serve;
    MbbRecord* r = mbb_recordOf(mbb_methodsOf(nMethods), MBB_MAP, &anyData, "");
    const strucpp::E_MODBUSRESULT result = [&]() -> strucpp::E_MODBUSRESULT {
        bWritten = false;
        bSafeApplied = false;
        if (r == nullptr) return strucpp::E_MODBUSRESULT::QUEUEFULL;
        ModbusAPI* mb = MBB_LINK();
        // A binding into a link that never opened is a map nothing serves.
        if (mb == nullptr || !(bool)bLinkUp) return strucpp::E_MODBUSRESULT::LINKDOWN;

        const ModbusTable table = (ModbusTable)(int)(strucpp::E_MODBUSTABLE)eTable;
        const uint16_t first = (uint16_t)nAddress;
        const int32_t count = anyData.DICOUNT;
        if (!r->bound) {
            const uint8_t bits = mbb_elementBits((uint32_t)anyData.ELEMCLASS);
            // Zero-copy: the register IS the variable. A REAL is four bytes in
            // a layout an order would rearrange, and rearranging is a copy a
            // client could read torn - so 1 and 16 bits only.
            if (count <= 0 || count > 0xFFFF || anyData.PVALUE == nullptr ||
                (bits != 1 && bits != 16) || mb_tableIsBits(table) != (bits == 1)) {
                return strucpp::E_MODBUSRESULT::INVALIDARGUMENT;
            }
            const uint16_t stride = (uint16_t)anyData.DISTRIDE;
            const bool ok = (bits == 1)
                ? mb->map().bindBlock(table, first, (bool*)anyData.PVALUE, (uint16_t)count, stride)
                : mb->map().bindBlock(table, first, (uint16_t*)anyData.PVALUE, (uint16_t)count, stride);
            if (!ok) return strucpp::E_MODBUSRESULT::INVALIDARGUMENT;
            // A safe state is per address, on a writable table; a range has no
            // single safe value, so it is never guessed.
            const bool reset = (strucpp::E_MODBUSFAILSAFE)eOnLoss == strucpp::E_MODBUSFAILSAFE::RESETTOVALUE;
            if (reset && count == 1 && mb_tableIsWritable(table)) {
                if (bits == 1) mb->failsafeCoil(first, (int32_t)nSafeValue != 0);
                else mb->failsafeHreg(first, (uint16_t)(int32_t)nSafeValue);
            }
            r->storage = anyData.PVALUE;
            r->table = (uint8_t)table;
            r->address = first;
            r->seenWrites = mb->map().bindingWrites(table, first);
            r->seenFailsafe = mb->map().failsafeCount(table, first);
            r->bound = true;
        }
        // A binding is made once: a variable that moved, or a new place, is
        // refused rather than served from where nothing looks.
        if (anyData.PVALUE != r->storage || (uint8_t)table != r->table || first != r->address) {
            return strucpp::E_MODBUSRESULT::INVALIDARGUMENT;
        }
        // The node counts a client's writes and every drive to a safe state;
        // each record keeps what it last saw, so two maps never take each
        // other's edges.
        const uint32_t writes = mb->map().bindingWrites(table, first);
        const uint16_t safed = mb->map().failsafeCount(table, first);
        bWritten = writes != r->seenWrites;
        bSafeApplied = safed != r->seenFailsafe;
        r->seenWrites = writes;
        r->seenFailsafe = safed;
        return strucpp::E_MODBUSRESULT::OK;
    }();
    return mbb_noteCall((strucpp::XWORD_t)nMethods, "Map", r, result);
}

strucpp::E_MODBUSRESULT Statistics()
{
    if (!mbb_inTask((strucpp::XWORD_t)nTask)) return strucpp::E_MODBUSRESULT::WRONGTASK;
    ModbusAPI* mb = MBB_LINK();
    const bool reset = (bool)bReset && !(bool)bResetSeen;
    bResetSeen = (bool)bReset;
    if (mb == nullptr) return strucpp::E_MODBUSRESULT::LINKDOWN;
    if (reset) mb->resetStats();
    // Counted across outages: a reconnect count is worth reading most while
    // the link is down.
    nPending = (int16_t)mb->pending();
    const ModbusLinkStats stats = mb->stats();
    nSent = (int32_t)stats.framesSent;
    nReceived = (int32_t)stats.framesReceived;
    nChecksumErrors = (int32_t)stats.checksumErrors;
    nFramingErrors = (int32_t)stats.framingErrors;
    nNoiseBytes = (int32_t)stats.noiseBytes;
    nReconnects = (int32_t)mb->reconnects();
    sFramingReason = mb->framingReason();
    return (bool)bLinkUp ? strucpp::E_MODBUSRESULT::OK : strucpp::E_MODBUSRESULT::LINKDOWN;
}

END_FUNCTION_BLOCK
