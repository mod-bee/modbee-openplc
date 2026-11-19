(* FB_SignalSelect — two or three sensors measuring the same thing, voted into one trusted measurement. Wire the
instance to any I_Measurement pin.
Pins: ipSensor1..3 (I_Measurement; NULL = not fitted, never used), bResetFaults -> fValue (the voted value; while not
good per set.eWhenNoneGood), bGood, fSpread (the largest difference between usable sensors), nSensorDropped (the sensor
dropped, 1..3; 0 none), nSensorsGood, plus FB_Object's bError / bWarning / eErrorId / eState. refData: its record.
A sensor is usable when it is fitted, good, has a value and the value is a number. Two sensors agree when they
are within set.fDisagreeSpreadAbove.
  3 usable  all agree: combined by set.eCombineBy. One agrees with neither of the others while those two agree: it
            is dropped (nSensorDropped, warning SensorDeviates). No two agree: no agreement.
  2 usable  agree: combined by eCombineBy. Not: warning SensorsDisagree, set.eWhenTwoDisagree (Highest or Lowest) used.
  1 usable  used, warning OneSensorLeft.
  0 usable  no agreement.
No agreement is a protection (set.stNoAgreementFault, default Trip after 10 s, Auto): ridden through with the last voted
value, then bGood FALSE, bError SensorsDisagree, fValue per eWhenNoneGood (Hold, Lowest / Highest of the raw values,
Substitute set.fSubstituteValue, Midpoint of the raw values). The spread is another (set.stDeviationFault, default Warn
after 5 s): fSpread above set.fWarnSpreadAbove, or a sensor dropped. set.tFilterTime smooths fValue (low-pass). No sensor
wired: bError NoMeasurement. Settings are kept by the block (a retained last-good copy): restored at power-up,
a bad write put back. eUnit: sensor 1's. *)

FUNCTION_BLOCK FB_SignalSelect EXTENDS FB_Object IMPLEMENTS I_Measurement
  VAR_INPUT
    ipSensor1 : I_Measurement; (* NULL = not fitted, never used *)
    ipSensor2 : I_Measurement; (* second sensor (unwired = not fitted) *)
    ipSensor3 : I_Measurement; (* third sensor (unwired = not fitted) *)
    bResetFaults : BOOL R_EDGE; (* rising edge: reset latched faults whose cause has gone *)
    refData : REFERENCE TO ST_SelectData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    fValue : REAL; (* voted value (while not good: per eWhenNoneGood) *)
    bGood : BOOL; (* the voted value can be used *)
    fSpread : REAL; (* the largest difference between usable sensors *)
    nSensorDropped : INT; (* the sensor dropped (1..3), 0 none *)
    nSensorsGood : INT; (* usable sensors *)
  END_VAR
  VAR RETAIN
    stKept : ST_SelectSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    fbFilter : FB_Filter;
    stWDev : ST_ProtectionWork;
    stWNo : ST_ProtectionWork;
    fHeld : REAL;
    bFitted : BOOL;
    eUnitNow : E_Unit;
  END_VAR
  VAR_TEMP
    bOkSet : BOOL;
    bResetReq : BOOL;
    aV : ARRAY [1..3] OF REAL;
    aUsable : ARRAY [1..3] OF BOOL;
    aUse : ARRAY [1..3] OF BOOL;
    aRaw : ARRAY [1..3] OF BOOL; (* a number, health ignored (eWhenNoneGood Lowest / Highest / Midpoint) *)
    bAg12 : BOOL;
    bAg13 : BOOL;
    bAg23 : BOOL;
    bNoAgreeNow : BOOL;
    bTwoApart : BOOL;
    bDev : BOOL;
    bNoAgree : BOOL;
    eMode : E_SelectMode;
    nI : INT;
    nN : INT;
    nLoIdx : INT;
    nHiIdx : INT;
    nSelIdx : INT;
    fLo : REAL;
    fHi : REAL;
    fSum : REAL;
  END_VAR


PROPERTY PUBLIC fActValue : REAL    // the value in its unit (held at the last good one while bad, when so set)
  GET
    fActValue := fValue;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL    // the value can be trusted now
  GET
    bIsGood := bGood;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL    // a continuous value (FALSE: switches only)
  GET
    bHasValue := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL    // the sensor is on this site (FALSE: no value, no bands, no fault)
  GET
    bIsFitted := bFitted;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit    // the unit of the value
  GET
    eUnit := eUnitNow;
  END_GET
END_PROPERTY

METHOD PUBLIC Band : BOOL
  VAR_INPUT
    eBand : E_Band;    // the band asked about (LowLow, Low, High, HighHigh); returns TRUE while the value is in it
  END_VAR
  Band := FALSE;
END_METHOD

METHOD PRIVATE ProtOk : BOOL
  VAR_INPUT
    stP : REFERENCE TO ST_ProtectionSet;
  END_VAR
  ProtOk := stP.tTripDelay >= T#0s AND stP.tAutoRecoverAfter >= T#0s AND stP.nMaxRetriesBeforeLockout >= 0;
END_METHOD

(* the settings are usable *)
METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_SelectSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.fWarnSpreadAbove >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fWarnSpreadAbove <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fDisagreeSpreadAbove >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fDisagreeSpreadAbove <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tFilterTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (ABS(stS.fSubstituteValue) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (ProtOk(stP := stS.stDeviationFault)) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (ProtOk(stP := stS.stNoAgreementFault)) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.eWhenTwoDisagree = E_SelectMode.Highest OR stS.eWhenTwoDisagree = E_SelectMode.Lowest) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.eCombineBy = E_SelectMode.Average OR stS.eCombineBy = E_SelectMode.Lowest
             OR stS.eCombineBy = E_SelectMode.Highest OR stS.eCombineBy = E_SelectMode.Median
             OR stS.eCombineBy = E_SelectMode.Primary) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.eWhenNoneGood = E_NoGood.Hold OR stS.eWhenNoneGood = E_NoGood.Lowest OR stS.eWhenNoneGood = E_NoGood.Highest
             OR stS.eWhenNoneGood = E_NoGood.Substitute OR stS.eWhenNoneGood = E_NoGood.Midpoint) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_SelectSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bGood := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();

