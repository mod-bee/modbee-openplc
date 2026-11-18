(* FB_RegisterMeter — totals from a device's own total register (a Modbus energy / flow meter, a BeeBus counter).
Offers I_Meter (the total, the rate per hour; an I_Measurement too: its rate).
Pins: fRegister (the device's running total, in its unit; LREAL so a 32-bit register stays exact), bInGood (the
read can be trusted), refData.
Each increase adds (fRegister - the last) x set.fScale. A drop is a device reset or a glitch: nothing is counted,
and only the part above the highest reading seen counts again, unless it is a wrap (set.fRolloverAt > 0: the
register restarts from 0 past it; a fall from the top half to the bottom half counts the wrap). An increase
above set.fMaxStep (0 = no limit) is a glitch: taken as the new reading, nothing counted. While bad nothing is
counted; the register catches up when good again. Bad past set.stInputBad's delay: bIsGood FALSE, a warning
(SensorBad). Units: set.eInUnit (the register's volume unit, with fScale applied after) and set.eOutUnit (the
total's), E_Unit volume units, both set convert each addition; both None = no conversion; one set, or a unit that
is not a volume, is a bad setting (put back). The total is LREAL, kept hourly, when bRunning falls (the pump stops; optional)
and on a reset (bCmdResetTotal).
Total commands: bCmdResetTotal (with set.bConfirmReset, only together with bCmdConfirm in the same write) and
bCmdPreset (the total to fPresetTotal, 0 .. 1E12). *)

FUNCTION_BLOCK FB_RegisterMeter EXTENDS FB_Object IMPLEMENTS I_Meter
  VAR_INPUT
    fRegister : LREAL;
    bInGood : BOOL := TRUE;
    bRunning : BOOL := FALSE; (* optional: the pump runs; its fall keeps the totals *)
    refData : REFERENCE TO ST_RegisterMeterData;
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


PROPERTY PUBLIC fActTotal : LREAL
  GET
    IF __ISVALIDREF(refData) THEN fActTotal := refData.tot.fTotal; ELSE fActTotal := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActRate : REAL
  GET
    IF __ISVALIDREF(refData) THEN fActRate := refData.sts.fRate; ELSE fActRate := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL
  GET
    IF __ISVALIDREF(refData) THEN bIsGood := refData.sts.bGood; ELSE bIsGood := FALSE; END_IF;
  END_GET
END_PROPERTY
(* I_Measurement: the rate (per hour), in set.eOutUnit per hour, no bands *)
PROPERTY PUBLIC fActValue : REAL
  GET
    IF __ISVALIDREF(refData) THEN fActValue := refData.sts.fRate; ELSE fActValue := 0.0; END_IF;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL
  GET
    bHasValue := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL
  GET
    bIsFitted := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit
  GET
    eUnit := E_Unit.None;
    IF __ISVALIDREF(refData) THEN eUnit := F_UnitPerHour(eUnit := refData.set.eOutUnit); END_IF;
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
  fU := F_UnitFactor(eFromUnit := stS.eInUnit, eToUnit := stS.eOutUnit, bOk => bU);
  SetWhy := E_UtError.None;
  IF NOT (bU) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.fScale >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fScale <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fRolloverAt >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fMaxStep >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.tRateWindow > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stInputBad.tDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stInputBad.tRecover >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
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
  refData.sts.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
END_IF;

(* count the increases *)
fMult := F_UnitFactor(eFromUnit := refData.set.eInUnit, eToUnit := refData.set.eOutUnit, bOk => bUnitOk);
bGoodNow := bInGood AND fRegister = fRegister AND ABS(fRegister) <= LREAL#1.0E300;
IF bGoodNow THEN
  IF NOT bHaveLast THEN
    bHaveLast := TRUE;
    fLast := fRegister;           (* the first reading: the start, nothing counted *)
  ELSIF fRegister > fLast THEN
    fD := fRegister - fLast;
    IF refData.set.fMaxStep > 0.0 AND fD > refData.set.fMaxStep THEN
      refData.sts.nGlitches := refData.sts.nGlitches + 1;   (* a jump: nothing counted *)
    ELSE
      refData.tot.fTotal := refData.tot.fTotal + fD * REAL_TO_LREAL(refData.set.fScale) * fMult;
    END_IF;
    fLast := fRegister;
  ELSIF fRegister < fLast THEN
    IF refData.set.fRolloverAt > 0.0 AND fLast >= refData.set.fRolloverAt / 2.0
       AND fRegister < refData.set.fRolloverAt / 2.0 THEN
      fD := refData.set.fRolloverAt - fLast + fRegister;    (* a wrap *)
      refData.tot.fTotal := refData.tot.fTotal + fD * REAL_TO_LREAL(refData.set.fScale) * fMult;
      fLast := fRegister;
    ELSE
      refData.sts.nGlitches := refData.sts.nGlitches + 1;   (* a drop: counts again only above fLast *)
    END_IF;
  END_IF;
  refData.sts.fRegister := fRegister;
END_IF;

(* the input bad *)
F_Protect(tNow := tNow, bCause := NOT bGoodNow, bResetReq := SystemReset(), tRetryWindow := T#1h,
          stSet := refData.set.stInputBad, stSts := refData.sts.stInputBad, stWork := stWInputBad);
refData.sts.bGood := NOT stWInputBad.bActive;

(* rate over the window, per hour *)
tWin := tNow - tWindowAt;
IF tWin >= refData.set.tRateWindow THEN
  refData.sts.fRate := LREAL_TO_REAL((refData.tot.fTotal - fWindowTotal) * 3600000.0 / TIME_TO_LREAL(tWin));
  fWindowTotal := refData.tot.fTotal;
  tWindowAt := tNow;
END_IF;

(* reset, keep *)
IF refData.bCmdResetTotal AND (refData.bCmdConfirm OR NOT refData.set.bConfirmReset) THEN
  refData.bCmdResetTotal := FALSE;
  refData.tot.fTotal := 0.0;
  fWindowTotal := 0.0;
  stKeptTot := refData.tot;
END_IF;
refData.bCmdResetTotal := FALSE;
refData.bCmdConfirm := FALSE;
IF refData.bCmdPreset THEN
  IF refData.fPresetTotal >= 0.0 AND refData.fPresetTotal <= 1.0E12 THEN
    refData.tot.fTotal := refData.fPresetTotal;
    fWindowTotal := refData.fPresetTotal;
    stKeptTot := refData.tot;
  END_IF;
  refData.bCmdPreset := FALSE;
END_IF;
IF (bRunningWas AND NOT bRunning) OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
bRunningWas := bRunning;

bError := NOT bOk OR stWInputBad.bTrip;
bWarning := NOT bError AND (stWInputBad.bWarn OR refData.sts.bRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF stWInputBad.bTrip OR stWInputBad.bWarn THEN
  eErrorId := E_UtError.SensorBad;
ELSIF refData.sts.bRefused THEN
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