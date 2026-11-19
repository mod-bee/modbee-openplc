(* F_CheckLreal — as F_CheckReal for an LREAL setting (a total, a preset): a number, within
fLowestAllowed..fHighestAllowed. Returns the first problem as an E_UtError, None when it is good. *)

FUNCTION F_CheckLreal : E_UtError
  VAR_INPUT
    fValue : LREAL; (* the value to check *)
    fLowestAllowed : LREAL; (* lowest value allowed *)
    fHighestAllowed : LREAL; (* highest value allowed *)
  END_VAR

IF NOT (fValue = fValue) OR fValue > LREAL#1.7E308 OR fValue < LREAL#-1.7E308 THEN
  F_CheckLreal := E_UtError.ValueBad;
ELSIF fLowestAllowed > fHighestAllowed THEN
  F_CheckLreal := E_UtError.LimitsBad;
ELSIF fValue < fLowestAllowed THEN
  F_CheckLreal := E_UtError.BelowMin;
ELSIF fValue > fHighestAllowed THEN
  F_CheckLreal := E_UtError.AboveMax;
ELSE
  F_CheckLreal := E_UtError.None;
END_IF;

END_FUNCTION