(* kept settings; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
END_IF;
bOkSet := SetOk(stS := refData.set);
IF bOkSet THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bResetReq := bResetFaults OR SystemReset();
IF refData.bCmdResetFaults THEN
  bResetReq := TRUE;
  refData.bCmdResetFaults := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* the sensors; IEC AND does not short-circuit, so NULL is tested on its own *)
FOR nI := 1 TO 3 DO
  aUsable[nI] := FALSE;
  aRaw[nI] := FALSE;
  aV[nI] := 0.0;
END_FOR;
bFitted := FALSE;
IF ipSensor1 <> NULL THEN
  IF ipSensor1.bIsFitted THEN
    aV[1] := ipSensor1.fActValue;
    aRaw[1] := ABS(aV[1]) <= REAL#3.4E38;
    aUsable[1] := ipSensor1.bIsGood AND ipSensor1.bHasValue AND aRaw[1];
    bFitted := TRUE;
    eUnitNow := ipSensor1.eUnit;
  END_IF;
END_IF;
IF ipSensor2 <> NULL THEN
  IF ipSensor2.bIsFitted THEN
    aV[2] := ipSensor2.fActValue;
    aRaw[2] := ABS(aV[2]) <= REAL#3.4E38;
    aUsable[2] := ipSensor2.bIsGood AND ipSensor2.bHasValue AND aRaw[2];
    bFitted := TRUE;
  END_IF;
