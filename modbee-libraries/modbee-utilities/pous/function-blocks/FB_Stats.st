(* FB_Stats — minimum, maximum and time-weighted average of a value, for the current period and the previous one.
Pins: fIn, bInputGood (its health; FALSE: samples skipped), bEnable (collect while TRUE), bClosePeriod (close the
period), bClearPeriods (clear both periods) -> fMinimum, fMaximum, fAverage (the current period), plus FB_Object's
bError / bWarning / eErrorId / eState. refData: its record.
Each scan the value read now stands for the time since the previous scan (time-weighted: the same result at any
scan rate). Only samples taken while bEnable and bInputGood, that are numbers and not left out by set.fIgnoreBelow /
fIgnoreAbove, count. bClosePeriod closes the period: tot.stCurrentPeriod moves to tot.stPreviousPeriod. bClearPeriods / bCmdClearPeriods clears
both. tot is kept hourly and at each rollover / reset; the sum is LREAL with compensated (Kahan) summation;
nSampleCount saturates at the UDINT maximum. The record's sts carries the live summary only; the previous period,
sample count, duration and the times of the extremes are read from tot. Settings are kept by the block (a
retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Stats EXTENDS FB_Object
  VAR_INPUT
    fIn : REAL; (* the value *)
    bInputGood : BOOL := TRUE; (* its health; FALSE: samples skipped *)
    bEnable : BOOL := TRUE; (* collect while TRUE *)
    bClosePeriod : BOOL R_EDGE; (* close the period *)
    bClearPeriods : BOOL R_EDGE; (* clear both periods *)
    refData : REFERENCE TO ST_StatsData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    fMinimum : REAL; (* current period *)
    fMaximum : REAL; (* the current period's highest value *)
    fAverage : REAL; (* the current period's time-weighted average *)
  END_VAR
  VAR RETAIN
    stKept : ST_StatsSet;
    stKeptTot : ST_StatsTot;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    tPrev : TIME;
    tKeptAt : TIME;
    bResetSeen : BOOL; (* bCmdClearPeriods was TRUE last scan: a held command acts once *)
  END_VAR
  VAR_TEMP
    bOkSet : BOOL;
    bResetReq : BOOL;
    bValid : BOOL;
    nMs : LINT;
    tScan : TIME;
    fY : LREAL;
    fT : LREAL;
    fAvg : REAL;
  END_VAR


(* the settings are usable *)
METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_StatsSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (ABS(stS.fIgnoreBelow) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (ABS(stS.fIgnoreAbove) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_StatsSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

(* clear the current period *)
METHOD PRIVATE ClearCur
  refData.tot.stCurrentPeriod.nSampleCount := 0;
  refData.tot.stCurrentPeriod.fValueTimesMs := 0.0;
  refData.tot.stCurrentPeriod.fSumCompensation := 0.0;
  refData.tot.stCurrentPeriod.tTimeCollected := T#0s;
  refData.tot.stCurrentPeriod.tMinimumAt := T#0s;
  refData.tot.stCurrentPeriod.tMaximumAt := T#0s;
  refData.tot.stCurrentPeriod.tElapsedTime := T#0s;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();

(* kept settings and totals; a bad write is put back *)
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
  tPrev := tNow;
  tKeptAt := tNow;
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
(* the HMI command acts once per write, then is cleared; one the master keeps writing acts once *)
bResetReq := bClearPeriods OR SystemReset() OR (refData.bCmdClearPeriods AND NOT bResetSeen);
IF bResetReq THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
bResetSeen := refData.bCmdClearPeriods;
refData.bCmdClearPeriods := FALSE;

(* the time this sample stands for, in whole ms (the rest carries on) *)
nMs := TIME_TO_LINT(tNow - tPrev);
IF nMs < 0 THEN
  nMs := 0;
  tPrev := tNow;
END_IF;
tScan := LINT_TO_TIME(nMs);
tPrev := tPrev + tScan;
refData.tot.stCurrentPeriod.tElapsedTime := refData.tot.stCurrentPeriod.tElapsedTime + tScan;
bValid := bEnable AND bInputGood AND ABS(fIn) <= REAL#3.4E38;
IF refData.set.fIgnoreBelow <> 0.0 AND fIn < refData.set.fIgnoreBelow THEN
  bValid := FALSE;
END_IF;
IF refData.set.fIgnoreAbove <> 0.0 AND fIn > refData.set.fIgnoreAbove THEN
  bValid := FALSE;
END_IF;
IF bValid THEN
  IF refData.tot.stCurrentPeriod.nSampleCount = 0 THEN
    refData.tot.stCurrentPeriod.fMinimum := fIn;
    refData.tot.stCurrentPeriod.fMaximum := fIn;
    refData.tot.stCurrentPeriod.tMinimumAt := refData.tot.stCurrentPeriod.tElapsedTime;
    refData.tot.stCurrentPeriod.tMaximumAt := refData.tot.stCurrentPeriod.tElapsedTime;
  ELSIF fIn < refData.tot.stCurrentPeriod.fMinimum THEN
    refData.tot.stCurrentPeriod.fMinimum := fIn;
    refData.tot.stCurrentPeriod.tMinimumAt := refData.tot.stCurrentPeriod.tElapsedTime;
  ELSIF fIn > refData.tot.stCurrentPeriod.fMaximum THEN
    refData.tot.stCurrentPeriod.fMaximum := fIn;
    refData.tot.stCurrentPeriod.tMaximumAt := refData.tot.stCurrentPeriod.tElapsedTime;
  END_IF;
  IF refData.tot.stCurrentPeriod.nSampleCount < UDINT#16#FFFFFFFF THEN
    refData.tot.stCurrentPeriod.nSampleCount := refData.tot.stCurrentPeriod.nSampleCount + 1;
  END_IF;
  fY := REAL_TO_LREAL(fIn) * LINT_TO_LREAL(nMs) - refData.tot.stCurrentPeriod.fSumCompensation;
  fT := refData.tot.stCurrentPeriod.fValueTimesMs + fY;
  refData.tot.stCurrentPeriod.fSumCompensation := (fT - refData.tot.stCurrentPeriod.fValueTimesMs) - fY;
  refData.tot.stCurrentPeriod.fValueTimesMs := fT;
  refData.tot.stCurrentPeriod.tTimeCollected := refData.tot.stCurrentPeriod.tTimeCollected + tScan;
END_IF;
IF refData.tot.stCurrentPeriod.tTimeCollected > T#0s THEN
  fAvg := LREAL_TO_REAL(refData.tot.stCurrentPeriod.fValueTimesMs / TIME_TO_LREAL(refData.tot.stCurrentPeriod.tTimeCollected));
ELSIF refData.tot.stCurrentPeriod.nSampleCount > 0 THEN
  fAvg := refData.tot.stCurrentPeriod.fMinimum + (refData.tot.stCurrentPeriod.fMaximum - refData.tot.stCurrentPeriod.fMinimum) / 2.0;
ELSE
  fAvg := 0.0;
END_IF;

(* close the period *)
IF bClosePeriod THEN
  refData.tot.stPreviousPeriod.nSampleCount := refData.tot.stCurrentPeriod.nSampleCount;
  refData.tot.stPreviousPeriod.tTimeCollected := refData.tot.stCurrentPeriod.tTimeCollected;
  IF refData.tot.stCurrentPeriod.nSampleCount > 0 THEN
    refData.tot.stPreviousPeriod.fMinimum := refData.tot.stCurrentPeriod.fMinimum;
    refData.tot.stPreviousPeriod.fMaximum := refData.tot.stCurrentPeriod.fMaximum;
    refData.tot.stPreviousPeriod.fAverage := fAvg;
  ELSE
    refData.tot.stPreviousPeriod.fMinimum := 0.0;
    refData.tot.stPreviousPeriod.fMaximum := 0.0;
    refData.tot.stPreviousPeriod.fAverage := 0.0;
  END_IF;
  ClearCur();
  fAvg := 0.0;
END_IF;
IF bResetReq THEN
  ClearCur();
  fAvg := 0.0;
  refData.tot.stPreviousPeriod.fMinimum := 0.0;
  refData.tot.stPreviousPeriod.fMaximum := 0.0;
  refData.tot.stPreviousPeriod.fAverage := 0.0;
  refData.tot.stPreviousPeriod.tTimeCollected := T#0s;
  refData.tot.stPreviousPeriod.nSampleCount := 0;
END_IF;
IF bClosePeriod OR bResetReq OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
IF refData.tot.stCurrentPeriod.nSampleCount > 0 THEN
  fMinimum := refData.tot.stCurrentPeriod.fMinimum;
  fMaximum := refData.tot.stCurrentPeriod.fMaximum;
ELSE
  fMinimum := 0.0;
  fMaximum := 0.0;
END_IF;
fAverage := fAvg;

(* errors *)
bError := FALSE;
bWarning := (bEnable AND NOT bInputGood) OR NOT bOkSet OR refData.sts.bSettingRefused;
IF bEnable AND NOT bInputGood THEN
  eErrorId := E_UtError.SensorBad;
ELSIF NOT bOkSet THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bEnable THEN
  eState := E_State.Running;      (* collecting *)
ELSE
  eState := E_State.Idle;
END_IF;
refData.sts.fMinimum := fMinimum;
refData.sts.fMaximum := fMaximum;
refData.sts.fAverage := fAverage;
bFirstScan := FALSE;

END_FUNCTION_BLOCK