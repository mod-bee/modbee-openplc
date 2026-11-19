(* FB_SettingCheck — write gate for one project value that belongs to no block. The HMI / SCADA writes its own
variable (fRequestedValue); each time fRequestedValue changes, or on bCheckNow, fRequestedValue is checked: a number, fLowestAllowed..fHighestAllowed,
above fMustBeAbove and below fMustBeBelow for related settings (e.g. high above low). Passed: refValueInUse := fRequestedValue, bRequestAccepted for
one scan. Failed: refValueInUse keeps its old value, bRequestRefused for one scan, eRefusedReason says why (ValueBad, LimitsBad,
BelowMin, AboveMax, NotAbove, NotBelow; None after an accepted write). bError / eErrorId: the value in use fails
the checks now (written past this block, or a limit moved). Unwired limits are open. Nothing is checked on the
first scan: a master variable that comes back 0 never overwrites a kept value (refValueInUse is the project's RETAIN
variable). No refValueInUse: bError, NoRecord. *)

FUNCTION_BLOCK FB_SettingCheck
  VAR_INPUT
    fRequestedValue : REAL; (* the value the master wrote *)
    bCheckNow : BOOL R_EDGE; (* check fRequestedValue now, even if unchanged *)
    fLowestAllowed : REAL := REAL#-3.4E38; (* lowest value allowed *)
    fHighestAllowed : REAL := REAL#3.4E38; (* highest value allowed *)
    fMustBeAbove : REAL := REAL#-3.4E38; (* must be above this related setting *)
    fMustBeBelow : REAL := REAL#3.4E38; (* must be below this related setting *)
    refValueInUse : REFERENCE TO REAL; (* the value in use (a project RETAIN variable) *)
  END_VAR
  VAR_OUTPUT
    bRequestAccepted : BOOL; (* one scan *)
    bRequestRefused : BOOL; (* one scan *)
    eRefusedReason : E_UtError; (* the last refused write (None after an accepted one) *)
    bError : BOOL; (* the value in use fails the checks *)
    eErrorId : E_UtError; (* which check it fails (None when all is well) *)
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


bRequestAccepted := FALSE;
bRequestRefused := FALSE;
IF NOT __ISVALIDREF(refValueInUse) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  RETURN;
END_IF;
IF NOT bStarted THEN
  bStarted := TRUE;
  bCheck := FALSE;
ELSE
  (* NaN never equals itself: NaN to NaN is no change *)
  bCheck := NOT (fRequestedValue = fNewPrev OR (NOT (fRequestedValue = fRequestedValue) AND NOT (fNewPrev = fNewPrev))) OR bCheckNow;
END_IF;
fNewPrev := fRequestedValue;
bLimitsOk := fLowestAllowed = fLowestAllowed AND fHighestAllowed = fHighestAllowed AND fMustBeAbove = fMustBeAbove AND fMustBeBelow = fMustBeBelow
             AND fLowestAllowed >= REAL#-3.4E38 AND fHighestAllowed <= REAL#3.4E38 AND fMustBeAbove >= REAL#-3.4E38 AND fMustBeBelow <= REAL#3.4E38;
IF bCheck THEN
  IF NOT bLimitsOk THEN
    eWhy := E_UtError.LimitsBad;
  ELSE
    eWhy := F_CheckReal(fValue := fRequestedValue, fLowestAllowed := fLowestAllowed, fHighestAllowed := fHighestAllowed, bCheckAbove := fMustBeAbove > REAL#-3.4E38,
                        fMustBeAbove := fMustBeAbove, bCheckBelow := fMustBeBelow < REAL#3.4E38, fMustBeBelow := fMustBeBelow);
  END_IF;
  IF eWhy = E_UtError.None THEN
    refValueInUse := fRequestedValue;
    bRequestAccepted := TRUE;
  ELSE
    bRequestRefused := TRUE;
  END_IF;
  eRefusedReason := eWhy;
END_IF;
IF NOT bLimitsOk THEN
  eErrorId := E_UtError.LimitsBad;
ELSE
  eErrorId := F_CheckReal(fValue := refValueInUse, fLowestAllowed := fLowestAllowed, fHighestAllowed := fHighestAllowed, bCheckAbove := fMustBeAbove > REAL#-3.4E38,
                          fMustBeAbove := fMustBeAbove, bCheckBelow := fMustBeBelow < REAL#3.4E38, fMustBeBelow := fMustBeBelow);
END_IF;
bError := eErrorId <> E_UtError.None;

END_FUNCTION_BLOCK