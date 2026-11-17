(* FB_Rate — rate of change, with rising-fast and falling-fast warnings (src-v2 UT_RATE).
Pins: fIn (the value), bInGood (its health), bReset (restart the measurement) -> fRate (change per set.eUnit),
bGood (a full window of good readings, settings valid), bRisingFast, bFallingFast, plus FB_Object's bError /
bWarning / eErrorId / eState. refData: its record.

fRate is the slope of the best straight line through the readings of the last set.tWindow (a least-squares
trend), so noise largely cancels. To keep the memory small at any task interval, the window is kept as ten
slices of tWindow / 10: each slice holds the average reading and the average time of its readings, and the line
is fitted through the last nine whole slices and the one being filled. A steady ramp gives exactly its rate at any
task interval, even with only a few scans in the window. fRate is updated every scan and is 0 until a full window
has been measured after a start, a reset or a change of window (sts.bReady). A step of S shows as a bump (peak
about 1.7 x S / window) lasting about one window. set.tFilter smooths fRate further (a low-pass, 63 % in tFilter).
tWindow 0 = off.

bRisingFast: fRate above set.fRiseLimit for set.tAlarmDelay; bFallingFast: fRate below -set.fFallLimit for
tAlarmDelay; a limit of 0 is off. Both clear as soon as the rate is back within the limit; both are warnings
(RateHigh / RateLow).

Time is measured from TIME() differences in whole milliseconds; the part of a millisecond left over is carried to
the next scan. A NaN or infinite fIn, or bInGood FALSE, is ignored: fRate holds, a warning (SensorBad), and the
time it lasted does not count. Settings are kept by the block (a retained last-good copy): restored at power-up,
a bad write put back. *)

FUNCTION_BLOCK FB_Rate EXTENDS FB_Object
  VAR_INPUT
    fIn : REAL; (* the value *)
    bInGood : BOOL := TRUE; (* its health; FALSE: fRate held *)
    bReset : BOOL; (* restart the measurement *)
    refData : REFERENCE TO ST_RateData;
  END_VAR
  VAR_OUTPUT
    fRate : REAL; (* change per set.eUnit *)
    bGood : BOOL; (* a full window of good readings, settings valid *)
    bRisingFast : BOOL; (* fRate > fRiseLimit (after tAlarmDelay) *)
    bFallingFast : BOOL; (* fRate < -fFallLimit (after tAlarmDelay) *)
  END_VAR
  VAR RETAIN
    stKept : ST_RateSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    bStarted : BOOL;
    tPrev : TIME; (* time counted up to *)
    tWinPrev : TIME;
    aSumX : ARRAY [0..9] OF LREAL; (* each whole slice: sum of reading x ms *)
    aSumT : ARRAY [0..9] OF LREAL; (* each whole slice: sum of reading time (ms into the slice) x ms *)
    nHead : INT; (* slot of the oldest slice (written next) *)
    nSlices : INT; (* whole slices, up to 10 *)
    fAccX : LREAL; (* the slice being filled: sum of reading x ms *)
    fAccT : LREAL; (* the slice being filled: sum of reading time x ms *)
    fFilled : LREAL; (* ms in the slice being filled *)
    fSmooth : LREAL; (* after tFilter, per second *)
    tRiseSince : TIME; (* when fRate went above the rise limit *)
    tFallSince : TIME;
    bRiseOver : BOOL;
    bFallOver : BOOL;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bBad : BOOL;
    bRestart : BOOL;
    fX : LREAL;
    fWidth : LREAL; (* ms per slice *)
    nDMs : LINT;
    fDtMs : LREAL;
    fRest : LREAL; (* ms of this scan still to place *)
    fPart : LREAL;
    fPerUnit : LREAL;
    nI : INT;
  END_VAR


