(* FB_RegisterMeter — totals from a device's own total register (a Modbus energy / flow meter, a BeeBus counter).
Offers I_Meter (the total, the rate per hour; an I_Measurement too: its rate).
Pins: fRegisterTotal (the device's running total, in its unit; LREAL so a 32-bit register stays exact), bInputGood (the
read can be trusted), refData.
Each increase adds (fRegisterTotal - the last) x set.fTotalPerRegisterUnit. A drop is a device reset or a glitch: nothing is counted,
and only the part above the highest reading seen counts again, unless it is a wrap (set.fRegisterWrapsAt > 0: the
register restarts from 0 past it; a fall from the top half to the bottom half counts the wrap). An increase
above set.fMaxStepPerRead (0 = no limit) is a glitch: taken as the new reading, nothing counted. While bad nothing is
counted; the register catches up when good again. Bad past set.stMeterBadFault's delay: bIsGood FALSE, a warning
(SensorBad). Units: set.eMeterUnit (the register's volume unit, with fTotalPerRegisterUnit applied after) and set.eTotalUnit (the
total's), E_Unit volume units, both set convert each addition; both None = no conversion; one set, or a unit that
is not a volume, is a bad setting (put back). The total is LREAL, kept hourly, when bPumpRunning falls (the pump stops; optional)
and on a reset (bCmdResetTotals).
Total commands: bCmdResetTotals (with set.bResetNeedsConfirm, only together with bCmdConfirmReset in the same write) and
bCmdPresetTotal (the total to fPresetTotal, 0 .. 1E12). *)

FUNCTION_BLOCK FB_RegisterMeter EXTENDS FB_Object IMPLEMENTS I_Meter
  VAR_INPUT
    fRegisterTotal : LREAL; (* the device's running total register, in its unit (LREAL keeps 32 bits exact) *)
    bInputGood : BOOL := TRUE; (* the input can be trusted *)
    bPumpRunning : BOOL := FALSE; (* optional: the pump runs; its fall keeps the totals *)
    refData : REFERENCE TO ST_RegisterMeterData; (* the block's record *)
  END_VAR
  VAR RETAIN
    stKept : ST_RegisterMeterSet;
    nKeptLayout : UINT;
    stKeptTot : ST_RegisterMeterTot;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 3;
  END_VAR
  VAR
    stWInputBad : ST_ProtectionWork;
    bHaveLast : BOOL;
    fLast : LREAL; (* the reading counted up to (the high-water mark) *)
    tKeptAt : TIME;
    bRunningWas : BOOL;
    tWindowAt : TIME;
    fWindowTotal : LREAL;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bGoodNow : BOOL;
    fD : LREAL;
    tWin : TIME;
    fMult : LREAL; (* register unit to total unit *)
    bUnitOk : BOOL;
  END_VAR


PROPERTY PUBLIC fActTotal : LREAL    // the lifetime total in its unit
  GET
    IF __ISVALIDREF(refData) THEN fActTotal := refData.tot.fTotal; ELSE fActTotal := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActFlowPerHour : REAL    // the rate, per hour
  GET
    IF __ISVALIDREF(refData) THEN fActFlowPerHour := refData.sts.fFlowPerHour; ELSE fActFlowPerHour := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL    // the value can be trusted now
  GET
    IF __ISVALIDREF(refData) THEN bIsGood := refData.sts.bGood; ELSE bIsGood := FALSE; END_IF;
  END_GET
END_PROPERTY
(* I_Measurement: the rate (per hour), in set.eTotalUnit per hour, no bands *)
PROPERTY PUBLIC fActValue : REAL    // the value now (the total, in its unit)
  GET
    IF __ISVALIDREF(refData) THEN fActValue := refData.sts.fFlowPerHour; ELSE fActValue := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL    // a value is available (fitted and read at least once)
  GET
    bHasValue := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL    // fitted on this site
  GET
    bIsFitted := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit    // the unit of the value
  GET
    eUnit := E_Unit.None;
    IF __ISVALIDREF(refData) THEN eUnit := F_UnitPerHour(eUnit := refData.set.eTotalUnit); END_IF;
  END_GET
END_PROPERTY
METHOD PUBLIC Band : BOOL
  VAR_INPUT
    eBand : E_Band;
  END_VAR
  Band := FALSE;
END_METHOD

METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_RegisterMeterSet;
  END_VAR
  VAR
    bU : BOOL;
    fU : LREAL;
  END_VAR
  fU := F_UnitFactor(eFromUnit := stS.eMeterUnit, eToUnit := stS.eTotalUnit, bUnitsMatch => bU);
  SetWhy := E_UtError.None;
  IF NOT (bU) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.fTotalPerRegisterUnit >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fTotalPerRegisterUnit <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fRegisterWrapsAt >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fMaxStepPerRead >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.tRateWindow > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stMeterBadFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stMeterBadFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_RegisterMeterSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
  tKeptAt := tNow;
  tWindowAt := tNow;
  fWindowTotal := refData.tot.fTotal;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* count the increases *)
fMult := F_UnitFactor(eFromUnit := refData.set.eMeterUnit, eToUnit := refData.set.eTotalUnit, bUnitsMatch => bUnitOk);
bGoodNow := bInputGood AND fRegisterTotal = fRegisterTotal AND ABS(fRegisterTotal) <= LREAL#1.0E300;
IF bGoodNow THEN
  IF NOT bHaveLast THEN
    bHaveLast := TRUE;
    fLast := fRegisterTotal;           (* the first reading: the start, nothing counted *)
  ELSIF fRegisterTotal > fLast THEN
    fD := fRegisterTotal - fLast;
    IF refData.set.fMaxStepPerRead > 0.0 AND fD > refData.set.fMaxStepPerRead THEN
      refData.sts.nGlitchCount := refData.sts.nGlitchCount + 1;   (* a jump: nothing counted *)
    ELSE
      refData.tot.fTotal := refData.tot.fTotal + fD * REAL_TO_LREAL(refData.set.fTotalPerRegisterUnit) * fMult;
    END_IF;
    fLast := fRegisterTotal;
  ELSIF fRegisterTotal < fLast THEN
    IF refData.set.fRegisterWrapsAt > 0.0 AND fLast >= refData.set.fRegisterWrapsAt / 2.0
       AND fRegisterTotal < refData.set.fRegisterWrapsAt / 2.0 THEN
      fD := refData.set.fRegisterWrapsAt - fLast + fRegisterTotal;    (* a wrap *)
      refData.tot.fTotal := refData.tot.fTotal + fD * REAL_TO_LREAL(refData.set.fTotalPerRegisterUnit) * fMult;
      fLast := fRegisterTotal;
    ELSE
      refData.sts.nGlitchCount := refData.sts.nGlitchCount + 1;   (* a drop: counts again only above fLast *)
    END_IF;
  END_IF;
  refData.sts.fLastGoodReading := fRegisterTotal;
END_IF;

(* the input bad *)
F_Protect(tNow := tNow, bConditionPresent := NOT bGoodNow, bResetRequest := SystemReset(), tRetryCountWindow := refData.set.tRetryCountWindow,
          stSettings := refData.set.stMeterBadFault, stStatus := refData.sts.stMeterBadFault, stWorking := stWInputBad);
refData.sts.bGood := NOT stWInputBad.bActive;

(* rate over the window, per hour *)
tWin := tNow - tWindowAt;
IF tWin >= refData.set.tRateWindow THEN
  refData.sts.fFlowPerHour := LREAL_TO_REAL((refData.tot.fTotal - fWindowTotal) * 3600000.0 / TIME_TO_LREAL(tWin));
  fWindowTotal := refData.tot.fTotal;
  tWindowAt := tNow;
END_IF;

(* reset, keep *)
IF refData.bCmdResetTotals AND (refData.bCmdConfirmReset OR NOT refData.set.bResetNeedsConfirm) THEN
  refData.bCmdResetTotals := FALSE;
  refData.tot.fTotal := 0.0;
  fWindowTotal := 0.0;
  stKeptTot := refData.tot;
END_IF;
refData.bCmdResetTotals := FALSE;
refData.bCmdConfirmReset := FALSE;
IF refData.bCmdPresetTotal THEN
  IF refData.fPresetTotal >= 0.0 AND refData.fPresetTotal <= 1.0E12 THEN
    refData.tot.fTotal := refData.fPresetTotal;
    fWindowTotal := refData.fPresetTotal;
    stKeptTot := refData.tot;
  END_IF;
  refData.bCmdPresetTotal := FALSE;
END_IF;
IF (bRunningWas AND NOT bPumpRunning) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
bRunningWas := bPumpRunning;

bError := NOT bOk OR stWInputBad.bTripping;
bWarning := NOT bError AND (stWInputBad.bWarning OR refData.sts.bSettingRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF stWInputBad.bTripping OR stWInputBad.bWarning THEN
  eErrorId := E_UtError.SensorBad;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT refData.sts.bGood THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK