FUNCTION F_CheckReal : E_UtError
  VAR_INPUT
    fValue : REAL;
    fMin : REAL := REAL#-3.4E38;
    fMax : REAL := REAL#3.4E38;
    bUseAbove : BOOL;
    fAbove : REAL; (* must be above this related setting (bUseAbove) *)
    bUseBelow : BOOL;
    fBelow : REAL; (* must be below this related setting (bUseBelow) *)
  END_VAR

IF NOT (fValue = fValue) OR fValue > REAL#3.4E38 OR fValue < REAL#-3.4E38 THEN
  F_CheckReal := E_UtError.ValueBad;
ELSIF fMin > fMax THEN
  F_CheckReal := E_UtError.LimitsBad;
ELSIF fValue < fMin THEN
  F_CheckReal := E_UtError.BelowMin;
ELSIF fValue > fMax THEN
  F_CheckReal := E_UtError.AboveMax;
ELSIF bUseAbove AND NOT (fValue > fAbove) THEN
  F_CheckReal := E_UtError.NotAbove;
ELSIF bUseBelow AND NOT (fValue < fBelow) THEN
  F_CheckReal := E_UtError.NotBelow;
ELSE
  F_CheckReal := E_UtError.None;
END_IF;

END_FUNCTION