(* the settings are usable *)
METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_RateSet;
  END_VAR
  SetOk := stS.tWindow >= T#0s AND stS.tFilter >= T#0s AND stS.tAlarmDelay >= T#0s
           AND stS.fRiseLimit >= 0.0 AND stS.fRiseLimit <= REAL#3.4E38
           AND stS.fFallLimit >= 0.0 AND stS.fFallLimit <= REAL#3.4E38
           AND (stS.eUnit = E_RateUnit.PerSec OR stS.eUnit = E_RateUnit.PerMin OR stS.eUnit = E_RateUnit.PerHour
                OR stS.eUnit = E_RateUnit.PerDay);
END_METHOD

(* the trend slope (per second) through the nine newest whole slices and the slice being filled: a weighted
   least-squares line through each slice's (average time, average reading) *)
METHOD PRIVATE Slope : LREAL
  VAR_INPUT
    fWidth : LREAL;
  END_VAR
  VAR
    fWSum : LREAL;
    fCMean : LREAL;
    fMMean : LREAL;
    fCj : LREAL;
    fNum : LREAL;
    fDen : LREAL;
    nSlot : INT;
    nJ : INT;
  END_VAR
  fWSum := 9.0 * fWidth + fFilled;
  fCMean := fAccT + 9.0 * fWidth * fFilled;
  fMMean := fAccX;
  FOR nJ := 0 TO 8 DO
    nSlot := (nHead + 1 + nJ) MOD 10;
    fCMean := fCMean + aSumT[nSlot] + INT_TO_LREAL(nJ) * fWidth * fWidth;
    fMMean := fMMean + aSumX[nSlot];
  END_FOR;
  fCMean := fCMean / fWSum;
  fMMean := fMMean / fWSum;
  fNum := 0.0;
  fDen := 0.0;
  FOR nJ := 0 TO 8 DO
    nSlot := (nHead + 1 + nJ) MOD 10;
    fCj := aSumT[nSlot] / fWidth + INT_TO_LREAL(nJ) * fWidth - fCMean;
    fNum := fNum + fWidth * fCj * (aSumX[nSlot] / fWidth - fMMean);
    fDen := fDen + fWidth * fCj * fCj;
  END_FOR;
  IF fFilled > 0.0 THEN
    fCj := fAccT / fFilled + 9.0 * fWidth - fCMean;
    fNum := fNum + fFilled * fCj * (fAccX / fFilled - fMMean);
    fDen := fDen + fFilled * fCj * fCj;
  END_IF;
  IF fDen > 0.0 THEN
    Slope := fNum / fDen * 1000.0;
  ELSE
    Slope := 0.0;
  END_IF;
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
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;

bRestart := bReset OR SystemReset();
IF refData.bCmdReset THEN
  bRestart := TRUE;
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
END_IF;

bBad := NOT bInGood OR NOT (ABS(fIn) <= REAL#3.4E38);
fX := REAL_TO_LREAL(fIn);
fWidth := TIME_TO_LREAL(refData.set.tWindow) / 10.0;
IF NOT bStarted OR bRestart OR refData.set.tWindow <> tWinPrev THEN
  bStarted := TRUE;
  tPrev := tNow;
  nSlices := 0;
  nHead := 0;
  fAccX := 0.0;
  fAccT := 0.0;
  fFilled := 0.0;
  fSmooth := 0.0;
END_IF;
tWinPrev := refData.set.tWindow;
IF bBad OR fWidth <= 0.0 THEN
  tPrev := tNow;                  (* bad time does not count; window 0 = off *)
  IF fWidth <= 0.0 THEN
    nSlices := 0;
    fSmooth := 0.0;
  END_IF;
ELSE
  nDMs := TIME_TO_LINT(tNow - tPrev);          (* whole ms elapsed *)
  IF nDMs > 0 THEN
    tPrev := tPrev + LINT_TO_TIME(nDMs);       (* the part of a ms left over carries on *)
    fDtMs := LINT_TO_LREAL(nDMs);
    (* this reading covers the last fDtMs and is timed at the end of the scan; a long scan spreads it over
       several slices *)
    fRest := fDtMs;
    FOR nI := 0 TO 11 DO
      IF fRest >= fWidth - fFilled THEN
        fPart := fWidth - fFilled;
        aSumX[nHead] := fAccX + fX * fPart;
        aSumT[nHead] := fAccT + (fFilled + fRest) * fPart;
        fRest := fRest - fPart;
        nHead := (nHead + 1) MOD 10;
        IF nSlices < 10 THEN
          nSlices := nSlices + 1;
        END_IF;
        fAccX := 0.0;
        fAccT := 0.0;
        fFilled := 0.0;
      ELSE
        fAccX := fAccX + fX * fRest;
        fAccT := fAccT + (fFilled + fRest) * fRest;
        fFilled := fFilled + fRest;
        fRest := 0.0;
        EXIT;
      END_IF;
    END_FOR;
    IF fRest > 0.0 THEN           (* longer than the whole window: it was all this value *)
      FOR nI := 0 TO 9 DO
        aSumX[nI] := fX * fWidth;
        aSumT[nI] := fWidth * fWidth / 2.0;
      END_FOR;
      nSlices := 10;
      fAccX := 0.0;
      fAccT := 0.0;
      fFilled := 0.0;
    END_IF;
    IF nSlices >= 10 THEN
      IF refData.set.tFilter <= T#0s OR NOT refData.sts.bReady THEN
        fSmooth := Slope(fWidth := fWidth);
      ELSE
        fSmooth := fSmooth + (Slope(fWidth := fWidth) - fSmooth)
                   * (1.0 - EXP(-fDtMs / TIME_TO_LREAL(refData.set.tFilter)));
      END_IF;
    END_IF;
  END_IF;
END_IF;
refData.sts.bReady := nSlices >= 10;
refData.sts.bBadInput := bBad;
CASE refData.set.eUnit OF
  E_RateUnit.PerMin:  fPerUnit := 60.0;
  E_RateUnit.PerHour: fPerUnit := 3600.0;
  E_RateUnit.PerDay:  fPerUnit := 86400.0;
ELSE
  fPerUnit := 1.0;
END_CASE;
fRate := LREAL_TO_REAL(fSmooth * fPerUnit);

(* rising / falling fast: past the limit for tAlarmDelay; clear at once *)
IF refData.sts.bReady AND refData.set.fRiseLimit > 0.0 AND fRate > refData.set.fRiseLimit THEN
  IF NOT bRiseOver THEN
    bRiseOver := TRUE;
    tRiseSince := tNow;
  END_IF;
ELSE
  bRiseOver := FALSE;
END_IF;
IF refData.sts.bReady AND refData.set.fFallLimit > 0.0 AND fRate < -refData.set.fFallLimit THEN
  IF NOT bFallOver THEN
    bFallOver := TRUE;
    tFallSince := tNow;
  END_IF;
ELSE
  bFallOver := FALSE;
END_IF;
bRisingFast := bRiseOver AND tNow - tRiseSince >= refData.set.tAlarmDelay;
bFallingFast := bFallOver AND tNow - tFallSince >= refData.set.tAlarmDelay;
bGood := refData.sts.bReady AND bOk AND NOT bBad;

(* errors: all warnings but a settings record that never was good *)
bError := NOT bOk;
bWarning := NOT bError AND (bBad OR bRisingFast OR bFallingFast OR refData.sts.bRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bBad THEN
  eErrorId := E_UtError.SensorBad;
ELSIF bRisingFast THEN
  eErrorId := E_UtError.RateHigh;
ELSIF bFallingFast THEN
  eErrorId := E_UtError.RateLow;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF fWidth <= 0.0 THEN
  eState := E_State.Off;
ELSIF bBad THEN
  eState := E_State.Held;
ELSIF NOT refData.sts.bReady THEN
  eState := E_State.Starting;
ELSE
  eState := E_State.Running;
END_IF;
refData.sts.fRate := fRate;
refData.sts.bRisingFast := bRisingFast;
refData.sts.bFallingFast := bFallingFast;
bFirstScan := FALSE;

END_FUNCTION_BLOCK