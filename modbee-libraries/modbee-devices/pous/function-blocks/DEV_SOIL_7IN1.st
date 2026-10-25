(* DEV_SOIL_7IN1 - a 7-in-1 RS485 soil sensor on Modbus RTU: moisture,
temperature, conductivity (EC), pH, nitrogen, phosphorus and potassium.

Wire Node to a MODBUS_NODE on the sensor's RS485 line (client). The common
sensor's line settings: 9600 baud, 8 data bits, no parity, 1 stop bit -
SERIAL_PARITY := MODBUS_PARITY_NONE_8N1; factory address 1.

Data.map picks the register map; makers differ. JXCT (JXBS-3001, most
generic units) is the default; LINEAR is the 0x0000-0x0006 layout of some
other makers. A wrong map shows as 'No reply' (the sensor refuses the
addresses) or 'Bad data' (impossible values), never as plausible numbers.

Outputs: Moisture % (as the sensor reports it), Temperature degC (negative
below zero), Ec uS/cm, Ph, Nitrogen / Phosphorus / Potassium mg/kg. They hold
the last reading while Good is FALSE. Good: the sensor answers and every
value is plausible (moisture 0-100 %, temperature -40-80 degC, pH 0-14, EC
0-20000 uS/cm, N P K 0-2000 mg/kg).

Status (Data.status / statusText): Off, OK, Setup (unit not 1..247), No reply
(never answered: address, baud, wiring, map), Comms lost (answered before),
Bad data (check the map). *)

