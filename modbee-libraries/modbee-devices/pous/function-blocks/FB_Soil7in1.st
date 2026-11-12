(* FB_Soil7in1 - a 7-in-1 RS485 soil sensor on Modbus RTU: moisture,
temperature, conductivity (EC), pH, nitrogen, phosphorus and potassium.

Wire fbNode to the FB_ModbusNode of the sensor's RS485 line (a client). The
common sensor's line settings: 9600 baud, 8 data bits, no parity, 1 stop bit;
factory address 1.

stData.eMap picks the register map; makers differ. Jxct (JXBS-3001, most
generic units) is the default; Linear is the 0x0000-0x0006 layout of some
other makers. A wrong map shows as 'No reply' (the sensor refuses the
addresses) or 'Bad data' (impossible values), never as plausible numbers.

Outputs: fMoisture % (as the sensor reports it), fTemperature degC (negative
below zero), fEc uS/cm, fPh, fNitrogen / fPhosphorus / fPotassium mg/kg. They
hold the last reading while bGood is FALSE. bGood: the sensor answers and every
value is plausible (moisture 0-100 %, temperature -40-80 degC, pH 0-14, EC
0-20000 uS/cm, N P K 0-2000 mg/kg).

Status (stData.eStatus / sStatus): Off, Ok, Setup (unit not 1..247), NoReply
(never answered: address, baud, wiring, map), Lost (answered before),
BadData (check the map). *)

