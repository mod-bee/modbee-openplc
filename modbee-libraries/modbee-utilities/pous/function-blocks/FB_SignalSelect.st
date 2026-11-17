(* FB_SignalSelect — two or three sensors measuring the same thing, voted into one trusted measurement. Wire the
instance to any I_Measurement pin.
Pins: ipSensor1..3 (I_Measurement; NULL = not fitted, never used), bReset -> fOut (the voted value; while not
good per set.eNoGood), bGood, fSpread (the largest difference between usable sensors), nDeviating (the sensor
dropped, 1..3; 0 none), nGoodCount, plus FB_Object's bError / bWarning / eErrorId / eState. refData: its record.
A sensor is usable when it is fitted, good, has a value and the value is a number. Two sensors agree when they
are within set.fFaultSpread.
  3 usable  all agree: combined by set.eSelect. One agrees with neither of the others while those two agree: it
            is dropped (nDeviating, warning SensorDeviates). No two agree: no agreement.
  2 usable  agree: combined by eSelect. Not: warning SensorsDisagree, set.eTwoDisagree (Highest or Lowest) used.
  1 usable  used, warning OneSensorLeft.
  0 usable  no agreement.
No agreement is a protection (set.stNoAgree, default Trip after 10 s, Auto): ridden through with the last voted
value, then bGood FALSE, bError SensorsDisagree, fOut per eNoGood (Hold, Lowest / Highest of the raw values,
Substitute set.fSubstitute, Midpoint of the raw values). The spread is another (set.stDeviation, default Warn
after 5 s): fSpread above set.fWarnSpread, or a sensor dropped. set.tFilter smooths fOut (low-pass). No sensor
wired: bError NoMeasurement. Settings are kept by the block (a retained last-good copy): restored at power-up,
a bad write put back. eUnit: sensor 1's. *)

FUNCTION_BLOCK FB_SignalSelect EXTENDS FB_Object IMPLEMENTS I_Measurement
  VAR_INPUT
    ipSensor1 : I_Measurement; (* NULL = not fitted, never used *)
    ipSensor2 : I_Measurement;
    ipSensor3 : I_Measurement;
    bReset : BOOL R_EDGE;
    refData : REFERENCE TO ST_SelectData;
  END_VAR
  VAR_OUTPUT
    fOut : REAL; (* voted value (while not good: per eNoGood) *)
    bGood : BOOL; (* the voted value can be used *)
    fSpread : REAL;
    nDeviating : INT; (* the sensor dropped (1..3), 0 none *)
    nGoodCount : INT;
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
    aRaw : ARRAY [1..3] OF BOOL; (* a number, health ignored (eNoGood Lowest / Highest / Midpoint) *)
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


PROPERTY PUBLIC fActValue : REAL
  GET
    fActValue := fOut;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsGood : BOOL
  GET
    bIsGood := bGood;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bHasValue : BOOL
  GET
    bHasValue := TRUE;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFitted : BOOL
  GET
    bIsFitted := bFitted;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eUnit : E_Unit
  GET
    eUnit := eUnitNow;
  END_GET
END_PROPERTY

METHOD PUBLIC Band : BOOL
  VAR_INPUT
    eBand : E_Band;
  END_VAR
  Band := FALSE;
END_METHOD

METHOD PRIVATE ProtOk : BOOL
  VAR_INPUT
    stP : REFERENCE TO ST_ProtectionSet;
  END_VAR
  ProtOk := stP.tDelay >= T#0s AND stP.tRecover >= T#0s AND stP.nMaxRetries >= 0;
END_METHOD

(* the settings are usable *)
METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_SelectSet;
  END_VAR
  SetOk := stS.fWarnSpread >= 0.0 AND stS.fWarnSpread <= REAL#3.4E38
           AND stS.fFaultSpread >= 0.0 AND stS.fFaultSpread <= REAL#3.4E38
           AND stS.tFilter >= T#0s AND stS.tRetryWindow >= T#0s AND ABS(stS.fSubstitute) <= REAL#3.4E38
           AND ProtOk(stP := stS.stDeviation) AND ProtOk(stP := stS.stNoAgree)
           AND (stS.eTwoDisagree = E_SelectMode.Highest OR stS.eTwoDisagree = E_SelectMode.Lowest)
           AND (stS.eSelect = E_SelectMode.Average OR stS.eSelect = E_SelectMode.Lowest
                OR stS.eSelect = E_SelectMode.Highest OR stS.eSelect = E_SelectMode.Median
                OR stS.eSelect = E_SelectMode.Primary)
           AND (stS.eNoGood = E_NoGood.Hold OR stS.eNoGood = E_NoGood.Lowest OR stS.eNoGood = E_NoGood.Highest
                OR stS.eNoGood = E_NoGood.Substitute OR stS.eNoGood = E_NoGood.Midpoint);
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
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bResetReq := bReset OR SystemReset();
IF refData.bCmdReset THEN
  bResetReq := TRUE;
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
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
nGoodCount := BOOL_TO_INT(aUsable[1]) + BOOL_TO_INT(aUsable[2]) + BOOL_TO_INT(aUsable[3]);

(* the vote *)
bAg12 := aUsable[1] AND aUsable[2] AND ABS(aV[1] - aV[2]) <= refData.set.fFaultSpread;
bAg13 := aUsable[1] AND aUsable[3] AND ABS(aV[1] - aV[3]) <= refData.set.fFaultSpread;
bAg23 := aUsable[2] AND aUsable[3] AND ABS(aV[2] - aV[3]) <= refData.set.fFaultSpread;
FOR nI := 1 TO 3 DO
  aUse[nI] := aUsable[nI];
END_FOR;
nDeviating := 0;
bNoAgreeNow := FALSE;
bTwoApart := FALSE;
eMode := refData.set.eSelect;
IF nGoodCount = 3 THEN
  IF NOT bAg12 AND NOT bAg13 AND NOT bAg23 THEN
    bNoAgreeNow := TRUE;
  ELSIF bAg23 AND NOT bAg12 AND NOT bAg13 THEN
    nDeviating := 1;
  ELSIF bAg13 AND NOT bAg12 AND NOT bAg23 THEN
    nDeviating := 2;
  ELSIF bAg12 AND NOT bAg13 AND NOT bAg23 THEN
    nDeviating := 3;
  END_IF;
  IF nDeviating > 0 THEN
    aUse[nDeviating] := FALSE;
  END_IF;
ELSIF nGoodCount = 2 THEN
  IF NOT (bAg12 OR bAg13 OR bAg23) THEN
    bTwoApart := TRUE;
    eMode := refData.set.eTwoDisagree;
  END_IF;
ELSIF nGoodCount = 0 THEN
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
bNoAgree := F_Protect(tNow := tNow, bCause := bNoAgreeNow AND bFitted, bResetReq := bResetReq,
                      tRetryWindow := refData.set.tRetryWindow, stSet := refData.set.stNoAgree,
                      stSts := refData.sts.stNoAgree, stWork := stWNo);
F_Protect(tNow := tNow, bCause := fSpread > refData.set.fWarnSpread OR nDeviating > 0, bResetReq := bResetReq,
          tRetryWindow := refData.set.tRetryWindow, stSet := refData.set.stDeviation,
          stSts := refData.sts.stDeviation, stWork := stWDev);
bDev := stWDev.bWarn OR stWDev.bTrip;
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
  CASE refData.set.eNoGood OF
  E_NoGood.Lowest: IF nN > 0 THEN fHeld := fLo; END_IF;
  E_NoGood.Highest: IF nN > 0 THEN fHeld := fHi; END_IF;
  E_NoGood.Substitute: fHeld := refData.set.fSubstitute;
  E_NoGood.Midpoint: IF nN > 0 THEN fHeld := (fLo + fHi) / 2.0; END_IF;
  END_CASE;
  nSelIdx := 0;
END_IF;
fbFilter(fIn := fHeld, tTc := refData.set.tFilter, eMode := E_FilterMode.Lowpass);
fOut := fbFilter.fOut;

(* errors *)
bError := NOT bFitted OR bNoAgree OR NOT bOkSet;
bWarning := NOT bError AND (bNoAgreeNow OR bTwoApart OR nDeviating > 0 OR nGoodCount = 1 OR bDev
                            OR refData.sts.bRefused);
IF NOT bOkSet THEN
  eErrorId := E_UtError.BadSetting;
ELSIF NOT bFitted THEN
  eErrorId := E_UtError.NoMeasurement;
ELSIF bNoAgree OR bNoAgreeNow OR bTwoApart THEN
  eErrorId := E_UtError.SensorsDisagree;
ELSIF nDeviating > 0 OR bDev THEN
  eErrorId := E_UtError.SensorDeviates;
ELSIF nGoodCount = 1 THEN
  eErrorId := E_UtError.OneSensorLeft;
ELSIF refData.sts.bRefused THEN
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
refData.sts.fOut := fOut;
refData.sts.fSpread := fSpread;
refData.sts.nSelected := nSelIdx;
refData.sts.nGoodCount := nGoodCount;
refData.sts.nDeviating := nDeviating;
refData.sts.bGood := bGood;
bFirstScan := FALSE;

END_FUNCTION_BLOCK