FUNCTION_BLOCK DEV_SOIL_7IN1
  VAR_IN_OUT
    Node : MODBUS_NODE; (* the RS485 line's node (client) *)
    Data : DEV_SOIL_DATA; (* settings and status *)
  END_VAR
  VAR_INPUT
    Enable : BOOL := TRUE; (* read the sensor *)
  END_VAR
  VAR_OUTPUT
    Good : BOOL; (* answering, every value plausible *)
    Moisture : REAL; (* % *)
    Temperature : REAL; (* degC *)
    Ec : REAL; (* uS/cm *)
    Ph : REAL;
    Nitrogen : REAL; (* mg/kg *)
    Phosphorus : REAL; (* mg/kg *)
    Potassium : REAL; (* mg/kg *)
  END_VAR
  VAR
    wPh : MODBUS_WATCH;
    wMt : MODBUS_WATCH;
    wEc : MODBUS_WATCH;
    wNpk : MODBUS_WATCH;
    wAll : MODBUS_WATCH;
    rPh : INT;
    rMt : ARRAY [0..1] OF INT;
    rEc : INT;
    rNpk : ARRAY [0..2] OF INT;
    rAll : ARRAY [0..6] OF INT;
    jxct : BOOL;
    unitOk : BOOL;
    every : TIME;
    seen : BOOL;
    answering : BOOL;
    plausible : BOOL;
    lastGood : TIME;
    started : BOOL;
  END_VAR


unitOk := Data.unit >= 1 AND Data.unit <= 247;
jxct := Data.map <> DEV_SOIL_LINEAR;
every := MAX(Data.every, T#1s);
wPh(NODE := Node, UNIT := Data.unit, FC := MODBUS_READ_FC#MODBUS_FC03_READ_HOLDING_REGISTERS, ADDRESS := 16#0006,
    EVERY := every, ENABLE := Enable AND unitOk AND jxct, VALUE := rPh);
wMt(NODE := Node, UNIT := Data.unit, FC := MODBUS_READ_FC#MODBUS_FC03_READ_HOLDING_REGISTERS, ADDRESS := 16#0012,
    EVERY := every, ENABLE := Enable AND unitOk AND jxct, VALUE := rMt);
wEc(NODE := Node, UNIT := Data.unit, FC := MODBUS_READ_FC#MODBUS_FC03_READ_HOLDING_REGISTERS, ADDRESS := 16#0015,
    EVERY := every, ENABLE := Enable AND unitOk AND jxct, VALUE := rEc);
wNpk(NODE := Node, UNIT := Data.unit, FC := MODBUS_READ_FC#MODBUS_FC03_READ_HOLDING_REGISTERS, ADDRESS := 16#001E,
     EVERY := every, ENABLE := Enable AND unitOk AND jxct, VALUE := rNpk);
wAll(NODE := Node, UNIT := Data.unit, FC := MODBUS_READ_FC#MODBUS_FC03_READ_HOLDING_REGISTERS, ADDRESS := 16#0000,
     EVERY := every, ENABLE := Enable AND unitOk AND NOT jxct, VALUE := rAll);

IF jxct THEN
  seen := wPh.SEEN AND wMt.SEEN AND wEc.SEEN AND wNpk.SEEN;
  answering := wPh.QUALITY = MODBUS_QUALITY#MODBUS_QUALITY_GOOD AND wMt.QUALITY = MODBUS_QUALITY#MODBUS_QUALITY_GOOD
               AND wEc.QUALITY = MODBUS_QUALITY#MODBUS_QUALITY_GOOD AND wNpk.QUALITY = MODBUS_QUALITY#MODBUS_QUALITY_GOOD;
  IF answering THEN
    Moisture := INT_TO_REAL(rMt[0]) / 10.0;
    Temperature := INT_TO_REAL(rMt[1]) / 10.0;          (* two's complement: below zero is negative *)
    Ec := INT_TO_REAL(rEc);
    Ph := INT_TO_REAL(rPh) / 100.0;
    Nitrogen := INT_TO_REAL(rNpk[0]);
    Phosphorus := INT_TO_REAL(rNpk[1]);
    Potassium := INT_TO_REAL(rNpk[2]);
  END_IF;
ELSE
  seen := wAll.SEEN;
  answering := wAll.QUALITY = MODBUS_QUALITY#MODBUS_QUALITY_GOOD;
  IF answering THEN
    Moisture := INT_TO_REAL(rAll[0]) / 10.0;
    Temperature := INT_TO_REAL(rAll[1]) / 10.0;
    Ec := INT_TO_REAL(rAll[2]);
    Ph := INT_TO_REAL(rAll[3]) / 10.0;
    Nitrogen := INT_TO_REAL(rAll[4]);
    Phosphorus := INT_TO_REAL(rAll[5]);
    Potassium := INT_TO_REAL(rAll[6]);
  END_IF;
END_IF;
IF Ec < 0.0 THEN
  Ec := Ec + 65536.0;                                   (* EC is unsigned *)
END_IF;
plausible := Moisture >= 0.0 AND Moisture <= 100.0 AND Temperature >= -40.0 AND Temperature <= 80.0
             AND Ph >= 0.0 AND Ph <= 14.0 AND Ec >= 0.0 AND Ec <= 20000.0
             AND Nitrogen >= 0.0 AND Nitrogen <= 2000.0 AND Phosphorus >= 0.0 AND Phosphorus <= 2000.0
             AND Potassium >= 0.0 AND Potassium <= 2000.0;

Good := Enable AND unitOk AND answering AND plausible;
IF NOT started OR Good THEN
  started := TRUE;
  lastGood := TIME();
END_IF;
Data.age := TIME() - lastGood;
IF NOT Enable THEN
  Data.status := DEV_ST_OFF;
  Data.statusText := 'Off';
ELSIF NOT unitOk THEN
  Data.status := DEV_ST_SETUP;
  Data.statusText := 'Setup: unit 1..247';
ELSIF Good THEN
  Data.status := DEV_ST_OK;
  Data.statusText := 'OK';
ELSIF answering THEN
  Data.status := DEV_ST_BAD_DATA;
  Data.statusText := 'Bad data: check the map';
ELSIF NOT seen THEN
  Data.status := DEV_ST_NO_REPLY;
  Data.statusText := 'No reply: address/baud/map';
ELSE
  Data.status := DEV_ST_LOST;
  Data.statusText := 'Comms lost';
END_IF;


END_FUNCTION_BLOCK