FUNCTION_BLOCK FB_Soil7in1
  VAR_IN_OUT
    fbNode : FB_ModbusNode; (* the RS485 line's node (a client) *)
    stData : ST_SoilData; (* settings and status *)
  END_VAR
  VAR_INPUT
    bEnable : BOOL := TRUE; (* read the sensor *)
  END_VAR
  VAR_OUTPUT
    bGood : BOOL; (* answering, every value plausible *)
    fMoisture : REAL; (* % *)
    fTemperature : REAL; (* degC *)
    fEc : REAL; (* uS/cm *)
    fPh : REAL;
    fNitrogen : REAL; (* mg/kg *)
    fPhosphorus : REAL; (* mg/kg *)
    fPotassium : REAL; (* mg/kg *)
  END_VAR
  VAR
    {attribute 'hide'}
    aPh : INT;
    {attribute 'hide'}
    aMt : ARRAY [0..1] OF INT;
    {attribute 'hide'}
    aEc : INT;
    {attribute 'hide'}
    aNpk : ARRAY [0..2] OF INT;
    {attribute 'hide'}
    aAll : ARRAY [0..6] OF INT;
    {attribute 'hide'}
    eQPh : E_ModbusQuality;
    {attribute 'hide'}
    eQMt : E_ModbusQuality;
    {attribute 'hide'}
    eQEc : E_ModbusQuality;
    {attribute 'hide'}
    eQNpk : E_ModbusQuality;
    {attribute 'hide'}
    eQAll : E_ModbusQuality;
    {attribute 'hide'}
    bSeenPh : BOOL;
    {attribute 'hide'}
    bSeenMt : BOOL;
    {attribute 'hide'}
    bSeenEc : BOOL;
    {attribute 'hide'}
    bSeenNpk : BOOL;
    {attribute 'hide'}
    bSeenAll : BOOL;
    {attribute 'hide'}
    eRPh : E_ModbusResult;
    {attribute 'hide'}
    eRMt : E_ModbusResult;
    {attribute 'hide'}
    eREc : E_ModbusResult;
    {attribute 'hide'}
    eRNpk : E_ModbusResult;
    {attribute 'hide'}
    eRAll : E_ModbusResult;
    {attribute 'hide'}
    bJxct : BOOL;
    {attribute 'hide'}
    bUnitOk : BOOL;
    {attribute 'hide'}
    bRead : BOOL;
    {attribute 'hide'}
    nUnit : BYTE;
    {attribute 'hide'}
    tEvery : TIME;
    {attribute 'hide'}
    bSeen : BOOL;
    {attribute 'hide'}
    bAnswering : BOOL;
    {attribute 'hide'}
    bPlausible : BOOL;
    {attribute 'hide'}
    tLastGood : TIME;
    {attribute 'hide'}
    bStarted : BOOL;
  END_VAR


bUnitOk := stData.nUnitId >= 1 AND stData.nUnitId <= 247;
bJxct := stData.eMap <> E_SoilMap.Linear;
tEvery := MAX(stData.tPeriod, T#1s);
nUnit := USINT_TO_BYTE(stData.nUnitId);
bRead := bEnable AND bUnitOk;

(* Each reading is its own standing Watch on the node: one record each. *)
eRPh := fbNode.Watch(anyData := aPh, nUnitId := nUnit, eTable := E_ModbusTable.HoldingRegister, nAddress := 16#0006,
             tPeriod := tEvery, bEnable := bRead AND bJxct, eQuality => eQPh, bSeen => bSeenPh);
eRMt := fbNode.Watch(anyData := aMt, nUnitId := nUnit, eTable := E_ModbusTable.HoldingRegister, nAddress := 16#0012,
             tPeriod := tEvery, bEnable := bRead AND bJxct, eQuality => eQMt, bSeen => bSeenMt);
eREc := fbNode.Watch(anyData := aEc, nUnitId := nUnit, eTable := E_ModbusTable.HoldingRegister, nAddress := 16#0015,
             tPeriod := tEvery, bEnable := bRead AND bJxct, eQuality => eQEc, bSeen => bSeenEc);
eRNpk := fbNode.Watch(anyData := aNpk, nUnitId := nUnit, eTable := E_ModbusTable.HoldingRegister, nAddress := 16#001E,
             tPeriod := tEvery, bEnable := bRead AND bJxct, eQuality => eQNpk, bSeen => bSeenNpk);
eRAll := fbNode.Watch(anyData := aAll, nUnitId := nUnit, eTable := E_ModbusTable.HoldingRegister, nAddress := 16#0000,
             tPeriod := tEvery, bEnable := bRead AND NOT bJxct, eQuality => eQAll, bSeen => bSeenAll);

IF bJxct THEN
  bSeen := bSeenPh AND bSeenMt AND bSeenEc AND bSeenNpk;
  bAnswering := eQPh = E_ModbusQuality.Good AND eQMt = E_ModbusQuality.Good
                AND eQEc = E_ModbusQuality.Good AND eQNpk = E_ModbusQuality.Good;
  IF bAnswering THEN
    fMoisture := INT_TO_REAL(aMt[0]) / 10.0;
    fTemperature := INT_TO_REAL(aMt[1]) / 10.0;         (* two's complement: below zero is negative *)
    fEc := INT_TO_REAL(aEc);
    fPh := INT_TO_REAL(aPh) / 100.0;
    fNitrogen := INT_TO_REAL(aNpk[0]);
    fPhosphorus := INT_TO_REAL(aNpk[1]);
    fPotassium := INT_TO_REAL(aNpk[2]);
  END_IF;
ELSE
  bSeen := bSeenAll;
  bAnswering := eQAll = E_ModbusQuality.Good;
  IF bAnswering THEN
    fMoisture := INT_TO_REAL(aAll[0]) / 10.0;
    fTemperature := INT_TO_REAL(aAll[1]) / 10.0;
    fEc := INT_TO_REAL(aAll[2]);
    fPh := INT_TO_REAL(aAll[3]) / 10.0;
    fNitrogen := INT_TO_REAL(aAll[4]);
    fPhosphorus := INT_TO_REAL(aAll[5]);
    fPotassium := INT_TO_REAL(aAll[6]);
  END_IF;
END_IF;
IF fEc < 0.0 THEN
  fEc := fEc + 65536.0;                                 (* EC is unsigned *)
END_IF;
bPlausible := fMoisture >= 0.0 AND fMoisture <= 100.0 AND fTemperature >= -40.0 AND fTemperature <= 80.0
              AND fPh >= 0.0 AND fPh <= 14.0 AND fEc >= 0.0 AND fEc <= 20000.0
              AND fNitrogen >= 0.0 AND fNitrogen <= 2000.0 AND fPhosphorus >= 0.0 AND fPhosphorus <= 2000.0
              AND fPotassium >= 0.0 AND fPotassium <= 2000.0;

bGood := bRead AND bAnswering AND bPlausible;
IF NOT bStarted OR bGood THEN
  bStarted := TRUE;
  tLastGood := TIME();
END_IF;
stData.tAge := TIME() - tLastGood;
IF NOT bEnable THEN
  stData.eStatus := E_DeviceStatus.Off;
  stData.sStatus := 'Off';
ELSIF NOT bUnitOk THEN
  stData.eStatus := E_DeviceStatus.Setup;
  stData.sStatus := 'Setup: unit 1..247';
ELSIF bGood THEN
  stData.eStatus := E_DeviceStatus.Ok;
  stData.sStatus := 'OK';
ELSIF bAnswering THEN
  stData.eStatus := E_DeviceStatus.BadData;
  stData.sStatus := 'Bad data: check the map';
ELSIF NOT bSeen THEN
  stData.eStatus := E_DeviceStatus.NoReply;
  stData.sStatus := 'No reply: address/baud/map';
ELSE
  stData.eStatus := E_DeviceStatus.Lost;
  stData.sStatus := 'Comms lost';
END_IF;


END_FUNCTION_BLOCK
