(* FB_Soil7in1 - a 7-in-1 RS485 soil sensor on Modbus RTU: moisture, temperature, conductivity (EC), pH, nitrogen,
phosphorus and potassium.

Wire fbNode to the FB_ModbusNode of the sensor's RS485 line (a client) and refData to its record (an ST_SoilData). The
common sensor's line settings: 9600 baud, 8 data bits, no parity, 1 stop bit; factory address 1.

The record's set.eRegisterMap picks the register map; makers differ. Jxct (JXBS-3001 type, most units) is the default;
Linear is registers 0-6 in a row (moisture, temperature, EC, pH, N, P, K). A wrong map shows as NoReply (the sensor
refuses the addresses) or BadData (impossible values), never as plausible numbers.

Outputs: fMoisturePct (as the sensor reports it), fTemperatureDegC (negative below zero), fConductivity uS/cm, fPh,
fNitrogen / fPhosphorus / fPotassium mg/kg; the same values in sts. They hold the last reading while bGood is FALSE.
bGood: the sensor answers and every value is plausible (moisture 0-100 %, temperature -40-80 degC, pH 0-14, EC
0-20000 uS/cm, N P K 0-2000 mg/kg). bError / eErrorId (E_DeviceError): enabled and the status is not Ok, so an
alarm block or SCADA wires it as any other block.

Status (sts.eStatus / sStatusText): Off, Ok, Setup (the address is not 1..247), NoReply (never answered: address,
baud, wiring, map), Lost (answered before), BadData (check the map).

Settings (set: nUnitId, eRegisterMap, tReadInterval) are kept by the block over a power cut (a retained last-good
copy): restored at power-up; a write that cannot work (an address outside 1..247, a map that does not exist, a
negative interval) is refused and the last good value put back (sts.bSettingRefused, until a good write). *)

