(* FB_SettingCheck — write gate for one project value that belongs to no block. The HMI / SCADA writes its own
variable (fNew); each time fNew changes, or on bWritten, fNew is checked: a number, fMin..fMax,
above fAbove and below fBelow for related settings (e.g. high above low). Passed: refValue := fNew, bAccepted for
one scan. Failed: refValue keeps its old value, bRefused for one scan, eRefusedId says why (ValueBad, LimitsBad,
BelowMin, AboveMax, NotAbove, NotBelow; None after an accepted write). bError / eErrorId: the value in use fails
the checks now (written past this block, or a limit moved). Unwired limits are open. Nothing is checked on the
first scan: a master variable that comes back 0 never overwrites a kept value (refValue is the project's RETAIN
variable). No refValue: bError, NoRecord. *)

FUNCTION_BLOCK FB_SettingCheck
  VAR_INPUT
    fNew : REAL; (* the value the master wrote *)
    bWritten : BOOL R_EDGE; (* check fNew now, even if unchanged *)
    fMin : REAL := REAL#-3.4E38;
    fMax : REAL := REAL#3.4E38;
    fAbove : REAL := REAL#-3.4E38; (* must be above this related setting *)
    fBelow : REAL := REAL#3.4E38; (* must be below this related setting *)
    refValue : REFERENCE TO REAL; (* the value in use (a project RETAIN variable) *)
  END_VAR
  VAR_OUTPUT
    bAccepted : BOOL; (* one scan *)
    bRefused : BOOL; (* one scan *)
    eRefusedId : E_UtError; (* the last refused write (None after an accepted one) *)
    bError : BOOL; (* the value in use fails the checks *)
    eErrorId : E_UtError;
  END_VAR
  VAR
    bStarted : BOOL;
    fNewPrev : REAL;
  END_VAR
  VAR_TEMP
    bCheck : BOOL;
    bLimitsOk : BOOL;
    eWhy : E_UtError;
  END_VAR


bAccepted := FALSE;
bRefused := FALSE;
IF NOT __ISVALIDREF(refValue) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
IF NOT bStarted THEN
  bStarted := TRUE;
  bCheck := FALSE;
ELSE
  (* NaN never equals itself: NaN to NaN is no change *)
  bCheck := NOT (fNew = fNewPrev OR (NOT (fNew = fNew) AND NOT (fNewPrev = fNewPrev))) OR bWritten;
END_IF;
fNewPrev := fNew;
bLimitsOk := fMin = fMin AND fMax = fMax AND fAbove = fAbove AND fBelow = fBelow
             AND fMin >= REAL#-3.4E38 AND fMax <= REAL#3.4E38 AND fAbove >= REAL#-3.4E38 AND fBelow <= REAL#3.4E38;
IF bCheck THEN
  IF NOT bLimitsOk THEN
    eWhy := E_UtError.LimitsBad;
  ELSE
    eWhy := F_CheckReal(fValue := fNew, fMin := fMin, fMax := fMax, bUseAbove := fAbove > REAL#-3.4E38,
                        fAbove := fAbove, bUseBelow := fBelow < REAL#3.4E38, fBelow := fBelow);
  END_IF;
  IF eWhy = E_UtError.None THEN
    refValue := fNew;
    bAccepted := TRUE;
  ELSE
    bRefused := TRUE;
  END_IF;
  eRefusedId := eWhy;
END_IF;
IF NOT bLimitsOk THEN
  eErrorId := E_UtError.LimitsBad;
ELSE
  eErrorId := F_CheckReal(fValue := refValue, fMin := fMin, fMax := fMax, bUseAbove := fAbove > REAL#-3.4E38,
                          fAbove := fAbove, bUseBelow := fBelow < REAL#3.4E38, fBelow := fBelow);
END_IF;
bError := eErrorId <> E_UtError.None;

END_FUNCTION_BLOCK