END_IF;
IF ipSensor3 <> NULL THEN
  IF ipSensor3.bIsFitted THEN
    aV[3] := ipSensor3.fActValue;
    aRaw[3] := ABS(aV[3]) <= REAL#3.4E38;
    aUsable[3] := ipSensor3.bIsGood AND ipSensor3.bHasValue AND aRaw[3];
    bFitted := TRUE;
  END_IF;
END_IF;
nSensorsGood := BOOL_TO_INT(aUsable[1]) + BOOL_TO_INT(aUsable[2]) + BOOL_TO_INT(aUsable[3]);

(* the vote *)
bAg12 := aUsable[1] AND aUsable[2] AND ABS(aV[1] - aV[2]) <= refData.set.fDisagreeSpreadAbove;
bAg13 := aUsable[1] AND aUsable[3] AND ABS(aV[1] - aV[3]) <= refData.set.fDisagreeSpreadAbove;
bAg23 := aUsable[2] AND aUsable[3] AND ABS(aV[2] - aV[3]) <= refData.set.fDisagreeSpreadAbove;
FOR nI := 1 TO 3 DO
  aUse[nI] := aUsable[nI];
END_FOR;
nSensorDropped := 0;
bNoAgreeNow := FALSE;
bTwoApart := FALSE;
eMode := refData.set.eCombineBy;
IF nSensorsGood = 3 THEN
  IF NOT bAg12 AND NOT bAg13 AND NOT bAg23 THEN
    bNoAgreeNow := TRUE;
  ELSIF bAg23 AND NOT bAg12 AND NOT bAg13 THEN
    nSensorDropped := 1;
  ELSIF bAg13 AND NOT bAg12 AND NOT bAg23 THEN
    nSensorDropped := 2;
  ELSIF bAg12 AND NOT bAg13 AND NOT bAg23 THEN
    nSensorDropped := 3;
  END_IF;
  IF nSensorDropped > 0 THEN
    aUse[nSensorDropped] := FALSE;
  END_IF;
ELSIF nSensorsGood = 2 THEN
  IF NOT (bAg12 OR bAg13 OR bAg23) THEN
    bTwoApart := TRUE;
    eMode := refData.set.eWhenTwoDisagree;
  END_IF;
ELSIF nSensorsGood = 0 THEN
  bNoAgreeNow := TRUE;
END_IF;
IF bNoAgreeNow THEN
  FOR nI := 1 TO 3 DO
    aUse[nI] := FALSE;
  END_FOR;
END_IF;

(* lowest, highest and mean of those used *)
nN := 0;
fSum := 0.0;
nLoIdx := 0;
nHiIdx := 0;
FOR nI := 1 TO 3 DO
  IF aUse[nI] THEN
    nN := nN + 1;
    fSum := fSum + aV[nI];
    IF nLoIdx = 0 THEN
      nLoIdx := nI;
      nHiIdx := nI;
    ELSIF aV[nI] < aV[nLoIdx] THEN
      nLoIdx := nI;
    ELSIF aV[nI] > aV[nHiIdx] THEN
      nHiIdx := nI;
    END_IF;
  END_IF;
END_FOR;

(* the spread among the usable sensors *)
fSpread := 0.0;
FOR nI := 1 TO 3 DO
  IF aUsable[nI] AND aUsable[(nI MOD 3) + 1] THEN
    fSpread := MAX(fSpread, ABS(aV[nI] - aV[(nI MOD 3) + 1]));
  END_IF;
