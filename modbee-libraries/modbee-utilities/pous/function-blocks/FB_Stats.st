(* FB_Stats — minimum, maximum and time-weighted average of a value, for the current period and the previous one
(src-v2 UT_STATS).
Pins: fIn, bInGood (its health; FALSE: samples skipped), bEnable (collect while TRUE), bRollover (close the
period), bReset (clear both periods) -> fMinimum, fMaximum, fAverage (the current period), plus FB_Object's
bError / bWarning / eErrorId / eState. refData: its record.
Each scan the value read now stands for the time since the previous scan (time-weighted: the same result at any
scan rate). Only samples taken while bEnable and bInGood, that are numbers and not left out by set.fIgnoreBelow /
fIgnoreAbove, count. bRollover closes the period: tot.stCur moves to tot.stPrev. bReset / bCmdResetStats clears
both. tot is kept hourly and at each rollover / reset; the sum is LREAL with compensated (Kahan) summation;
nSamples saturates at the UDINT maximum. The record's sts carries the live summary only; the previous period,
sample count, duration and the times of the extremes are read from tot. Settings are kept by the block (a
retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Stats EXTENDS FB_Object
  VAR_INPUT
    fIn : REAL;
    bInGood : BOOL := TRUE; (* its health; FALSE: samples skipped *)
    bEnable : BOOL := TRUE; (* collect while TRUE *)
    bRollover : BOOL R_EDGE; (* close the period *)
    bReset : BOOL R_EDGE; (* clear both periods *)
    refData : REFERENCE TO ST_StatsData;
  END_VAR
  VAR_OUTPUT
    fMinimum : REAL; (* current period *)
    fMaximum : REAL;
    fAverage : REAL;
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
    bResetSeen : BOOL; (* bCmdResetStats was TRUE last scan: a held command acts once *)
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
METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_StatsSet;
  END_VAR
  SetOk := ABS(stS.fIgnoreBelow) <= REAL#3.4E38 AND ABS(stS.fIgnoreAbove) <= REAL#3.4E38;
END_METHOD

(* clear the current period *)
METHOD PRIVATE ClearCur
  refData.tot.stCur.nSamples := 0;
  refData.tot.stCur.fSum := 0.0;
  refData.tot.stCur.fComp := 0.0;
  refData.tot.stCur.tDuration := T#0s;
  refData.tot.stCur.tMinAt := T#0s;
  refData.tot.stCur.tMaxAt := T#0s;
  refData.tot.stCur.tElapsed := T#0s;
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
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;
(* the HMI command acts once per write, then is cleared; one the master keeps writing acts once *)
bResetReq := bReset OR SystemReset() OR (refData.bCmdResetStats AND NOT bResetSeen);
IF bResetReq THEN
  refData.sts.bRefused := FALSE;
END_IF;
bResetSeen := refData.bCmdResetStats;
refData.bCmdResetStats := FALSE;

(* the time this sample stands for, in whole ms (the rest carries on) *)
nMs := TIME_TO_LINT(tNow - tPrev);
IF nMs < 0 THEN
  nMs := 0;
  tPrev := tNow;
END_IF;
tScan := LINT_TO_TIME(nMs);
tPrev := tPrev + tScan;
refData.tot.stCur.tElapsed := refData.tot.stCur.tElapsed + tScan;
bValid := bEnable AND bInGood AND ABS(fIn) <= REAL#3.4E38;
IF refData.set.fIgnoreBelow <> 0.0 AND fIn < refData.set.fIgnoreBelow THEN
  bValid := FALSE;
END_IF;
IF refData.set.fIgnoreAbove <> 0.0 AND fIn > refData.set.fIgnoreAbove THEN
  bValid := FALSE;
END_IF;
IF bValid THEN
  IF refData.tot.stCur.nSamples = 0 THEN
    refData.tot.stCur.fMin := fIn;
    refData.tot.stCur.fMax := fIn;
    refData.tot.stCur.tMinAt := refData.tot.stCur.tElapsed;
    refData.tot.stCur.tMaxAt := refData.tot.stCur.tElapsed;
  ELSIF fIn < refData.tot.stCur.fMin THEN
    refData.tot.stCur.fMin := fIn;
    refData.tot.stCur.tMinAt := refData.tot.stCur.tElapsed;
  ELSIF fIn > refData.tot.stCur.fMax THEN
    refData.tot.stCur.fMax := fIn;
    refData.tot.stCur.tMaxAt := refData.tot.stCur.tElapsed;
  END_IF;
  IF refData.tot.stCur.nSamples < UDINT#16#FFFFFFFF THEN
    refData.tot.stCur.nSamples := refData.tot.stCur.nSamples + 1;
  END_IF;
  fY := REAL_TO_LREAL(fIn) * LINT_TO_LREAL(nMs) - refData.tot.stCur.fComp;
  fT := refData.tot.stCur.fSum + fY;
  refData.tot.stCur.fComp := (fT - refData.tot.stCur.fSum) - fY;
  refData.tot.stCur.fSum := fT;
  refData.tot.stCur.tDuration := refData.tot.stCur.tDuration + tScan;
END_IF;
IF refData.tot.stCur.tDuration > T#0s THEN
  fAvg := LREAL_TO_REAL(refData.tot.stCur.fSum / TIME_TO_LREAL(refData.tot.stCur.tDuration));
ELSIF refData.tot.stCur.nSamples > 0 THEN
  fAvg := refData.tot.stCur.fMin + (refData.tot.stCur.fMax - refData.tot.stCur.fMin) / 2.0;
ELSE
  fAvg := 0.0;
END_IF;

(* close the period *)
IF bRollover THEN
  refData.tot.stPrev.nSamples := refData.tot.stCur.nSamples;
  refData.tot.stPrev.tDuration := refData.tot.stCur.tDuration;
  IF refData.tot.stCur.nSamples > 0 THEN
    refData.tot.stPrev.fMin := refData.tot.stCur.fMin;
    refData.tot.stPrev.fMax := refData.tot.stCur.fMax;
    refData.tot.stPrev.fAverage := fAvg;
  ELSE
    refData.tot.stPrev.fMin := 0.0;
    refData.tot.stPrev.fMax := 0.0;
    refData.tot.stPrev.fAverage := 0.0;
  END_IF;
  ClearCur();
  fAvg := 0.0;
END_IF;
IF bResetReq THEN
  ClearCur();
  fAvg := 0.0;
  refData.tot.stPrev.fMin := 0.0;
  refData.tot.stPrev.fMax := 0.0;
  refData.tot.stPrev.fAverage := 0.0;
  refData.tot.stPrev.tDuration := T#0s;
  refData.tot.stPrev.nSamples := 0;
END_IF;
IF bRollover OR bResetReq OR tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
IF refData.tot.stCur.nSamples > 0 THEN
  fMinimum := refData.tot.stCur.fMin;
  fMaximum := refData.tot.stCur.fMax;
ELSE
  fMinimum := 0.0;
  fMaximum := 0.0;
END_IF;
fAverage := fAvg;

(* errors *)
bError := FALSE;
bWarning := (bEnable AND NOT bInGood) OR NOT bOkSet OR refData.sts.bRefused;
IF bEnable AND NOT bInGood THEN
  eErrorId := E_UtError.SensorBad;
ELSIF NOT bOkSet THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bRefused THEN
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