FUNCTION_BLOCK FB_Soil7in1
  VAR_IN_OUT
    fbNode : FB_ModbusNode; (* the RS485 line's FB_ModbusNode (a client) *)
  END_VAR
  VAR_INPUT
    bEnable : BOOL := TRUE; (* read the sensor *)
    refData : REFERENCE TO ST_SoilData; (* the sensor's record: settings set and status sts *)
  END_VAR
  VAR_OUTPUT
    bGood : BOOL; (* answering, every value plausible *)
    fMoisturePct : REAL; (* soil moisture, % (as the sensor reports it) *)
    fTemperatureDegC : REAL; (* soil temperature, degC (negative below zero) *)
    fConductivity : REAL; (* electrical conductivity (EC), uS/cm *)
    fPh : REAL; (* pH, 0-14 *)
    fNitrogen : REAL; (* nitrogen, mg/kg *)
    fPhosphorus : REAL; (* phosphorus, mg/kg *)
    fPotassium : REAL; (* potassium, mg/kg *)
    bError : BOOL; (* enabled and not Ok (Setup, NoReply, Lost or BadData) *)
    eErrorId : E_DeviceError; (* which error: None while all is well *)
  END_VAR
  VAR RETAIN
    stKept : ST_SoilSet; (* the last good settings, kept over a power cut *)
    nKeptLayout : UINT; (* the layout stKept was written with *)
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1; (* this version's stKept layout *)
  END_VAR
  VAR
    aPh : INT;
    aMt : ARRAY [0..1] OF INT;
    aEc : INT;
    aNpk : ARRAY [0..2] OF INT;
    aAll : ARRAY [0..6] OF INT;
    eQPh : E_ModbusQuality;
    eQMt : E_ModbusQuality;
    eQEc : E_ModbusQuality;
    eQNpk : E_ModbusQuality;
    eQAll : E_ModbusQuality;
    bEverPh : BOOL;
    bEverMt : BOOL;
    bEverEc : BOOL;
    bEverNpk : BOOL;
    bEverAll : BOOL;
    eRPh : E_ModbusResult;
    eRMt : E_ModbusResult;
    eREc : E_ModbusResult;
    eRNpk : E_ModbusResult;
    eRAll : E_ModbusResult;
    bJxct : BOOL;
    bUnitOk : BOOL;
    bRead : BOOL;
    nUnit : BYTE;
    tEvery : TIME;
    bEverAnswered : BOOL;
    bAnswering : BOOL;
    bPlausible : BOOL;
    tLastGood : TIME;
    bStarted : BOOL;
    bFirstScan : BOOL := TRUE;
    bSetOk : BOOL;
  END_VAR


IF NOT __ISVALIDREF(refData) THEN
  bGood := FALSE;
  bError := TRUE;
  eErrorId := E_DeviceError.NoRecord;
  RETURN;
END_IF;

(* settings: kept over a power cut, a write that cannot work put back *)
bSetOk := refData.set.nUnitId >= 1 AND refData.set.nUnitId <= 247 AND refData.set.tReadInterval >= T#0s
          AND (refData.set.eRegisterMap = E_SoilMap.Jxct OR refData.set.eRegisterMap = E_SoilMap.Linear);
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  bFirstScan := FALSE;
ELSIF bSetOk THEN
  IF refData.set.nUnitId <> stKept.nUnitId OR refData.set.eRegisterMap <> stKept.eRegisterMap
     OR refData.set.tReadInterval <> stKept.tReadInterval THEN
    stKept := refData.set;
    refData.sts.bSettingRefused := FALSE;
  END_IF;
ELSIF stKept.nUnitId >= 1 AND stKept.nUnitId <= 247 THEN
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;

bUnitOk := refData.set.nUnitId >= 1 AND refData.set.nUnitId <= 247;
bJxct := refData.set.eRegisterMap <> E_SoilMap.Linear;
tEvery := MAX(refData.set.tReadInterval, T#1s);
nUnit := refData.set.nUnitId;
bRead := bEnable AND bUnitOk;

(* Each reading is its own standing Watch on the node: one record each. *)
eRPh := fbNode.Watch(anyData := aPh, nUnitId := nUnit, eTable := E_ModbusTable.HoldingRegister, nStartAddress := 16#0006,
             tReadInterval := tEvery, bEnable := bRead AND bJxct, eQuality => eQPh, bValueEverReceived => bEverPh);
eRMt := fbNode.Watch(anyData := aMt, nUnitId := nUnit, eTable := E_ModbusTable.HoldingRegister, nStartAddress := 16#0012,
             tReadInterval := tEvery, bEnable := bRead AND bJxct, eQuality => eQMt, bValueEverReceived => bEverMt);
eREc := fbNode.Watch(anyData := aEc, nUnitId := nUnit, eTable := E_ModbusTable.HoldingRegister, nStartAddress := 16#0015,
             tReadInterval := tEvery, bEnable := bRead AND bJxct, eQuality => eQEc, bValueEverReceived => bEverEc);
eRNpk := fbNode.Watch(anyData := aNpk, nUnitId := nUnit, eTable := E_ModbusTable.HoldingRegister, nStartAddress := 16#001E,
             tReadInterval := tEvery, bEnable := bRead AND bJxct, eQuality => eQNpk, bValueEverReceived => bEverNpk);
eRAll := fbNode.Watch(anyData := aAll, nUnitId := nUnit, eTable := E_ModbusTable.HoldingRegister, nStartAddress := 16#0000,
             tReadInterval := tEvery, bEnable := bRead AND NOT bJxct, eQuality => eQAll, bValueEverReceived => bEverAll);

IF bJxct THEN
  bEverAnswered := bEverPh AND bEverMt AND bEverEc AND bEverNpk;
  bAnswering := eQPh = E_ModbusQuality.Good AND eQMt = E_ModbusQuality.Good
                AND eQEc = E_ModbusQuality.Good AND eQNpk = E_ModbusQuality.Good;
  IF bAnswering THEN
    fMoisturePct := INT_TO_REAL(aMt[0]) / 10.0;
    fTemperatureDegC := INT_TO_REAL(aMt[1]) / 10.0;     (* two's complement: below zero is negative *)
    fConductivity := INT_TO_REAL(aEc);
    fPh := INT_TO_REAL(aPh) / 100.0;
    fNitrogen := INT_TO_REAL(aNpk[0]);
    fPhosphorus := INT_TO_REAL(aNpk[1]);
    fPotassium := INT_TO_REAL(aNpk[2]);
  END_IF;
ELSE
  bEverAnswered := bEverAll;
  bAnswering := eQAll = E_ModbusQuality.Good;
  IF bAnswering THEN
    fMoisturePct := INT_TO_REAL(aAll[0]) / 10.0;
    fTemperatureDegC := INT_TO_REAL(aAll[1]) / 10.0;
    fConductivity := INT_TO_REAL(aAll[2]);
    fPh := INT_TO_REAL(aAll[3]) / 10.0;
    fNitrogen := INT_TO_REAL(aAll[4]);
    fPhosphorus := INT_TO_REAL(aAll[5]);
    fPotassium := INT_TO_REAL(aAll[6]);
  END_IF;
END_IF;
IF fConductivity < 0.0 THEN
  fConductivity := fConductivity + 65536.0;           (* EC is unsigned *)
END_IF;
bPlausible := fMoisturePct >= 0.0 AND fMoisturePct <= 100.0 AND fTemperatureDegC >= -40.0 AND fTemperatureDegC <= 80.0
              AND fPh >= 0.0 AND fPh <= 14.0 AND fConductivity >= 0.0 AND fConductivity <= 20000.0
              AND fNitrogen >= 0.0 AND fNitrogen <= 2000.0 AND fPhosphorus >= 0.0 AND fPhosphorus <= 2000.0
              AND fPotassium >= 0.0 AND fPotassium <= 2000.0;

bGood := bRead AND bAnswering AND bPlausible;
IF NOT bStarted OR bGood THEN
  bStarted := TRUE;
  tLastGood := TIME();
END_IF;
refData.sts.tValueAge := TIME() - tLastGood;
IF NOT bEnable THEN
  refData.sts.eStatus := E_DeviceStatus.Off;
  refData.sts.sStatusText := 'Off';
  eErrorId := E_DeviceError.None;
ELSIF NOT bUnitOk THEN
  refData.sts.eStatus := E_DeviceStatus.Setup;
  refData.sts.sStatusText := 'Address not 1-247';
  eErrorId := E_DeviceError.AddressBad;
ELSIF bGood THEN
  refData.sts.eStatus := E_DeviceStatus.Ok;
  refData.sts.sStatusText := 'OK';
  eErrorId := E_DeviceError.None;
ELSIF bAnswering THEN
  refData.sts.eStatus := E_DeviceStatus.BadData;
  refData.sts.sStatusText := 'Bad data: check the map';
  eErrorId := E_DeviceError.BadData;
ELSIF NOT bEverAnswered THEN
  refData.sts.eStatus := E_DeviceStatus.NoReply;
  refData.sts.sStatusText := 'No reply: address/baud/map';
  eErrorId := E_DeviceError.NoReply;
ELSE
  refData.sts.eStatus := E_DeviceStatus.Lost;
  refData.sts.sStatusText := 'Comms lost';
  eErrorId := E_DeviceError.Lost;
END_IF;
bError := eErrorId <> E_DeviceError.None;
refData.sts.bGood := bGood;
refData.sts.bError := bError;
refData.sts.eErrorId := eErrorId;
refData.sts.fMoisturePct := fMoisturePct;
refData.sts.fTemperatureDegC := fTemperatureDegC;
refData.sts.fConductivity := fConductivity;
refData.sts.fPh := fPh;
refData.sts.fNitrogen := fNitrogen;
refData.sts.fPhosphorus := fPhosphorus;
refData.sts.fPotassium := fPotassium;

END_FUNCTION_BLOCK