END_FOR;
nSelIdx := 0;
IF nN > 0 THEN
  CASE eMode OF
  E_SelectMode.Lowest:
    fHeld := aV[nLoIdx];
    nSelIdx := nLoIdx;
  E_SelectMode.Highest:
    fHeld := aV[nHiIdx];
    nSelIdx := nHiIdx;
  E_SelectMode.Median:
    IF nN = 3 THEN
      nSelIdx := 6 - nLoIdx - nHiIdx;
      IF nSelIdx = nLoIdx OR nSelIdx = nHiIdx OR nSelIdx < 1 OR nSelIdx > 3 THEN
        nSelIdx := 2;             (* all equal *)
      END_IF;
      fHeld := aV[nSelIdx];
    ELSE
      fHeld := fSum / INT_TO_REAL(nN);
      IF nN = 1 THEN nSelIdx := nLoIdx; END_IF;
    END_IF;
  E_SelectMode.Primary:
    IF aUse[1] THEN
      nSelIdx := 1;
    ELSIF aUse[2] THEN
      nSelIdx := 2;
    ELSE
      nSelIdx := 3;
    END_IF;
    fHeld := aV[nSelIdx];
  ELSE
    fHeld := fSum / INT_TO_REAL(nN);
    IF nN = 1 THEN nSelIdx := nLoIdx; END_IF;
  END_CASE;
END_IF;

(* no agreement: ridden through, then not good; the spread: a warning *)
bNoAgree := F_Protect(tNow := tNow, bConditionPresent := bNoAgreeNow AND bFitted, bResetRequest := bResetReq,
                      tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stNoAgreementFault,
                      stStatus := refData.sts.stNoAgreementFault, stWorking := stWNo);
F_Protect(tNow := tNow, bConditionPresent := fSpread > refData.set.fWarnSpreadAbove OR nSensorDropped > 0, bResetRequest := bResetReq,
          tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stDeviationFault,
          stStatus := refData.sts.stDeviationFault, stWorking := stWDev);
bDev := stWDev.bWarning OR stWDev.bTripping;
bGood := bFitted AND NOT bNoAgree;
IF NOT bGood THEN                 (* the value at the pin while not good *)
  nN := 0;
  fLo := 0.0;
  fHi := 0.0;
  FOR nI := 1 TO 3 DO
    IF aRaw[nI] THEN
      IF nN = 0 OR aV[nI] < fLo THEN fLo := aV[nI]; END_IF;
      IF nN = 0 OR aV[nI] > fHi THEN fHi := aV[nI]; END_IF;
      nN := nN + 1;
    END_IF;
  END_FOR;
  CASE refData.set.eWhenNoneGood OF
  E_NoGood.Lowest: IF nN > 0 THEN fHeld := fLo; END_IF;
  E_NoGood.Highest: IF nN > 0 THEN fHeld := fHi; END_IF;
  E_NoGood.Substitute: fHeld := refData.set.fSubstituteValue;
  E_NoGood.Midpoint: IF nN > 0 THEN fHeld := (fLo + fHi) / 2.0; END_IF;
  END_CASE;
  nSelIdx := 0;
END_IF;
fbFilter(fIn := fHeld, tFilterTime := refData.set.tFilterTime, eFilterType := E_FilterMode.Lowpass);
fValue := fbFilter.fOut;

(* errors *)
bError := NOT bFitted OR bNoAgree OR NOT bOkSet;
bWarning := NOT bError AND (bNoAgreeNow OR bTwoApart OR nSensorDropped > 0 OR nSensorsGood = 1 OR bDev
                            OR refData.sts.bSettingRefused);
IF NOT bOkSet THEN
  eErrorId := E_UtError.BadSetting;
ELSIF NOT bFitted THEN
  eErrorId := E_UtError.NoMeasurement;
ELSIF bNoAgree OR bNoAgreeNow OR bTwoApart THEN
  eErrorId := E_UtError.SensorsDisagree;
ELSIF nSensorDropped > 0 OR bDev THEN
  eErrorId := E_UtError.SensorDeviates;
ELSIF nSensorsGood = 1 THEN
  eErrorId := E_UtError.OneSensorLeft;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bNoAgreeNow THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Running;
END_IF;
refData.sts.fValue := fValue;
refData.sts.fSpread := fSpread;
refData.sts.nSensorUsed := nSelIdx;
refData.sts.nSensorsGood := nSensorsGood;
refData.sts.nSensorDropped := nSensorDropped;
refData.sts.bGood := bGood;
bFirstScan := FALSE;

END_FUNCTION_BLOCK